#!/usr/bin/env bash
# Clones all repos for a GitHub user, syncs forks to their upstreams,
# and runs security scans (secret detection + pip-audit) on each one.
#
# Usage:
#   chmod +x fix-all-repos.sh
#   GITHUB_TOKEN=<your-pat> ./fix-all-repos.sh
#
# Requirements:
#   - gh CLI (brew install gh  OR  https://cli.github.com)
#   - git
#   - pip-audit (pip install pip-audit)
#   - gitleaks (brew install gitleaks  OR  https://github.com/gitleaks/gitleaks)
#
# The script creates a working directory ./all-repos/ next to itself.

set -euo pipefail

GITHUB_USER="avnit"
WORKDIR="$(pwd)/all-repos"
REPORT="$(pwd)/security-report-$(date +%Y%m%d-%H%M%S).txt"

# ── Prerequisites ─────────────────────────────────────────────────────────────
for cmd in gh git pip-audit gitleaks jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Missing: $cmd — install it first."
    exit 1
  fi
done

gh auth status &>/dev/null || { echo "❌ Run: gh auth login"; exit 1; }

mkdir -p "$WORKDIR"
echo "▶ Working directory: $WORKDIR"
echo "▶ Report: $REPORT"
echo "" | tee "$REPORT"

# ── 1. Fetch all repos ────────────────────────────────────────────────────────
echo "▶ Fetching repo list for @${GITHUB_USER}..." | tee -a "$REPORT"
REPOS=$(gh repo list "$GITHUB_USER" \
  --limit 200 \
  --json nameWithOwner,isFork,defaultBranchRef,isPrivate \
  --jq '.[] | [.nameWithOwner, (.isFork|tostring), .defaultBranchRef.name, (.isPrivate|tostring)] | @tsv')

TOTAL=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "  Found $TOTAL repos" | tee -a "$REPORT"

CLONE_ERRORS=()
SYNC_ERRORS=()
VULN_FINDINGS=()

# ── 2. Clone / update + sync forks ───────────────────────────────────────────
while IFS=$'\t' read -r FULL_NAME IS_FORK DEFAULT_BRANCH IS_PRIVATE; do
  REPO_NAME="${FULL_NAME#*/}"
  REPO_DIR="$WORKDIR/$REPO_NAME"

  echo ""
  echo "━━━ $FULL_NAME (fork=$IS_FORK, branch=$DEFAULT_BRANCH) ━━━" | tee -a "$REPORT"

  # Clone if not already present
  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "  ↻ Pulling latest..." | tee -a "$REPORT"
    git -C "$REPO_DIR" fetch --all -q 2>/dev/null || true
    git -C "$REPO_DIR" pull origin "$DEFAULT_BRANCH" -q 2>/dev/null \
      || { echo "  ⚠ Pull failed (merge conflict?)" | tee -a "$REPORT"; }
  else
    echo "  ⬇ Cloning..." | tee -a "$REPORT"
    if ! gh repo clone "$FULL_NAME" "$REPO_DIR" -- -q 2>/dev/null; then
      echo "  ❌ Clone failed" | tee -a "$REPORT"
      CLONE_ERRORS+=("$FULL_NAME")
      continue
    fi
  fi

  # Sync fork to upstream
  if [[ "$IS_FORK" == "true" ]]; then
    echo "  🔄 Syncing fork to upstream..." | tee -a "$REPORT"
    if gh repo sync "$FULL_NAME" --branch "$DEFAULT_BRANCH" 2>/dev/null; then
      git -C "$REPO_DIR" pull origin "$DEFAULT_BRANCH" -q 2>/dev/null || true
      echo "  ✅ Fork synced" | tee -a "$REPORT"
    else
      echo "  ⚠ Fork sync failed (upstream may have conflicts)" | tee -a "$REPORT"
      SYNC_ERRORS+=("$FULL_NAME")
    fi
  fi

done <<< "$REPOS"

# ── 3. Security scans ─────────────────────────────────────────────────────────
echo "" | tee -a "$REPORT"
echo "════════════════════════════════" | tee -a "$REPORT"
echo "  SECURITY SCAN RESULTS" | tee -a "$REPORT"
echo "════════════════════════════════" | tee -a "$REPORT"

while IFS=$'\t' read -r FULL_NAME IS_FORK DEFAULT_BRANCH IS_PRIVATE; do
  REPO_NAME="${FULL_NAME#*/}"
  REPO_DIR="$WORKDIR/$REPO_NAME"

  [[ -d "$REPO_DIR/.git" ]] || continue

  echo "" | tee -a "$REPORT"
  echo "── $FULL_NAME ──" | tee -a "$REPORT"

  # Secret scan with gitleaks
  echo "  [secrets]" | tee -a "$REPORT"
  if LEAKS=$(gitleaks detect --source "$REPO_DIR" --no-git 2>&1); then
    echo "  ✅ No secrets detected" | tee -a "$REPORT"
  else
    echo "  ❌ Secrets found:" | tee -a "$REPORT"
    echo "$LEAKS" | tee -a "$REPORT"
    VULN_FINDINGS+=("SECRETS: $FULL_NAME")
  fi

  # Python dependency audit
  REQ_FILES=$(find "$REPO_DIR" -name "requirements*.txt" -not -path "*/.git/*" 2>/dev/null)
  if [[ -n "$REQ_FILES" ]]; then
    echo "  [pip-audit]" | tee -a "$REPORT"
    while IFS= read -r REQ_FILE; do
      REL_PATH="${REQ_FILE#$REPO_DIR/}"
      echo "    $REL_PATH" | tee -a "$REPORT"
      AUDIT=$(pip-audit -r "$REQ_FILE" --no-deps -f columns 2>/dev/null \
        | grep -v "^No known" | grep -v "^Name" | grep -v "^-" || true)
      if [[ -n "$AUDIT" ]]; then
        while IFS= read -r line; do
          echo "    ❌ $line" | tee -a "$REPORT"
        done < <(echo "$AUDIT")
        VULN_FINDINGS+=("PY-VULNS: $FULL_NAME ($REL_PATH)")
      else
        echo "    ✅ No known vulnerabilities" | tee -a "$REPORT"
      fi
    done <<< "$REQ_FILES"
  fi

  # package.json audit (Node)
  PKG_FILES=$(find "$REPO_DIR" -name "package.json" \
    -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null)
  if [[ -n "$PKG_FILES" ]]; then
    echo "  [npm audit]" | tee -a "$REPORT"
    while IFS= read -r PKG_FILE; do
      PKG_DIR=$(dirname "$PKG_FILE")
      REL_PATH="${PKG_DIR#$REPO_DIR/}"
      if [[ -f "$PKG_DIR/package-lock.json" ]] || [[ -f "$PKG_DIR/yarn.lock" ]]; then
        echo "    $REL_PATH" | tee -a "$REPORT"
        NPM_OUT=$(cd "$PKG_DIR" && npm audit --json 2>/dev/null \
          | jq -r '.vulnerabilities | to_entries[] | "\(.value.severity) \(.key)"' 2>/dev/null || true)
        if [[ -n "$NPM_OUT" ]]; then
          while IFS= read -r line; do
            echo "    ❌ $line" | tee -a "$REPORT"
          done < <(echo "$NPM_OUT")
          VULN_FINDINGS+=("NPM-VULNS: $FULL_NAME ($REL_PATH)")
        else
          echo "    ✅ No known vulnerabilities" | tee -a "$REPORT"
        fi
      fi
    done <<< "$PKG_FILES"
  fi

done <<< "$REPOS"

# ── 4. Summary ────────────────────────────────────────────────────────────────
echo "" | tee -a "$REPORT"
echo "════════════════════════════════" | tee -a "$REPORT"
echo "  SUMMARY" | tee -a "$REPORT"
echo "════════════════════════════════" | tee -a "$REPORT"

if [[ ${#CLONE_ERRORS[@]} -gt 0 ]]; then
  echo "Clone failures (${#CLONE_ERRORS[@]}):" | tee -a "$REPORT"
  printf '  - %s\n' "${CLONE_ERRORS[@]}" | tee -a "$REPORT"
fi

if [[ ${#SYNC_ERRORS[@]} -gt 0 ]]; then
  echo "Fork sync failures (${#SYNC_ERRORS[@]}):" | tee -a "$REPORT"
  printf '  - %s\n' "${SYNC_ERRORS[@]}" | tee -a "$REPORT"
fi

if [[ ${#VULN_FINDINGS[@]} -gt 0 ]]; then
  echo "Repos with findings (${#VULN_FINDINGS[@]}):" | tee -a "$REPORT"
  printf '  - %s\n' "${VULN_FINDINGS[@]}" | tee -a "$REPORT"
else
  echo "✅ No security findings across all repos" | tee -a "$REPORT"
fi

echo "" | tee -a "$REPORT"
echo "Full report saved to: $REPORT" | tee -a "$REPORT"

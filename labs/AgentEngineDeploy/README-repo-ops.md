# Bulk repo copy, fork sync & vulnerability scan

Scripts to clone every repo for a GitHub user into a local folder, sync all
forks to their upstreams, scan for vulnerabilities, and optionally auto-fix
dependency CVEs.

| Script                | Platform            | Use                                   |
|-----------------------|---------------------|---------------------------------------|
| `fix-all-repos.ps1`   | Windows PowerShell  | Native Windows (`C:\Users\...`)        |
| `fix-all-repos.sh`    | Linux / macOS / WSL | Bash environments                      |

## Windows (PowerShell)

Creates the copy at `C:\Users\abamb\projects` by default.

### 1. Install prerequisites

```powershell
winget install --id GitHub.cli
winget install --id Git.Git
winget install --id OpenJS.NodeJS        # for npm audit (optional)
winget install --id gitleaks.gitleaks    # for secret scan (optional)
pip install pip-audit                     # for Python CVE scan (optional)
```

Missing optional scanners are simply skipped — the script still clones and syncs.

### 2. Authenticate

```powershell
gh auth login
```

### 3. Run

```powershell
# Clone + sync forks + scan (report only)
.\fix-all-repos.ps1

# Same, plus auto-apply dependency fixes (pip-audit --fix / npm audit fix)
.\fix-all-repos.ps1 -Fix

# Custom location / user
.\fix-all-repos.ps1 -ProjectsDir 'D:\work\repos' -GithubUser avnit
```

If PowerShell blocks the script, allow it for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

A timestamped `security-report-*.txt` is written to the projects folder.

## Linux / macOS / WSL (Bash)

```bash
chmod +x fix-all-repos.sh
./fix-all-repos.sh
```

## Notes

- Forks are synced with `gh repo sync`; conflicts are reported, not forced.
- `-Fix` creates dependency updates in place — review and commit per repo before pushing.
- This repo's own CVE remediation lives in `requirements.txt`; 6 starlette CVEs
  remain blocked upstream by `google-adk` (`starlette<1`).

<#
.SYNOPSIS
    Clones every repo for a GitHub user into a local projects folder, syncs
    forks to their upstreams, scans each repo for vulnerabilities, and
    optionally auto-applies dependency fixes.

.DESCRIPTION
    Windows-native (PowerShell) counterpart to fix-all-repos.sh. Creates a
    working copy of all repos under -ProjectsDir (default C:\Users\abamb\projects),
    then runs security scans:
      - gitleaks   : secret detection        (optional, skipped if not installed)
      - pip-audit  : Python dependency CVEs   (optional)
      - npm audit  : Node dependency CVEs     (optional)
    A timestamped report is written to the projects folder.

.PARAMETER GithubUser
    GitHub owner whose repos are cloned. Default: avnit

.PARAMETER ProjectsDir
    Local folder to hold all clones. Default: C:\Users\abamb\projects

.PARAMETER Fix
    When set, runs 'pip-audit --fix' and 'npm audit fix' to auto-remediate
    vulnerable dependencies in place (creates a branch per repo).

.EXAMPLE
    # Just clone + sync + scan (report only)
    .\fix-all-repos.ps1

.EXAMPLE
    # Clone + sync + scan + auto-fix dependencies
    .\fix-all-repos.ps1 -Fix

.NOTES
    Prerequisites (install what you have; missing scanners are skipped):
      - GitHub CLI     : winget install --id GitHub.cli
      - Git            : winget install --id Git.Git
      - Python+pip-audit : pip install pip-audit
      - Node/npm       : winget install --id OpenJS.NodeJS
      - gitleaks       : winget install --id gitleaks.gitleaks
    Authenticate first:  gh auth login
#>

[CmdletBinding()]
param(
    [string]$GithubUser  = 'avnit',
    [string]$ProjectsDir = 'C:\Users\abamb\projects',
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'

function Test-Cmd([string]$name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Write-Both([string]$msg, [string]$report) {
    Write-Host $msg
    Add-Content -Path $report -Value $msg
}

# --- Prerequisites -----------------------------------------------------------
if (-not (Test-Cmd 'gh'))  { Write-Error 'GitHub CLI (gh) not found. Install: winget install --id GitHub.cli'; exit 1 }
if (-not (Test-Cmd 'git')) { Write-Error 'git not found. Install: winget install --id Git.Git'; exit 1 }

# Optional scanners — record availability, don't fail if missing.
$HasGitleaks = Test-Cmd 'gitleaks'
$HasPipAudit = Test-Cmd 'pip-audit'
$HasNpm      = Test-Cmd 'npm'

# Verify gh auth
gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Write-Error 'Not authenticated. Run: gh auth login'; exit 1 }

# --- Setup -------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $ProjectsDir "security-report-$stamp.txt"
New-Item -ItemType File -Force -Path $report | Out-Null

Write-Both "==============================================" $report
Write-Both "  Repo copy + fork sync + vulnerability scan"  $report
Write-Both "  User:     $GithubUser"                        $report
Write-Both "  Location: $ProjectsDir"                       $report
Write-Both "  Auto-fix: $($Fix.IsPresent)"                  $report
Write-Both "  Scanners: gitleaks=$HasGitleaks pip-audit=$HasPipAudit npm=$HasNpm" $report
Write-Both "==============================================" $report

# --- 1. Fetch repo list ------------------------------------------------------
Write-Both "`n> Fetching repo list for @$GithubUser ..." $report
$reposJson = gh repo list $GithubUser --limit 200 `
    --json 'nameWithOwner,isFork,defaultBranchRef' | ConvertFrom-Json

if (-not $reposJson) { Write-Error "No repos returned for $GithubUser"; exit 1 }
Write-Both "  Found $($reposJson.Count) repos" $report

$cloneErrors = @()
$syncErrors  = @()
$findings    = @()

# --- 2. Clone / update + sync forks -----------------------------------------
foreach ($r in $reposJson) {
    $full   = $r.nameWithOwner
    $name   = $full.Split('/')[-1]
    $branch = if ($r.defaultBranchRef) { $r.defaultBranchRef.name } else { 'main' }
    $dir    = Join-Path $ProjectsDir $name

    Write-Both "`n--- $full (fork=$($r.isFork), branch=$branch) ---" $report

    if (Test-Path (Join-Path $dir '.git')) {
        Write-Both "  updating..." $report
        git -C $dir fetch --all -q 2>$null
        git -C $dir pull origin $branch -q 2>$null
    }
    else {
        Write-Both "  cloning..." $report
        gh repo clone $full $dir -- -q 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Both "  ERROR: clone failed" $report
            $cloneErrors += $full
            continue
        }
    }

    if ($r.isFork) {
        Write-Both "  syncing fork to upstream..." $report
        gh repo sync $full --branch $branch 2>$null
        if ($LASTEXITCODE -eq 0) {
            git -C $dir pull origin $branch -q 2>$null
            Write-Both "  OK: fork synced" $report
        }
        else {
            Write-Both "  WARN: fork sync failed (upstream conflicts?)" $report
            $syncErrors += $full
        }
    }
}

# --- 3. Security scans (+ optional fixes) -----------------------------------
Write-Both "`n================================" $report
Write-Both "  SECURITY SCAN RESULTS"           $report
Write-Both "================================"   $report

foreach ($r in $reposJson) {
    $full = $r.nameWithOwner
    $name = $full.Split('/')[-1]
    $dir  = Join-Path $ProjectsDir $name
    if (-not (Test-Path (Join-Path $dir '.git'))) { continue }

    Write-Both "`n-- $full --" $report

    # 3a. Secret scan
    if ($HasGitleaks) {
        $leaks = gitleaks detect --source $dir --no-git -q 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Both "  [secrets] none detected" $report
        }
        else {
            Write-Both "  [secrets] FOUND:" $report
            Write-Both ($leaks | Out-String) $report
            $findings += "SECRETS: $full"
        }
    }

    # 3b. Python dependency audit
    if ($HasPipAudit) {
        $reqFiles = Get-ChildItem -Path $dir -Recurse -Filter 'requirements*.txt' `
            -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\\.git\\' }
        foreach ($req in $reqFiles) {
            $rel = $req.FullName.Substring($dir.Length).TrimStart('\')
            Write-Both "  [pip-audit] $rel" $report
            $audit = pip-audit -r $req.FullName --no-deps 2>&1 | Out-String
            if ($audit -match 'No known vulnerabilities') {
                Write-Both "    none" $report
            }
            else {
                Write-Both "    $audit" $report
                $findings += "PY-VULNS: $full ($rel)"
                if ($Fix) {
                    Write-Both "    applying pip-audit --fix ..." $report
                    pip-audit -r $req.FullName --fix 2>&1 | Out-String | ForEach-Object { Add-Content $report $_ }
                }
            }
        }
    }

    # 3c. Node dependency audit
    if ($HasNpm) {
        $pkgFiles = Get-ChildItem -Path $dir -Recurse -Filter 'package.json' `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\\.git\\' }
        foreach ($pkg in $pkgFiles) {
            $pkgDir = Split-Path $pkg.FullName -Parent
            $hasLock = (Test-Path (Join-Path $pkgDir 'package-lock.json')) -or `
                       (Test-Path (Join-Path $pkgDir 'yarn.lock'))
            if (-not $hasLock) { continue }
            $rel = $pkgDir.Substring($dir.Length).TrimStart('\')
            Write-Both "  [npm audit] $rel" $report
            Push-Location $pkgDir
            $npmOut = npm audit 2>&1 | Out-String
            if ($npmOut -match 'found 0 vulnerabilities') {
                Write-Both "    none" $report
            }
            else {
                Write-Both "    $npmOut" $report
                $findings += "NPM-VULNS: $full ($rel)"
                if ($Fix) {
                    Write-Both "    applying npm audit fix ..." $report
                    npm audit fix 2>&1 | Out-String | ForEach-Object { Add-Content $report $_ }
                }
            }
            Pop-Location
        }
    }
}

# --- 4. Summary --------------------------------------------------------------
Write-Both "`n================================" $report
Write-Both "  SUMMARY"                          $report
Write-Both "================================"   $report

if ($cloneErrors.Count) {
    Write-Both "Clone failures ($($cloneErrors.Count)):" $report
    $cloneErrors | ForEach-Object { Write-Both "  - $_" $report }
}
if ($syncErrors.Count) {
    Write-Both "Fork sync failures ($($syncErrors.Count)):" $report
    $syncErrors | ForEach-Object { Write-Both "  - $_" $report }
}
if ($findings.Count) {
    Write-Both "Repos with findings ($($findings.Count)):" $report
    $findings | ForEach-Object { Write-Both "  - $_" $report }
}
else {
    Write-Both "No security findings across all repos." $report
}

Write-Both "`nFull report: $report" $report

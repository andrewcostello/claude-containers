# bootstrap-windows.ps1 — Stage 1: Install prerequisites for claude-containers on Windows
# Run from PowerShell (Admin recommended):
#   Set-ExecutionPolicy -Scope Process Bypass; .\bootstrap-windows.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== claude-containers: Windows Bootstrap ===" -ForegroundColor Cyan
Write-Host "This installs the prerequisites needed to run claude-containers."
Write-Host ""

# Check for admin privileges (WSL install requires elevation)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "WARNING: Some operations (WSL install) require admin privileges." -ForegroundColor Yellow
    Write-Host "Consider re-running as Administrator if installs fail." -ForegroundColor Yellow
    Write-Host ""
}

# Check winget is available (ships with Windows 11)
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: winget is not available. Install 'App Installer' from the Microsoft Store." -ForegroundColor Red
    exit 1
}

$restartNeeded = $false

# ── 1. WSL2 ──────────────────────────────────────────────────────────────────
Write-Host "--- WSL2 ---" -ForegroundColor Yellow

$wslInstalled = $false
try {
    $wslOutput = wsl --status 2>&1 | Out-String
    if ($wslOutput -match "Default Distribution|Default Version") {
        $wslInstalled = $true
    }
} catch {}

if ($wslInstalled) {
    Write-Host "  WSL2 is already installed." -ForegroundColor Green
} else {
    Write-Host "  Installing WSL2 (required by Docker Desktop)..."
    wsl --install --no-distribution
    $restartNeeded = $true
    Write-Host "  WSL2 installed." -ForegroundColor Green
}

# ── 2. Git for Windows ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- Git for Windows ---" -ForegroundColor Yellow

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = git --version
    Write-Host "  Already installed: $gitVersion" -ForegroundColor Green
} else {
    Write-Host "  Installing Git for Windows..."
    winget install --id Git.Git --accept-source-agreements --accept-package-agreements
    Write-Host "  Git installed. You may need to restart your terminal." -ForegroundColor Green
}

# ── 3. Docker Desktop ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- Docker Desktop ---" -ForegroundColor Yellow

if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dockerVersion = docker --version
    Write-Host "  Already installed: $dockerVersion" -ForegroundColor Green
} else {
    Write-Host "  Installing Docker Desktop..."
    winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
    $restartNeeded = $true
    Write-Host "  Docker Desktop installed." -ForegroundColor Green
    Write-Host "  NOTE: Docker Desktop needs a logout/restart to finish setup." -ForegroundColor Yellow
}

# ── 4. Claude Code ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- Claude Code ---" -ForegroundColor Yellow

if (Get-Command claude -ErrorAction SilentlyContinue) {
    $claudeVersion = claude --version 2>&1 | Select-Object -First 1
    Write-Host "  Already installed: $claudeVersion" -ForegroundColor Green
} else {
    Write-Host "  Installing Claude Code..."
    winget install --id Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements
    Write-Host "  Claude Code installed." -ForegroundColor Green
}

# ── 5. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Bootstrap complete ===" -ForegroundColor Cyan
Write-Host ""

if ($restartNeeded) {
    Write-Host "ACTION REQUIRED: Restart your computer to finish WSL2/Docker setup." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "After restart:" -ForegroundColor White
} else {
    Write-Host "Next steps:" -ForegroundColor White
}

Write-Host "  1. Open Docker Desktop and wait for it to start"
Write-Host "  2. Open Git Bash"
Write-Host "  3. Run:"
Write-Host ""
Write-Host "     cd ~/Project/claude-containers" -ForegroundColor Green
Write-Host "     bash windows-setup.sh" -ForegroundColor Green
Write-Host ""

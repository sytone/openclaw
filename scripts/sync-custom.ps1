#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Syncs the custom/jon-mods branch with upstream openclaw, rebuilds, and updates.

.DESCRIPTION
    1. Stashes any uncommitted work on custom/jon-mods
    2. Switches to main, fetches upstream, rebases main on upstream/main
    3. Pushes main to origin
    4. Switches back to custom/jon-mods, rebases on main
    5. Builds (pnpm install + pnpm ui:build)
    6. Optionally runs openclaw update --channel dev

.PARAMETER SkipUpdate
    Skip the final openclaw update --channel dev step.

.PARAMETER SkipBuild
    Skip pnpm install and ui:build (useful for quick rebase-only checks).

.PARAMETER DryRun
    Show what would happen without making changes.

.EXAMPLE
    .\scripts\sync-custom.ps1
    .\scripts\sync-custom.ps1 -SkipUpdate
    .\scripts\sync-custom.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [switch]$SkipUpdate,
    [switch]$SkipBuild,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-Step($msg) { Write-Host "`n▶ $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  ✗ $msg" -ForegroundColor Red }

Push-Location $repoRoot
try {
    $customBranch = 'custom/jon-mods'
    $currentBranch = (git rev-parse --abbrev-ref HEAD 2>&1).Trim()

    Write-Step "Starting sync (current branch: $currentBranch)"

    if ($DryRun) {
        Write-Warn "DRY RUN — no changes will be made"
        Write-Host ""
        Write-Host "  Would: stash uncommitted changes (if any)"
        Write-Host "  Would: checkout main, fetch upstream, rebase main on upstream/main"
        Write-Host "  Would: push main to origin"
        Write-Host "  Would: checkout $customBranch, rebase on main"
        if (-not $SkipBuild) { Write-Host "  Would: pnpm install + pnpm ui:build" }
        if (-not $SkipUpdate) { Write-Host "  Would: openclaw update --channel dev" }
        Write-Host ""
        return
    }

    # --- Stash uncommitted work ---
    Write-Step "Checking for uncommitted changes"
    $status = git status --porcelain 2>&1
    $didStash = $false
    if ($status) {
        Write-Warn "Uncommitted changes detected — stashing"
        git stash push -m "sync-custom: auto-stash before rebase $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1
        $didStash = $true
        Write-Ok "Stashed"
    } else {
        Write-Ok "Working tree clean"
    }

    # --- Sync main with upstream ---
    Write-Step "Syncing main with upstream"
    git checkout main 2>&1
    git fetch upstream 2>&1
    Write-Ok "Fetched upstream"

    $mainBefore = (git rev-parse HEAD).Substring(0, 8)
    $rebaseResult = git rebase upstream/main 2>&1
    $mainAfter = (git rev-parse HEAD).Substring(0, 8)

    if ($mainBefore -eq $mainAfter) {
        Write-Ok "main already up to date ($mainAfter)"
    } else {
        Write-Ok "main rebased: $mainBefore → $mainAfter"
    }

    # Push main to origin (your fork)
    Write-Step "Pushing main to origin"
    git push origin main 2>&1
    Write-Ok "Pushed"

    # --- Rebase custom branch on main ---
    Write-Step "Rebasing $customBranch on main"
    git checkout $customBranch 2>&1
    $customBefore = (git rev-parse HEAD).Substring(0, 8)

    try {
        $rebaseOut = git rebase main 2>&1
        $customAfter = (git rev-parse HEAD).Substring(0, 8)

        if ($customBefore -eq $customAfter) {
            Write-Ok "$customBranch already up to date ($customAfter)"
        } else {
            Write-Ok "$customBranch rebased: $customBefore → $customAfter"
        }
    }
    catch {
        Write-Fail "Rebase conflict! Resolve manually:"
        Write-Host "  git rebase --continue   (after fixing conflicts)"
        Write-Host "  git rebase --abort       (to undo)"
        throw "Rebase of $customBranch failed — resolve conflicts manually"
    }

    # --- Build ---
    if (-not $SkipBuild) {
        Write-Step "Installing dependencies"
        pnpm install 2>&1
        Write-Ok "pnpm install complete"

        Write-Step "Building Control UI"
        pnpm ui:build 2>&1
        Write-Ok "ui:build complete"
    } else {
        Write-Warn "Skipping build (--SkipBuild)"
    }

    # --- Update ---
    if (-not $SkipUpdate) {
        Write-Step "Running openclaw update --channel dev"
        openclaw update --channel dev 2>&1
        Write-Ok "Update complete"
    } else {
        Write-Warn "Skipping update (--SkipUpdate)"
    }

    # --- Restore stash ---
    if ($didStash) {
        Write-Step "Restoring stashed changes"
        git stash pop 2>&1
        Write-Ok "Stash restored"
    }

    Write-Host ""
    Write-Ok "Sync complete! You're on $customBranch ✨"
    Write-Host ""

} catch {
    Write-Fail $_.Exception.Message
    exit 1
} finally {
    Pop-Location
}

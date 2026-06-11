<#
.SYNOPSIS
    Install EPICS skills to AI coding assistants.

.DESCRIPTION
    Installs EPICS skill directories to the correct location for
    Claude Code, OpenCode, Gemini CLI, or Codex CLI.

.PARAMETER Target
    Which tool to install for: claude, opencode, gemini, codex, or all.

.PARAMETER Scope
    Install scope: Global (user-level, default) or Project.

.PARAMETER ProjectPath
    Path to project when Scope is Project.

.PARAMETER Method
    Install method: Copy (default), Symlink, or Clone.

.EXAMPLE
    .\install.ps1 claude

.EXAMPLE
    .\install.ps1 -ProjectPath ~\my-ioc claude

.EXAMPLE
    .\install.ps1 -Method Symlink opencode

.EXAMPLE
    .\install.ps1 all
#>

param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('claude', 'opencode', 'gemini', 'codex', 'all')]
    [string]$Target,

    [ValidateSet('Global', 'Project')]
    [string]$Scope = 'Global',

    [string]$ProjectPath = '',

    [ValidateSet('Copy', 'Symlink', 'Clone')]
    [string]$Method = 'Copy'
)

$ErrorActionPreference = 'Stop'

# ── Target directory map ──────────────────────────────────────
$HomeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }

$GlobalDirs = @{
    claude   = Join-Path $HomeDir '.claude\skills'
    opencode = Join-Path $HomeDir '.config\opencode\skills'
    gemini   = Join-Path $HomeDir '.gemini\skills'
    codex    = Join-Path $HomeDir '.codex\skills'
}

$ProjectSuffixes = @{
    claude   = '.claude\skills'
    opencode = '.opencode\skills'
    gemini   = '.gemini\skills'
    codex    = '.codex\skills'
}

# ── Resolve target list ───────────────────────────────────────
$AllTargets = @('claude', 'opencode', 'gemini', 'codex')
$Targets = if ($Target -eq 'all') { $AllTargets } else { @($Target) }

# ── Warn about Symlink method on Windows ──────────────────────
if ($Method -eq 'Symlink' -and $IsWindows) {
    Write-Warning "Symlink on Windows may require Administrator privileges or Developer Mode."
    Write-Warning "If symlink creation fails, re-run with -Method Copy."
}

# ── Find source skills directory ──────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = (Resolve-Path $ScriptDir).Path

$SkillCount = @(Get-ChildItem -Path $SourceDir -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'SKILL.md')
}).Count

if ($SkillCount -eq 0) {
    Write-Error "No SKILL.md files found. Run this script from the epics-skills repo root."
    exit 1
}

# ── Resolve destination directory ─────────────────────────────
function Get-DestinationDir {
    param([string]$T)
    if ($Scope -eq 'Project') {
        if (-not $ProjectPath) {
            Write-Error "--project requires a path. Use -ProjectPath <path>."
            exit 1
        }
        return Join-Path $ProjectPath $ProjectSuffixes[$T]
    }
    return $GlobalDirs[$T]
}

# ── Install-Clone ─────────────────────────────────────────────
function Install-Clone {
    param([string]$Dest)
    if (Test-Path (Join-Path $Dest '.git')) {
        Write-Host "  $(Symbol arrow) Git repo exists, pulling latest..."
        Push-Location $Dest
        try {
            git pull --ff-only 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "  git pull failed; continuing"
            }
        } finally { Pop-Location }
    } else {
        Write-Host "  $(Symbol arrow) Cloning repo..."
        if (Test-Path $Dest) {
            Write-Warning "  Removing existing non-git directory: $Dest"
            Remove-Item -Recurse -Force $Dest
        }
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent)

        Push-Location $SourceDir
        try {
            $Remote = (git remote get-url origin 2>$null) -replace "`n|`r", ''
        } finally { Pop-Location }

        if ($Remote) {
            git clone $Remote $Dest
            if ($LASTEXITCODE -ne 0) {
                throw "git clone failed"
            }
        } else {
            Write-Host "  $(Symbol arrow) No git remote; copying instead"
            Copy-Item -Recurse $SourceDir $Dest
            Push-Location $Dest
            try {
                git init 2>&1 | Out-Null
                git add . 2>&1 | Out-Null
                git commit -m "Initial import" 2>&1 | Out-Null
            } finally { Pop-Location }
        }
    }
}

# ── Install one target ────────────────────────────────────────
function Install-Target {
    param([string]$T)

    $Dest = Get-DestinationDir -T $T

    Write-Host ''
    Write-Host ('━' * 54)
    Write-Host "Installing to: $T"
    Write-Host "  Destination: $Dest"
    Write-Host "  Method:      $Method"
    Write-Host "  Scope:       $Scope"

    # Clone method — delegate to separate function
    if ($Method -eq 'Clone') {
        Install-Clone -Dest $Dest
        Write-Host "  $(Symbol check) Done ($T)"
        return
    }

    # Ensure destination directory
    $null = New-Item -ItemType Directory -Force -Path $Dest

    # Install each skill
    $Count = 0
    $SkillDirs = Get-ChildItem -Path $SourceDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'SKILL.md')
    }

    foreach ($SkillDir in $SkillDirs) {
        $SkillName = $SkillDir.Name
        $TargetSkillDir = Join-Path $Dest $SkillName

        switch ($Method) {
            'Copy' {
                if (Test-Path $TargetSkillDir) {
                    Remove-Item -Recurse -Force $TargetSkillDir
                }
                Copy-Item -Recurse $SkillDir.FullName $TargetSkillDir
            }
            'Symlink' {
                if (Test-Path $TargetSkillDir) {
                    Remove-Item -Recurse -Force $TargetSkillDir
                }
                if ($IsWindows) {
                    New-Item -ItemType SymbolicLink -Path $TargetSkillDir -Target $SkillDir.FullName -Force | Out-Null
                } else {
                    $null = ln -s $SkillDir.FullName $TargetSkillDir 2>&1
                }
            }
        }
        $Count++
    }

    Write-Host "  $(Symbol check) Installed $Count skills ($T)"
}

# ── Symbols (Unicode-safe fallback) ───────────────────────────
function Symbol {
    param([string]$Name)
    $map = @{
        check = if ($IsWindows) { '+' } else { '✔' }
        arrow = if ($IsWindows) { '>' } else { '→' }
    }
    return $map[$Name]
}

# ── Run ───────────────────────────────────────────────────────
foreach ($T in $Targets) {
    Install-Target -T $T
}

Write-Host ''
Write-Host ('━' * 54)
Write-Host 'Installation complete.'
Write-Host ''
Write-Host 'Restart your AI coding assistant to pick up the new skills.'
Write-Host ''
Write-Host 'To verify:'
foreach ($T in $Targets) {
    $VerifyDir = Get-DestinationDir -T $T
    Write-Host "  Get-ChildItem `"$VerifyDir\*\SKILL.md`""
}

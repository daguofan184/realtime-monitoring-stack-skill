#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Install the realtime-monitoring-stack AI skills.

.DESCRIPTION
  Links (or copies) every skill in this repository into an AI tool's skill
  discovery root, then verifies the result. Idempotent: safe to re-run, and
  re-running is how you update after a `git pull`.

  This file is pure ASCII on purpose. Windows PowerShell 5.1 parses a
  BOM-less UTF-8 script as ANSI, which turns non-ASCII text into mojibake and
  can shift the parsing. Do not add Chinese to this file; put it in README.md.

.PARAMETER Scope
  user     -> %USERPROFILE%\.dsh\skills      (default; works in every project)
  project  -> .\.dsh\skills                  (only sessions started here)
  custom   -> the path given via -Target

.PARAMETER Target
  Explicit destination root. Required when -Scope custom.

.PARAMETER Copy
  Copy the skills instead of linking them. Use when links are not available
  (some sync tools, some containers). Downside: updates need a re-run.

.PARAMETER Uninstall
  Remove what this script installed. Links are deleted non-recursively so the
  real skill files are never touched.

.EXAMPLE
  irm https://raw.githubusercontent.com/daguofan184/realtime-monitoring-stack-skill/main/install.ps1 | iex

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -Scope project

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
  [ValidateSet('user', 'project', 'custom')]
  [string]$Scope = 'user',
  [string]$Target = '',
  [switch]$Copy,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$RepoUrl  = 'https://github.com/daguofan184/realtime-monitoring-stack-skill.git'
$CacheDir = Join-Path $env:USERPROFILE '.dsh\skill-src\realtime-monitoring-stack-skill'

function Write-Step($msg) { Write-Host "  $msg" }
function Write-Head($msg) { Write-Host ''; Write-Host $msg }

# ---------------------------------------------------------------- source
# Running from a clone -> use it in place. Piped through iex -> no script dir,
# so clone into a stable cache directory first.
$src = ''
if ($PSScriptRoot) {
  $candidate = Get-ChildItem $PSScriptRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
  if ($candidate) { $src = $PSScriptRoot }
}

if (-not $src) {
  Write-Head 'Fetching the skills'
  if (Test-Path (Join-Path $CacheDir '.git')) {
    Write-Step "Updating $CacheDir"
    git -C $CacheDir pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "git pull failed in $CacheDir" }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $CacheDir -Parent) | Out-Null
    Write-Step "Cloning into $CacheDir"
    git clone --depth 1 $RepoUrl $CacheDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed. Is git installed and on PATH?" }
  }
  $src = $CacheDir
}

$skills = Get-ChildItem $src -Directory |
  Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
if (-not $skills) { throw "No <name>\SKILL.md found in $src" }

# ---------------------------------------------------------------- target
switch ($Scope) {
  'user'    { $root = Join-Path $env:USERPROFILE '.dsh\skills' }
  'project' { $root = Join-Path (Get-Location).Path '.dsh\skills' }
  'custom'  {
    if (-not $Target) { throw '-Scope custom needs -Target <path>' }
    $root = $Target
  }
}

Write-Head "Source : $src"
Write-Step "Skills : $($skills.Count)  ($(($skills.Name) -join ', '))"
Write-Step "Target : $root"
Write-Step "Mode   : $(if ($Copy) { 'copy' } else { 'link (junction)' })"

function Remove-Link([string]$path) {
  # A junction/symlink must be deleted NON-recursively. "Remove-Item -Recurse"
  # can follow the link and wipe the real skill files behind it.
  $item = Get-Item $path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return }
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    [System.IO.Directory]::Delete($path, $false)
  } else {
    Remove-Item $path -Recurse -Force
  }
}

if ($Uninstall) {
  Write-Head 'Uninstalling'
  foreach ($s in $skills) {
    $dest = Join-Path $root $s.Name
    if (Test-Path $dest) { Remove-Link $dest; Write-Step "removed  $($s.Name)" }
    else { Write-Step "absent   $($s.Name)" }
  }
  Write-Head 'Done.'
  exit 0
}

# ---------------------------------------------------------------- install
New-Item -ItemType Directory -Force -Path $root | Out-Null

Write-Head 'Installing'
foreach ($s in $skills) {
  $dest = Join-Path $root $s.Name
  if (Test-Path $dest) { Remove-Link $dest }
  if ($Copy) {
    Copy-Item $s.FullName $dest -Recurse -Force
  } else {
    New-Item -ItemType Junction -Path $dest -Target $s.FullName | Out-Null
  }
  $ok = Test-Path (Join-Path $dest 'SKILL.md')
  Write-Step ("{0,-24} {1}" -f $s.Name, $(if ($ok) { 'OK' } else { 'FAILED' }))
}

# ---------------------------------------------------------------- verify
Write-Head 'Verify'
$bad = 0
foreach ($s in $skills) {
  $f = Join-Path (Join-Path $root $s.Name) 'SKILL.md'
  if (-not (Test-Path $f)) { $bad++; continue }
  $raw = Get-Content $f -Raw -Encoding UTF8
  $name = ''
  if ($raw -match '(?m)^name:\s*(.+?)\s*$') { $name = $Matches[1].Trim() }
  $desc = ($raw -match '(?m)^description:\s*.+$')
  $verdict = @()
  if ($name -ne $s.Name) { $verdict += "name mismatch ($name)" }
  if (-not $desc)        { $verdict += 'missing description' }
  if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $verdict += 'has BOM' }
  Write-Step ("{0,-24} {1}" -f $s.Name, $(if ($verdict.Count) { 'WARN: ' + ($verdict -join '; ') } else { 'frontmatter OK' }))
}

Write-Head 'Done.'
if ($bad) { Write-Step "$bad skill(s) did not land. Check the target path." }
Write-Host ''
Write-Host '  Start a NEW session in your AI tool and look for these in its skill catalog:'
foreach ($s in $skills) { Write-Host "    - $($s.Name)" }
Write-Host ''
Write-Host '  Not showing up? Check, in order:'
Write-Host '    1. the tool actually supports skills (some presets/profiles do not)'
Write-Host '    2. -Scope project only applies to sessions started in this directory'
Write-Host '    3. the link still resolves: Test-Path <root>\<name>\SKILL.md'
Write-Host ''

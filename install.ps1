# Link (or copy) the kit's skills and rules file into user-level tool folders.
# Usage: install.ps1 [-Action install|uninstall|status] [-Copy] [-UserHome <path>]
# Windows PowerShell 5.1 compatible. -NoSymlink is a test switch that simulates file symlink failure.
# Only -Action is positional; anything else unknown or extra lands in $Rest and is rejected.
[CmdletBinding(PositionalBinding = $false)]
param(
	[Parameter(Position = 0)][string]$Action = 'install',
	[switch]$Copy,
	[string]$UserHome,
	[switch]$NoSymlink,
	[Parameter(ValueFromRemainingArguments = $true)]$Rest
)

$Usage = 'usage: install.ps1 [-Action install|uninstall|status] [-Copy] [-UserHome <path>]'
# pwsh -File rewrites --name to -name before binding, so check the raw arguments after the script path.
$Dashed = $false
$AfterScript = $false
foreach ($a in [Environment]::GetCommandLineArgs()) {
	if ($AfterScript -and $a.StartsWith('--')) { $Dashed = $true }
	if ($a -like '*install.ps1') { $AfterScript = $true }
}
if ($Dashed -or $Rest.Count -gt 0 -or @('install', 'uninstall', 'status') -notcontains $Action) {
	[Console]::Error.WriteLine($Usage)
	exit 2
}
if (-not $UserHome) { $UserHome = $env:USERPROFILE }
if (-not $UserHome) { $UserHome = $HOME }

$OnWindows = $env:OS -eq 'Windows_NT'
$Mark = '<!-- adk-installed -->'
$script:Rc = 0

function P { [IO.Path]::Combine([string[]]$args) }
function Say([string]$prefix, [string]$path) { Write-Output "$prefix $path" }
function Get-Entry([string]$p) { Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
function Is-Link($i) { $i.LinkType -eq 'SymbolicLink' -or $i.LinkType -eq 'Junction' }

# Absolute link target of an item.
function Get-LinkTarget($i) {
	$t = @($i.Target)[0]
	if (-not [IO.Path]::IsPathRooted($t)) { $t = P (Split-Path -Parent $i.FullName) $t }
	return $t
}

# Physical path: resolve links in every path component (like pwd -P).
function Get-RealPath([string]$p) {
	$p = [IO.Path]::GetFullPath($p)
	$parent = Split-Path -Parent $p
	if (-not $parent) { return $p }
	$p = P (Get-RealPath $parent) (Split-Path -Leaf $p)
	$i = Get-Entry $p
	if ($i -and (Is-Link $i)) { return Get-RealPath (Get-LinkTarget $i) }
	return $p
}

$Repo = Get-RealPath $PSScriptRoot
$RulesSrc = P $Repo 'rules' 'adk.md'

# Kit-owned: link into this repo, or a copy carrying the marker (file in a dir, line in a file).
function Test-KitOwned([string]$p) {
	$i = Get-Entry $p
	if (-not $i) { return $false }
	if (Is-Link $i) {
		$sep = [string][IO.Path]::DirectorySeparatorChar
		$cmp = [StringComparison]::Ordinal
		if ($OnWindows) { $cmp = [StringComparison]::OrdinalIgnoreCase }
		return (Get-LinkTarget $i).StartsWith($Repo + $sep, $cmp)
	}
	if ($i.PSIsContainer) { return Test-Path -LiteralPath (P $p '.adk-installed') -PathType Leaf }
	return @([IO.File]::ReadAllLines($p)) -contains $Mark
}

# Delete one entry without following links; report failure through the exit code.
function Remove-Entry([string]$p, [bool]$Report = $true) {
	$i = Get-Entry $p
	try {
		if (Is-Link $i) {
			if ($i.Attributes -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($p) } else { [IO.File]::Delete($p) }
		} elseif ($i.PSIsContainer) {
			[IO.Directory]::Delete($p, $true)
		} else {
			[IO.File]::Delete($p)
		}
	} catch {
		[Console]::Error.WriteLine("error: cannot remove ${p}: $($_.Exception.Message)")
		$script:Rc = 1
		return
	}
	if ($Report) { Say removed $p }
}

# Copy a file, inserting the marker after the closing --- of frontmatter, else on line 1.
function Copy-WithMarker([string]$src, [string]$tgt) {
	$lines = New-Object System.Collections.Generic.List[string]
	$lines.AddRange([string[]][IO.File]::ReadAllLines($src))
	$at = 0
	if ($lines.Count -gt 0 -and $lines[0] -eq '---') {
		$at = $lines.Count
		for ($n = 1; $n -lt $lines.Count; $n++) { if ($lines[$n] -eq '---') { $at = $n + 1; break } }
	}
	$lines.Insert($at, $Mark)
	[IO.File]::WriteAllText($tgt, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
}

# Install one kit entry, never overwrite foreign content.
function Install-Entry([string]$src, [string]$tgt) {
	$isDir = Test-Path -LiteralPath $src -PathType Container
	$i = Get-Entry $tgt
	if (-not $Copy -and $i -and (Is-Link $i) -and (Get-LinkTarget $i) -eq $src) { Say ok $tgt; return }
	if ($i) {
		if (-not (Test-KitOwned $tgt)) { Say conflict $tgt; $script:Rc = 1; return }
		Remove-Entry $tgt $false
		if (Get-Entry $tgt) { return }
	}
	[void][IO.Directory]::CreateDirectory((Split-Path -Parent $tgt))
	if ($Copy) {
		if ($isDir) {
			Copy-Item -LiteralPath $src -Destination $tgt -Recurse -Force
			[IO.File]::WriteAllText((P $tgt '.adk-installed'), '')
		} else {
			Copy-WithMarker $src $tgt
		}
		Say copied $tgt
		return
	}
	if ($isDir) {
		$type = 'SymbolicLink'
		if ($OnWindows) { $type = 'Junction' }
		[void](New-Item -ItemType $type -Path $tgt -Target $src -ErrorAction Stop)
		Say linked $tgt
		return
	}
	# Files: symlink, else a marked copy. No hard links: git replaces files on checkout, so they go stale.
	try {
		if ($NoSymlink) { throw 'symlink disabled' }
		[void](New-Item -ItemType SymbolicLink -Path $tgt -Target $src -ErrorAction Stop)
		Say linked $tgt
		return
	} catch {}
	Copy-WithMarker $src $tgt
	Say copied "$tgt (re-run install after updates)"
}

# Remove kit-owned entries in dir (all on uninstall, stale ones on install).
function Invoke-Prune([string]$dir) {
	if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return }
	foreach ($e in @(Get-ChildItem -LiteralPath $dir -Force)) {
		$p = P $dir $e.Name
		if (-not (Test-KitOwned $p)) { continue }
		if ($Action -eq 'uninstall' -or -not (Test-Path -LiteralPath (P $Repo 'skills' $e.Name) -PathType Container)) {
			Remove-Entry $p
		}
	}
}

function Show-Status([string]$p) {
	if (-not (Get-Entry $p)) { return }
	if (Test-KitOwned $p) { Say ok $p } else { Say conflict $p; $script:Rc = 1 }
}

$SkillDirs = @((P $UserHome '.claude' 'skills'), (P $UserHome '.agents' 'skills'))
$Rules = @((P $UserHome '.claude' 'rules' 'adk.md'), (P $UserHome '.copilot' 'instructions' 'adk.instructions.md'))
$Skills = @()
$SkillsRoot = P $Repo 'skills'
if (Test-Path -LiteralPath $SkillsRoot -PathType Container) {
	$Skills = @(Get-ChildItem -LiteralPath $SkillsRoot -Directory | ForEach-Object { $_.Name })
}

switch ($Action) {
	'install' {
		foreach ($d in $SkillDirs) { Invoke-Prune $d }
		foreach ($n in $Skills) {
			foreach ($d in $SkillDirs) { Install-Entry (P $SkillsRoot $n) (P $d $n) }
		}
		foreach ($r in $Rules) { Install-Entry $RulesSrc $r }
	}
	'uninstall' {
		foreach ($d in $SkillDirs) { Invoke-Prune $d }
		foreach ($r in $Rules) {
			if ((Get-Entry $r) -and (Test-KitOwned $r)) { Remove-Entry $r }
		}
	}
	'status' {
		foreach ($n in $Skills) {
			foreach ($d in $SkillDirs) { Show-Status (P $d $n) }
		}
		foreach ($r in $Rules) { Show-Status $r }
	}
}

exit $script:Rc

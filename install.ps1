# Link (or copy) the kit's skills and rules file into user-level tool folders and register
# hooks/guard.py as a pre-tool hook for Claude Code (settings.json) and Copilot CLI.
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
# Windows PowerShell 5.1 can serialize arrays as {"value":[...],"Count":n} without this.
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }
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

# Absolute path of a Python 3 interpreter (forward slashes), or $null.
function Find-Python {
	foreach ($c in 'py -3', 'python3', 'python') {
		$parts = $c -split ' '
		if (-not (Get-Command $parts[0] -CommandType Application -ErrorAction SilentlyContinue)) { continue }
		$rest = @($parts | Select-Object -Skip 1)
		$out = & $parts[0] @rest -c 'import sys; assert sys.version_info[0] == 3; print(sys.executable)' 2>$null
		if ($LASTEXITCODE -eq 0 -and $out) { return (@($out)[0].Trim() -replace '\\', '/') }
	}
	return $null
}

function Write-Utf8([string]$p, [string]$text) {
	[void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
	[IO.File]::WriteAllText($p, $text, (New-Object Text.UTF8Encoding $false))
}

function Set-Prop($o, [string]$name, $value) {
	if ($o.PSObject.Properties[$name]) { $o.$name = $value } else { $o | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Is-Obj($o) { $o -is [Management.Automation.PSCustomObject] }

# Kit's settings entry: a hook whose command contains the quoted guard path + --tool claude.
function Test-KitHook($h) {
	if (-not (Is-Obj $h)) { return $false }
	$c = $h.PSObject.Properties['command']
	return $c -and $c.Value -is [string] -and $c.Value.Contains($ClaudeId)
}

function Write-CopilotHook([string]$cmd) {
	$hook = [pscustomobject]@{ type = 'command'; bash = $cmd; powershell = "& $cmd"; timeoutSec = 10 }
	$text = (ConvertTo-Json -InputObject ([pscustomobject]@{ version = 1; hooks = [pscustomobject]@{ preToolUse = @($hook) } }) -Depth 5) + "`n"
	if ((Test-Path -LiteralPath $CopilotHook -PathType Leaf) -and [IO.File]::ReadAllText($CopilotHook) -eq $text) { Say ok $CopilotHook; return }
	Write-Utf8 $CopilotHook $text
	Say linked $CopilotHook
}

# Merge, remove or report the kit's PreToolUse entry in ~/.claude/settings.json.
function Set-ClaudeSettings([string]$act, [string]$cmd) {
	$exists = Test-Path -LiteralPath $Settings -PathType Leaf
	if (-not $exists -and $act -ne 'install') { return }
	$data = '{}' | ConvertFrom-Json
	if ($exists) {
		try { $data = [IO.File]::ReadAllText($Settings) | ConvertFrom-Json -ErrorAction Stop } catch { $data = $null }
		if (-not (Is-Obj $data)) { Say conflict "$Settings (invalid JSON)"; $script:Rc = 1; return }
	}
	$hooks = $null
	$pre = @()
	if ($data.PSObject.Properties['hooks']) {
		$hooks = $data.hooks
		if (-not (Is-Obj $hooks)) { $pre = $null }
		elseif ($hooks.PSObject.Properties['PreToolUse']) {
			$pre = $hooks.PreToolUse
			if ($pre -isnot [array]) { $pre = $null }
		}
	}
	if ($null -eq $pre) { Say conflict "$Settings (unexpected hooks structure)"; $script:Rc = 1; return }
	$found = @()
	$rest = New-Object Collections.ArrayList
	foreach ($g in $pre) {
		if ((Is-Obj $g) -and $g.PSObject.Properties['hooks'] -and $g.hooks -is [array]) {
			$kit = @($g.hooks | Where-Object { Test-KitHook $_ })
			if ($kit.Count -gt 0) {
				$found += $kit
				$g.hooks = @($g.hooks | Where-Object { -not (Test-KitHook $_) })
				if ($g.hooks.Count -eq 0) { continue }
			}
		}
		[void]$rest.Add($g)
	}
	if ($act -eq 'status') { if ($found.Count -gt 0) { Say ok $Settings }; return }
	if ($act -eq 'install') {
		if ($found.Count -eq 1 -and $found[0].command -eq $cmd) { Say ok $Settings; return }
		[void]$rest.Add([pscustomobject]@{ matcher = 'Bash|PowerShell'; hooks = @([pscustomobject]@{ type = 'command'; command = $cmd }) })
	} elseif ($found.Count -eq 0) { return }
	if ($rest.Count -gt 0) {
		if (-not $hooks) { $hooks = '{}' | ConvertFrom-Json; Set-Prop $data 'hooks' $hooks }
		Set-Prop $hooks 'PreToolUse' $rest.ToArray()
	} elseif ($hooks) {
		$hooks.PSObject.Properties.Remove('PreToolUse')
		if (@($hooks.PSObject.Properties).Count -eq 0) { $data.PSObject.Properties.Remove('hooks') }
	}
	$backup = "$Settings.adk-backup"
	if ($exists -and -not (Test-Path -LiteralPath $backup)) { [IO.File]::Copy($Settings, $backup) }
	Write-Utf8 $Settings ((ConvertTo-Json -InputObject $data -Depth 20) + "`n")
	if ($act -eq 'install') { Say linked $Settings } else { Say removed $Settings }
}

$Guard = (P $Repo 'hooks' 'guard.py') -replace '\\', '/'
$ClaudeId = "`"$Guard`" --tool claude"
$Settings = P $UserHome '.claude' 'settings.json'
$CopilotHook = P $UserHome '.copilot' 'hooks' 'adk-guard.json'

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
		$py = Find-Python
		if ($py) {
			Write-CopilotHook "`"$py`" `"$Guard`" --tool copilot"
			Set-ClaudeSettings install "`"$py`" $ClaudeId"
		} else {
			Say conflict 'hooks (python 3 not found)'
			$script:Rc = 1
		}
	}
	'uninstall' {
		foreach ($d in $SkillDirs) { Invoke-Prune $d }
		foreach ($r in $Rules) {
			if ((Get-Entry $r) -and (Test-KitOwned $r)) { Remove-Entry $r }
		}
		if (Get-Entry $CopilotHook) { Remove-Entry $CopilotHook }
		Set-ClaudeSettings uninstall
	}
	'status' {
		foreach ($n in $Skills) {
			foreach ($d in $SkillDirs) { Show-Status (P $d $n) }
		}
		foreach ($r in $Rules) { Show-Status $r }
		if (Get-Entry $CopilotHook) { Say ok $CopilotHook }
		Set-ClaudeSettings status
	}
}

exit $script:Rc

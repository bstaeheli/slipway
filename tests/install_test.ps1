# Tests for install.ps1. Each test runs against a temp copy of the repo with a fresh user home.
# Runs under Windows PowerShell 5.1 and PowerShell 7 (Windows, macOS, Linux).
$ErrorActionPreference = 'Continue'
$Src = Split-Path -Parent $PSScriptRoot
$Exe = (Get-Process -Id $PID).Path
$OnWindows = $env:OS -eq 'Windows_NT'
$Mark = '<!-- slipway-installed -->'
$script:Fails = 0
$script:Cases = 0

function Check([string]$desc, [bool]$ok) {
	$script:Cases++
	if (-not $ok) { $script:Fails++; Write-Output "FAIL: $desc" }
}

function P { [IO.Path]::Combine([string[]]$args) }

# Physical path of a directory (temp dirs are symlinked on macOS).
function Real([string]$p) {
	if ($OnWindows) { return $p }
	return (& sh -c 'cd "$1" && pwd -P' sh $p)
}

function Setup([string]$homeName = 'home') {
	$base = [IO.Path]::GetTempPath()
	# GitHub Windows runners expose TEMP as an 8.3 short path; RUNNER_TEMP is a long path.
	if ($env:RUNNER_TEMP) { $base = $env:RUNNER_TEMP }
	$t = P $base ('slipway-test-' + [guid]::NewGuid().ToString('N'))
	[void](New-Item -ItemType Directory -Path $t)
	$script:T = Real $t
	$script:Repo = P $script:T 'repo'
	foreach ($d in 'rules', 'hooks', (P 'skills' 'slipway-a'), (P 'skills' 'slipway-b')) {
		[void](New-Item -ItemType Directory -Force -Path (P $script:Repo $d))
	}
	Copy-Item -LiteralPath (P $Src 'install.ps1') -Destination $script:Repo
	Copy-Item -LiteralPath (P $Src 'rules' 'slipway.md') -Destination (P $script:Repo 'rules')
	Copy-Item -LiteralPath (P $Src 'hooks' 'guard.py') -Destination (P $script:Repo 'hooks')
	Copy-Item -LiteralPath (P $Src 'hooks' 'install_hooks.py') -Destination (P $script:Repo 'hooks')
	Set-Text (P $script:Repo 'skills' 'slipway-a' 'SKILL.md') "a`n"
	Set-Text (P $script:Repo 'skills' 'slipway-b' 'SKILL.md') "b`n"
	$script:H = P $script:T $homeName
	[void](New-Item -ItemType Directory -Path $script:H)
}

function Set-Text([string]$p, [string]$s) { [IO.File]::WriteAllText($p, $s) }
function Get-Text([string]$p) { [IO.File]::ReadAllText($p) }

# Run <script> with args; output lines in $script:Out, exit code in $script:Rc.
function Run-Script([string]$script) {
	$a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script) + $args + @('-UserHome', $script:H)
	$script:Out = @(& $Exe @a 2>&1 | ForEach-Object { "$_" })
	$script:Rc = $LASTEXITCODE
}
function Run { Run-Script (P $script:Repo 'install.ps1') @args }

function Item([string]$p) { Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
function Exists([string]$p) { $null -ne (Item $p) }
function Is-Link([string]$p) {
	$i = Item $p
	return ($null -ne $i) -and ($i.LinkType -eq 'SymbolicLink' -or $i.LinkType -eq 'Junction')
}
function Points-To([string]$p, [string]$want) {
	if (-not (Is-Link $p)) { return $false }
	return @((Item $p).Target)[0] -eq $want
}
function Has-Line([string]$line) { $script:Out -contains $line }

# Directory link: junction on Windows, symlink elsewhere. Target must exist when created.
function New-DirLink([string]$link, [string]$target) {
	$type = 'SymbolicLink'
	if ($OnWindows) { $type = 'Junction' }
	[void](New-Item -ItemType $type -Path $link -Target $target)
}
function New-Dangling([string]$link, [string]$target) {
	[void](New-Item -ItemType Directory -Force -Path $target)
	New-DirLink $link $target
	[IO.Directory]::Delete($target)
}

function Check-Links {
	foreach ($n in 'slipway-a', 'slipway-b') {
		Check "claude skill $n" (Points-To (P $H '.claude' 'skills' $n) (P $Repo 'skills' $n))
		Check "agents skill $n" (Points-To (P $H '.agents' 'skills' $n) (P $Repo 'skills' $n))
	}
	Check 'claude rule' (Points-To (P $H '.claude' 'rules' 'slipway.md') (P $Repo 'rules' 'slipway.md'))
	Check 'copilot rule' (Points-To (P $H '.copilot' 'instructions' 'slipway.instructions.md') (P $Repo 'rules' 'slipway.md'))
	Check 'no copilot skills' (-not (Exists (P $H '.copilot' 'skills')))
}

function test_install_links_all {
	Setup
	Run
	Check-Links
}

function test_idempotent {
	Setup
	Run
	Run
	Check 'second run has no non-ok line' (@($Out | Where-Object { $_ -notlike 'ok *' }).Count -eq 0)
	Check 'second run has ok lines' (@($Out | Where-Object { $_ -like 'ok *' }).Count -gt 0)
}

function test_creates_missing_dirs {
	Setup
	Check 'HOME empty' (@(Get-ChildItem -LiteralPath $H -Force).Count -eq 0)
	Run
	Check 'install exit 0' ($Rc -eq 0)
	Check 'rules dir created' (Is-Link (P $H '.claude' 'rules' 'slipway.md'))
}

function test_conflict_not_overwritten {
	Setup
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude' 'skills' 'slipway-spec'))
	[void](New-Item -ItemType Directory -Force -Path (P $H '.agents' 'skills' 'slipway-a'))
	$f = P $H '.agents' 'skills' 'slipway-a' 'SKILL.md'
	Set-Text $f "mine`n"
	$foreign = P $T 'foreign'
	[void](New-Item -ItemType Directory -Path $foreign)
	New-DirLink (P $H '.claude' 'skills' 'slipway-a') $foreign
	Run
	Check 'exit 1' ($Rc -eq 1)
	Check 'conflict printed for dir' (Has-Line ('conflict ' + (P $H '.agents' 'skills' 'slipway-a')))
	Check 'content intact' ((Get-Text $f) -eq "mine`n")
	Check 'still real dir' (-not (Is-Link (P $H '.agents' 'skills' 'slipway-a')))
	Check 'conflict printed for foreign link' (Has-Line ('conflict ' + (P $H '.claude' 'skills' 'slipway-a')))
	Check 'foreign link kept' (Points-To (P $H '.claude' 'skills' 'slipway-a') $foreign)
	Check 'others still linked' (Points-To (P $H '.claude' 'skills' 'slipway-b') (P $Repo 'skills' 'slipway-b'))
}

function test_prune_stale_link {
	Setup
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude' 'skills'))
	[void](New-Item -ItemType Directory -Force -Path (P $H '.agents' 'skills' 'foreign-dir'))
	[void](New-Item -ItemType Directory -Force -Path (P $T 'repo-other' 'skills' 'x'))
	$gone = P $Repo 'skills' 'slipway-gone'
	[void](New-Item -ItemType Directory -Path $gone)
	New-DirLink (P $H '.claude' 'skills' 'slipway-gone') $gone
	New-DirLink (P $H '.agents' 'skills' 'slipway-gone') $gone
	[IO.Directory]::Delete($gone)
	$dangling = P $T 'foreign-gone'
	New-Dangling (P $H '.agents' 'skills' 'foreign-dangling') $dangling
	$twin = P $T 'repo-other' 'skills' 'x'
	New-DirLink (P $H '.agents' 'skills' 'prefix-twin') $twin
	Run
	Check 'removed printed' (Has-Line ('removed ' + (P $H '.claude' 'skills' 'slipway-gone')))
	Check 'link gone' (-not (Exists (P $H '.claude' 'skills' 'slipway-gone')))
	Check 'agents removed printed' (Has-Line ('removed ' + (P $H '.agents' 'skills' 'slipway-gone')))
	Check 'agents link gone' (-not (Exists (P $H '.agents' 'skills' 'slipway-gone')))
	Check 'foreign dir kept' (Test-Path -LiteralPath (P $H '.agents' 'skills' 'foreign-dir') -PathType Container)
	Check 'foreign dangling link kept' (Points-To (P $H '.agents' 'skills' 'foreign-dangling') $dangling)
	Check 'prefix-sharing link kept' (Points-To (P $H '.agents' 'skills' 'prefix-twin') $twin)
}

function test_prune_rm_failure {
	Setup
	$dir = P $H '.claude' 'skills'
	$link = P $dir 'slipway-gone'
	[void](New-Item -ItemType Directory -Force -Path $dir)
	$gone = P $Repo 'skills' 'slipway-gone'
	[void](New-Item -ItemType Directory -Path $gone)
	New-DirLink $link $gone
	[IO.Directory]::Delete($gone)
	if ($OnWindows) {
		# Deny delete on the link and delete-child on its parent for Everyone.
		[void](& icacls $dir /deny '*S-1-1-0:(DC)')
		[void](& icacls $link /L /deny '*S-1-1-0:(DE)')
	} else {
		& chmod 555 $dir
	}
	Run
	if ($OnWindows) {
		[void](& icacls $link /L /remove:d '*S-1-1-0')
		[void](& icacls $dir /remove:d '*S-1-1-0')
	} else {
		& chmod 755 $dir
	}
	Check 'rm failure exits nonzero' ($Rc -ne 0)
	Check 'no removed line on rm failure' (@($Out | Where-Object { $_ -like 'removed *' }).Count -eq 0)
	Check 'link still there' (Is-Link $link)
}

function test_symlinked_repo_path {
	Setup
	$rl = P $T 'repolink'
	New-DirLink $rl $Repo
	Run-Script (P $rl 'install.ps1')
	Check 'link uses physical repo path' (Points-To (P $H '.claude' 'skills' 'slipway-a') (P $Repo 'skills' 'slipway-a'))
	Check 'hook uses physical repo path' ((Copilot-Hook).bash.EndsWith((Guard-Id 'copilot') + ' || true'))
	Run-Script (P $rl 'install.ps1') uninstall
	Check 'uninstall via physical path' (-not (Exists (P $H '.claude' 'skills' 'slipway-a')))
}

function test_uninstall_keeps_foreign {
	Setup
	Run
	[void](New-Item -ItemType Directory -Force -Path (P $H '.agents' 'skills' 'foreign-dir'))
	New-Dangling (P $H '.agents' 'skills' 'foreign-link') (P $T 'foreign-gone')
	Run uninstall
	Check 'foreign dir kept' (Test-Path -LiteralPath (P $H '.agents' 'skills' 'foreign-dir') -PathType Container)
	Check 'foreign link kept' (Is-Link (P $H '.agents' 'skills' 'foreign-link'))
	foreach ($p in (P '.claude' 'skills' 'slipway-a'), (P '.claude' 'skills' 'slipway-b'), (P '.agents' 'skills' 'slipway-a'),
		(P '.agents' 'skills' 'slipway-b'), (P '.claude' 'rules' 'slipway.md'), (P '.copilot' 'instructions' 'slipway.instructions.md')) {
		Check "gone $p" (-not (Exists (P $H $p)))
	}
}

function test_home_with_spaces {
	Setup 'with space'
	Run
	Check-Links
}

function test_never_touches_claude_md {
	Setup
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude'))
	$f = P $H '.claude' 'CLAUDE.md'
	Set-Text $f "user notes`n"
	Run
	Check 'unchanged after install' ((Get-Text $f) -eq "user notes`n")
	Run uninstall
	Check 'unchanged after uninstall' ((Get-Text $f) -eq "user notes`n")
}

function test_copy_mode {
	Setup
	Run -Copy
	Check 'copied printed' (Has-Line ('copied ' + (P $H '.claude' 'skills' 'slipway-a')))
	foreach ($d in (P '.claude' 'skills' 'slipway-a'), (P '.agents' 'skills' 'slipway-b')) {
		Check "real dir $d" ((Test-Path -LiteralPath (P $H $d) -PathType Container) -and -not (Is-Link (P $H $d)))
		Check "marker $d" (Test-Path -LiteralPath (P $H $d '.slipway-installed') -PathType Leaf)
	}
	$rule = P $H '.claude' 'rules' 'slipway.md'
	Check 'rule is real file' ((Test-Path -LiteralPath $rule -PathType Leaf) -and -not (Is-Link $rule))
	Check 'rule marker' (@(Get-Content -LiteralPath $rule) -contains $Mark)
	Set-Text (P $Repo 'skills' 'slipway-b' 'SKILL.md') "b2`n"
	Run -Copy
	Check 'refresh exit 0' ($Rc -eq 0)
	Check 'refresh prints no removed line' (@($Out | Where-Object { $_ -like 'removed *' }).Count -eq 0)
	Check 'refreshed content' ((Get-Text (P $H '.agents' 'skills' 'slipway-b' 'SKILL.md')) -eq "b2`n")
	Run uninstall
	Check 'copies removed' (-not ((Exists (P $H '.claude' 'skills' 'slipway-a')) -or (Exists (P $H '.agents' 'skills' 'slipway-b')) -or (Exists $rule)))
}

function test_copy_mode_keeps_frontmatter {
	Setup
	$f = P $H '.copilot' 'instructions' 'slipway.instructions.md'
	Run -Copy
	$lines = @(Get-Content -LiteralPath $f)
	$close = -1
	for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $close = $i; break } }
	Check 'starts with ---' ($lines[0] -eq '---')
	Check 'applyTo in frontmatter' ($close -gt 0 -and @($lines[1..($close - 1)] | Where-Object { $_ -like 'applyTo:*' }).Count -gt 0)
	Check 'marker right after frontmatter' ($close -gt 0 -and $lines[$close + 1] -eq $Mark)
	Check 'marker not in frontmatter' ($close -gt 0 -and @($lines[0..$close] | Where-Object { $_ -like '*slipway-installed*' }).Count -eq 0)
	Run -Copy
	Check 're-run exit 0' ($Rc -eq 0)
	Check 're-run recognizes copy' (Has-Line "copied $f")
	Run uninstall
	Check 'uninstall removes copy' (-not (Exists $f))
	Run -Copy
	Set-Text $f (((1..30) -join "`n") + "`n" + (Get-Text $f))
	Run uninstall
	Check 'marker past line 20 still kit-owned' (-not (Exists $f))
	Set-Text (P $Repo 'rules' 'slipway.md') "plain`n"
	Run -Copy
	Check 'no frontmatter: marker on line 1' (@(Get-Content -LiteralPath $f)[0] -eq $Mark)
}

function test_rules_file_fallback {
	Setup
	$srcFile = P $Repo 'rules' 'slipway.md'
	$src = Get-Text $srcFile
	Run -NoSymlink
	Check 'fallback exit 0' ($Rc -eq 0)
	foreach ($f in (P $H '.claude' 'rules' 'slipway.md'), (P $H '.copilot' 'instructions' 'slipway.instructions.md')) {
		$lines = @(Get-Content -LiteralPath $f)
		Check "real file $f" ((Test-Path -LiteralPath $f -PathType Leaf) -and -not (Is-Link $f))
		Check "warning line $f" (Has-Line "copied $f (re-run install after updates)")
		Check "frontmatter intact $f" (($lines[0] -eq '---') -and ($lines[1] -like 'applyTo:*'))
		$close = -1
		for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $close = $i; break } }
		Check "marker after frontmatter $f" ($close -gt 0 -and $lines[$close + 1] -eq $Mark)
		Check "not a hard link $f" ((Get-Text $f) -ne $src)
	}
	Check 'skills still linked' (Points-To (P $H '.claude' 'skills' 'slipway-a') (P $Repo 'skills' 'slipway-a'))
	$r = P $H '.claude' 'rules' 'slipway.md'
	Set-Text $srcFile ($src + "new rule`n")
	Run -NoSymlink
	Check 'fallback re-run exit 0' ($Rc -eq 0)
	Check 'fallback re-run warns again' (Has-Line "copied $r (re-run install after updates)")
	Check 'fallback re-run refreshes' (@(Get-Content -LiteralPath $r) -contains 'new rule')
	Check 'fallback re-run prints no removed line' (@($Out | Where-Object { $_ -like 'removed *' }).Count -eq 0)
	Run uninstall
	Check 'fallback uninstall removes claude rule' (-not (Exists $r))
	Check 'fallback uninstall removes copilot rule' (-not (Exists (P $H '.copilot' 'instructions' 'slipway.instructions.md')))
	Check 'repo rule intact' ((Get-Text $srcFile) -eq ($src + "new rule`n"))
}

function test_rejects_extra_arguments {
	Setup
	$stray = P $T 'stray'
	# No -UserHome here (a stray positional must not bind to it); HOME and USERPROFILE point at the
	# temp home so a regression can never touch the real one.
	$saved = @($env:HOME, $env:USERPROFILE)
	$env:HOME = $H
	$env:USERPROFILE = $H
	foreach ($bad in @(@('install', $stray), @('install', '--copy'), @('-Bogus'))) {
		$a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (P $Repo 'install.ps1')) + $bad
		$script:Out = @(& $Exe @a 2>&1 | ForEach-Object { "$_" })
		$script:Rc = $LASTEXITCODE
		Check "exit 2 for $($bad -join ' ')" ($Rc -eq 2)
		Check "usage for $($bad -join ' ')" (@($Out | Where-Object { $_ -like 'usage:*' }).Count -eq 1)
		Check "home untouched for $($bad -join ' ')" (@('.claude', '.agents', '.copilot' | Where-Object { Exists (P $H $_) }).Count -eq 0)
		Check "nothing created for $($bad -join ' ')" (-not (Exists $stray) -and -not (Exists (P $Repo '--copy')))
	}
	$env:HOME = $saved[0]
	$env:USERPROFILE = $saved[1]
}

function test_status_output {
	Setup
	Run status
	Check 'status before install exit 0' ($Rc -eq 0)
	Check 'status before install prints nothing' ($Out.Count -eq 0)
	Run
	[IO.Directory]::Delete((P $H '.agents' 'skills' 'slipway-b'))
	$rule = P $H '.claude' 'rules' 'slipway.md'
	[IO.File]::Delete($rule)
	Set-Text $rule "mine`n"
	Run status
	Check 'status exit 1 on conflict' ($Rc -eq 1)
	$want = @(
		('ok ' + (P $H '.claude' 'skills' 'slipway-a')),
		('ok ' + (P $H '.agents' 'skills' 'slipway-a')),
		('ok ' + (P $H '.claude' 'skills' 'slipway-b')),
		"conflict $rule",
		('ok ' + (P $H '.copilot' 'instructions' 'slipway.instructions.md')),
		('ok ' + (P $H '.copilot' 'hooks' 'slipway-guard.json')),
		('ok ' + (P $H '.claude' 'settings.json')))
	Check 'status lines only for existing entries' (($Out -join "`n") -eq ($want -join "`n"))
	Check 'status changes nothing' ((Get-Text $rule) -eq "mine`n")
}

function test_zero_skills {
	Setup
	[IO.Directory]::Delete((P $Repo 'skills'), $true)
	Run
	Check 'zero skills exit 0' ($Rc -eq 0)
	Check 'zero skills: claude rule' (Points-To (P $H '.claude' 'rules' 'slipway.md') (P $Repo 'rules' 'slipway.md'))
	Check 'zero skills: copilot rule' (Points-To (P $H '.copilot' 'instructions' 'slipway.instructions.md') (P $Repo 'rules' 'slipway.md'))
	Check 'zero skills: no skill dirs' (-not (Exists (P $H '.claude' 'skills')) -and -not (Exists (P $H '.agents' 'skills')))
}

function Read-Json([string]$p) { [IO.File]::ReadAllText($p) | ConvertFrom-Json }
function Canon($o) { ConvertTo-Json -InputObject $o -Depth 20 -Compress }
function Settings-Path { P $H '.claude' 'settings.json' }
function Copilot-Path { P $H '.copilot' 'hooks' 'slipway-guard.json' }
function Copilot-Hook { @((Read-Json (Copilot-Path)).hooks.preToolUse)[0] }
# Guard path with forward slashes, quoted, plus the tool flag: the kit's command suffix.
function Guard-Path { (P $Repo 'hooks' 'guard.py') -replace '\\', '/' }
function Guard-Id([string]$tool) { '"' + (Guard-Path) + '" --tool ' + $tool }
# "<python>" "<guard>" --tool <tool>
function Is-KitRun([string]$c, [string]$tool) { $c.StartsWith('"') -and $c.EndsWith('" ' + (Guard-Id $tool)) }
# Kit hooks in settings, from any clone path.
function Kit-Hooks {
	@(@((Read-Json (Settings-Path)).hooks.PreToolUse) | ForEach-Object { @($_.hooks) } | Where-Object { $_.command -like '*/hooks/guard.py" --tool claude' })
}
# Replace the interpreter path (the first quoted string after the guard test) in a hook command.
function Without-Python([string]$c) {
	$py = [regex]::Match($c, '(?:^|\|\| |& )"([^"]+)" "').Groups[1].Value
	$c.Replace('"' + $py + '"', '"/nonexistent/python3"')
}
function Write-Orig {
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude'))
	Set-Text (Settings-Path) ($Orig + "`n")
}
$Orig = '{"model": "opus", "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "mine"}]}], "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "post"}]}]}, "env": {"A": "1"}}'

function test_hooks_written {
	Setup
	Run
	$f = Copilot-Path
	$s = Settings-Path
	Check 'copilot hook linked line' (Has-Line "linked $f")
	$c = Read-Json $f
	$h = Copilot-Hook
	Check 'copilot hook version' ($c.version -eq 1)
	Check 'copilot hook type' ($h.type -eq 'command' -and $h.timeoutSec -eq 10)
	$run = $h.bash -replace ' \|\| true$', ''
	Check 'copilot hook bash command' ((Is-KitRun $run 'copilot') -and $h.bash -eq ($run + ' || true'))
	Check 'copilot hook powershell command' ($h.powershell -eq ('if (Test-Path "' + (Guard-Path) + '") { & ' + $run + ' }; exit 0'))
	Check 'settings linked line' (Has-Line "linked $s")
	$d = Read-Json $s
	$g = @($d.hooks.PreToolUse)
	Check 'settings one group' ($g.Count -eq 1 -and $g[0].matcher -eq 'Bash|PowerShell')
	Check 'settings one hook' (@($g[0].hooks).Count -eq 1 -and $g[0].hooks[0].type -eq 'command')
	$c = $g[0].hooks[0].command
	$prefix = '[ ! -f "' + (Guard-Path) + '" ] || '
	Check 'settings kit command' ($c.StartsWith($prefix) -and (Is-KitRun $c.Substring($prefix.Length) 'claude'))
	Check 'no backup without prior settings' (-not (Exists "$s.slipway-backup"))
	Run uninstall
	Check 'kit-created settings left empty' ((Canon (Read-Json $s)) -eq '{}')
}

function test_hook_commands_run {
	Setup
	$moved = P $T 'my repo'
	[IO.Directory]::Move($Repo, $moved)
	$script:Repo = $moved
	Run
	$proj = P $T 'proj'
	[void](New-Item -ItemType Directory -Force -Path (P $proj 'docs' 'agents'))
	$cwd = $proj -replace '\\', '/'
	$deny = '{"cwd": "' + $cwd + '", "toolName": "bash", "toolArgs": {"command": "cargo publish"}, "tool_input": {"command": "cargo publish"}}'
	$allow = '{"cwd": "' + $cwd + '", "tool_input": {"command": "echo hi"}}'
	$ps = (Copilot-Hook).powershell
	$out = $deny | & $Exe -NoProfile -Command $ps
	Check 'copilot powershell hook denies publish' ((($out -join '') | ConvertFrom-Json).permissionDecision -eq 'deny')
	$c = @((Read-Json (Settings-Path)).hooks.PreToolUse)[0].hooks[0].command
	$b = (Copilot-Hook).bash
	if (-not $OnWindows) {
		[void]($deny | & sh -c $c 2>&1)
		Check 'claude hook denies publish (exit 2)' ($LASTEXITCODE -eq 2)
		[void]($allow | & sh -c $c 2>&1)
		Check 'claude hook allows echo' ($LASTEXITCODE -eq 0)
		$out = $deny | & sh -c $b
		Check 'copilot bash hook denies publish' ((($out -join '') | ConvertFrom-Json).permissionDecision -eq 'deny')
	}
	# Kit moved or deleted, Python gone: every hook command must exit 0 and print nothing.
	[IO.File]::Move((P $Repo 'hooks' 'guard.py'), (P $Repo 'hooks' 'guard.py.moved'))
	$out = $deny | & $Exe -NoProfile -Command (Without-Python $ps) 2>$null
	Check 'copilot powershell hook without guard or python exits 0' ($LASTEXITCODE -eq 0)
	Check 'copilot powershell hook without guard or python prints nothing' ($null -eq $out)
	if (-not $OnWindows) {
		foreach ($cmd in $c, $b) {
			$out = $deny | & sh -c (Without-Python $cmd) 2>$null
			Check "hook without guard or python exits 0: $cmd" ($LASTEXITCODE -eq 0)
			Check "hook without guard or python prints nothing: $cmd" ($null -eq $out)
		}
	}
}

function test_moved_clone_replaces_entry {
	Setup
	Write-Orig
	Run
	$s = Settings-Path
	$f = Copilot-Path
	$old = $Repo
	$script:Repo = P $T 'repo2'
	Copy-Item -LiteralPath $old -Destination $Repo -Recurse
	Run status
	Check 'moved clone: status exit 1' ($Rc -eq 1)
	Check 'moved clone: settings stale' (Has-Line "conflict $s (stale, re-run install)")
	Check 'moved clone: copilot stale' (Has-Line "conflict $f (stale, re-run install)")
	Run
	Check 'moved clone: exactly one kit entry' ((Kit-Hooks).Count -eq 1)
	Check 'moved clone: entry points at new clone' ((Kit-Hooks)[0].command.EndsWith((Guard-Id 'claude')))
	$d = Read-Json $s
	Check 'moved clone: foreign entry untouched' ((Canon @($d.hooks.PreToolUse)[0]) -eq (Canon @(($Orig | ConvertFrom-Json).hooks.PreToolUse)[0]))
	Run status
	Check 'moved clone: settings ok after install' (Has-Line "ok $s")
	Check 'moved clone: copilot ok after install' (Has-Line "ok $f")
	$script:Repo = $old
	Run uninstall
	Check 'uninstall from old clone restores original' ((Canon (Read-Json $s)) -eq (Canon ($Orig | ConvertFrom-Json)))
}

function test_claude_settings_merged_once {
	Setup
	Write-Orig
	Run
	Run
	$s = Settings-Path
	Check 'second run ok line' (Has-Line "ok $s")
	Check 'exactly one guard entry' ((Kit-Hooks).Count -eq 1)
	$d = Read-Json $s
	$o = $Orig | ConvertFrom-Json
	Check 'key order kept' ((@($d.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') -eq 'model,hooks,env')
	Check 'user hook kept first' ((Canon @($d.hooks.PreToolUse)[0]) -eq (Canon @($o.hooks.PreToolUse)[0]))
	Check 'other keys kept' ((Canon $d.model) -eq (Canon $o.model) -and (Canon $d.env) -eq (Canon $o.env) -and (Canon $d.hooks.PostToolUse) -eq (Canon $o.hooks.PostToolUse))
	$k = @($d.hooks.PreToolUse)[1].hooks[0]
	$k.command = '"/old/python3" ' + (Guard-Id 'claude')
	Set-Text $s (ConvertTo-Json -InputObject $d -Depth 20)
	Run
	Check 'stale entry replaced line' (Has-Line "linked $s")
	Check 'stale entry replaced, still one' ((Kit-Hooks).Count -eq 1)
	Check 'stale entry now current' (-not ((Kit-Hooks)[0].command.StartsWith('"/old/')))
}

function test_backup_created {
	Setup
	$s = Settings-Path
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude'))
	Set-Text $s "{`"model`": `"opus`"}`n"
	Run
	Check 'backup is original' ((Get-Text "$s.slipway-backup") -eq "{`"model`": `"opus`"}`n")
	Run uninstall
	Set-Text $s "{`"model`": `"sonnet`"}`n"
	Run
	Check 'backup never overwritten' ((Get-Text "$s.slipway-backup") -eq "{`"model`": `"opus`"}`n")
}

function test_uninstall_removes_only_guard_entry {
	Setup
	Write-Orig
	$s = Settings-Path
	$f = Copilot-Path
	[void](New-Item -ItemType Directory -Force -Path (P $H '.copilot' 'hooks'))
	$mine = P $H '.copilot' 'hooks' 'mine.json'
	Set-Text $mine "{}`n"
	Run
	Run uninstall
	Check 'settings removed line' (Has-Line "removed $s")
	Check 'copilot hook removed line' (Has-Line "removed $f")
	Check 'settings equal original' ((Canon (Read-Json $s)) -eq (Canon ($Orig | ConvertFrom-Json)))
	Check 'copilot hook gone' (-not (Exists $f))
	Check 'foreign copilot hook kept' (Exists $mine)
	Run uninstall
	Check 'second uninstall prints nothing' ($Out.Count -eq 0)
}

function test_invalid_settings_json {
	Setup
	$s = Settings-Path
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude'))
	Set-Text $s "{not json`n"
	Run
	Check 'invalid json exit 1' ($Rc -eq 1)
	Check 'invalid json conflict line' (Has-Line "conflict $s (invalid JSON)")
	Check 'invalid json untouched' ((Get-Text $s) -eq "{not json`n")
	Check 'invalid json no backup' (-not (Exists "$s.slipway-backup"))
	Check 'copilot hook still written' (Exists (Copilot-Path))
	Check-Links
}

function test_missing_python {
	Setup
	$bin = P $T 'emptybin'
	[void](New-Item -ItemType Directory -Path $bin)
	$saved = $env:PATH
	$env:PATH = $bin
	Run
	$env:PATH = $saved
	Check 'no python exit 1' ($Rc -eq 1)
	Check 'no python conflict line' (Has-Line 'conflict hooks (python 3 not found)')
	Check 'no python: no copilot hook' (-not (Exists (Copilot-Path)))
	Check 'no python: no settings' (-not (Exists (Settings-Path)))
	Check-Links
}

function test_values_untouched {
	Setup
	$s = Settings-Path
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude'))
	$offset = '"2026-01-02T03:04:05.1234567+02:00"'
	$zulu = '"2026-01-02T03:04:05.100Z"'
	$deep = ('{"d": ' * 25) + '{"leaf": "deep"}' + ('}' * 25)
	Set-Text $s ('{"a": ' + $offset + ', "b": ' + $zulu + ', "n": ' + $deep + '}')
	foreach ($act in 'install', 'uninstall') {
		Run $act
		$text = Get-Text $s
		Check "$act exit 0" ($Rc -eq 0)
		Check "$act keeps offset date" ($text.Contains('"a": ' + $offset))
		Check "$act keeps Z date" ($text.Contains('"b": ' + $zulu))
		Check "$act keeps deep nesting" (([regex]::Matches($text, '"d": \{')).Count -eq 25 -and $text.Contains('"leaf": "deep"'))
	}
	Check 'uninstall removes hooks key' (-not (Get-Text $s).Contains('"hooks"'))
}

function test_unexpected_hooks_structure {
	Setup
	$s = Settings-Path
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude'))
	Set-Text $s "{`"hooks`": []}`n"
	Run
	Check 'structure exit 1' ($Rc -eq 1)
	Check 'structure conflict line' (Has-Line "conflict $s (unexpected hooks structure)")
	Check 'structure untouched' ((Get-Text $s) -eq "{`"hooks`": []}`n")
	Check 'structure no backup' (-not (Exists "$s.slipway-backup"))
}

function test_status_stale_copilot_hook {
	Setup
	Run
	$f = Copilot-Path
	Set-Text $f "{}`n"
	Run status
	Check 'stale status exit 1' ($Rc -eq 1)
	Check 'stale status conflict line' (Has-Line "conflict $f (stale, re-run install)")
	Check 'stale status changes nothing' ((Get-Text $f) -eq "{}`n")
}

foreach ($t in 'test_install_links_all', 'test_idempotent', 'test_creates_missing_dirs', 'test_conflict_not_overwritten',
	'test_prune_stale_link', 'test_prune_rm_failure', 'test_symlinked_repo_path', 'test_uninstall_keeps_foreign',
	'test_home_with_spaces', 'test_never_touches_claude_md', 'test_copy_mode', 'test_copy_mode_keeps_frontmatter',
	'test_rules_file_fallback', 'test_rejects_extra_arguments', 'test_status_output', 'test_zero_skills',
	'test_hooks_written', 'test_hook_commands_run', 'test_claude_settings_merged_once', 'test_backup_created',
	'test_uninstall_removes_only_guard_entry', 'test_invalid_settings_json', 'test_missing_python', 'test_values_untouched',
	'test_unexpected_hooks_structure', 'test_status_stale_copilot_hook', 'test_moved_clone_replaces_entry') {
	& $t
}

Write-Output "$script:Cases assertions, $script:Fails failed"
if ($script:Fails -ne 0) { exit 1 }
exit 0

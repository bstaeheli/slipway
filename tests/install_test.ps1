# Tests for install.ps1. Each test runs against a temp copy of the repo with a fresh user home.
# Runs under Windows PowerShell 5.1 and PowerShell 7 (Windows, macOS, Linux).
$ErrorActionPreference = 'Continue'
$Src = Split-Path -Parent $PSScriptRoot
$Exe = (Get-Process -Id $PID).Path
$OnWindows = $env:OS -eq 'Windows_NT'
$Mark = '<!-- adk-installed -->'
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
	$t = P $base ('adk-test-' + [guid]::NewGuid().ToString('N'))
	[void](New-Item -ItemType Directory -Path $t)
	$script:T = Real $t
	$script:Repo = P $script:T 'repo'
	foreach ($d in 'rules', (P 'skills' 'adk-a'), (P 'skills' 'adk-b')) {
		[void](New-Item -ItemType Directory -Force -Path (P $script:Repo $d))
	}
	Copy-Item -LiteralPath (P $Src 'install.ps1') -Destination $script:Repo
	Copy-Item -LiteralPath (P $Src 'rules' 'adk.md') -Destination (P $script:Repo 'rules')
	Set-Text (P $script:Repo 'skills' 'adk-a' 'SKILL.md') "a`n"
	Set-Text (P $script:Repo 'skills' 'adk-b' 'SKILL.md') "b`n"
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
	foreach ($n in 'adk-a', 'adk-b') {
		Check "claude skill $n" (Points-To (P $H '.claude' 'skills' $n) (P $Repo 'skills' $n))
		Check "agents skill $n" (Points-To (P $H '.agents' 'skills' $n) (P $Repo 'skills' $n))
	}
	Check 'claude rule' (Points-To (P $H '.claude' 'rules' 'adk.md') (P $Repo 'rules' 'adk.md'))
	Check 'copilot rule' (Points-To (P $H '.copilot' 'instructions' 'adk.instructions.md') (P $Repo 'rules' 'adk.md'))
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
	Check 'rules dir created' (Is-Link (P $H '.claude' 'rules' 'adk.md'))
}

function test_conflict_not_overwritten {
	Setup
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude' 'skills' 'adk-spec'))
	[void](New-Item -ItemType Directory -Force -Path (P $H '.agents' 'skills' 'adk-a'))
	$f = P $H '.agents' 'skills' 'adk-a' 'SKILL.md'
	Set-Text $f "mine`n"
	$foreign = P $T 'foreign'
	[void](New-Item -ItemType Directory -Path $foreign)
	New-DirLink (P $H '.claude' 'skills' 'adk-a') $foreign
	Run
	Check 'exit 1' ($Rc -eq 1)
	Check 'conflict printed for dir' (Has-Line ('conflict ' + (P $H '.agents' 'skills' 'adk-a')))
	Check 'content intact' ((Get-Text $f) -eq "mine`n")
	Check 'still real dir' (-not (Is-Link (P $H '.agents' 'skills' 'adk-a')))
	Check 'conflict printed for foreign link' (Has-Line ('conflict ' + (P $H '.claude' 'skills' 'adk-a')))
	Check 'foreign link kept' (Points-To (P $H '.claude' 'skills' 'adk-a') $foreign)
	Check 'others still linked' (Points-To (P $H '.claude' 'skills' 'adk-b') (P $Repo 'skills' 'adk-b'))
}

function test_prune_stale_link {
	Setup
	[void](New-Item -ItemType Directory -Force -Path (P $H '.claude' 'skills'))
	[void](New-Item -ItemType Directory -Force -Path (P $H '.agents' 'skills' 'foreign-dir'))
	[void](New-Item -ItemType Directory -Force -Path (P $T 'repo-other' 'skills' 'x'))
	$gone = P $Repo 'skills' 'adk-gone'
	[void](New-Item -ItemType Directory -Path $gone)
	New-DirLink (P $H '.claude' 'skills' 'adk-gone') $gone
	New-DirLink (P $H '.agents' 'skills' 'adk-gone') $gone
	[IO.Directory]::Delete($gone)
	$dangling = P $T 'foreign-gone'
	New-Dangling (P $H '.agents' 'skills' 'foreign-dangling') $dangling
	$twin = P $T 'repo-other' 'skills' 'x'
	New-DirLink (P $H '.agents' 'skills' 'prefix-twin') $twin
	Run
	Check 'removed printed' (Has-Line ('removed ' + (P $H '.claude' 'skills' 'adk-gone')))
	Check 'link gone' (-not (Exists (P $H '.claude' 'skills' 'adk-gone')))
	Check 'agents removed printed' (Has-Line ('removed ' + (P $H '.agents' 'skills' 'adk-gone')))
	Check 'agents link gone' (-not (Exists (P $H '.agents' 'skills' 'adk-gone')))
	Check 'foreign dir kept' (Test-Path -LiteralPath (P $H '.agents' 'skills' 'foreign-dir') -PathType Container)
	Check 'foreign dangling link kept' (Points-To (P $H '.agents' 'skills' 'foreign-dangling') $dangling)
	Check 'prefix-sharing link kept' (Points-To (P $H '.agents' 'skills' 'prefix-twin') $twin)
}

function test_prune_rm_failure {
	Setup
	$dir = P $H '.claude' 'skills'
	$link = P $dir 'adk-gone'
	[void](New-Item -ItemType Directory -Force -Path $dir)
	$gone = P $Repo 'skills' 'adk-gone'
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
	Check 'link uses physical repo path' (Points-To (P $H '.claude' 'skills' 'adk-a') (P $Repo 'skills' 'adk-a'))
	Run-Script (P $rl 'install.ps1') uninstall
	Check 'uninstall via physical path' (-not (Exists (P $H '.claude' 'skills' 'adk-a')))
}

function test_uninstall_keeps_foreign {
	Setup
	Run
	[void](New-Item -ItemType Directory -Force -Path (P $H '.agents' 'skills' 'foreign-dir'))
	New-Dangling (P $H '.agents' 'skills' 'foreign-link') (P $T 'foreign-gone')
	Run uninstall
	Check 'foreign dir kept' (Test-Path -LiteralPath (P $H '.agents' 'skills' 'foreign-dir') -PathType Container)
	Check 'foreign link kept' (Is-Link (P $H '.agents' 'skills' 'foreign-link'))
	foreach ($p in (P '.claude' 'skills' 'adk-a'), (P '.claude' 'skills' 'adk-b'), (P '.agents' 'skills' 'adk-a'),
		(P '.agents' 'skills' 'adk-b'), (P '.claude' 'rules' 'adk.md'), (P '.copilot' 'instructions' 'adk.instructions.md')) {
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
	Check 'copied printed' (Has-Line ('copied ' + (P $H '.claude' 'skills' 'adk-a')))
	foreach ($d in (P '.claude' 'skills' 'adk-a'), (P '.agents' 'skills' 'adk-b')) {
		Check "real dir $d" ((Test-Path -LiteralPath (P $H $d) -PathType Container) -and -not (Is-Link (P $H $d)))
		Check "marker $d" (Test-Path -LiteralPath (P $H $d '.adk-installed') -PathType Leaf)
	}
	$rule = P $H '.claude' 'rules' 'adk.md'
	Check 'rule is real file' ((Test-Path -LiteralPath $rule -PathType Leaf) -and -not (Is-Link $rule))
	Check 'rule marker' (@(Get-Content -LiteralPath $rule) -contains $Mark)
	Set-Text (P $Repo 'skills' 'adk-b' 'SKILL.md') "b2`n"
	Run -Copy
	Check 'refresh exit 0' ($Rc -eq 0)
	Check 'refresh prints no removed line' (@($Out | Where-Object { $_ -like 'removed *' }).Count -eq 0)
	Check 'refreshed content' ((Get-Text (P $H '.agents' 'skills' 'adk-b' 'SKILL.md')) -eq "b2`n")
	Run uninstall
	Check 'copies removed' (-not ((Exists (P $H '.claude' 'skills' 'adk-a')) -or (Exists (P $H '.agents' 'skills' 'adk-b')) -or (Exists $rule)))
}

function test_copy_mode_keeps_frontmatter {
	Setup
	$f = P $H '.copilot' 'instructions' 'adk.instructions.md'
	Run -Copy
	$lines = @(Get-Content -LiteralPath $f)
	$close = -1
	for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $close = $i; break } }
	Check 'starts with ---' ($lines[0] -eq '---')
	Check 'applyTo in frontmatter' ($close -gt 0 -and @($lines[1..($close - 1)] | Where-Object { $_ -like 'applyTo:*' }).Count -gt 0)
	Check 'marker right after frontmatter' ($close -gt 0 -and $lines[$close + 1] -eq $Mark)
	Check 'marker not in frontmatter' ($close -gt 0 -and @($lines[0..$close] | Where-Object { $_ -like '*adk-installed*' }).Count -eq 0)
	Run -Copy
	Check 're-run exit 0' ($Rc -eq 0)
	Check 're-run recognizes copy' (Has-Line "copied $f")
	Run uninstall
	Check 'uninstall removes copy' (-not (Exists $f))
	Run -Copy
	Set-Text $f (((1..30) -join "`n") + "`n" + (Get-Text $f))
	Run uninstall
	Check 'marker past line 20 still kit-owned' (-not (Exists $f))
	Set-Text (P $Repo 'rules' 'adk.md') "plain`n"
	Run -Copy
	Check 'no frontmatter: marker on line 1' (@(Get-Content -LiteralPath $f)[0] -eq $Mark)
}

function test_rules_file_fallback {
	Setup
	$srcFile = P $Repo 'rules' 'adk.md'
	$src = Get-Text $srcFile
	Run -NoSymlink
	Check 'fallback exit 0' ($Rc -eq 0)
	foreach ($f in (P $H '.claude' 'rules' 'adk.md'), (P $H '.copilot' 'instructions' 'adk.instructions.md')) {
		$lines = @(Get-Content -LiteralPath $f)
		Check "real file $f" ((Test-Path -LiteralPath $f -PathType Leaf) -and -not (Is-Link $f))
		Check "warning line $f" (Has-Line "copied $f (re-run install after updates)")
		Check "frontmatter intact $f" (($lines[0] -eq '---') -and ($lines[1] -like 'applyTo:*'))
		$close = -1
		for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $close = $i; break } }
		Check "marker after frontmatter $f" ($close -gt 0 -and $lines[$close + 1] -eq $Mark)
		Check "not a hard link $f" ((Get-Text $f) -ne $src)
	}
	Check 'skills still linked' (Points-To (P $H '.claude' 'skills' 'adk-a') (P $Repo 'skills' 'adk-a'))
	$r = P $H '.claude' 'rules' 'adk.md'
	Set-Text $srcFile ($src + "new rule`n")
	Run -NoSymlink
	Check 'fallback re-run exit 0' ($Rc -eq 0)
	Check 'fallback re-run warns again' (Has-Line "copied $r (re-run install after updates)")
	Check 'fallback re-run refreshes' (@(Get-Content -LiteralPath $r) -contains 'new rule')
	Check 'fallback re-run prints no removed line' (@($Out | Where-Object { $_ -like 'removed *' }).Count -eq 0)
	Run uninstall
	Check 'fallback uninstall removes claude rule' (-not (Exists $r))
	Check 'fallback uninstall removes copilot rule' (-not (Exists (P $H '.copilot' 'instructions' 'adk.instructions.md')))
	Check 'repo rule intact' ((Get-Text $srcFile) -eq ($src + "new rule`n"))
}

foreach ($t in 'test_install_links_all', 'test_idempotent', 'test_creates_missing_dirs', 'test_conflict_not_overwritten',
	'test_prune_stale_link', 'test_prune_rm_failure', 'test_symlinked_repo_path', 'test_uninstall_keeps_foreign',
	'test_home_with_spaces', 'test_never_touches_claude_md', 'test_copy_mode', 'test_copy_mode_keeps_frontmatter',
	'test_rules_file_fallback') {
	& $t
}

Write-Output "$script:Cases assertions, $script:Fails failed"
if ($script:Fails -ne 0) { exit 1 }
exit 0

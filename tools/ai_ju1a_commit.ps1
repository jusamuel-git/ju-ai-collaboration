# JU-1A 로컬 commit만 (검증은 ai_ju1a.ps1에서 완료. 빌드 요약 판정 오탐으로 commit 단계가 중단됨)
$ErrorActionPreference = 'Continue'
$ws = 'C:\MyData\MyDev\workspace'; $jp = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_ju1a_commit_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-1a') { Log '중단: 브랜치'; exit 1 }
Run 'git add juprovider.backend juprovider.core' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("staged $n, 기타 $other")
if ($n -ne 21 -or $other -ne 0) { Log '중단: 예상 외 변경'; exit 1 }
Run "git commit -F `"$ws\ai_changes\ju1a\commit_ju1a.txt`"" | Out-Null
Run 'git log --oneline -2' | Out-Null
Run 'git status --short --branch' | Out-Null
Log 'COMMIT-DONE'

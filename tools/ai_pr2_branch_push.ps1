# PC-B 검증용: feature/protocol-ref (157635a, ← 02ab18c ← fce5048) 브랜치만 원격 push. main merge/push 없음 (사용자 승인 2026-10-27 17:04)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'; $jp = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_pr2_branch_push_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'BRANCH-PUSH-STOPPED'; exit 1 }
Log ("feature/protocol-ref push " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/protocol-ref') { Stop '브랜치가 feature/protocol-ref 아님' }
if ((& git -C $jp rev-parse --short HEAD) -ne '157635a') { Stop 'HEAD가 157635a 아님' }
if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop '작업 트리 변경 있음' }
Run 'git fetch origin' | Out-Null
Run 'git log --oneline origin/main..feature/protocol-ref' | Out-Null
$mainBefore = (& git -C $jp rev-parse origin/main)
if ((Run 'git push -u origin feature/protocol-ref') -ne 0) { Stop 'push 실패' }
Run 'git fetch origin' | Out-Null
Run 'git ls-remote origin refs/heads/feature/protocol-ref refs/heads/main' | Out-Null
$mainAfter = (& git -C $jp rev-parse origin/main)
Log ("  origin/main 변경 없음: " + ($mainBefore -eq $mainAfter) + " (" + $mainAfter.Substring(0,7) + ")")
Run 'git status --short --branch' | Out-Null
Log 'BRANCH-PUSH-DONE'

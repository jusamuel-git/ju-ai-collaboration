# JU-1c Desktop 사용자 실기 검증 PASS 후 (사용자 승인 2026-10-27 14:22): fce5048 main ff → push
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_ju1cd_push_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'PUSH-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("JU-1c Desktop push " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-1c-desktop') { Stop '브랜치가 feature/ju-1c-desktop 아님' }
if ((& git -C $jp rev-parse --short HEAD) -ne 'fce5048') { Stop 'HEAD가 fce5048 아님' }
$st = @(& git -C $jp status --porcelain); if ($st.Count -ne 0) { Stop ('작업 트리 변경 있음: ' + ($st -join ', ')) }
Run $jp 'git fetch origin' | Out-Null
if ((Run $jp 'git merge-base --is-ancestor origin/main feature/ju-1c-desktop') -ne 0) { Stop 'ff 불가' }
Run $jp 'git log --oneline origin/main..feature/ju-1c-desktop' | Out-Null
if ((Run $jp 'git checkout main') -ne 0) { Stop 'main checkout 실패' }
if ((Run $jp 'git merge --ff-only origin/main') -ne 0) { Stop 'main ff(origin) 실패' }
if ((Run $jp 'git merge --ff-only feature/ju-1c-desktop') -ne 0) { Stop 'ff 실패' }
if ((Run $jp 'git push origin main') -ne 0) { Stop 'push 실패' }
Run $jp 'git fetch origin' | Out-Null
Run $jp 'git status --short --branch' | Out-Null
Run $jp 'git log --oneline -3' | Out-Null
Log 'PUSH-DONE'

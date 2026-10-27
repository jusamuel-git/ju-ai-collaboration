# JU-1 통합 검증 PASS 후 (사용자 승인 2026-10-27 10:38): 18081 종료 → 1A~1C main ff → push → 초기 DB README(비밀번호 포함) 삭제
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_ju1_push_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'PUSH-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("JU-1 push " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 18081 종료 ====='
$pf = Join-Path $ws 'ai_ju1_local.pid'
if (Test-Path $pf) { $id = [int](Get-Content $pf); Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3; Remove-Item $pf -Force; Log "  PID $id 종료" } else { Log '  pid 파일 없음' }
$up = $false; try { $up = ((Invoke-WebRequest 'http://localhost:18081/juprovider/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) } catch {}
if ($up) { Stop '18081이 아직 응답함' }
Log '  18081 응답 없음 (종료 확인)'

Log ''; Log '===== 2. main ff + push ====='
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-1c') { Stop '브랜치가 feature/ju-1c 아님' }
if ((& git -C $jp rev-parse --short HEAD) -ne 'acac1fa') { Stop 'HEAD가 acac1fa 아님' }
$st = @(& git -C $jp status --porcelain); if ($st.Count -ne 0) { Stop ('작업 트리 변경 있음: ' + ($st -join ', ')) }
Run $jp 'git fetch origin' | Out-Null
if ((Run $jp 'git merge-base --is-ancestor origin/main feature/ju-1c') -ne 0) { Stop 'origin/main이 feature/ju-1c의 조상이 아님 (ff 불가)' }
Run $jp 'git log --oneline origin/main..feature/ju-1c' | Out-Null
if ((Run $jp 'git checkout main') -ne 0) { Stop 'main checkout 실패' }
if ((Run $jp 'git merge --ff-only origin/main') -ne 0) { Stop 'main을 origin/main으로 ff 실패' }
if ((Run $jp 'git merge --ff-only feature/ju-1c') -ne 0) { Stop 'ff 실패' }
if ((Run $jp 'git push origin main') -ne 0) { Stop 'push 실패' }
Run $jp 'git fetch origin' | Out-Null
Run $jp 'git status --short --branch' | Out-Null
Run $jp 'git log --oneline -5' | Out-Null

Log ''; Log '===== 3. 초기 DB README 정리 ====='
$rd = 'C:\MyData\MyDev\backup\juprovider_database_README_20261025_initial.md'
if (Test-Path $rd) { Remove-Item $rd -Force }
Log ("  " + $rd + " 남음: " + (Test-Path $rd))
Log 'PUSH-DONE'

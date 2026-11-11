# C5d 실장비 회귀: GTEC COM3, 실제 C5c 서버 응답(ai_c4srv -C5d 저장)만으로 CollectionPlan(내장 설정 없음) → 초기화·START·수집·STOP·분리·재연결.
# 제품 저장소 변경 없음 (도구는 workspace\ai_changes\c5dprobe). 장치 미연결이면 '미검증'으로 끝낸다 (PASS 아님).
param([string]$Port = 'COM3')
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$prj = Join-Path $ws 'ai_changes\c5dprobe\GtecProbe5d.csproj'
$log = Join-Path $ws ("ai_c5dprobe_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C5D PROBE " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$b = (& git -C $jp rev-parse --abbrev-ref HEAD); $h = (& git -C $jp log -1 --format=%h)
Log "branch $b @ $h"
if ($b -ne 'feature/collect-c5d') { Log "중단: collect-c5d 브랜치 아님 ($b)"; Log 'C5DPROBE-STOPPED'; exit 1 }
$sd = Join-Path $ws 'ai_changes\c5d\server'
foreach ($f in 'protocols_GTEC.json','data_tags.json','data_map.json') { if (-not (Test-Path (Join-Path $sd $f))) { Log "중단: 서버 응답 $f 없음 (run_ai_c5d 먼저)"; Log 'C5DPROBE-STOPPED'; exit 1 } }
if (([System.IO.Ports.SerialPort]::GetPortNames()) -notcontains $Port) { Log "미검증: $Port 없음 (GTEC 장비 미연결, 포트 목록: $([System.IO.Ports.SerialPort]::GetPortNames() -join ','))"; Log 'C5DPROBE-UNVERIFIED'; exit 2 }
$before = @(& git -C $jp status --porcelain)
Log ("포트 목록: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))

Log ''; Log '===== 1. 도구 빌드 ====='
$o = & dotnet build $prj -c Debug -v q -nologo 2>&1; $c = $LASTEXITCODE
foreach ($x in $o) { if ($x -match 'error|오류|경고|warn') { Log ('  ' + $x) } }
Log "  (exit $c)"
if ($c -ne 0) { Log 'C5DPROBE-BUILD-FAIL'; exit 1 }

Log ''; Log "===== 2. 실장비 ($Port 115200) — 안내가 나오면 케이블을 뽑았다가 다시 꽂아 주세요 ====="
& dotnet run --project $prj -c Debug --no-build -- $Port 115200 60 $sd 2>&1 | ForEach-Object { Log ('  ' + $_) }
$probe = $LASTEXITCODE
Log "  (exit $probe)"

Log ''; Log '===== 4. 제품 저장소 변경 확인 ====='
$after = @(& git -C $jp status --porcelain)
Log ("  실행 전 {0}건, 실행 후 {1}건, HEAD {2}" -f $before.Count, $after.Count, (& git -C $jp log -1 --format=%h))
foreach ($x in $after) { Log ('  ' + $x) }
Log 'C5DPROBE-DONE'

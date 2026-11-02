# C4 실장비 회귀: GTEC (기본 COM3 = PC-B, PC-A 는 COM6), CollectionPlan(내려받기 JSON + GTEC 수집 설정) → DeviceSession 자동 초기화 루틴 + 케이블 분리·재연결.
# 제품 저장소 변경 없음 (도구는 workspace\ai_changes\c3probe).
param([string]$Port = 'COM3')
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$prj = Join-Path $ws 'ai_changes\c4probe\GtecProbe4.csproj'
$log = Join-Path $ws ("ai_c4probe_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C4 PROBE " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$b = (& git -C $jp rev-parse --abbrev-ref HEAD); $h = (& git -C $jp log -1 --format=%h)
Log "branch $b @ $h"
if ($b -notin 'feature/collect-c4', 'feature/collect-c5') { Log "중단: collect-c4/c5 브랜치 아님 ($b)"; Log 'C4PROBE-STOPPED'; exit 1 }
if (([System.IO.Ports.SerialPort]::GetPortNames()) -notcontains $Port) { Log "중단: $Port 없음 (장비 연결 확인)"; Log 'C4PROBE-STOPPED'; exit 1 }
$before = @(& git -C $jp status --porcelain)
Log ("포트 목록: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))

Log ''; Log '===== 1. 도구 빌드 ====='
$o = & dotnet build $prj -c Debug -v q -nologo 2>&1; $c = $LASTEXITCODE
foreach ($x in $o) { if ($x -match 'error|오류|경고|warn') { Log ('  ' + $x) } }
Log "  (exit $c)"
if ($c -ne 0) { Log 'C4PROBE-BUILD-FAIL'; exit 1 }

Log ''; Log "===== 2. 실장비 ($Port 115200) — 안내가 나오면 케이블을 뽑았다가 다시 꽂아 주세요 ====="
& dotnet run --project $prj -c Debug --no-build -- $Port 115200 60 2>&1 | ForEach-Object { Log ('  ' + $_) }
$probe = $LASTEXITCODE
Log "  (exit $probe)"

Log ''; Log '===== 4. 제품 저장소 변경 확인 ====='
$after = @(& git -C $jp status --porcelain)
Log ("  실행 전 {0}건, 실행 후 {1}건, HEAD {2}" -f $before.Count, $after.Count, (& git -C $jp log -1 --format=%h))
foreach ($x in $after) { Log ('  ' + $x) }
Log 'C4PROBE-DONE'

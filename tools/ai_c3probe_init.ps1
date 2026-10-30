# C3 실장비 확인: COM6 GTEC, DeviceSession + LinkSupervisor + SerialTransport (+ 케이블 분리·재연결), 이후 빌드 5종 + 테스트.
# 제품 저장소 변경 없음 (도구는 workspace\ai_changes\c3probe).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$prj = Join-Path $ws 'ai_changes\c3probe\GtecProbe3.csproj'
$log = Join-Path $ws ("ai_c3probe_init_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C3 PROBE " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$b = (& git -C $jp rev-parse --abbrev-ref HEAD); $h = (& git -C $jp log -1 --format=%h)
Log "branch $b @ $h"
if ($b -ne 'feature/collect-c3' -or $h -ne 'ad9fda3') { Log '중단: feature/collect-c3 @ ad9fda3 아님'; Log 'C3PROBE-STOPPED'; exit 1 }
$before = @(& git -C $jp status --porcelain)
Log ("포트 목록: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))

Log ''; Log '===== 1. 도구 빌드 ====='
$o = & dotnet build $prj -c Debug -v q -nologo 2>&1; $c = $LASTEXITCODE
foreach ($x in $o) { if ($x -match 'error|오류|경고|warn') { Log ('  ' + $x) } }
Log "  (exit $c)"
if ($c -ne 0) { Log 'C3PROBE-BUILD-FAIL'; exit 1 }

Log ''; Log '===== 2. 실장비 (COM6 115200) — 안내가 나오면 케이블을 뽑았다가 다시 꽂아 주세요 ====='
& dotnet run --project $prj -c Debug --no-build -- COM6 115200 0 initseq 2>&1 | ForEach-Object { Log ('  ' + $_) }
$probe = $LASTEXITCODE
Log "  (exit $probe)"

Log ''; Log '===== 4. 제품 저장소 변경 확인 ====='
$after = @(& git -C $jp status --porcelain)
Log ("  실행 전 {0}건, 실행 후 {1}건, HEAD {2}" -f $before.Count, $after.Count, (& git -C $jp log -1 --format=%h))
foreach ($x in $after) { Log ('  ' + $x) }
Log 'C3PROBE-DONE'

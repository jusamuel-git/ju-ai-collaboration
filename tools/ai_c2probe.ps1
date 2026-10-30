# C2 실장비 확인: COM6 GTEC, SerialTransport + Framer + Parser. 제품 저장소 변경 없음(도구는 workspace\ai_changes\c2probe).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$prj = Join-Path $ws 'ai_changes\c2probe\GtecProbe.csproj'
$log = Join-Path $ws ("ai_c2probe_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C2 PROBE " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$b = (& git -C $jp rev-parse --abbrev-ref HEAD); $h = (& git -C $jp log -1 --format=%h)
Log "branch $b @ $h"
if ($b -ne 'feature/collect-c2' -or $h -ne '332c229') { Log '중단: feature/collect-c2 @ 332c229 아님'; Log 'C2PROBE-STOPPED'; exit 1 }
$before = @(& git -C $jp status --porcelain)
Log ("포트 목록: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))
Log ''; Log '===== 빌드 ====='
$o = & dotnet build $prj -c Debug -v q -nologo 2>&1; $c = $LASTEXITCODE
foreach ($x in $o) { if ($x -match 'error|warn|오류|경고|Build succeeded|빌드했습니다') { Log ('  ' + $x) } }
Log "  (exit $c)"
if ($c -ne 0) { Log 'C2PROBE-BUILD-FAIL'; exit 1 }
Log ''; Log '===== 실행 (COM6 115200) ====='
$o = & dotnet run --project $prj -c Debug --no-build -- COM6 115200 2>&1; $c = $LASTEXITCODE
foreach ($x in $o) { Log ('  ' + $x) }
Log "  (exit $c)"
Log ''; Log '===== 제품 저장소 변경 확인 ====='
$after = @(& git -C $jp status --porcelain)
Log ("  실행 전 {0}건, 실행 후 {1}건" -f $before.Count, $after.Count)
foreach ($x in $after) { Log ('  ' + $x) }
Log 'C2PROBE-DONE'

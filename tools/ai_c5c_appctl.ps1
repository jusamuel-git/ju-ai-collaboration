# 읽기 전용 진단: 애플리케이션 제어(Smart App Control / WDAC) 차단 원인 확인. 설정 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5c_appctl_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("appctl " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
Log ("  Smart App Control VerifiedAndReputablePolicyState = " + $v + "  (0=끔, 1=켜짐, 2=평가)")
$os = Get-CimInstance Win32_OperatingSystem; Log ("  OS " + $os.Caption + " " + $os.Version + " build " + $os.BuildNumber + ", 마지막 부팅 " + $os.LastBootUpTime)
Log '  최근 업데이트(설치일 10/25 이후):'
Get-HotFix | Where-Object { $_.InstalledOn -ge (Get-Date '2026-10-25') } | Sort-Object InstalledOn | ForEach-Object { Log ("    " + $_.HotFixID + " " + $_.InstalledOn.ToString('yyyy-MM-dd') + " " + $_.Description) }
Log '  CodeIntegrity 차단 이벤트 (최근 15건, 3033/3034/3076/3077/3089):'
try {
  Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 400 -ErrorAction Stop |
    Where-Object { $_.Id -in 3033,3034,3076,3077,3089 } | Select-Object -First 15 |
    ForEach-Object { $m = ($_.Message -split "`n")[0]; Log ("    " + $_.TimeCreated.ToString('MM-dd HH:mm:ss') + " " + $_.Id + " " + $m.Substring(0, [Math]::Min(220, $m.Length))) }
  $first = Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 5000 -ErrorAction Stop | Where-Object { $_.Id -in 3033,3077 } | Select-Object -Last 1
  if ($first) { Log ("  가장 오래된 차단 이벤트(최근 5000건 중): " + $first.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')) }
} catch { Log ("  이벤트 읽기 실패: " + $_.Exception.Message) }
$dll = Join-Path $ws 'juprovider\desktop\tests\juprovider.tests.protocol\bin\Debug\juprovider.lib.protocol.dll'
if (Test-Path $dll) { $z = Get-Item $dll -Stream Zone.Identifier -ErrorAction SilentlyContinue; Log ("  lib.protocol.dll " + (Get-Item $dll).LastWriteTime + ", Zone.Identifier " + [bool]$z) }
Log 'APPCTL-DONE'

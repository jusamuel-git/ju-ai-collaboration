# C6c 실장비 준비(11/24): Tomcat 8081(꺼져 있으면 배포된 WAR 그대로 기동) · Terminal · Client 상태 확인 후 없으면 실행.
# 서버 설정·DB·WAR·서비스 변경 없음. 키는 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$app = Join-Path $jp 'desktop\app'
$tcHome = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$log = Join-Path $ws ("ai_c6c_rd_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C6c rd " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Log ("  git " + @(cmd /c "git -C `"$jp`" rev-parse --abbrev-ref HEAD 2>nul")[0] + " @ " + @(cmd /c "git -C `"$jp`" log -1 --format=%h 2>nul")[0] + " | status: " + ((& git -C $jp status --porcelain) -join ' | '))
$server = 'http://localhost:8081/juprovider'
function Health { try { return [int](Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 ($server + '/api/health')).StatusCode } catch { return -1 } }
$cat = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' })
$h = Health
Log ("1. Tomcat 8081 health $h, catalina 프로세스 " + $cat.Count)
if ($h -ne 200 -and $cat.Count -eq 0) {
    $env:CATALINA_HOME = $tcHome; Start-Process cmd.exe -ArgumentList '/c', "`"$tcHome\bin\startup.bat`"" -WindowStyle Hidden; $env:CATALINA_HOME = $null
    for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 3; $h = Health; if ($h -eq 200) { break } }
    Log "   배포된 WAR 그대로 기동 → health $h"
}
foreach ($f in 'config\client.json', 'config\connections.json', 'config\template.accdb', 'data') { Log ("   $f " + $(if (Test-Path (Join-Path $app $f)) { '있음' } else { '없음' })) }
Log ("   connections.json: " + ((Get-Content -Encoding UTF8 (Join-Path $app 'config\connections.json')) -join ' '))
Log ("   포트: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))
$t = @(Get-Process -Name 'juprovider.terminal' -ErrorAction SilentlyContinue)
Log ("2. Terminal " + $(if ($t.Count) { 'PID ' + (($t | ForEach-Object { $_.Id }) -join ',') } else { '없음' }))
if (-not $t.Count) { $p = Start-Process -FilePath (Join-Path $app 'service\juprovider.terminal.exe') -WorkingDirectory (Join-Path $app 'service') -PassThru; Log ("   시작 PID " + $p.Id); Start-Sleep -Seconds 3 }
$c = @(Get-Process -Name 'juprovider.client' -ErrorAction SilentlyContinue)
Log ("3. Client " + $(if ($c.Count) { 'PID ' + (($c | ForEach-Object { $_.Id }) -join ',') } else { '없음' }))
if (-not $c.Count) { $p = Start-Process -FilePath (Join-Path $app 'juprovider.client.exe') -WorkingDirectory $app -PassThru; Log ("   시작 PID " + $p.Id) }
Log 'RD-READY'

# C6c 실장비 준비: 서버 장치별 DEV_CONFIG 다시 확인(읽기만, 키는 로그에 쓰지 않음) → Terminal(app\service) → Client 실행.
# 로그인은 사용자가 직접 입력한다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$app = Join-Path $ws 'juprovider\desktop\app'
$log = Join-Path $ws ("ai_c6c_app_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C6c app " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 1. 서버 장치 DEV_CONFIG ====='
$cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $app 'config\client.json') | ConvertFrom-Json
$server = ([string]$cfg.ServerUrl).TrimEnd('/')
$k = [string]$cfg.ClientKey
try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 ($server + '/api/core/sync/devices') -Headers @{ 'X-JU-Client-Id' = [string]$cfg.ClientId; 'X-JU-Client-Key' = $k }
    $k = $null
    $arr = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json
    Log ("  sync/devices HTTP " + [int]$r.StatusCode)
    foreach ($d in @($arr | ForEach-Object { $_ })) {
        $dc = $d.devConfig
        Log ("  {0} devType={1} devComm={2} ptlGrpCd={3} useYn={4} devCh={5} DEV_CONFIG={6}" -f $d.devCd, $d.devType, $d.devComm, $d.ptlGrpCd, $d.useYn, $d.devCh, $(if ($null -eq $dc) { '(null)' } elseif ([string]$dc -eq '') { '(빈 문자열)' } else { [string]$dc }))
    }
} catch { $k = $null; Log ("  실패: " + $_.Exception.Message) }
Log ("  connections.json: " + ((Get-Content -Encoding UTF8 (Join-Path $app 'config\connections.json')) -join ' '))
Log ("  포트 목록: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))

Log ''; Log '===== 2. 앱 실행 ====='
$t = @(Get-Process -Name 'juprovider.terminal' -ErrorAction SilentlyContinue)
if ($t.Count) { Log ("  Terminal 이미 실행 중 PID " + (($t | ForEach-Object { $_.Id }) -join ',')) }
else { $p = Start-Process -FilePath (Join-Path $app 'service\juprovider.terminal.exe') -WorkingDirectory (Join-Path $app 'service') -PassThru; Log ("  Terminal 시작 PID " + $p.Id) }
Start-Sleep -Seconds 3
$c = @(Get-Process -Name 'juprovider.client' -ErrorAction SilentlyContinue)
if ($c.Count) { Log ("  Client 이미 실행 중 PID " + (($c | ForEach-Object { $_.Id }) -join ',')) }
else { $p = Start-Process -FilePath (Join-Path $app 'juprovider.client.exe') -WorkingDirectory $app -PassThru; Log ("  Client 시작 PID " + $p.Id) }
Log 'C6CAPP-STARTED'

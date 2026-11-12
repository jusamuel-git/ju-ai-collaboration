# C5e 5단계 W-2/W-4 원인 확인 (읽기 전용). 응답 본문, 배포 클래스 정보, 과거 접근 로그 상태코드만 본다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5e_diag5_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Req([string]$method, [string]$url, [string]$body) {
    try {
        $p = @{ Uri = $url; Method = $method; UseBasicParsing = $true; TimeoutSec = 15 }
        if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json; charset=utf-8' }
        $r = Invoke-WebRequest @p; return ("" + [int]$r.StatusCode + " " + $r.Content)
    } catch {
        $code = -1; $txt = $_.Exception.Message
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream(), [Text.Encoding]::UTF8); $txt = $sr.ReadToEnd() } catch {}
        }
        return ("" + $code + " " + $txt)
    }
}
function Cut([string]$s) { return $s.Substring(0, [Math]::Min(300, $s.Length)) }
$api = 'http://localhost:8081/juprovider'
Log ("C5e diag5 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Log ("D-1 login 없는 사용자: " + (Cut (Req 'POST' "$api/api/auth/login" '{"loginId":"c5e_check_no_user","password":"wrong-pw-000"}')))
Log ("D-2 login 빈 본문 {}: " + (Cut (Req 'POST' "$api/api/auth/login" '{}')))
Log ("D-3 sync protocols 키 없음: " + (Cut (Req 'GET' "$api/api/core/sync/protocols" '')))
Log ("D-4 sync devices 키 없음: " + (Cut (Req 'GET' "$api/api/core/sync/devices" '')))
Log ("D-5 없는 경로 /api/c5e_none: " + (Cut (Req 'GET' "$api/api/c5e_none" '')))
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$war = Get-Item (Join-Path $tc 'webapps\juprovider.war') -ErrorAction SilentlyContinue
if ($war) { Log ("D-6 WAR " + $war.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + " " + $war.Length + " bytes") }
$cls = Join-Path $tc 'webapps\juprovider\WEB-INF\classes\com\asdp\juprovider'
foreach ($n in @('dto\LoginRequest.class', 'controller\ProtocolSyncController.class', 'controller\DeviceSyncController.class')) {
    $f = Join-Path $cls $n
    if (Test-Path $f) {
        $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($f))
        $words = @([regex]::Matches($txt, '[A-Za-z/{}]{4,}') | ForEach-Object { $_.Value } | Where-Object { $_ -match '^(loginId|userId|password|userPw|/api/.*)$' } | Select-Object -Unique)
        Log ("D-7 $n 있음: " + ($words -join ', '))
    } else { Log ("D-7 $n 없음") }
}
$jars = @(Get-ChildItem (Join-Path $tc 'webapps\juprovider\WEB-INF\classes\com\asdp\juprovider') -Recurse -Filter '*Sync*Controller.class' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
Log ("D-8 Sync 컨트롤러: " + ($jars -join ', '))
Log 'D-9 과거 접근 로그 (오늘 이전, auth/login · core/sync 상태코드 집계):'
$acc = @(Get-ChildItem (Join-Path $tc 'logs') -Filter 'localhost_access_log*.txt' | Sort-Object Name)
foreach ($a in $acc) {
    $lines = @(Get-Content $a.FullName | Where-Object { $_ -match '/api/auth/login|/api/core/sync' })
    if ($lines.Count -eq 0) { continue }
    $g = $lines | ForEach-Object { if ($_ -match '"(\w+) (\S+?)(\?\S*)? HTTP/[\d.]+" (\d{3})') { $matches[1] + ' ' + $matches[2] + ' ' + $matches[4] } } | Group-Object | ForEach-Object { $_.Name + ' x' + $_.Count }
    Log ('  ' + $a.Name + ': ' + ($g -join '; '))
}
Log 'C5E-DIAG5-DONE'

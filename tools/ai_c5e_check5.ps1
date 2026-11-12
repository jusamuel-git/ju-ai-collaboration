# C5e 5단계 확인만 (읽기 전용): Tomcat 8081 동작·로그 확인. ai_c5e_apply.ps1 이 startup.bat 출력 파이프에서 대기에 걸려 따로 실행.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5e_check5_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $id $name $note") }
function Http([string]$method, [string]$url, [string]$body) {
    try {
        $p = @{ Uri = $url; Method = $method; UseBasicParsing = $true; TimeoutSec = 15 }
        if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json' }
        $r = Invoke-WebRequest @p; return [int]$r.StatusCode
    } catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } return -1 }
}
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
Log ("C5e check5 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$listen = @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue)
$procs = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' })
Log ("  8081 listen " + $listen.Count + ", catalina java 프로세스 " + $procs.Count + $(if ($procs.Count) { ' (시작 ' + $procs[0].CreationDate.ToString('HH:mm:ss') + ')' } else { '' }))
$api = 'http://localhost:8081/juprovider'
$h = -1
for ($i = 0; $i -lt 60; $i++) { $h = Http 'GET' "$api/api/health" ''; if ($h -eq 200) { break }; Start-Sleep -Seconds 1 }
Check 'W-1' 'Tomcat 8081 + GET /api/health' ($h -eq 200) "HTTP $h"
$l = Http 'POST' "$api/api/auth/login" '{"loginId":"c5e_check_no_user","password":"wrong-pw-000"}'
Check 'W-2' '로그인 실패 응답 401 (DB 조회 정상)' ($l -eq 401) "HTTP $l"
$ix = Http 'GET' "$api/" ''
Check 'W-3' '웹 화면 GET /' ($ix -eq 200) "HTTP $ix"
$sy = Http 'GET' "$api/api/core/sync/protocols" ''
Log ("  [INFO] W-4 내려받기 API 인증 없이 HTTP $sy (401 정상, 배포본에 경로 없으면 404)")
$t0 = $(if ($procs.Count) { $procs[0].CreationDate } else { (Get-Date).AddMinutes(-15) })
$files = @(Get-ChildItem (Join-Path $tc 'logs') -File | Where-Object { $_.LastWriteTime -ge $t0 })
Log ("  기동 후 로그 파일: " + (($files | ForEach-Object { $_.Name }) -join ', '))
$errs = @($files | ForEach-Object { Get-Content $_.FullName -Encoding UTF8 | Select-String -Pattern 'SEVERE|ERROR|Exception' | ForEach-Object { $_.Line } })
Check 'W-5' '기동 후 Tomcat 로그 ERROR/SEVERE/Exception' ($errs.Count -eq 0) ("" + $errs.Count + "건")
$errs | Select-Object -First 8 | ForEach-Object { Log ('    ' + $_.Substring(0, [Math]::Min(220, $_.Length))) }
Log ("FAIL " + $script:fail)
Log 'C5E-CHECK5-DONE'

# Tomcat 서비스 전환 사전 검증 (11/18, 실제 서비스 설치 없음).
# 서비스(procrun)는 setenv.bat 을 읽지 않는다 → JU_* 를 환경변수 없이 "권한 제한 설정 파일 + spring.config.additional-location" 으로 넘기는 방식을
# 별도 CATALINA_BASE(18082/18005) + 테스트 DB 사본 + 현재 배포 WAR 로 리허설한다. 실제 8081·DB·서비스 무변경. 임시 파일은 끝에 삭제.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5n'
$log = Join-Path $ws ("ai_c5n_svc_rehearsal_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $id $name $note") }
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$tb = Join-Path $src 'svcbase'
$TD = 'juprovider_c5nsvc'
$sec = Join-Path $tb 'conf\juprovider-secret.properties'
$api = 'http://localhost:18082/juprovider'
Log ("C5n service rehearsal " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Http([string]$m, [string]$url, [string]$body) {
    try { $p = @{ Uri = $url; Method = $m; UseBasicParsing = $true; TimeoutSec = 10 }; if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json' }; return [int](Invoke-WebRequest @p).StatusCode }
    catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }; return -1 }
}
function Cleanup {
    Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tb) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    if (Test-Path $tb) { Copy-Item (Join-Path $tb 'logs') (Join-Path $src 'svc_logs') -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $tb -Recurse -Force -ErrorAction SilentlyContinue }
    cmd /c "$base -e `"DROP DATABASE IF EXISTS $TD`"" | Out-Null
}
foreach ($p in 18082, 18005) { if (@(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue).Count) { Log "중단: $p 사용 중"; exit 1 } }
Remove-Item (Join-Path $src 'svc_logs') -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $tb) { Remove-Item $tb -Recurse -Force }
foreach ($d in 'conf', 'bin', 'logs', 'temp', 'webapps', 'work') { New-Item -ItemType Directory -Force -Path (Join-Path $tb $d) | Out-Null }
Get-ChildItem "$tc\conf" -File | Copy-Item -Destination "$tb\conf"
$x = Get-Content "$tb\conf\server.xml" -Raw -Encoding UTF8
$x = $x -replace 'port="8081"', 'port="18082"' -replace 'port="8005"', 'port="18005"' -replace 'port="8009"', 'port="18009"' -replace 'port="8443"', 'port="18443"' -replace 'port="8080"', 'port="18080"'
[IO.File]::WriteAllText("$tb\conf\server.xml", $x, $enc)
[IO.File]::WriteAllText("$tb\bin\setenv.bat", "@rem empty: service mode does not use setenv JU_* values`r`n", $enc)
Copy-Item "$tc\webapps\juprovider.war" "$tb\webapps\juprovider.war"
cmd /c "$base -e `"CREATE DATABASE $TD CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
$dump = Join-Path $src 'svc_dump.sql'
& "$bin\mysqldump.exe" -h localhost -u $vars['JU_DB_USER'] --default-character-set=utf8mb4 --single-transaction --routines --triggers --hex-blob "--result-file=$dump" juprovider 2>&1 | Out-Null
cmd /c "$base $TD < `"$dump`"" | Out-Null; Remove-Item $dump -Force
# 비밀 설정 파일: 상속 끊고 SYSTEM·Administrators·현재 사용자만
function Esc([string]$v) { return ($v -replace '\\', '\\') }
$url = $vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $TD)
[IO.File]::WriteAllText($sec, ("JU_DB_URL=" + (Esc $url) + "`nJU_DB_USER=" + (Esc $vars['JU_DB_USER']) + "`nJU_DB_PASSWORD=" + (Esc $vars['JU_DB_PASSWORD']) + "`nJU_JWT_SECRET=" + (Esc $vars['JU_JWT_SECRET']) + "`n"), $enc)
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls $sec /inheritance:r /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F" "${me}:M" 2>&1 | Out-Null
$acl = (icacls $sec 2>&1 | Select-Object -First 4 | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' ; '
Check 'V-1' '비밀 설정 파일 권한 (SYSTEM·Administrators·현재 사용자만, Users 없음)' ($acl -notmatch 'Users|Everyone') $acl.Substring(0, [Math]::Min(220, $acl.Length))
# 기동: JU_* 환경변수 없이, CATALINA_OPTS 로 additional-location 만 전달 (서비스의 ++JvmOptions 와 같은 효과)
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
$env:MYSQL_PWD = $null
$env:CATALINA_HOME = $tc; $env:CATALINA_BASE = $tb
$env:CATALINA_OPTS = "-Dspring.config.additional-location=file:/" + ($sec -replace '\\', '/')
Start-Process cmd.exe -ArgumentList '/c', "`"$tc\bin\catalina.bat`" run" -WindowStyle Hidden
$env:CATALINA_OPTS = $null; $env:CATALINA_BASE = $null; $env:CATALINA_HOME = $null
$h = -1; $sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 150) { Start-Sleep -Seconds 3; $h = Http 'GET' "$api/api/health" ''; if ($h -eq 200) { break } }
Check 'V-2' 'JU_* 환경변수 없이 설정 파일만으로 기동 · health' ($h -eq 200) ("HTTP $h, " + [int]$sw.Elapsed.TotalSeconds + "초")
$l = Http 'POST' "$api/api/auth/login" '{"loginId":"c5n_no_user","password":"wrong-pw-000"}'
Check 'V-3' 'DB 연결 (없는 사용자 로그인 401)' ($l -eq 401) "HTTP $l"
$k = Http 'GET' "$api/api/core/sync/devices" ''
Check 'V-4' 'Client Key 필터 동작 (키 없음 401)' ($k -eq 401) "HTTP $k"
$errs = @(Get-ChildItem "$tb\logs" -File | ForEach-Object { Get-Content $_.FullName -Encoding UTF8 } | Select-String 'SEVERE|ERROR' | ForEach-Object { $_.Line })
Check 'V-5' 'Tomcat 로그 SEVERE/ERROR' ($errs.Count -eq 0) ("" + $errs.Count + "건")
$errs | Select-Object -First 4 | ForEach-Object { Log ('    ' + $_.Substring(0, [Math]::Min(200, $_.Length))) }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
Cleanup
$env:MYSQL_PWD = $null
Check 'V-6' '정리 (18082 닫힘·임시 폴더·비밀 파일·테스트 DB 삭제)' ((@(Get-NetTCPConnection -LocalPort 18082 -State Listen -ErrorAction SilentlyContinue).Count -eq 0) -and -not (Test-Path $tb)) ''
Log ("  8081 health " + (Http 'GET' 'http://localhost:8081/juprovider/api/health' ''))
Log ("FAIL " + $script:fail)
Log 'C5N-SVC-REHEARSAL-DONE'

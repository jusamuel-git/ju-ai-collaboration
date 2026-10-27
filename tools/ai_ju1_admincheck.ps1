# [읽기 전용] 실제 juprovider DB admin 상태 확인. 해시 원문은 쓰지 않고 SHA-256 앞 10자리만 기록
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_ju1_admincheck_{0}.log" -f $env:COMPUTERNAME)
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -N -B juprovider"
function Ed([string]$sql) { return (cmd /c "$base -e `"$sql`" 2>&1") }
$out = @()
$out += "확인 시각: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$out += "hash fp: " + (Ed "SELECT LEFT(SHA2(USER_PW_HASH,256),10) FROM ju_user WHERE LOGIN_ID='admin'")
$out += "user: " + (Ed "SELECT CONCAT_WS(' | ', u.USER_ID, u.LOGIN_ID, u.AUTH_ID, u.USE_YN, LENGTH(u.USER_PW_HASH), LEFT(u.USER_PW_HASH,7)) FROM ju_user u WHERE u.LOGIN_ID='admin'")
$out += "detail(PW_CHANGE_DT | LOGIN_FAIL_CNT | LAST_LOGIN_DT): " + (Ed "SELECT CONCAT_WS(' | ', IFNULL(d.PW_CHANGE_DT,'NULL'), d.LOGIN_FAIL_CNT, IFNULL(d.LAST_LOGIN_DT,'NULL')) FROM ju_user_detail d JOIN ju_user u ON u.USER_ID=d.USER_ID WHERE u.LOGIN_ID='admin'")
$out += "ju_user_detail 컬럼: " + ((Ed "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_user_detail' ORDER BY ORDINAL_POSITION") -join ',')
$out += "auth 1: " + (Ed "SELECT CONCAT_WS(' | ', AUTH_ID, AUTH_TYPE, USE_YN) FROM ju_auth WHERE AUTH_ID=1")
$out += "사용자 수: " + (Ed "SELECT COUNT(*) FROM ju_user")
$env:MYSQL_PWD = $null
$app = Join-Path $ws 'ai_ju1_local_app_out.txt'
if (Test-Path $app) { $out += '--- 18081 로그 (login/auth/error 관련 최근 20줄) ---'; $out += (Get-Content $app -Encoding UTF8 | Select-String -Pattern 'login|auth|ERROR|WARN|Exception' | Select-Object -Last 20 | ForEach-Object { $_.Line }) }
$out += 'ADMINCHECK-DONE'
Set-Content -Path $log -Value $out -Encoding UTF8

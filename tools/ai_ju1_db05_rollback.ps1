# [필요할 때만] migration 05 직전 백업으로 실제 juprovider DB 복원 (ju_client 제거, AUTH_ATTR 9자리로 되돌림)
$ws = 'C:\MyData\MyDev\workspace'
$bf = Get-Content (Join-Path $ws 'ai_ju1_db05_lastbackup.txt')
$log = Join-Path $ws ("ai_ju1_db05_rollback_{0}.log" -f $env:COMPUTERNAME)
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$m = "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
$o1 = cmd /c "$m -e `"DROP TABLE IF EXISTS juprovider.ju_client_detail; DROP TABLE IF EXISTS juprovider.ju_client;`" 2>&1"
$o2 = cmd /c "$m < `"$bf`" 2>&1"; $c = $LASTEXITCODE
$o3 = cmd /c "$m -N -B -e `"SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_client'`" 2>&1"
$env:MYSQL_PWD = $null
Set-Content -Path $log -Value ("복원 원본: $bf`r`nexit $c`r`nju_client 남음: $o3`r`n" + ($o1 + $o2 -join "`r`n") + "`r`nROLLBACK-DONE") -Encoding UTF8

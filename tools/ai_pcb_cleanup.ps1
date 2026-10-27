# PC-B 검증 정리: 남은 테스트 DB 삭제, 18081 확인 (실제 juprovider DB는 건드리지 않음)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$log = 'C:\MyData\MyDev\workspace\ai_pcb_cleanup.log'
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) -N -B"
$out = @()
foreach ($d in 'juprovider_pcbxinst','juprovider_pcbxtest','juprovider_pcbinst','juprovider_pcbtest') { $out += ("DROP ${d}: " + ((cmd /c "$base -e `"DROP DATABASE IF EXISTS $d`" 2>&1") -join ' ')) }
$out += ("남은 DB: " + ((cmd /c "$base -e `"SHOW DATABASES LIKE 'juprovider%'`" 2>&1") -join ', '))
$env:MYSQL_PWD = $null
$out += ("18081 LISTEN: " + [bool](Get-NetTCPConnection -LocalPort 18081 -State Listen -ErrorAction SilentlyContinue))
$out += ("java -jar juprovider.war 프로세스: " + @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'juprovider.war' -and $_.CommandLine -match '18081' }).Count)
$out += 'CLEANUP-DONE'
Set-Content -Path $log -Value $out -Encoding UTF8

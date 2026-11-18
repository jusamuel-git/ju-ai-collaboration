# 서비스 리허설 정리: 비밀 설정 파일(소유자 권한으로 ACL 복구 후 삭제)·임시 폴더·테스트 DB·18082 프로세스
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5n'
$tb = Join-Path $src 'svcbase'
$log = Join-Path $ws ("ai_c5n_svc_cleanup_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$p = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tb) })
Log ("리허설 java 프로세스 " + $p.Count); $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep -Seconds 2
$sec = Join-Path $tb 'conf\juprovider-secret.properties'
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if (Test-Path $sec) { icacls $sec /grant "${me}:F" 2>&1 | Out-Null; Remove-Item $sec -Force -ErrorAction SilentlyContinue }
Log ("비밀 파일 남음: " + (Test-Path $sec))
if (Test-Path $tb) { Remove-Item $tb -Recurse -Force -ErrorAction SilentlyContinue }
Log ("임시 폴더 남음: " + (Test-Path $tb))
if (Test-Path $tb) { Get-ChildItem $tb -Recurse -Force | Select-Object -First 5 | ForEach-Object { Log ('  ' + $_.FullName) } }
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
cmd /c "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) -e `"DROP DATABASE IF EXISTS juprovider_c5nsvc`"" | Out-Null
$left = @(cmd /c "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"")
$env:MYSQL_PWD = $null
Log ("남은 DB: " + ($left -join ', '))
Log ("18082 listen " + @(Get-NetTCPConnection -LocalPort 18082 -State Listen -ErrorAction SilentlyContinue).Count)
Log 'C5N-SVC-CLEANUP-DONE'

# 18081 미리보기 종료: 서버 종료 + 테스트 DB(juprovider_preview) 삭제
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\preview'
$log = Join-Path $ws ("ai_preview_stop_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$pidf = Join-Path $src 'server.pid'
if (Test-Path $pidf) { $id = [int](Get-Content $pidf); Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; Log "  서버 종료 PID $id"; Remove-Item $pidf -Force }
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
cmd /c "$base -e `"DROP DATABASE IF EXISTS juprovider_preview`"" | Out-Null
Log ("  남은 DB: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null
Log 'PREVIEW-STOP-DONE'

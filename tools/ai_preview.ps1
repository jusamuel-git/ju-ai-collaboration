# 18081 미리보기: feature/web-01 @ 60bc008 WAR + 테스트 DB(실제 DB 덤프 사본 + 06). 실제 DB·8081 무변경. 종료는 ai_preview_stop.ps1
#
# 실제 juprovider DB는 mysqldump(읽기)만. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\preview'
$log = Join-Path $ws ("ai_preview_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'PREVIEW-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("PREVIEW " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / WAR ====='
New-Item -ItemType Directory -Force -Path $src | Out-Null
$b = (& git -C $jp rev-parse --abbrev-ref HEAD); $h = (& git -C $jp log -1 --format=%h)
Log "  브랜치 $b @ $h"
if ($b -ne 'feature/web-01' -or $h -ne '60bc008') { Stop '브랜치/HEAD가 feature/web-01@60bc008 아님' }
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if (-not (Test-Path $war)) { Stop 'WAR 없음' }
Log ("  WAR " + (Get-Item $war).LastWriteTime)
$script:fail = 0
if ((Test-NetConnection localhost -Port 18081 -WarningAction SilentlyContinue).TcpTestSucceeded) { Stop '18081 이미 사용 중' }

Log ''; Log '===== 3. 테스트 DB (실제 DB 덤프 사본) ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$db, [string]$sql) { return (cmd /c "$base -N -B $db -e `"$sql`" 2>&1") }
$T = 'juprovider_preview'
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T; CREATE DATABASE $T CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force
cmd /c "$base $T < `"$jp\database\migration\06_protocol_actions.sql`"" ; Log ("  06 적용 exit $LASTEXITCODE")
Log ("  M02010100 Action 수: " + (Ed $T "SELECT COUNT(*) FROM ju_menu_action a JOIN ju_menu m ON m.MNU_ID=a.MNU_ID WHERE m.MNU_CD='M02010100' AND a.USE_YN='YENO0001'"))

Log ''; Log '===== 4. 서버 기동 (18081, 테스트 DB) ====='
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'
$env:JU_DB_URL = ($vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $T))
$env:JU_DB_USER = $vars['JU_DB_USER']; $env:JU_DB_PASSWORD = $vars['JU_DB_PASSWORD']; $env:JU_JWT_SECRET = $vars['JU_JWT_SECRET']
$env:SPRING_PROFILES_ACTIVE = $null
if ($env:JU_DB_URL -notmatch $T) { Stop '테스트 DB URL 치환 실패' }
$p1 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\app_out.txt" -RedirectStandardError "$src\app_err.txt"
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
$api = 'http://localhost:18081/juprovider'
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; try { if ((Invoke-WebRequest -Uri 'http://localhost:18081/juprovider/api/health' -UseBasicParsing).StatusCode -eq 200) { $ready = $true; break } } catch {} }
[IO.File]::WriteAllText((Join-Path $src 'server.pid'), [string]$p1.Id, $enc)
$env:MYSQL_PWD = $null
if ($ready) { Log ("  서버 기동 OK (PID " + $p1.Id + ") → http://localhost:18081/juprovider/"); Log 'PREVIEW-READY' } else { Log '  서버 기동 실패'; Log 'PREVIEW-STOPPED' }

# [사용자 승인 후 실행] 실제 juprovider DB: 사전 확인 → 백업 → migration 05 → 검증 (재실행 무변경 포함)
# 브랜치 feature/ju-1c (acac1fa)의 05 파일을 사용한다. push 하지 않는다. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'; $jp = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_ju1_db05_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'DB05-STOPPED'; exit 1 }
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$sql) { return (cmd /c "$base -N -B juprovider -e `"$sql`" 2>&1") }
Log ("migration 05 (실제 DB) " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 사전 확인 ====='
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-1c') { Stop 'juprovider 브랜치가 feature/ju-1c 아님' }
Log ("  HEAD: " + (& git -C $jp log -1 --oneline))
$m05 = Join-Path $jp 'database\migration\05_ju1_auth.sql'
if (-not (Test-Path $m05)) { Stop '05 파일 없음' }
$hasClient = [string](Ed "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_client'")
Log ("  ju_client 존재: $hasClient (적용 전 0 예상)")
Log ("  ju_auth: " + ((Ed "SELECT CONCAT(AUTH_ID,':',AUTH_TYPE,':',LEFT(AUTH_ATTR,25)) FROM ju_auth ORDER BY AUTH_ID") -join ' / '))
Log ("  사용자 수: " + (Ed "SELECT COUNT(*) FROM ju_user"))

Log ''; Log '===== 2. 백업 (Git 밖) ====='
$bk = 'C:\MyData\MyDev\backup'; New-Item -ItemType Directory -Force -Path $bk | Out-Null
$bf = Join-Path $bk ("juprovider_{0}_before_05.sql" -f (Get-Date -Format 'yyyyMMdd_HHmm'))
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers --databases juprovider > `"$bf`" 2>`"$bf.err`""
$c = $LASTEXITCODE; $tail = Get-Content $bf -Tail 1
Log ("  $bf (" + (Get-Item $bf).Length + " bytes, exit $c, $tail)")
if ($c -ne 0 -or $tail -notmatch 'Dump completed') { Stop '백업 실패' }
Remove-Item "$bf.err" -Force
Set-Content -Path (Join-Path $ws 'ai_ju1_db05_lastbackup.txt') -Value $bf

Log ''; Log '===== 3. 05 적용 ====='
cmd /c "$base juprovider < `"$m05`" > `"$ws\ai_ju1_db05_run1.txt`" 2>&1"
Check '05 1회 적용' ($LASTEXITCODE -eq 0) ''
$s1 = Ed 'CHECKSUM TABLE ju_auth, ju_client, ju_client_detail'
cmd /c "$base juprovider < `"$m05`" > `"$ws\ai_ju1_db05_run2.txt`" 2>&1"
Check '05 재실행 무변경' (($LASTEXITCODE -eq 0) -and (($s1 -join '|') -eq ((Ed 'CHECKSUM TABLE ju_auth, ju_client, ju_client_detail') -join '|'))) ''

Log ''; Log '===== 4. 검증 ====='
Check 'ju_client / ju_client_detail 생성' ([string](Ed "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME IN ('ju_client','ju_client_detail')") -eq '2') ''
Check 'AUTH_ATTR 9자리 항목 없음' ([string](Ed "SELECT COUNT(*) FROM ju_auth WHERE AUTH_ATTR REGEXP 'M[0-9]{8}[^0-9A-F]'") -eq '0') ''
Check '어드민(AUTH0001) 전 항목 FF' ([string](Ed "SELECT COUNT(*) FROM ju_auth WHERE AUTH_TYPE='AUTH0001' AND AUTH_ATTR REGEXP 'M[0-9]{8}(?!FF)[0-9A-F]{2}'") -eq '0') ''
Check '비어드민 전 항목 01' ([string](Ed "SELECT COUNT(*) FROM ju_auth WHERE AUTH_TYPE!='AUTH0001' AND AUTH_ATTR REGEXP 'M[0-9]{8}(?!01)[0-9A-F]{2}'") -eq '0') ''
Log ("  ju_auth: " + ((Ed "SELECT CONCAT(AUTH_ID,':',AUTH_TYPE,':',LEFT(AUTH_ATTR,28)) FROM ju_auth ORDER BY AUTH_ID") -join ' / '))
Log ("  사용자 수(변화 없음): " + (Ed "SELECT COUNT(*) FROM ju_user"))
$env:MYSQL_PWD = $null
Log ("결과: FAIL " + $script:fail + "   (되돌리기: ai_ju1_db05_rollback.ps1 — 백업 파일로 복원)")
Log 'DB05-DONE'

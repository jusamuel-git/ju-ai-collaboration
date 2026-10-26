# JU-0A SQL 테스트 DB 검증. 대상 DB: juprovider_installtest, juprovider_migtest, juprovider_realtest (테스트 전용)
# 실제 DB(juprovider)는 읽기(mysqldump)만 한다. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$out = Join-Path $ws 'ai_changes\ju0a_db\out'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = Join-Path $ws ("ai_ju0a_db_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$jp  = Join-Path $ws 'juprovider'
$db  = Join-Path $jp 'database'
$snap = Join-Path $ws 'ai_changes\ju0a_db\ju0a_snapshot.sql'

# 접속 정보: Tomcat setenv.bat (값은 로그에 쓰지 않음)
$setenv = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat'
$vars = @{}
foreach ($l in Get-Content $setenv) { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$dbHost = 'localhost'; $dbPort = '3306'
if ($vars['JU_DB_URL'] -match '//([^:/]+)(:(\d+))?/') { $dbHost = $matches[1]; if ($matches[3]) { $dbPort = $matches[3] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$user = $vars['JU_DB_USER']
Log ("JU-0A DB 검증 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " host=$dbHost port=$dbPort user=" + $(if ($user) {'SET'} else {'MISSING'}) + " password=" + $(if ($env:MYSQL_PWD) {'SET'} else {'MISSING'}))
Log ("juprovider 브랜치: " + (& git -C $jp rev-parse --abbrev-ref HEAD))
$base = "`"$bin\mysql.exe`" -h $dbHost -P $dbPort -u $user --default-character-set=utf8mb4"

function Sql([string]$name, [string]$database, [string]$file) {
    $cmd = "$base $database < `"$file`""
    $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE
    Log ("  [$name] exit $c"); foreach ($x in $o) { Log ('    ' + $x) }
    return $c
}
function Exec([string]$name, [string]$sql) {
    $o = cmd /c "$base -e `"$sql`" 2>&1"; $c = $LASTEXITCODE
    Log ("  [$name] exit $c"); foreach ($x in $o) { Log ('    ' + $x) }
    return $c
}
function Snap([string]$database, [string]$tag) {
    $f = Join-Path $out "$tag.txt"
    cmd /c "$base -B $database < `"$snap`" > `"$f`" 2>&1"
    Log ("  snapshot $tag exit $LASTEXITCODE")
}
function Sums([string]$database, [string]$tag) {
    $f = Join-Path $out "$tag.checksum.txt"
    $tables = (cmd /c "$base -N -B -e `"SELECT GROUP_CONCAT(TABLE_NAME ORDER BY TABLE_NAME) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$database'`"")
    cmd /c "$base -B $database -e `"CHECKSUM TABLE $tables`" > `"$f`" 2>&1"
    Log ("  checksum $tag exit $LASTEXITCODE")
}
$ddl = 'CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci'

# 이전 버전(main, seed V2.2) 파일
$old = Join-Path $ws 'ai_changes\ju0a_db\old'; New-Item -ItemType Directory -Force -Path $old | Out-Null
cmd /c "git -C `"$jp`" show main:database/baseline/01_ju_core_baseline.sql > `"$old\01.sql`""
cmd /c "git -C `"$jp`" show main:database/seed/02_ju_core_seed.sql > `"$old\02.sql`""

Log ''; Log '===== A. 신규 설치 (juprovider_installtest): JU-0A baseline + seed + 03, 이어서 04 ====='
Exec 'recreate' "DROP DATABASE IF EXISTS juprovider_installtest; CREATE DATABASE juprovider_installtest $ddl" | Out-Null
Sql 'baseline' 'juprovider_installtest' "$db\baseline\01_ju_core_baseline.sql" | Out-Null
Sql 'seed' 'juprovider_installtest' "$db\seed\02_ju_core_seed.sql" | Out-Null
Sql '03 validate' 'juprovider_installtest' "$db\migration\03_validate_baseline.sql" | Out-Null
Snap 'juprovider_installtest' 'A_install'
Sums 'juprovider_installtest' 'A_install'
Sql '04 on new install' 'juprovider_installtest' "$db\migration\04_ju0_install_fix.sql" | Out-Null
Snap 'juprovider_installtest' 'A_install_after04'
Sums 'juprovider_installtest' 'A_install_after04'

Log ''; Log '===== B. 기존 설치 재현 (juprovider_migtest): main baseline + seed V2.2 → 04 → 04 ====='
Exec 'recreate' "DROP DATABASE IF EXISTS juprovider_migtest; CREATE DATABASE juprovider_migtest $ddl" | Out-Null
Sql 'old baseline' 'juprovider_migtest' "$old\01.sql" | Out-Null
Sql 'old seed' 'juprovider_migtest' "$old\02.sql" | Out-Null
Snap 'juprovider_migtest' 'B_before'
Sql '04 run1' 'juprovider_migtest' "$db\migration\04_ju0_install_fix.sql" | Out-Null
Snap 'juprovider_migtest' 'B_run1'
Sums 'juprovider_migtest' 'B_run1'
Sql '04 run2' 'juprovider_migtest' "$db\migration\04_ju0_install_fix.sql" | Out-Null
Snap 'juprovider_migtest' 'B_run2'
Sums 'juprovider_migtest' 'B_run2'

Log ''; Log '===== C. 현재 PC-A DB 사본 (juprovider_realtest): mysqldump juprovider(읽기) → 04 → 04 ====='
$dump = Join-Path $ws 'ai_changes\ju0a_db\juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h $dbHost -P $dbPort -u $user --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
Log ("  [dump] exit $LASTEXITCODE")
Exec 'recreate' "DROP DATABASE IF EXISTS juprovider_realtest; CREATE DATABASE juprovider_realtest $ddl" | Out-Null
Sql 'load dump' 'juprovider_realtest' $dump | Out-Null
Snap 'juprovider_realtest' 'C_before'
Sql '04 run1' 'juprovider_realtest' "$db\migration\04_ju0_install_fix.sql" | Out-Null
Snap 'juprovider_realtest' 'C_run1'
Sums 'juprovider_realtest' 'C_run1'
Sql '04 run2' 'juprovider_realtest' "$db\migration\04_ju0_install_fix.sql" | Out-Null
Snap 'juprovider_realtest' 'C_run2'
Sums 'juprovider_realtest' 'C_run2'
Remove-Item $dump -Force
Log '  dump 파일 삭제 (실데이터 사본은 남기지 않음)'

$env:MYSQL_PWD = $null
Log ''; Log ("결과 파일: " + $out)
Log 'JU0A-DB-DONE'

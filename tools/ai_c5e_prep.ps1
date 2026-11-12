# C5e 준비 (11/12 승인):
#  1) regex 공통 호환 보완(D3)을 feature/collect-c5d 에 로컬 commit (빌드 5종 + 테스트 PASS 일 때만)
#  2) feature/collect-c5b·c5c·c5d 원격 push (main 제외, 1 이 PASS 일 때만)
#  3) C5e 사전 점검(실제 DB 읽기 전용) + 백업·복구 리허설(실제 DB 덤프 → 리허설 DB 에서만 적용·되돌림·복원)
# 실제 DB 변경·서버 배포·main 병합 없음. 비밀 값은 로그에 쓰지 않는다 (DB 비밀번호는 MYSQL_PWD 로만, 덤프 파일은 끝에 삭제).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5e'
$log = Join-Path $ws ("ai_c5e_prep_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0; $script:rows = @()
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) {
    $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }
    $script:rows += ("| {0} | {1} | {2} | {3} |" -f $id, $name, $note, $r); Log ("  [$r] $id $name $note")
}
function Info([string]$id, [string]$name, [string]$note) { $script:rows += ("| {0} | {1} | {2} | INFO |" -f $id, $name, $note); Log ("  [INFO] $id $name $note") }
function Cleanup { Get-ChildItem $src -Include 'snap_*.sql', 'q.sql' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force; if ($script:bk -and (Test-Path $script:bk)) { Remove-Item $script:bk -Force } }
function Summary {
    Log ''; Log '===== 요약 ====='; Log '| # | 항목 | 결과 요약 | 판정 |'; Log '|---|---|---|---|'
    foreach ($x in $script:rows) { Log $x }
    Log ("FAIL " + $script:fail)
}
function Stop([string]$why) { Log ("중단: " + $why); Cleanup; $env:MYSQL_PWD = $null; Summary; Log 'C5E-PREP-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
$lock = 'juprovider.frontvue/package-lock.json'
Log ("C5e prep " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)

# ======================================================================
Log ''; Log '===== 1. regex 공통 호환 보완 (D3) → feature/collect-c5d 로컬 commit ====='
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
$cur = (& git -C $jp rev-parse --abbrev-ref HEAD); $head = (& git -C $jp log -1 --format=%h)
Log "  현재 $cur @ $head"
if ($cur -ne 'feature/collect-c5d') { Stop 'feature/collect-c5d 가 아님' }
if ($head -eq '33a6494') {
    Run $jp 'git reset -q' | Out-Null
    $st = @(& git -C $jp status --porcelain | Where-Object { $l = $_; ($l -notmatch [regex]::Escape($lock)) -and -not (@($files | Where-Object { $l.EndsWith($_) }).Count -gt 0) })
    & git -C $jp status --porcelain | ForEach-Object { Log ('  ' + $_) }
    if ($st.Count -ne 0) { Stop '작업 폴더 변경 있음' }
    foreach ($f in $files) { Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) (Join-Path $jp $f.Replace('/', '\')) -Force }
    Run $jp 'git diff --stat' | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
    $bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
    $si = [Array]::IndexOf($bl, '===== 요약 =====')
    if ($si -lt 0) { Check 'A-1' '빌드 5종 + 테스트' $false '요약 없음' } else {
        $sum = $bl[$si..($bl.Length - 1)]; $sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
        Check 'A-1' '빌드 5종 + 테스트' (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
    }
    $bl | Select-String -Pattern '통과!|실패!|\[ERROR\]|error CS|Assert' | Select-Object -First 20 | ForEach-Object { Log ('  ' + $_.Line.Trim().Substring(0, [Math]::Min(300, $_.Line.Trim().Length))) }
    $t = @($bl | Select-String -Pattern 'Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: \d+$' | Select-Object -Last 1)
    if ($t.Count -gt 0) { Log ("  서버 테스트 합계: " + $t[0].Line.Trim()) }
    if ($script:fail -gt 0) { Stop '빌드·테스트 FAIL → commit·push 하지 않음 (변경은 작업 폴더에 유지)' }
    foreach ($f in $files) { Run $jp ("git add -- `"$f`"") | Out-Null }
    $names = @(& git -C $jp diff --cached --name-only)
    $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' -and $_ -notmatch [regex]::Escape($lock) })
    Check 'A-2' ("변경 범위 = " + $files.Count + "개 파일") (($names.Count -eq $files.Count) -and ($other.Count -eq 0)) ($names -join ', ')
    if ($script:fail -gt 0) { Run $jp 'git reset -q' | Out-Null; Stop '변경 범위 다름' }
    if ((Run $jp "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -F `"$src\commit_regex.txt`"") -ne 0) { Stop 'commit 실패' }
    cmd /c "git -C `"$jp`" format-patch -1 --stdout > `"$src\c5e_regex.patch`""
} else {
    Log '  이미 commit 됨 → 건너뜀'
}
Run $jp 'git log --oneline -3' | Out-Null
$c5d = (& git -C $jp rev-parse --short HEAD)
Check 'A-3' 'feature/collect-c5d 로컬 commit' ($c5d -ne '33a6494') "HEAD $c5d"

# ======================================================================
Log ''; Log '===== 2. feature 브랜치 원격 push (main 제외) ====='
$br = @('feature/collect-c5b', 'feature/collect-c5c', 'feature/collect-c5d')
Run $jp ('git push origin ' + ($br -join ' ')) | Out-Null
Run $jp 'git fetch -q origin' | Out-Null
foreach ($b in $br) {
    $l = (& git -C $jp rev-parse --short $b); $o = (& git -C $jp rev-parse --short "origin/$b" 2>$null)
    Check 'P-1' ("$b 원격 = 로컬") ($l -eq $o) "local $l / origin $o"
}
$m = (& git -C $jp rev-parse --short origin/main); Check 'P-2' 'origin/main 변경 없음' ($m -eq 'fce5048') "origin/main $m"

# ======================================================================
Log ''; Log '===== 3. C5e 사전 점검 (실제 DB 읽기 전용) ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$U = $vars['JU_DB_USER']
$base = "`"$bin\mysql.exe`" -h localhost -u $U --default-character-set=utf8mb4"
$R = 'juprovider'
$T = 'juprovider_c5e_rh'
function Q([string]$db, [string]$sql) {
    $f = Join-Path $src 'q.sql'
    [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`nSET SESSION group_concat_max_len=67108864;`n" + $sql + "`n", $enc)
    $o = cmd /c "$base -N -B $db < `"$f`" 2>&1"; $script:qx = $LASTEXITCODE; Remove-Item $f -Force
    return @($o)
}
function Q1([string]$db, [string]$sql) { return ([string]((Q $db $sql) -join ' ')).Trim() }
function Apply([string]$db, [string]$file, [string]$label) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $o = cmd /c "$base $db < `"$file`" 2>&1"; $c = $LASTEXITCODE; $sw.Stop()
    Log ("  $label exit $c, " + $sw.ElapsedMilliseconds + " ms"); if ($c -ne 0) { foreach ($x in $o) { Log ('    ' + $x) } }
    return @($c, $sw.ElapsedMilliseconds)
}
$dumpCmp = @('-h', 'localhost', '-u', $U, '--default-character-set=utf8mb4', '--skip-comments', '--skip-dump-date', '--order-by-primary', '--skip-extended-insert', '--routines', '--triggers')
function Snap([string]$db, [string]$name) { $f = Join-Path $src ("snap_$name.sql"); & "$bin\mysqldump.exe" @dumpCmp "--result-file=$f" $db 2>&1 | Out-Null; return $f }
function HashOf([string]$f) { return (Get-FileHash $f -Algorithm SHA256).Hash.Substring(0, 16) }
function Sums([string]$db) {
    $tables = @(Q $db 'SHOW TABLES')
    return @((Q $db ("CHECKSUM TABLE " + (($tables | ForEach-Object { "``$_``" }) -join ', '))) | ForEach-Object { $_ -replace "^$db\.", '' })
}
$mig = Join-Path $jp 'database\migration'

Info 'E-1' 'MariaDB' (Q1 $R "SELECT CONCAT(VERSION(), ', log_bin=', @@log_bin, ', binlog_format=', @@binlog_format, ', autocommit=', @@autocommit)")
$tc = Q1 $R "SELECT CONCAT(COUNT(*), ' tables, ', ROUND(SUM(DATA_LENGTH+INDEX_LENGTH)/1048576, 2), ' MB') FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider'"
Info 'E-2' '실제 DB 크기' $tc
$drv = Get-PSDrive C; Info 'E-3' 'C: 여유 공간' ([string][Math]::Round($drv.Free / 1GB, 1) + ' GB')
$war = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\webapps\juprovider.war'
$port = @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count
Info 'E-4' '운영 서버(Tomcat 8081)' ("listen " + $port + ", 배포 WAR " + $(if (Test-Path $war) { (Get-Item $war).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '없음' }))
$s06 = Q1 $R "SELECT COUNT(*) FROM ju_menu_action a JOIN ju_menu m ON m.MNU_ID=a.MNU_ID WHERE m.MNU_CD='M02010100' AND a.USE_YN='YENO0001'"
$s07 = Q1 $R "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_schema_version'"
$s08 = Q1 $R "SELECT CONCAT((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='juprovider' AND COLUMN_NAME IN ('FRAME_RULE','CMD_GAP_MS','INIT_ROUTINE','INIT_DELAY_MS','PTL_ROLES','PTL_ACTION','EXPECT_RULE','IDEMPOTENT_YN')), '/', (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME IN ('ju_data_channel_map','ju_mig08_bak_protocol','ju_mig08_bak_packet')))"
$prot = Q1 $R "SELECT COUNT(*) FROM ju_com_code WHERE GRP_CD='PROT' AND COM_CD IN ('PROT0000','PROT0001','PROT0002','PROT0003')"
$codes = Q1 $R "SELECT COUNT(*) FROM ju_com_group WHERE GRP_CD IN ('PROL','PACT')"
Check 'E-5' 'migration 상태: 06 미적용 확인·07 없음·08 미적용·PROT 코드 있음·PROL/PACT 없음' (($s07 -eq '0') -and ($s08 -eq '0/0') -and ($prot -eq '4') -and ($codes -eq '0')) "06 Action $s06/10, 07 $s07, 08 컬럼/테이블 $s08, PROT $prot/4, PROL·PACT $codes"
$gt = Q1 $R "SELECT CONCAT(SUM(USE_YN='YENO0001'), '/', COUNT(*)) FROM ju_protocol WHERE PTL_GRP_CD='GTEC' AND PTL_CD IN ('GTEC0000','GTEC0001','GTEC0002','GTEC0100','GTEC0300','GTEC0301','GTEC0400')"
$tg = Q1 $R "SELECT CONCAT(SUM(t.USE_YN='YENO0001'), '/', COUNT(*), ' dev=', MAX(g.DEV_CD)) FROM ju_data_tag t JOIN ju_data_group g ON g.DAT_GR_CD=t.DAT_GR_CD WHERE t.DAT_GR_CD='DG_GTEC01'"
$dv = Q1 $R "SELECT COUNT(*) FROM ju_device WHERE DEV_CD='SDEV_GTEC01'"
Check 'E-6' '08 정정 대상: GTEC 검증 7개 사용 중, DG_GTEC01 태그 4개, 장치 SDEV_GTEC01' (($gt -eq '7/7') -and ($tg -match '^4/4 dev=SDEV_GTEC01') -and ($dv -eq '1')) "프로토콜 $gt, 태그 $tg, 장치 $dv"
Log '  08_collect_settings_check.sql (실제 DB, 읽기 전용):'
foreach ($x in (cmd /c "$base $R < `"$mig\08_collect_settings_check.sql`" 2>&1")) { Log ('    ' + $x) }
$pl = Q1 $R "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE DB='juprovider' AND ID<>CONNECTION_ID()"
$trx = Q1 $R "SELECT COUNT(*) FROM information_schema.INNODB_TRX"
$long = Q1 $R "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE COMMAND<>'Sleep' AND TIME>60 AND ID<>CONNECTION_ID()"
Info 'E-7' '실제 DB 접속·트랜잭션' "juprovider 접속 $pl, 진행 중 트랜잭션 $trx, 60초 넘는 쿼리 $long (ALTER 는 메타데이터 잠금 필요 → 적용 시 서버 중지 권장)"
$g = (Q $R 'SHOW GRANTS') -join ' '
$need = @('ALTER', 'CREATE', 'DROP', 'INSERT', 'UPDATE', 'DELETE', 'INDEX', 'REFERENCES')
$miss = @($need | Where-Object { ($g -notmatch "\b$_\b") -and ($g -notmatch 'ALL PRIVILEGES') })
Check 'E-8' '적용 계정 권한 (ALTER·CREATE·DROP·INSERT·UPDATE·DELETE·INDEX·REFERENCES)' ($miss.Count -eq 0) $(if ($miss.Count -eq 0) { '충분' } else { '부족: ' + ($miss -join ',') })
$realBefore = Sums $R
Log ("  실제 DB CHECKSUM 기록 " + $realBefore.Count + "개 테이블")

# ======================================================================
Log ''; Log '===== 4. 백업·복구 리허설 (리허설 DB 에서만) ====='
$bkDir = 'C:\MyData\MyDev\backup\c5e_rehearsal'; New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
$script:bk = Join-Path $bkDir ("juprovider_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".sql")
$sw = [Diagnostics.Stopwatch]::StartNew()
$ev = Q1 $R "SELECT COUNT(*) FROM information_schema.EVENTS WHERE EVENT_SCHEMA='juprovider'"
$bkArgs = @('-h', 'localhost', '-u', $U, '--default-character-set=utf8mb4', '--single-transaction', '--routines', '--triggers', '--hex-blob')
if ($ev -ne '0') { $bkArgs += '--events' }
Log "  이벤트 $ev 개 → --events $(if ($ev -ne '0') {'포함'} else {'불필요'})"
& "$bin\mysqldump.exe" @bkArgs "--result-file=$($script:bk)" $R 2>&1 | ForEach-Object { Log ('    ' + $_) }
$sw.Stop(); $bkMs = $sw.ElapsedMilliseconds
$bkOk = (Test-Path $script:bk) -and ((Get-Item $script:bk).Length -gt 1000) -and ((Get-Content $script:bk -Tail 3) -match 'Dump completed')
Check 'R-1' '백업 (mysqldump --single-transaction --routines --triggers --hex-blob)' $bkOk ("$bkMs ms, " + [Math]::Round((Get-Item $script:bk).Length / 1MB, 2) + " MB, SHA256 " + (HashOf $script:bk))
$sReal = Snap $R 'real'
$hReal = HashOf $sReal
function Restore {
    cmd /c "$base -e `"DROP DATABASE IF EXISTS $T; CREATE DATABASE $T CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew(); $o = cmd /c "$base $T < `"$($script:bk)`" 2>&1"; $c = $LASTEXITCODE; $sw.Stop()
    foreach ($x in $o) { Log ('    ' + $x) }
    return @($c, $sw.ElapsedMilliseconds)
}
$rs1 = Restore   # 주의: PowerShell 변수는 대소문자 무시 → `$R`(실제 DB 이름)과 겹치지 않게
$sR = Snap $T 'restore1'
$sumOk = (Compare-Object $realBefore (Sums $T)).Count -eq 0
Check 'R-2' '백업 → 복원 = 실제 DB (전체 덤프·CHECKSUM)' (($rs1[0] -eq 0) -and ((HashOf $sR) -eq (HashOf $sReal)) -and $sumOk) ("복원 exit " + $rs1[0] + ", " + $rs1[1] + " ms, 덤프 " + (HashOf $sR) + "/" + (HashOf $sReal) + ", CHECKSUM 같음 " + $sumOk)
$a6 = Apply $T "$mig\06_protocol_actions.sql" '06'
$s6 = Snap $T 'after06'
$a8 = Apply $T "$mig\08_collect_settings.sql" '08'
$v = Q1 $T "SELECT CONCAT_WS('|',(SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND COLUMN_NAME IN ('FRAME_RULE','CMD_GAP_MS','INIT_ROUTINE','INIT_DELAY_MS','PTL_ROLES','PTL_ACTION','EXPECT_RULE','IDEMPOTENT_YN')),(SELECT COUNT(*) FROM ju_protocol WHERE PTL_ROLES IS NOT NULL),(SELECT COUNT(*) FROM ju_data_channel_map),(SELECT CMD_GAP_MS FROM ju_protocol_group WHERE PTL_GRP_CD='GTEC'),(SELECT COUNT(*) FROM ju_com_code WHERE GRP_CD IN ('PROL','PACT')))"
Check 'R-3' '리허설: 06 → 08 적용 (컬럼 8·정정 7·매핑 4·간격 200·코드 7)' (($a6[0] -eq 0) -and ($a8[0] -eq 0) -and ($v -eq '8|7|4|200|7')) ("06 " + $a6[1] + " ms, 08 " + $a8[1] + " ms, 결과 $v")
$a8b = Apply $T "$mig\08_collect_settings.sql" '08 재실행'
Check 'R-4' '리허설: 08 재실행' ($a8b[0] -eq 0) ("" + $a8b[1] + " ms")
$d8 = Apply $T "$mig\08_collect_settings_down.sql" '08 down'
$sD = Snap $T 'down'
Check 'R-5' '리허설: 08 down → 06 적용 상태와 같음 (1차 복구)' (($d8[0] -eq 0) -and ((HashOf $sD) -eq (HashOf $s6))) ("" + $d8[1] + " ms, 덤프 " + (HashOf $sD) + "/" + (HashOf $s6))
Apply $T "$mig\08_collect_settings.sql" '08 (전체 복원 리허설 전)' | Out-Null
$r2 = Restore
$sR2 = Snap $T 'restore2'
Check 'R-6' '리허설: 08 적용 DB 를 백업으로 전체 복원 → 실제 DB 와 같음 (2차 복구)' (($r2[0] -eq 0) -and ((HashOf $sR2) -eq (HashOf $sReal))) ("복원 " + $r2[1] + " ms, 덤프 " + (HashOf $sR2) + "/" + (HashOf $sReal))

Log ''; Log '===== 5. 정리 · 실제 DB 무변경 ====='
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T`"" | Out-Null
Log ("  리허설 DB 삭제: 남은 juprovider* = " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
Cleanup
Log ("  리허설 백업 파일 삭제 (실제 적용 때 새로 백업): " + (-not (Test-Path $script:bk)))
$realAfter = Sums $R
Check 'Z-1' ("실제 DB 무변경 (CHECKSUM " + $realAfter.Count + "개 테이블, 전체 덤프)") (((Compare-Object $realBefore $realAfter).Count -eq 0) -and ($realAfter.Count -eq $realBefore.Count) -and ((HashOf (Snap $R 'realAfter')) -eq $hReal)) ''
Get-ChildItem $src -Filter 'snap_*.sql' -ErrorAction SilentlyContinue | Remove-Item -Force
$env:MYSQL_PWD = $null
Summary
Log 'C5E-PREP-DONE'

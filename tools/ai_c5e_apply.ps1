# C5e 실제 DB 적용 (11/12 21:27 사용자 최종 승인, reviews/claude/2026-11-12_c5e_plan.md 기준)
#  1) Tomcat 중지 + 사전 점검   2) 전체 백업 + 복원 확인   3) 06 → 08 적용   4) 사후 검증   5) 기존 Tomcat 기동 + 동작 확인
# 오류가 나면 그 자리에서 중단하고 보고한다 (자동 복구 안 함). C5c 서버 배포·main 병합 없음. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5e'
$log = Join-Path $ws ("ai_c5e_apply_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0; $script:rows = @(); $script:stage = '시작 전'
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) {
    $res = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }
    $script:rows += ("| {0} | {1} | {2} | {3} |" -f $id, $name, $note, $res); Log ("  [$res] $id $name $note")
}
function Info([string]$id, [string]$name, [string]$note) { $script:rows += ("| {0} | {1} | {2} | INFO |" -f $id, $name, $note); Log ("  [INFO] $id $name $note") }
function Summary {
    Log ''; Log '===== 요약 ====='; Log '| # | 항목 | 결과 요약 | 판정 |'; Log '|---|---|---|---|'
    foreach ($x in $script:rows) { Log $x }
    Log ("FAIL " + $script:fail + ", 마지막 단계: " + $script:stage)
}
function Halt([string]$why) {
    Log ''; Log ("중단: " + $why + " (단계: " + $script:stage + ")")
    Get-ChildItem $src -Include 'snap_*.sql', 'q.sql' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force
    $env:MYSQL_PWD = $null; Summary; Log 'C5E-APPLY-STOPPED'; exit 1
}
function AssertNoFail([string]$why) { if ($script:fail -gt 0) { Halt $why } }

$jp = Join-Path $ws 'juprovider'
$mig = Join-Path $jp 'database\migration'
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$U = $vars['JU_DB_USER']
$base = "`"$bin\mysql.exe`" -h localhost -u $U --default-character-set=utf8mb4"
$DB = 'juprovider'
$VF = 'juprovider_c5e_verify'
function Q([string]$db, [string]$sql) {
    $f = Join-Path $src 'q.sql'
    [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`n" + $sql + "`n", $enc)
    $o = cmd /c "$base -N -B $db < `"$f`" 2>&1"; $script:qx = $LASTEXITCODE; Remove-Item $f -Force
    return @($o)
}
function Q1([string]$db, [string]$sql) { return ([string]((Q $db $sql) -join ' ')).Trim() }
function Apply([string]$db, [string]$file) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $o = @(cmd /c "$base $db < `"$file`" 2>&1"); $c = $LASTEXITCODE; $sw.Stop()
    return @{ code = $c; ms = $sw.ElapsedMilliseconds; out = $o }
}
$dumpCmp = @('-h', 'localhost', '-u', $U, '--default-character-set=utf8mb4', '--skip-comments', '--skip-dump-date', '--order-by-primary', '--skip-extended-insert', '--routines', '--triggers')
function Snap([string]$db, [string]$name) { $f = Join-Path $src ("snap_$name.sql"); & "$bin\mysqldump.exe" @dumpCmp "--result-file=$f" $db 2>&1 | Out-Null; return $f }
function HashOf([string]$f) { return (Get-FileHash $f -Algorithm SHA256).Hash.Substring(0, 16) }
function Sums([string]$db) {
    $tables = @(Q $db 'SHOW TABLES')
    return @((Q $db ("CHECKSUM TABLE " + (($tables | ForEach-Object { "``$_``" }) -join ', '))) | ForEach-Object { $_ -replace "^$db\.", '' })
}
function Port8081 { return @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count -gt 0 }
function Http([string]$method, [string]$url, [string]$body) {
    try {
        $p = @{ Uri = $url; Method = $method; UseBasicParsing = $true; TimeoutSec = 15 }
        if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json' }
        $r = Invoke-WebRequest @p; return [int]$r.StatusCode
    } catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } return -1 }
}
Log ("C5e apply " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)

# ======================================================================
$script:stage = '1. Tomcat 중지 · 사전 점검'
Log ''; Log "===== $($script:stage) ====="
# 적용 스크립트가 검토된 버전(C5b c8474c6)과 같은지
foreach ($f in '06_protocol_actions.sql', '08_collect_settings.sql', '08_collect_settings_down.sql', '08_collect_settings_check.sql') {
    $blob = (& git -C $jp rev-parse "c8474c6:database/migration/$f"); $work = (& git -C $jp hash-object "database/migration/$f")
    Check 'S-1' "스크립트 = 검토본(c8474c6) $f" ($blob -eq $work) "$blob"
}
AssertNoFail '적용 스크립트가 검토본과 다름'
$svc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'tomcat' -or $_.DisplayName -match 'tomcat' })
$wasRunning = Port8081
Info 'T-0' 'Tomcat 상태' ("8081 listen " + $wasRunning + ", 서비스 " + $(if ($svc.Count) { ($svc | ForEach-Object { $_.Name + '=' + $_.Status }) -join ',' } else { '없음(배치 실행)' }))
if ($wasRunning) {
    if ($svc.Count -and ($svc[0].Status -eq 'Running')) { Stop-Service $svc[0].Name -ErrorAction SilentlyContinue }
    else { $env:CATALINA_HOME = $tc; cmd /c "`"$tc\bin\shutdown.bat`"" 2>&1 | ForEach-Object { Log ('    ' + $_) } }
    for ($i = 0; $i -lt 60 -and (Port8081); $i++) { Start-Sleep -Seconds 1 }
}
Check 'T-1' 'Tomcat 중지 (8081 닫힘)' (-not (Port8081)) ''
AssertNoFail 'Tomcat 중지 실패'
$st07 = Q1 $DB "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_schema_version'"
$st06 = Q1 $DB "SELECT COUNT(*) FROM ju_menu_action a JOIN ju_menu m ON m.MNU_ID=a.MNU_ID WHERE m.MNU_CD='M02010100'"
$st08 = Q1 $DB "SELECT CONCAT((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='juprovider' AND COLUMN_NAME IN ('FRAME_RULE','CMD_GAP_MS','INIT_ROUTINE','INIT_DELAY_MS','PTL_ROLES','PTL_ACTION','EXPECT_RULE','IDEMPOTENT_YN')), '/', (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME IN ('ju_data_channel_map','ju_mig08_bak_protocol','ju_mig08_bak_packet')))"
$prot = Q1 $DB "SELECT COUNT(*) FROM ju_com_code WHERE GRP_CD='PROT' AND COM_CD IN ('PROT0000','PROT0001','PROT0002','PROT0003')"
$pp = Q1 $DB "SELECT COUNT(*) FROM ju_com_group WHERE GRP_CD IN ('PROL','PACT')"
Check 'P1' '마이그레이션 상태 (06 없음·07 없음·08 없음·PROT 4·PROL/PACT 없음)' (($st06 -eq '0') -and ($st07 -eq '0') -and ($st08 -eq '0/0') -and ($prot -eq '4') -and ($pp -eq '0')) "06 $st06, 07 $st07, 08 $st08, PROT $prot, PROL·PACT $pp"
$gt = Q1 $DB "SELECT CONCAT(SUM(USE_YN='YENO0001'), '/', COUNT(*)) FROM ju_protocol WHERE PTL_GRP_CD='GTEC' AND PTL_CD IN ('GTEC0000','GTEC0001','GTEC0002','GTEC0100','GTEC0300','GTEC0301','GTEC0400')"
$tg = Q1 $DB "SELECT CONCAT(SUM(t.USE_YN='YENO0001'), '/', COUNT(*), ' dev=', MAX(g.DEV_CD)) FROM ju_data_tag t JOIN ju_data_group g ON g.DAT_GR_CD=t.DAT_GR_CD WHERE t.DAT_GR_CD='DG_GTEC01'"
$dv = Q1 $DB "SELECT COUNT(*) FROM ju_device WHERE DEV_CD='SDEV_GTEC01'"
Check 'P2' '08 정정 대상 (GTEC 7 사용 중·태그 4·장치)' (($gt -eq '7/7') -and ($tg -match '^4/4 dev=SDEV_GTEC01') -and ($dv -eq '1')) "프로토콜 $gt, 태그 $tg, 장치 $dv"
$pl = Q1 $DB "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE DB='juprovider' AND ID<>CONNECTION_ID()"
$trx = Q1 $DB "SELECT COUNT(*) FROM information_schema.INNODB_TRX"
Check 'P3' '접속·트랜잭션 없음' (($pl -eq '0') -and ($trx -eq '0')) "접속 $pl, 트랜잭션 $trx"
$g = (Q $DB 'SHOW GRANTS') -join ' '
$miss = @('ALTER', 'CREATE', 'DROP', 'INSERT', 'UPDATE', 'DELETE', 'INDEX', 'REFERENCES') | Where-Object { ($g -notmatch "\b$_\b") -and ($g -notmatch 'ALL PRIVILEGES') }
Check 'P4' '적용 계정 권한' (@($miss).Count -eq 0) $(if (@($miss).Count -eq 0) { '충분' } else { '부족 ' + ($miss -join ',') })
$freeGB = [Math]::Round((Get-PSDrive C).Free / 1GB, 1)
Check 'P5' '디스크 여유' ($freeGB -gt 1) "$freeGB GB"
$before = Sums $DB
$sBefore = Snap $DB 'before'; $hBefore = HashOf $sBefore
Check 'P6' '적용 전 기준값 기록 (CHECKSUM·전체 덤프)' ($before.Count -ge 39) ("테이블 " + $before.Count + ", 덤프 " + $hBefore)
Log '  08_collect_settings_check.sql (적용 전):'
foreach ($x in (cmd /c "$base $DB < `"$mig\08_collect_settings_check.sql`" 2>&1")) { Log ('    ' + $x) }
AssertNoFail '사전 점검 FAIL'

# ======================================================================
$script:stage = '2. 전체 백업 · 복원 확인'
Log ''; Log "===== $($script:stage) ====="
$bkDir = Join-Path 'C:\MyData\MyDev\backup' ("c5e_" + (Get-Date -Format 'yyyyMMdd_HHmmss')); New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
$bk = Join-Path $bkDir 'juprovider_before_c5e.sql'
$ev = Q1 $DB "SELECT COUNT(*) FROM information_schema.EVENTS WHERE EVENT_SCHEMA='juprovider'"
$bkArgs = @('-h', 'localhost', '-u', $U, '--default-character-set=utf8mb4', '--single-transaction', '--routines', '--triggers', '--hex-blob')
if ($ev -ne '0') { $bkArgs += '--events' }
& "$bin\mysqldump.exe" @bkArgs "--result-file=$bk" $DB 2>&1 | ForEach-Object { Log ('    ' + $_) }
$bkOk = (Test-Path $bk) -and ((Get-Item $bk).Length -gt 1000) -and ((Get-Content $bk -Tail 3) -match 'Dump completed')
$bkHash = $(if (Test-Path $bk) { (Get-FileHash $bk -Algorithm SHA256).Hash } else { '' })
[IO.File]::WriteAllText((Join-Path $bkDir 'juprovider_before_c5e.sha256'), $bkHash + "  juprovider_before_c5e.sql`r`n", $enc)
[IO.File]::WriteAllLines((Join-Path $bkDir 'checksum_before.txt'), [string[]]$before, $enc)
Check 'B-1' '전체 백업' $bkOk ("$bkDir, " + [Math]::Round((Get-Item $bk).Length / 1KB) + " KB, SHA256 " + $bkHash.Substring(0, [Math]::Min(16, $bkHash.Length)))
AssertNoFail '백업 실패'
cmd /c "$base -e `"DROP DATABASE IF EXISTS $VF; CREATE DATABASE $VF CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
$o = @(cmd /c "$base $VF < `"$bk`" 2>&1"); $rc = $LASTEXITCODE
$hV = HashOf (Snap $VF 'verify')
$sumSame = (Compare-Object $before (Sums $VF)).Count -eq 0
Check 'B-2' '백업 복원 확인 (임시 DB = 실제 DB)' (($rc -eq 0) -and ($hV -eq $hBefore) -and $sumSame) ("복원 exit $rc, 덤프 $hV/$hBefore, CHECKSUM 같음 $sumSame " + (($o | Select-Object -First 2) -join ' '))
AssertNoFail '백업 복원 확인 실패 (실제 DB 변경 전에 중단)'
# 사후 비교 기준: 백업 사본에 같은 06 → 08 적용 (실제 DB 결과와 덤프가 같아야 함)
$v6 = Apply $VF "$mig\06_protocol_actions.sql"; $v8 = Apply $VF "$mig\08_collect_settings.sql"
$hExpect = HashOf (Snap $VF 'expect')
Check 'B-3' '사후 비교 기준 (백업 사본 + 06 + 08)' (($v6.code -eq 0) -and ($v8.code -eq 0)) ("06 " + $v6.code + ", 08 " + $v8.code + ", 기준 덤프 $hExpect")
cmd /c "$base -e `"DROP DATABASE IF EXISTS $VF`"" | Out-Null
AssertNoFail '비교 기준 만들기 실패 (실제 DB 변경 전에 중단)'

# ======================================================================
$script:stage = '3. 06 → 08 적용 (실제 DB)'
Log ''; Log "===== $($script:stage) ====="
$a6 = Apply $DB "$mig\06_protocol_actions.sql"
foreach ($x in $a6.out) { Log ('    ' + $x) }
$n6 = Q1 $DB "SELECT COUNT(*) FROM ju_menu_action a JOIN ju_menu m ON m.MNU_ID=a.MNU_ID WHERE m.MNU_CD='M02010100' AND a.USE_YN='YENO0001'"
Check 'A-1' '06 적용 (Protocol Menu Action 10개)' (($a6.code -eq 0) -and ($n6 -eq '10')) ("exit " + $a6.code + ", " + $a6.ms + " ms, Action $n6")
AssertNoFail '06 적용 오류 → 08 적용하지 않음. 복구: 백업 전체 복원 또는 06 재실행(재실행 안전)'
$a8 = Apply $DB "$mig\08_collect_settings.sql"
foreach ($x in $a8.out) { Log ('    ' + $x) }
Check 'A-2' '08 적용' ($a8.code -eq 0) ("exit " + $a8.code + ", " + $a8.ms + " ms")
AssertNoFail '08 적용 오류 → 복구 계획 1차(08 down) 또는 2차(백업 전체 복원) 결정 필요'

# ======================================================================
$script:stage = '4. 사후 데이터 검증'
Log ''; Log "===== $($script:stage) ====="
$v = Q1 $DB "SELECT CONCAT_WS('|',(SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND COLUMN_NAME IN ('FRAME_RULE','CMD_GAP_MS','INIT_ROUTINE','INIT_DELAY_MS','PTL_ROLES','PTL_ACTION','EXPECT_RULE','IDEMPOTENT_YN')),(SELECT COUNT(*) FROM ju_protocol WHERE PTL_ROLES IS NOT NULL),(SELECT COUNT(*) FROM ju_data_channel_map),(SELECT CMD_GAP_MS FROM ju_protocol_group WHERE PTL_GRP_CD='GTEC'),(SELECT COUNT(*) FROM ju_com_code WHERE GRP_CD IN ('PROL','PACT')),(SELECT COUNT(*) FROM ju_mig08_bak_protocol))"
Check 'V-1' '08 결과 (컬럼 8·정정 7·매핑 4·간격 200·코드 7·백업 7)' ($v -eq '8|7|4|200|7|7') $v
$grp = Q1 $DB "SELECT CONCAT_WS('|',CMD_GAP_MS,INIT_DELAY_MS,INIT_ROUTINE) FROM ju_protocol_group WHERE PTL_GRP_CD='GTEC'"
Check 'V-2' 'GTEC 그룹 수집 설정' ($grp -eq '200|500|GTEC0301,GTEC0001,GTEC0002,GTEC0100') $grp
$hAfter = HashOf (Snap $DB 'after')
Check 'V-3' '실제 DB 전체 = 백업 사본에 같은 06·08 을 적용한 결과 (다른 데이터 변경 없음)' ($hAfter -eq $hExpect) "덤프 $hAfter / 기준 $hExpect"
$after = Sums $DB
$touched = 'ju_menu_action', 'ju_menu_action_detail', 'ju_multi_lang', 'ju_com_group', 'ju_com_group_detail', 'ju_com_code', 'ju_com_code_detail', 'ju_protocol', 'ju_protocol_group', 'ju_protocol_packet'
$newT = @($after | ForEach-Object { ($_ -split "`t")[0] } | Where-Object { $_ -notin @($before | ForEach-Object { ($_ -split "`t")[0] }) })
$changed = @(Compare-Object $before $after | ForEach-Object { ($_.InputObject -split "`t")[0] } | Sort-Object -Unique | Where-Object { ($_ -notin $touched) -and ($_ -notin $newT) })
Check 'V-4' '06·08 대상 외 테이블 CHECKSUM 그대로' ($changed.Count -eq 0) ("바뀐 다른 테이블 " + $changed.Count + ", 새 테이블 " + ($newT -join ','))
Log '  08_collect_settings_check.sql (적용 후):'
foreach ($x in (cmd /c "$base $DB < `"$mig\08_collect_settings_check.sql`" 2>&1")) { Log ('    ' + $x) }
[IO.File]::WriteAllLines((Join-Path $bkDir 'checksum_after.txt'), [string[]]$after, $enc)
AssertNoFail '사후 검증 FAIL → Tomcat 기동하지 않음. 복구 결정 필요'

# ======================================================================
$script:stage = '5. 기존 Tomcat 기동 · 동작 확인'
Log ''; Log "===== $($script:stage) ====="
$t0 = Get-Date
if ($svc.Count) { Start-Service $svc[0].Name -ErrorAction SilentlyContinue }
else { $env:CATALINA_HOME = $tc; Push-Location (Join-Path $tc 'bin'); cmd /c "startup.bat" 2>&1 | ForEach-Object { Log ('    ' + $_) }; Pop-Location }
$api = 'http://localhost:8081/juprovider'
$h = -1
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Seconds 1; if (Port8081) { $h = Http 'GET' "$api/api/health" ''; if ($h -eq 200) { break } } }
Check 'W-1' 'Tomcat 기동 (8081) + GET /api/health' ($h -eq 200) ("HTTP $h, " + [int]((Get-Date) - $t0).TotalSeconds + " s")
$l = Http 'POST' "$api/api/auth/login" '{"loginId":"c5e_check_no_user","password":"wrong-pw-000"}'
Check 'W-2' '로그인 실패 응답 401 (DB 조회 정상)' ($l -eq 401) "HTTP $l"
$ix = Http 'GET' "$api/" ''
Check 'W-3' '웹 화면 GET /' ($ix -eq 200) "HTTP $ix"
$sy = Http 'GET' "$api/api/core/sync/protocols" ''
Info 'W-4' '내려받기 API 인증 없이 호출' ("HTTP $sy (Client Key 없으면 401 이 정상, 배포본에 경로가 없으면 404)")
Start-Sleep -Seconds 2
$errs = @(Get-ChildItem (Join-Path $tc 'logs') -File | Where-Object { $_.LastWriteTime -ge $t0 } | ForEach-Object {
    Get-Content $_.FullName -Encoding UTF8 | Select-String -Pattern 'SEVERE|ERROR|Exception' | ForEach-Object { $_.Line } })
Check 'W-5' '기동 후 Tomcat 로그 ERROR/SEVERE/Exception' ($errs.Count -eq 0) ("" + $errs.Count + "건")
$errs | Select-Object -First 5 | ForEach-Object { Log ('    ' + $_.Substring(0, [Math]::Min(200, $_.Length))) }

Get-ChildItem $src -Filter 'snap_*.sql' -ErrorAction SilentlyContinue | Remove-Item -Force
$env:MYSQL_PWD = $null
$script:stage = '완료'
Summary
Log ("백업 보관: " + $bkDir + " (로컬 전용)")
Log $(if ($script:fail -eq 0) { 'C5E-APPLY-DONE' } else { 'C5E-APPLY-DONE-WITH-FAIL' })

# C5b: feature/collect-c5(854da5c) → feature/collect-c5b. migration 08 up/down/재실행을 테스트 DB 사본에서만 검증 + 빌드 5종 + 실서버 회귀 → PASS면 로컬 commit. push·실제 DB 변경 없음.
# 비밀 값은 로그에 쓰지 않는다 (DB 비밀번호는 MYSQL_PWD 환경변수로만, 덤프 파일은 끝에 삭제).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5b'
$log = Join-Path $ws ("ai_c5b_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0; $script:rows = @()
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) {
    $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }
    $script:rows += ("| {0} | {1} | {2} | {3} |" -f $id, $name, $note, $r); Log ("  [$r] $id $name $note")
}
function Stop([string]$why) { Log ("중단: " + $why); Get-ChildItem $src -Include 'snap_*.sql','pres_*.sql','bk_*.sql','juprovider_dump.sql' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force; $env:MYSQL_PWD = $null; Log 'C5B-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
$mig = Join-Path $jp 'database\migration'
Log ("C5b " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
Log ('  현재 ' + (& git -C $jp rev-parse --abbrev-ref HEAD) + ' @ ' + (& git -C $jp log -1 --format=%h))
$lock = 'juprovider.frontvue/package-lock.json'  # 빌드(npm)가 고치는 파일: 건드리지 않고 commit 대상에서 제외, 보고만
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
$c5 = (& git -C $jp rev-parse --short feature/collect-c5); Log "  feature/collect-c5 $c5"
if ($c5 -ne '854da5c') { Stop 'feature/collect-c5 가 854da5c 아님' }
$cur = (& git -C $jp rev-parse --abbrev-ref HEAD)
# 이전 실행이 commit 전에 멈춘 경우: feature/collect-c5b @ 854da5c (commit 없음) 이면 이어서 진행 (C5b 파일은 다시 복사)
$resume = ($cur -eq 'feature/collect-c5b') -and ((& git -C $jp log -1 --format=%h) -eq '854da5c')
if ($resume) { Run $jp 'git reset -q' | Out-Null }
$st = @(& git -C $jp status --porcelain | Where-Object { $l = $_; ($l -notmatch [regex]::Escape($lock)) -and -not ($resume -and @($files | Where-Object { $l.EndsWith($_) }).Count -gt 0) })
& git -C $jp status --porcelain | ForEach-Object { Log ('  ' + $_) }
if ($st.Count -ne 0) { Stop '작업 폴더 변경 있음' }
if (-not $resume) {
    & git -C $jp rev-parse --verify -q feature/collect-c5b | Out-Null
    if ($LASTEXITCODE -eq 0) { Stop 'feature/collect-c5b 이미 있음' }
    if ((Run $jp 'git checkout -b feature/collect-c5b feature/collect-c5') -ne 0) { Stop 'checkout 실패' }
} else { Log '  feature/collect-c5b (commit 없음) 이어서 진행' }
$now = Get-Date
foreach ($f in $files) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null

# --- DB 접속 (setenv.bat 값은 읽기만, 출력하지 않음) ---
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$U = $vars['JU_DB_USER']
$base = "`"$bin\mysql.exe`" -h localhost -u $U --default-character-set=utf8mb4"
$T = 'juprovider_c5btest'
function Q([string]$db, [string]$sql) {
    $f = Join-Path $src 'q.sql'
    [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`nSET SESSION group_concat_max_len=67108864;`n" + $sql + "`n", $enc)
    $o = cmd /c "$base -N -B $db < `"$f`" 2>&1"; $script:qx = $LASTEXITCODE; Remove-Item $f -Force
    return @($o)
}
function Q1([string]$db, [string]$sql) { return ([string]((Q $db $sql) -join ' ')).Trim() }
function Apply([string]$file, [string]$label, [switch]$Quiet) {
    $o = cmd /c "$base $T < `"$file`" 2>&1"; $c = $LASTEXITCODE
    Log ("  $label exit $c"); if (-not $Quiet -or $c -ne 0) { foreach ($x in $o) { Log ('    ' + $x) } }
    return $c
}
$dumpArgs = @('-h', 'localhost', '-u', $U, '--default-character-set=utf8mb4', '--skip-comments', '--skip-dump-date', '--order-by-primary', '--skip-extended-insert')
function Snap([string]$name) {
    $f = Join-Path $src ("snap_$name.sql")
    & "$bin\mysqldump.exe" @dumpArgs '--routines' '--triggers' "--result-file=$f" $T 2>&1 | Out-Null
    return $f
}
function HashOf([string]$f) { return (Get-FileHash $f -Algorithm SHA256).Hash.Substring(0, 16) }
function DiffTables([string]$a, [string]$b) {
    $d = Compare-Object ([IO.File]::ReadAllLines($a)) ([IO.File]::ReadAllLines($b))
    $n = @($d | ForEach-Object { if ($_.InputObject -match '^INSERT INTO `([^`]+)`') { $matches[1] } elseif ($_.InputObject -match '^CREATE TABLE `([^`]+)`') { 'create:' + $matches[1] } else { 'schema' } } | Sort-Object -Unique)
    return ($n -join ',')
}
function SameAs([string]$id, [string]$name, [string]$ref, [string]$cur) {
    $ok = ((HashOf $ref) -eq (HashOf $cur)); $note = ("전체 덤프 " + (HashOf $cur) + $(if ($ok) {' = '} else {' ≠ '}) + (HashOf $ref))
    if (-not $ok) { $note += (" (다른 테이블: " + (DiffTables $ref $cur) + ")") }
    Check $id $name $ok $note
}
# 기존 데이터 보존: 08이 손대지 않는 테이블 전체 + 손대는 테이블의 기존 컬럼(정정 대상 값은 가림)
$ign = @('ju_protocol','ju_protocol_group','ju_protocol_packet','ju_com_group','ju_com_group_detail','ju_com_code','ju_com_code_detail','ju_multi_lang','ju_data_channel_map','ju_mig08_bak_protocol','ju_mig08_bak_packet','ju_schema_version') | ForEach-Object { "--ignore-table=$T.$_" }
$projSql = @"
SELECT MD5(GROUP_CONCAT(CONCAT_WS('|',PTL_GRP_CD,POLLING_INTVAL,TIMEOUT_MS,RETRY_CNT,USE_YN,SORT_ORD) ORDER BY PTL_GRP_CD SEPARATOR '\n')) FROM ju_protocol_group;
SELECT MD5(GROUP_CONCAT(CONCAT_WS('|',PTL_GRP_CD,PTL_CD,IF(PTL_GRP_CD='GTEC' AND PTL_CD IN ('GTEC0000','GTEC0001','GTEC0002','GTEC0100','GTEC0300','GTEC0301','GTEC0400'),'*',PTL_TYPE),IFNULL(PTL_LEN,'~'),IFNULL(PTL_VAL,'~'),USE_YN) ORDER BY PTL_GRP_CD,PTL_CD SEPARATOR '\n')) FROM ju_protocol;
SELECT MD5(GROUP_CONCAT(CONCAT_WS('|',PTL_GRP_CD,PTL_CD,PACKET_SEQ,IFNULL(PACKET_TYPE,'~'),DIRECTION,IFNULL(PACKET_EXPR,'~'),IFNULL(RESPONSE_PTL_CD,'~'),IFNULL(PARSE_RULE,'~'),DATA_COUNT,IFNULL(DATA_TYPE,'~'),IFNULL(DATA_POSITION,'~'),USE_YN) ORDER BY PTL_GRP_CD,PTL_CD,PACKET_SEQ SEPARATOR '\n')) FROM ju_protocol_packet WHERE NOT (PTL_GRP_CD='GTEC' AND PTL_CD IN ('GTEC0002','GTEC0400') AND DIRECTION='RX');
"@
function Pres {
    $f1 = Join-Path $src 'pres_other.sql'; $f2 = Join-Path $src 'pres_code.sql'; $f3 = Join-Path $src 'pres_lang.sql'
    & "$bin\mysqldump.exe" @dumpArgs '--no-create-info' @ign "--result-file=$f1" $T 2>&1 | Out-Null
    & "$bin\mysqldump.exe" @dumpArgs '--no-create-info' "--where=GRP_CD NOT IN ('PROL','PACT')" "--result-file=$f2" $T ju_com_group ju_com_group_detail ju_com_code ju_com_code_detail 2>&1 | Out-Null
    & "$bin\mysqldump.exe" @dumpArgs '--no-create-info' "--where=RES_KEY NOT IN ('GROUP.PROL.NM','GROUP.PACT.NM') AND RES_KEY NOT LIKE 'CODE.PROL.%' AND RES_KEY NOT LIKE 'CODE.PACT.%'" "--result-file=$f3" $T ju_multi_lang 2>&1 | Out-Null
    $p = (Q $T $projSql) | ForEach-Object { $_.Substring(0, [Math]::Min(8, $_.Length)) }
    $r = ("기타 " + (HashOf $f1) + ", 코드 " + (HashOf $f2) + ", 다국어 " + (HashOf $f3) + ", 그룹/프로토콜/패킷 " + ($p -join '/'))
    Remove-Item $f1, $f2, $f3 -Force -ErrorAction SilentlyContinue
    return $r
}

Log ''; Log '===== 2. 의존성 · 실제 DB 상태 (읽기 전용) ====='
$realTables = @(Q 'juprovider' 'SHOW TABLES')
$realSum = { (Q 'juprovider' ("CHECKSUM TABLE " + ($realTables -join ', '))) -join ' ; ' }
$realBefore = & $realSum
Log ("  실제 DB 테이블 " + $realTables.Count + "개, CHECKSUM 기록")
$a06 = Q1 'juprovider' "SELECT COUNT(*) FROM ju_menu_action a JOIN ju_menu m ON m.MNU_ID=a.MNU_ID WHERE m.MNU_CD='M02010100' AND a.USE_YN='YENO0001'"
$sv  = Q1 'juprovider' "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_schema_version'"
$c08 = Q1 'juprovider' "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='juprovider' AND COLUMN_NAME IN ('FRAME_RULE','PTL_ROLES')"
$t08 = Q1 'juprovider' "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME IN ('ju_data_channel_map','ju_mig08_bak_protocol','ju_mig08_bak_packet')"
$prot = Q1 'juprovider' "SELECT COUNT(*) FROM ju_com_code WHERE GRP_CD='PROT' AND COM_CD IN ('PROT0000','PROT0001','PROT0002','PROT0003')"
Log "  실제 DB: 06 Action $a06/10, ju_schema_version(07) $sv, 08 컬럼 $c08, 08 테이블 $t08, PROT 코드 $prot/4"
Check 'D-1' '실제 DB 08 미적용 (컬럼·테이블 없음)' (($c08 -eq '0') -and ($t08 -eq '0')) "컬럼 $c08, 테이블 $t08"
Check 'D-2' '08 선행 조건: PROT0000~0003 (04)' ($prot -eq '4') "$prot/4"
Log '  08_collect_settings_check.sql (실제 DB, 읽기 전용):'
foreach ($x in (cmd /c "$base juprovider < `"$mig\08_collect_settings_check.sql`" 2>&1")) { Log ('    ' + $x) }

Log ''; Log '===== 3. 테스트 DB (실제 DB 덤프 사본) ====='
$dump = Join-Path $src 'juprovider_dump.sql'
& "$bin\mysqldump.exe" -h localhost -u $U --default-character-set=utf8mb4 --single-transaction --routines --triggers "--result-file=$dump" juprovider 2>&1 | Out-Null
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T; CREATE DATABASE $T CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force
$sReal = Snap 'real'
Log '  -- 06 없이 08 (순서 의존성 확인)'
Check 'N-1' '06 미적용 사본에 08 up' ((Apply "$mig\08_collect_settings.sql" '08 up' -Quiet) -eq 0) ''
Check 'N-2' '06 미적용 사본에서 08 down → 사본 원상태' ((Apply "$mig\08_collect_settings_down.sql" '08 down' -Quiet) -eq 0) ''
SameAs 'N-3' '06 미적용 사본: up→down 후 동일' $sReal (Snap 'n3')
$c06 = Apply "$mig\06_protocol_actions.sql" '06 적용(테스트 DB)' -Quiet
Check 'N-4' '06 적용 (재실행 안전)' ($c06 -eq 0) ''
$s0 = Snap 's0'; $p0 = Pres
Log "  S0 (06 적용, 08 전) $(HashOf $s0)"; Log "  보존 기준 $p0"

Log ''; Log '===== 4. 08 up ====='
Check 'U-0' '08 up 실행' ((Apply "$mig\08_collect_settings.sql" '08 up') -eq 0) ''
$cols = Q1 $T "SELECT GROUP_CONCAT(CONCAT(TABLE_NAME,'.',COLUMN_NAME,' ',COLUMN_TYPE,' ',IS_NULLABLE,' ',IFNULL(COLUMN_DEFAULT,'-')) ORDER BY TABLE_NAME, ORDINAL_POSITION SEPARATOR '; ') FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND ((TABLE_NAME='ju_protocol_group' AND COLUMN_NAME IN ('FRAME_RULE','CMD_GAP_MS','INIT_ROUTINE','INIT_DELAY_MS')) OR (TABLE_NAME='ju_protocol' AND COLUMN_NAME IN ('PTL_ROLES','PTL_ACTION','EXPECT_RULE','IDEMPOTENT_YN')))"
$expCols = "ju_protocol.PTL_ROLES varchar(50) YES NULL; ju_protocol.PTL_ACTION varchar(8) YES NULL; ju_protocol.EXPECT_RULE varchar(500) YES NULL; ju_protocol.IDEMPOTENT_YN varchar(8) YES NULL; ju_protocol_group.FRAME_RULE longtext YES NULL; ju_protocol_group.CMD_GAP_MS int(11) NO 0; ju_protocol_group.INIT_ROUTINE varchar(500) YES NULL; ju_protocol_group.INIT_DELAY_MS int(11) NO 500"
Check 'U-1' '추가 컬럼 8개 (형식·NULL·기본값)' ($cols -eq $expCols) $cols
$lang = Q1 $T "SELECT COUNT(*) FROM ju_language WHERE LANG_CD IN ('LANG0001','LANG0002')"
$codes = Q1 $T "SELECT CONCAT_WS('/',(SELECT COUNT(*) FROM ju_com_group WHERE GRP_CD IN ('PROL','PACT')),(SELECT COUNT(*) FROM ju_com_group_detail WHERE GRP_CD IN ('PROL','PACT')),(SELECT GROUP_CONCAT(COM_CD,'=',COM_VAL ORDER BY COM_CD) FROM ju_com_code WHERE GRP_CD IN ('PROL','PACT')),(SELECT COUNT(*) FROM ju_com_code_detail WHERE GRP_CD IN ('PROL','PACT')),(SELECT COUNT(*) FROM ju_multi_lang WHERE RES_KEY IN ('GROUP.PROL.NM','GROUP.PACT.NM') OR RES_KEY LIKE 'CODE.PROL.%' OR RES_KEY LIKE 'CODE.PACT.%'))"
$expCodes = "2/2/PACT0000=NONE,PACT0001=START,PACT0002=PAUSE,PACT0003=STOP,PROL0001=INFO,PROL0002=CONTROL,PROL0003=DATA/7/" + (9 * [int]$lang)
Check 'U-2' '공통코드 PROL 3 · PACT 4 (+detail, 다국어)' ($codes -eq $expCodes) $codes
$cons = Q1 $T "SELECT GROUP_CONCAT(CONSTRAINT_NAME,':',CONSTRAINT_TYPE ORDER BY CONSTRAINT_NAME) FROM information_schema.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='ju_data_channel_map'"
$coll = Q1 $T "SELECT COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='ju_data_channel_map' AND COLUMN_NAME='CHANNEL_KEY'"
Check 'U-3' 'ju_data_channel_map PK·UK·FK 2개, CHANNEL_KEY binary' (($cons -eq 'FK_DCMAP_DEVICE:FOREIGN KEY,FK_DCMAP_TAG:FOREIGN KEY,PRIMARY:PRIMARY KEY,UK_DCMAP:UNIQUE') -and ($coll -eq 'utf8mb4_bin')) "$cons, $coll"
$grp = Q1 $T "SELECT CONCAT_WS('|',CMD_GAP_MS,INIT_DELAY_MS,INIT_ROUTINE,FRAME_RULE) FROM ju_protocol_group WHERE PTL_GRP_CD='GTEC'"
$grpOther = Q1 $T "SELECT COUNT(*) FROM ju_protocol_group WHERE PTL_GRP_CD<>'GTEC' AND (FRAME_RULE IS NOT NULL OR CMD_GAP_MS<>0 OR INIT_ROUTINE IS NOT NULL OR INIT_DELAY_MS<>500)"
Check 'U-4' 'GTEC 그룹 수집 설정, 다른 그룹은 기본값' (($grp -eq '200|500|GTEC0301,GTEC0001,GTEC0002,GTEC0100|{"v":1,"kind":"DELIM","start":"{","end":"[CR][LF]","maxLen":512}') -and ($grpOther -eq '0')) "$grp, 다른 그룹 비기본 $grpOther"
$ptl = Q1 $T "SELECT GROUP_CONCAT(CONCAT_WS(':',PTL_CD,PTL_TYPE,PTL_ROLES,IFNULL(PTL_ACTION,'-'),IFNULL(IDEMPOTENT_YN,'-'),IFNULL(EXPECT_RULE,'-')) ORDER BY PTL_GRP_CD,PTL_CD SEPARATOR ';') FROM ju_protocol WHERE PTL_ROLES IS NOT NULL"
$expPtl = 'GTEC0000:PROT0003:PROL0001:-:-:{"startsWith":"{OK"};GTEC0001:PROT0003:PROL0001:-:-:{"regex":"^[{][A-Za-z]"};GTEC0002:PROT0003:PROL0001:-:-:{"regex":"^[{][0-9]{3},[0-9]{3},[0-9]{3},[0-9]{3}[}]$"};GTEC0100:PROT0001:PROL0002:-:YENO0001:-;GTEC0300:PROT0001:PROL0002:PACT0001:-:-;GTEC0301:PROT0001:PROL0002:PACT0003:YENO0001:-;GTEC0400:PROT0002:PROL0003:-:-:-'
Check 'U-5' 'GTEC 검증 7개 정정 (유형·역할·동작·멱등·응답판정)' ($ptl -eq $expPtl) $ptl
Log ("  정정하지 않은 GTEC 프로토콜: " + (Q1 $T "SELECT GROUP_CONCAT(PTL_CD ORDER BY PTL_CD) FROM ju_protocol WHERE PTL_GRP_CD='GTEC' AND PTL_ROLES IS NULL"))
$pk = Q1 $T "SELECT GROUP_CONCAT(CONCAT_WS(':',k.PTL_CD,k.PACKET_SEQ,b.ROW_STATE,k.DIRECTION,k.DATA_COUNT,k.PARSE_RULE) ORDER BY k.PTL_CD SEPARATOR ' ; ') FROM ju_protocol_packet k JOIN ju_mig08_bak_packet b ON b.PTL_GRP_CD=k.PTL_GRP_CD AND b.PTL_CD=k.PTL_CD AND b.PACKET_SEQ=k.PACKET_SEQ"
$pkOk = Q1 $T "SELECT COUNT(*) FROM ju_protocol_packet k JOIN ju_mig08_bak_packet b ON b.PTL_GRP_CD=k.PTL_GRP_CD AND b.PTL_CD=k.PTL_CD AND b.PACKET_SEQ=k.PACKET_SEQ WHERE k.DIRECTION='RX' AND k.USE_YN='YENO0001' AND ((k.PTL_CD='GTEC0002' AND k.PARSE_RULE='{`"v`":1,`"kind`":`"INFO`",`"trim`":`"{}`",`"fields`":[`"CH1`",`"CH2`",`"CH3`",`"CH4`"],`"absent`":`"000`"}') OR (k.PTL_CD='GTEC0400' AND k.PARSE_RULE='{`"v`":1,`"kind`":`"TEXT`",`"trim`":`"{}`",`"sep`":`"SPACE`",`"count`":3}'))"
$bakP = Q1 $T "SELECT COUNT(*) FROM ju_mig08_bak_protocol"
Check 'U-6' 'RX 패킷 해석 규칙 (GTEC0002 INFO, GTEC0400 TEXT) + 백업' (($pkOk -eq '2') -and ($bakP -eq '7')) "$pk / 프로토콜 백업 $bakP"
$map = Q1 $T "SELECT GROUP_CONCAT(CONCAT_WS(':',DEV_CD,CHANNEL_KEY,IFNULL(PTL_CD,'*'),DAT_GR_CD,DAT_CD,DAT_IDX,SCALE,OFFSET_VAL,USE_YN) ORDER BY SORT_ORD SEPARATOR ';') FROM ju_data_channel_map"
$expMap = (1..4 | ForEach-Object { "SDEV_GTEC01:${_}:*:DG_GTEC01:GTEC-DATA-0${_}:${_}:1:0:YENO0001" }) -join ';'
Check 'U-7' '채널 매핑 SDEV_GTEC01 1~4 → DG_GTEC01' ($map -eq $expMap) $map
$bad = Q1 $T "SELECT COUNT(*) FROM ju_protocol p WHERE p.PTL_ROLES IS NOT NULL AND (NOT EXISTS (SELECT 1 FROM ju_com_code c WHERE c.GRP_CD='PROT' AND c.COM_CD=p.PTL_TYPE) OR NOT EXISTS (SELECT 1 FROM ju_com_code c WHERE c.GRP_CD='PROL' AND c.COM_CD=p.PTL_ROLES) OR (p.PTL_ACTION IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ju_com_code c WHERE c.GRP_CD='PACT' AND c.COM_CD=p.PTL_ACTION)) OR (p.IDEMPOTENT_YN IS NOT NULL AND p.IDEMPOTENT_YN NOT IN ('YENO0001','YENO0002')))"
Check 'U-8' '정정 값이 공통코드(PROT·PROL·PACT·YENO)에 있음' ($bad -eq '0') "위반 $bad"
$p1 = Pres
Check 'U-9' '기존 데이터 보존 (정정 대상 외 전부 동일)' (($p1 -eq $p0) -and ($p0 -match '^기타 [0-9A-F]{16}, 코드 [0-9A-F]{16}, 다국어 [0-9A-F]{16}, 그룹/프로토콜/패킷 [0-9a-f]{8}/[0-9a-f]{8}/[0-9a-f]{8}$')) $p1
$s1 = Snap 's1'
$T2 = $T + '2'; $bk = Join-Path $src 'bk_t2.sql'
& "$bin\mysqldump.exe" -h localhost -u $U --default-character-set=utf8mb4 --single-transaction --routines --triggers "--result-file=$bk" $T 2>&1 | Out-Null
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T2; CREATE DATABASE $T2 CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
$o = cmd /c "$base $T2 < `"$bk`" 2>&1"; $rc = $LASTEXITCODE; Remove-Item $bk -Force
$m2 = Q1 $T2 "SELECT CONCAT_WS('/',COUNT(*),SUM(PTL_CD_KEY='')) FROM ju_data_channel_map"
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T2`"" | Out-Null
Check 'U-10' '08 적용 DB 덤프→복원 (생성 컬럼 포함)' (($rc -eq 0) -and ($m2 -eq '4/4')) ("복원 exit $rc, 매핑 $m2 " + (($o | Select-Object -First 2) -join ' '))

Log ''; Log '===== 5. 재실행 ====='
Check 'R-1' '08 up 재실행' ((Apply "$mig\08_collect_settings.sql" '08 up (2회)' -Quiet) -eq 0) ''
SameAs 'R-2' '재실행 후 결과 동일' $s1 (Snap 'r2')

Log ''; Log '===== 6. 제약조건 (테스트 DB) ====='
$ins = "INSERT INTO ju_data_channel_map (DEV_CD,CHANNEL_KEY,PTL_CD,DAT_GR_CD,DAT_CD,DAT_IDX) VALUES "
$o = Q $T ($ins + "('SDEV_GTEC01','1',NULL,'DG_GTEC01','GTEC-DATA-01',1)"); Check 'K-1' '중복 매핑 (PTL_CD NULL) 거부' ((($o -join ' ') -match 'ERROR 1062')) (($o -join ' ') -replace '\s+', ' ')
$o = Q $T ($ins + "('SDEV_GTEC01','1','GTEC0400','DG_GTEC01','GTEC-DATA-01',1)"); $k2a = $script:qx
$o2 = Q $T ($ins + "('SDEV_GTEC01','1','GTEC0400','DG_GTEC01','GTEC-DATA-01',1)")
Check 'K-2' 'PTL_CD 지정 매핑 허용, 같은 행 중복 거부' (($k2a -eq 0) -and (($o2 -join ' ') -match 'ERROR 1062')) (($o2 -join ' ') -replace '\s+', ' ')
$o = Q $T ($ins + "('SDEV_GTEC01','CH1',NULL,'DG_GTEC01','GTEC-DATA-01',1),('SDEV_GTEC01','ch1',NULL,'DG_GTEC01','GTEC-DATA-01',1)")
Check 'K-3' 'CHANNEL_KEY 대소문자 구분 (CH1·ch1 둘 다 허용)' ($script:qx -eq 0) (($o -join ' ') -replace '\s+', ' ')
$o = Q $T ($ins + "('NO_SUCH_DEV','1',NULL,'DG_GTEC01','GTEC-DATA-01',1)"); Check 'K-4' 'FK 장치 없음 거부' ((($o -join ' ') -match 'ERROR 1452')) ''
$o = Q $T ($ins + "('SDEV_GTEC01','9',NULL,'DG_GTEC01','NO_TAG',9)"); Check 'K-5' 'FK 데이터 태그 없음 거부' ((($o -join ' ') -match 'ERROR 1452')) ''
$o = Q $T "START TRANSACTION; DELETE FROM ju_data_tag WHERE DAT_GR_CD='DG_GTEC01' AND DAT_CD='GTEC-DATA-01' AND DAT_IDX=1; ROLLBACK;"
Check 'K-6' '매핑된 태그 물리삭제 거부' ((($o -join ' ') -match 'ERROR 1451')) ''
$o = Q1 $T "START TRANSACTION; UPDATE ju_data_tag SET USE_YN='YENO0002' WHERE DAT_GR_CD='DG_GTEC01' AND DAT_CD='GTEC-DATA-01' AND DAT_IDX=1; SELECT ROW_COUNT(); ROLLBACK;"
Check 'K-7' '매핑된 태그 논리삭제 허용 (롤백)' ($o -eq '1') "변경 $($o)행, 롤백"
Q $T "DELETE FROM ju_data_channel_map WHERE CHANNEL_KEY IN ('CH1','ch1') OR PTL_CD='GTEC0400'" | Out-Null
Log ("  정리 후 매핑 " + (Q1 $T "SELECT COUNT(*) FROM ju_data_channel_map") + "행, 태그 USE_YN " + (Q1 $T "SELECT USE_YN FROM ju_data_tag WHERE DAT_GR_CD='DG_GTEC01' AND DAT_CD='GTEC-DATA-01' AND DAT_IDX=1"))

Log ''; Log '===== 7. down / 재실행 / 재적용 ====='
Check 'B-1' '08 down' ((Apply "$mig\08_collect_settings_down.sql" '08 down') -eq 0) ''
SameAs 'B-2' 'down 후 08 전(S0)과 동일' $s0 (Snap 'b2')
Check 'B-3' '08 down 재실행' ((Apply "$mig\08_collect_settings_down.sql" '08 down (2회)' -Quiet) -eq 0) ''
SameAs 'B-4' 'down 재실행 후에도 S0과 동일' $s0 (Snap 'b4')
Check 'B-5' '08 재적용' ((Apply "$mig\08_collect_settings.sql" '08 up (down 후)' -Quiet) -eq 0) ''
SameAs 'B-6' '재적용 결과 = 처음 적용 결과(S1)' $s1 (Snap 'b6')

Log ''; Log '===== 8. 논리삭제 행은 정정하지 않음 ====='
Apply "$mig\08_collect_settings_down.sql" '08 down' -Quiet | Out-Null
$o300 = Q1 $T "SELECT CONCAT_WS('|',PTL_TYPE,USE_YN) FROM ju_protocol WHERE PTL_GRP_CD='GTEC' AND PTL_CD='GTEC0300'"
$o04 = Q1 $T "SELECT USE_YN FROM ju_data_tag WHERE DAT_GR_CD='DG_GTEC01' AND DAT_CD='GTEC-DATA-04' AND DAT_IDX=4"
Q $T "UPDATE ju_protocol SET USE_YN='YENO0002' WHERE PTL_GRP_CD='GTEC' AND PTL_CD='GTEC0300'; UPDATE ju_data_tag SET USE_YN='YENO0002' WHERE DAT_GR_CD='DG_GTEC01' AND DAT_CD='GTEC-DATA-04' AND DAT_IDX=4;" | Out-Null
$l0 = Snap 'l0'
Apply "$mig\08_collect_settings.sql" '08 up (GTEC0300·태그04 논리삭제 상태)' -Quiet | Out-Null
$l300 = Q1 $T "SELECT CONCAT_WS('|',PTL_TYPE,IFNULL(PTL_ROLES,'-'),USE_YN) FROM ju_protocol WHERE PTL_GRP_CD='GTEC' AND PTL_CD='GTEC0300'"
Check 'L-1' '논리삭제 프로토콜(GTEC0300) 변경 없음' ($l300 -eq (($o300.Split('|')[0]) + '|-|YENO0002')) "$l300 (원래 $o300)"
$lmap = Q1 $T "SELECT GROUP_CONCAT(CHANNEL_KEY ORDER BY SORT_ORD) FROM ju_data_channel_map"
$l04 = Q1 $T "SELECT USE_YN FROM ju_data_tag WHERE DAT_GR_CD='DG_GTEC01' AND DAT_CD='GTEC-DATA-04' AND DAT_IDX=4"
Check 'L-2' '논리삭제 태그(04)는 매핑하지 않음, USE_YN 유지' (($lmap -eq '1,2,3') -and ($l04 -eq 'YENO0002')) "매핑 $lmap, 태그04 $l04"
Check 'L-3' '백업은 정정한 6개만' ((Q1 $T "SELECT COUNT(*) FROM ju_mig08_bak_protocol") -eq '6') ''
Apply "$mig\08_collect_settings_down.sql" '08 down' -Quiet | Out-Null
SameAs 'L-4' 'down 후 논리삭제 상태 그대로' $l0 (Snap 'l4')
Q $T ("UPDATE ju_protocol SET USE_YN='" + $o300.Split('|')[1] + "' WHERE PTL_GRP_CD='GTEC' AND PTL_CD='GTEC0300'; UPDATE ju_data_tag SET USE_YN='$o04' WHERE DAT_GR_CD='DG_GTEC01' AND DAT_CD='GTEC-DATA-04' AND DAT_IDX=4;") | Out-Null
SameAs 'L-5' '논리삭제 원복 후 S0과 동일' $s0 (Snap 'l5')

Log ''; Log '===== 9. 07(ju_schema_version) 있을 때 ====='
Q $T @"
CREATE TABLE ju_schema_version (
  SCHEMA_VER varchar(10) NOT NULL, SCRIPT_NM varchar(100) NOT NULL, APPLY_TYPE varchar(10) NOT NULL,
  VERIFY_NOTE varchar(500) DEFAULT NULL, APPLIED_DT datetime(3) NOT NULL DEFAULT current_timestamp(3), APPLIED_BY varchar(100) DEFAULT NULL,
  PRIMARY KEY (SCHEMA_VER)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
"@ | Out-Null
Apply "$mig\08_collect_settings.sql" '08 up (07 테이블 있음)' -Quiet | Out-Null
$v1 = Q1 $T "SELECT CONCAT_WS('|',SCHEMA_VER,SCRIPT_NM,APPLY_TYPE,APPLIED_BY IS NOT NULL) FROM ju_schema_version"
Check 'V-1' "ju_schema_version '08' APPLY 기록" ($v1 -eq '08|08_collect_settings.sql|APPLY|1') $v1
Apply "$mig\08_collect_settings.sql" '08 up (07 테이블 있음, 2회)' -Quiet | Out-Null
Check 'V-2' '재실행해도 기록 1건' ((Q1 $T "SELECT COUNT(*) FROM ju_schema_version") -eq '1') ''
Apply "$mig\08_collect_settings_down.sql" '08 down (07 테이블 있음)' -Quiet | Out-Null
Check 'V-3' "down → '08' 기록 삭제, 테이블 유지" ((Q1 $T "SELECT COUNT(*) FROM ju_schema_version") -eq '0') ''
Q $T 'DROP TABLE ju_schema_version' | Out-Null
SameAs 'V-4' '07 테이블 제거 후 S0과 동일' $s0 (Snap 'v4')

Log ''; Log '===== 10. 정리 · 실제 DB 무변경 ====='
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T`"" | Out-Null
Get-ChildItem $src -Filter 'snap_*.sql' | Remove-Item -Force
Log ("  테스트 DB 삭제: 남은 juprovider* = " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$realAfter = & $realSum
Check 'Z-1' ("실제 DB 무변경 (CHECKSUM " + $realTables.Count + "개 테이블)") ($realBefore -eq $realAfter) ''
$env:MYSQL_PWD = $null

Log ''; Log '===== 11. 로컬 빌드 5종 + 테스트 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Check 'G-1' '빌드 5종' $false '요약 없음' } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
    Check 'G-1' '빌드 5종 + 테스트' (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
}
$bl | Select-String -Pattern 'Tests run: \d+, Failures|통과!|실패!|\[ERROR\]|error CS' | Select-Object -First 30 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }

Log ''; Log '===== 12. 실서버 회귀 (테스트 DB + 06 + 08, ai_c4srv.ps1 -Mig08) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_c4srv.ps1') -Mig08 *>&1 | Out-Null
$sl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_c5b_srv_{0}.log" -f $env:COMPUTERNAME))
$sl | Where-Object { $_ -match '적용\(테스트 DB\)' } | ForEach-Object { Log ('  ' + $_.Trim()) }
$ri = [Array]::IndexOf($sl, '===== 요약 =====')
if ($ri -ge 0) { $sl[$ri..($sl.Length - 1)] | ForEach-Object { Log ('  ' + $_) } }
Check 'G-2' '실서버 회귀 (08 적용 테스트 DB)' (($ri -ge 0) -and ($sl -contains 'FAIL 0')) ''

Log ''; Log '===== 13. 변경 범위 · 로컬 commit (push 없음) ====='
Run $jp 'git add -A database' | Out-Null
$names = @(& git -C $jp diff --cached --name-only)
$other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' -and $_ -notmatch [regex]::Escape($lock) })
Log ("  staged " + $names.Count + ", 기타 " + $other.Count); $names | ForEach-Object { Log ('  ' + $_) }
Check 'G-3' '변경 범위 = database 4개 파일' (($names.Count -eq $files.Count) -and ($other.Count -eq 0)) ''
Log ''; Log '===== 요약 ====='
Log '| # | 항목 | 결과 요약 | 판정 |'
Log '|---|---|---|---|'
foreach ($x in $script:rows) { Log $x }
Log ("FAIL " + $script:fail)
if ($script:fail -gt 0) { Run $jp 'git reset -q' | Out-Null; Stop "FAIL $($script:fail) → commit 하지 않음 (변경은 작업 폴더에 유지)" }
# PC-B에 git 사용자 설정이 없음 → 기존 commit과 같은 작성자를 이 commit에만 지정 (설정 변경 없음)
if ((Run $jp "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -F `"$src\commit_c5b.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
cmd /c "git -C `"$jp`" format-patch -1 --stdout > `"$src\c5b_result.patch`""
Log ("  patch " + (Get-Item "$src\c5b_result.patch").Length + " bytes")
Log 'C5B-DONE'

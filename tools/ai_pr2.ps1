# PR-2 Protocol Backend: feature/protocol-ref (← feature/action-contract 02ab18c), 코드 반영, 빌드 5종(테스트),
#   migration 06 테스트 DB 검증(1·2회, 신규 설치 동일), 18081 Action Contract HTTP smoke(Input/Output/Error),
#   원자성(GRP_CREATE·GRP_DELETE·CREATE) 검증, 테스트 DB 삭제, 로컬 commit. push 없음
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\pr2'
$log = Join-Path $ws ("ai_pr2_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0; $script:pass = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) { $script:pass++; 'PASS' } else { $script:fail++; 'FAIL' }); Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'PR2-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("PR-2 Protocol Backend " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -eq 'feature/action-contract') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop 'feature/action-contract 변경 있음' }
    if ((& git -C $jp log -1 --format=%h) -ne '02ab18c') { Stop 'HEAD가 02ab18c 아님' }
    Run $jp 'git checkout -b feature/protocol-ref' | Out-Null
} elseif ($b -ne 'feature/protocol-ref') { Stop "브랜치 $b" }
$now = Get-Date
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
foreach ($f in $files) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null

Log ''; Log '===== 2. 로컬 빌드 5종 (테스트 포함) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Check '빌드 요약 찾기' $false '' } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | ForEach-Object { Log ('  ' + $_) }
    Check '로컬 빌드 5종' (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
}
$bl | Select-String -Pattern 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+' | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$bl | Select-String -Pattern '\[ERROR\]' | Select-Object -First 25 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($script:fail -gt 0 -or -not (Test-Path $war)) { Stop '빌드 실패' }

Log ''; Log '===== 3. migration 06 (테스트 DB) ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$db, [string]$sql) { return (cmd /c "$base -N -B $db -e `"$sql`" 2>&1") }
function Fd([string]$db, [string]$file, [string]$out) { cmd /c "$base -B $db < `"$file`" > `"$out`" 2>&1"; return $LASTEXITCODE }
$T = 'juprovider_pr2test'; $I = 'juprovider_pr2inst'
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
foreach ($d in $T, $I) { cmd /c "$base -e `"DROP DATABASE IF EXISTS $d; CREATE DATABASE $d CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null }
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force
$db = Join-Path $jp 'database'
$m06 = Join-Path $db 'migration\06_protocol_actions.sql'
Check '06 1회 적용' ((Fd $T $m06 "$src\06_run1.txt") -eq 0) ''
$snapSql = "SELECT a.ACT_CD,a.ACT_KIND,a.HANDLER_ID,a.USE_YN,a.ENABLED_YN,a.SORT_ORD,d.ACT_NM,d.ACT_DESC,d.ACT_NM_KEY,d.ACT_DESC_KEY FROM ju_menu m JOIN ju_menu_action a ON a.MNU_ID=m.MNU_ID LEFT JOIN ju_menu_action_detail d ON d.ACT_ID=a.ACT_ID WHERE m.MNU_CD='M02010100' ORDER BY a.SORT_ORD; SELECT LANG_CD,RES_KEY,RES_VAL FROM ju_multi_lang WHERE RES_KEY LIKE 'ACTION.PROTOCOL.%' ORDER BY LANG_CD,RES_KEY"
$s1 = Ed $T $snapSql
Check '06 Action 10개' (@(Ed $T "SELECT a.ACT_CD FROM ju_menu m JOIN ju_menu_action a ON a.MNU_ID=m.MNU_ID WHERE m.MNU_CD='M02010100'").Count -eq 10) ''
Check '06 2회 적용' ((Fd $T $m06 "$src\06_run2.txt") -eq 0) ''
Check '06 재실행 무변경' ((($s1 -join '|') -eq ((Ed $T $snapSql) -join '|'))) ''
$c1 = Fd $I "$db\baseline\01_ju_core_baseline.sql" "$src\inst_baseline.txt"; $c2 = Fd $I "$db\seed\02_ju_core_seed.sql" "$src\inst_seed.txt"; $c3 = Fd $I "$db\migration\03_validate_baseline.sql" "$src\inst_03.txt"
Check '신규 설치 baseline+seed+03' (($c1 -eq 0) -and ($c2 -eq 0) -and ($c3 -eq 0)) ''
Check '기존 DB+06 = 신규 설치 (M02010100 Action·detail·다국어)' (($s1 -join '|') -eq ((Ed $I $snapSql) -join '|')) ''
cmd /c "$base -e `"DROP DATABASE IF EXISTS $I`"" | Out-Null

Log ''; Log '===== 4. 서버 기동 (18081, 테스트 DB) ====='
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'
$env:JU_DB_URL = ($vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $T))
$env:JU_DB_USER = $vars['JU_DB_USER']; $env:JU_DB_PASSWORD = $vars['JU_DB_PASSWORD']; $env:JU_JWT_SECRET = $vars['JU_JWT_SECRET']
$env:SPRING_PROFILES_ACTIVE = $null
if ($env:JU_DB_URL -notmatch $T) { Stop '테스트 DB URL 치환 실패' }
$p1 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\app_out.txt" -RedirectStandardError "$src\app_err.txt"
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
$api = 'http://localhost:18081/juprovider'
function Call([string]$m, [string]$path, [string]$tok, $body) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }
    $p = @{ Uri = $api + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json; charset=utf-8' }
    if ($null -ne $body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress -Depth 8)) }
    try { $r = Invoke-WebRequest @p; $c = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()); $j = $null; if ($c) { try { $j = $c | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j; raw = $c; hdr = $r.Headers } }
    catch {
        $code = 0; $c = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream(), [Text.Encoding]::UTF8); $c = $sr.ReadToEnd() } catch {} }
        $j = $null; if ($c) { try { $j = $c | ConvertFrom-Json } catch {} }
        return @{ code = $code; json = $j; raw = $c; hdr = $null }
    }
}
function Act([string]$tok, [string]$act, $params, $ver) {
    $body = @{ parameters = $params }; if ($null -ne $ver) { $body['contractVersion'] = $ver }
    return Call 'POST' "/api/action/M02010100/$act" $tok $body
}
function ErrHas($r, [string]$field, [string]$code) { return @($r.json.errors | Where-Object { $_.field -eq $field -and $_.code -eq $code }).Count -ge 1 }
function Keys($o) { if ($null -eq $o) { return '' }; return (($o.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') }
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; if ((Call 'GET' '/api/health' '' $null).code -eq 200) { $ready = $true; break } }
Check '서버 기동' $ready ''

if ($ready) {
    Log ''; Log '===== 5. smoke 사용자 ====='
    function NewPw { -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!a1' }
    function BHash([string]$pw) {
        $jar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object FullName | Select-Object -Last 1
        $env:SMOKE_PW = $pw; $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$ws\ai_changes\ju1a\bcrypt.jsh`" 2>&1"; $env:SMOKE_PW = $null
        return (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
    }
    $tok = @{}; $pws = @{}
    foreach ($u in @(@('smoke_admin', 1), @('smoke_mgr', 2), @('smoke_usr', 4))) {
        $pw = NewPw; $pws[$u[0]] = $pw
        Ed $T ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('" + $u[0] + "','" + (BHash $pw) + "'," + $u[1] + ",'YENO0001')") | Out-Null
        Ed $T ("INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT,PW_CHANGE_DT) SELECT USER_ID,'" + $u[0] + "',0,NOW() FROM ju_user WHERE LOGIN_ID='" + $u[0] + "'") | Out-Null
        $r = Call 'POST' '/api/auth/login' '' @{ loginId = $u[0]; password = $pw }; $tok[$u[0]] = $r.json.data.accessToken
        Check ("로그인 " + $u[0]) (($r.code -eq 200) -and $tok[$u[0]]) ("code=" + $r.code)
    }
    $ta = $tok['smoke_admin']; $tm = $tok['smoke_mgr']; $tu = $tok['smoke_usr']

    Log ''; Log '===== 6. Output Contract (조회) ====='
    $r = Act $ta 'GRP_SEARCH' @{} $null
    $g = @($r.json.data.items | Where-Object { $_.ptlGrpCd -eq 'GTEC' })
    Check 'GRP_SEARCH 200, contractVersion=1, list={items,total}, X-JU-Request-Id' (($r.code -eq 200) -and $r.json.contractVersion -eq 1 -and ((Keys $r.json.data) -eq 'items,total') -and ($r.json.data.total -eq @($r.json.data.items).Count) -and $r.hdr['X-JU-Request-Id']) ("code=" + $r.code + " keys=" + (Keys $r.json.data))
    Check 'GRP_SEARCH 항목 필드 = 계약 출력' (($g.Count -eq 1) -and ((Keys $g[0]) -eq 'ptlGrpCd,ptlGrpNm,ptlGrpDesc,pollingIntval,timeoutMs,retryCnt,useYn,sortOrd,protocolCount') -and ($g[0].protocolCount -ge 1)) ("keys=" + (Keys $g[0]))
    Check 'GRP_SEARCH 기본은 사용 중만 (GETC 제외)' (@($r.json.data.items | Where-Object { $_.ptlGrpCd -eq 'GETC' }).Count -eq 0) ''
    $r = Act $ta 'GRP_SEARCH' @{ useYn = 'YENO0000' } $null
    Check 'GRP_SEARCH useYn=YENO0000 → 전체 (GETC 포함)' (@($r.json.data.items | Where-Object { $_.ptlGrpCd -eq 'GETC' }).Count -eq 1) ''
    $r = Act $ta 'GRP_GET' @{ ptlGrpCd = 'GTEC' } 1
    Check 'GRP_GET record + 다국어 키 규칙' (($r.code -eq 200) -and $r.json.data.ptlGrpNmKey -eq 'PROTOCOL_GROUP.GTEC.NM' -and $r.json.data.ptlGrpDescKey -eq 'PROTOCOL_GROUP.GTEC.DESC') ("code=" + $r.code)
    $r = Act $ta 'SEARCH' @{ ptlGrpCd = 'GTEC' } $null
    $it = @($r.json.data.items)
    Check 'SEARCH list, 항목 필드 = 계약 출력' (($r.code -eq 200) -and $it.Count -ge 1 -and ((Keys $it[0]) -eq 'ptlGrpCd,ptlCd,ptlType,ptlTypeNm,ptlLen,ptlNm,ptlDesc,useYn,packetCount')) ("keys=" + (Keys $it[0]))
    $r = Act $ta 'GET' @{ ptlGrpCd = 'GTEC'; ptlCd = 'GTEC0001' } $null
    Check 'GET record + packets 목록 + 다국어 키' (($r.code -eq 200) -and ($r.raw -match '"packets":\[') -and $r.json.data.ptlNmKey -eq 'PROTOCOL.GTEC.GTEC0001.NM' -and $r.json.data.ptlTypeNm) ("code=" + $r.code)

    Log ''; Log '===== 7. Input / Error Contract ====='
    $r = Act $ta 'GRP_GET' @{} $null
    Check '필수 누락 → 400 VALIDATION / REQUIRED(ptlGrpCd)' (($r.code -eq 400) -and $r.json.code -eq 'VALIDATION' -and (ErrHas $r 'ptlGrpCd' 'REQUIRED')) ("code=" + $r.code)
    $r = Act $ta 'GRP_GET' @{ ptlGrpCd = 'GTEC'; extra = 1 } $null
    Check '선언 안 된 필드 → 400 UNKNOWN_FIELD(extra)' (($r.code -eq 400) -and (ErrHas $r 'extra' 'UNKNOWN_FIELD')) ("code=" + $r.code)
    $r = Act $ta 'CREATE' @{ ptlGrpCd = 'GTEC'; ptlCd = 'SMKV001'; ptlType = 'PROT9999'; ptlLen = '12'; ptlNm = ('a' * 101); packets = @(@{ packetSeq = 1; direction = 'TX'; bogus = 1 }) } $null
    Check 'CREATE 오류 모음: INVALID_CODE·TYPE_MISMATCH·MAX_LENGTH·중첩 UNKNOWN_FIELD' (($r.code -eq 400) -and (ErrHas $r 'ptlType' 'INVALID_CODE') -and (ErrHas $r 'ptlLen' 'TYPE_MISMATCH') -and (ErrHas $r 'ptlNm' 'MAX_LENGTH') -and (ErrHas $r 'packets[0].bogus' 'UNKNOWN_FIELD')) ("errors=" + (($r.json.errors | ForEach-Object { $_.field + ':' + $_.code }) -join ','))
    $r = Act $ta 'CREATE' @{ ptlGrpCd = 'GTEC'; ptlCd = 'SMKV001'; ptlType = 'PROT0003'; ptlNm = 'v'; packets = @(@{ packetSeq = 1; direction = 'TX' }, @{ packetSeq = 1; direction = 'XX' }) } $null
    Check '업무 검증: packetSeq 중복 DUPLICATE, direction INVALID_VALUE' (($r.code -eq 400) -and (ErrHas $r 'packets[1].packetSeq' 'DUPLICATE') -and (ErrHas $r 'packets[1].direction' 'INVALID_VALUE')) ("code=" + $r.code)
    $r = Act $ta 'GRP_SEARCH' @{} 2
    Check 'contractVersion 불일치 → 400 CONTRACT_VERSION_MISMATCH' (($r.code -eq 400) -and (ErrHas $r 'contractVersion' 'CONTRACT_VERSION_MISMATCH')) ("code=" + $r.code)
    $r = Act $ta 'GRP_GET' @{ ptlGrpCd = 'NOPE' } $null
    Check '없는 그룹 → 404 NOT_FOUND' (($r.code -eq 404) -and $r.json.code -eq 'NOT_FOUND') ("code=" + $r.code)
    $r = Act $ta 'NOPE' @{} $null
    Check '정의 없는 Action → 404' ($r.code -eq 404) ("code=" + $r.code)
    $r = Act $tm 'GRP_SEARCH' @{} $null
    Check '비관리자(01) 조회 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Act $tm 'GRP_CREATE' @{ ptlGrpCd = 'SMKM'; ptlGrpNm = 'm' } $null
    Check '비관리자 등록 → 403 FORBIDDEN' (($r.code -eq 403) -and $r.json.code -eq 'FORBIDDEN') ("code=" + $r.code)
    $r = Act $tu 'GRP_SEARCH' @{} $null
    Check 'M02010100 권한 없는 사용자 조회 → 403' ($r.code -eq 403) ("code=" + $r.code)

    Log ''; Log '===== 8. CRUD + 다국어 ====='
    $r = Act $ta 'GRP_CREATE' @{ ptlGrpCd = 'SMKA'; ptlGrpNm = '스모크A'; ptlGrpDesc = '설명A' } $null
    Check 'GRP_CREATE → key 출력 {ptlGrpCd}만' (($r.code -eq 200) -and ((Keys $r.json.data) -eq 'ptlGrpCd') -and $r.json.data.ptlGrpCd -eq 'SMKA') ("code=" + $r.code + " " + $r.raw)
    Check 'GRP_CREATE: 그룹·detail 키·LANG0001' (([string](Ed $T "SELECT CONCAT(g.USE_YN,'|',d.PTL_GRP_NM_KEY,'|',d.PTL_GRP_DESC_KEY,'|',ml.RES_VAL) FROM ju_protocol_group g JOIN ju_protocol_group_detail d ON d.PTL_GRP_CD=g.PTL_GRP_CD JOIN ju_multi_lang ml ON ml.LANG_CD='LANG0001' AND ml.RES_KEY=d.PTL_GRP_NM_KEY WHERE g.PTL_GRP_CD='SMKA'")) -eq 'YENO0001|PROTOCOL_GROUP.SMKA.NM|PROTOCOL_GROUP.SMKA.DESC|스모크A') ''
    Check 'GRP_CREATE: 기본 프로토콜 SMKA0000 (PROT0000, 기본 TX/RX, 키 규칙)' (([string](Ed $T "SELECT CONCAT(p.PTL_TYPE,'|',p.USE_YN,'|',d.PTL_NM,'|',d.PTL_NM_KEY,'|',ml.RES_VAL) FROM ju_protocol p JOIN ju_protocol_detail d ON d.PTL_GRP_CD=p.PTL_GRP_CD AND d.PTL_CD=p.PTL_CD JOIN ju_multi_lang ml ON ml.LANG_CD='LANG0001' AND ml.RES_KEY=d.PTL_NM_KEY WHERE p.PTL_GRP_CD='SMKA' AND p.PTL_CD='SMKA0000'")) -eq 'PROT0000|YENO0001|기본 TX/RX|PROTOCOL.SMKA.SMKA0000.NM|기본 TX/RX') ''
    $r = Act $ta 'GRP_CREATE' @{ ptlGrpCd = 'SMKA'; ptlGrpNm = 'x' } $null
    Check '중복 그룹 → 409 CONFLICT' (($r.code -eq 409) -and $r.json.code -eq 'CONFLICT') ("code=" + $r.code)
    $r = Act $ta 'CREATE' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001'; ptlType = 'PROT0003'; ptlLen = 8; ptlVal = 'S{10}'; ptlNm = '측정'; packets = @(@{ packetSeq = 1; direction = 'TX'; packetExpr = 'S{10}' }, @{ packetSeq = 2; direction = 'RX'; dataCount = 3 }) } $null
    Check 'CREATE → key {ptlGrpCd,ptlCd}' (($r.code -eq 200) -and ((Keys $r.json.data) -eq 'ptlGrpCd,ptlCd')) ("code=" + $r.code + " " + $r.raw)
    $r = Act $ta 'GET' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001' } $null
    Check 'GET: 패킷 2개, PTL_VAL 저장' (($r.code -eq 200) -and @($r.json.data.packets).Count -eq 2 -and $r.json.data.ptlVal -eq 'S{10}') ("code=" + $r.code)
    $r = Act $ta 'UPDATE' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001'; ptlNm = '측정2'; ptlVal = 'S{11}'; packets = @(@{ packetSeq = 5; direction = 'TX' }) } $null
    $g2 = Act $ta 'GET' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001' } $null
    Check 'UPDATE: 패킷 전체 교체(1개), 이름·PTL_VAL·LANG0001 갱신' (($r.code -eq 200) -and @($g2.json.data.packets).Count -eq 1 -and $g2.json.data.packets[0].packetSeq -eq 5 -and $g2.json.data.ptlNm -eq '측정2' -and $g2.json.data.ptlVal -eq 'S{11}' -and ([string](Ed $T "SELECT RES_VAL FROM ju_multi_lang WHERE LANG_CD='LANG0001' AND RES_KEY='PROTOCOL.SMKA.SMKA0001.NM'")) -eq '측정2') ("code=" + $r.code)
    $r = Act $ta 'UPDATE' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001'; useYn = 'YENO0002' } $null
    Check 'UPDATE로 삭제 시도 → 400 INVALID_VALUE(useYn)' (($r.code -eq 400) -and (ErrHas $r 'useYn' 'INVALID_VALUE')) ("code=" + $r.code)
    $r = Act $ta 'CREATE' @{ ptlGrpCd = 'NOGRP'; ptlCd = 'NOGRP0001'; ptlType = 'PROT0000'; ptlNm = 'x' } $null
    Check '없는 그룹에 CREATE → 404' ($r.code -eq 404) ("code=" + $r.code)
    $r = Act $ta 'GRP_UPDATE' @{ ptlGrpCd = 'SMKA'; ptlGrpNm = '스모크A2'; timeoutMs = 5000 } $null
    Check 'GRP_UPDATE: 이름·LANG0001·timeout 갱신' (($r.code -eq 200) -and ([string](Ed $T "SELECT CONCAT(g.TIMEOUT_MS,'|',ml.RES_VAL) FROM ju_protocol_group g JOIN ju_multi_lang ml ON ml.LANG_CD='LANG0001' AND ml.RES_KEY='PROTOCOL_GROUP.SMKA.NM' WHERE g.PTL_GRP_CD='SMKA'")) -eq '5000|스모크A2') ("code=" + $r.code)
    $r = Act $ta 'GRP_UPDATE' @{ ptlGrpCd = 'SMKA'; timeoutMs = 0 } $null
    Check 'GRP_UPDATE timeoutMs=0 → 400 INVALID_VALUE' (($r.code -eq 400) -and (ErrHas $r 'timeoutMs' 'INVALID_VALUE')) ("code=" + $r.code)
    $r = Act $ta 'DELETE' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001' } $null
    Check 'DELETE: 프로토콜·패킷 논리 삭제' (($r.code -eq 200) -and ([string](Ed $T "SELECT CONCAT((SELECT USE_YN FROM ju_protocol WHERE PTL_GRP_CD='SMKA' AND PTL_CD='SMKA0001'),'|',(SELECT COUNT(*) FROM ju_protocol_packet WHERE PTL_GRP_CD='SMKA' AND PTL_CD='SMKA0001' AND USE_YN='YENO0001'))")) -eq 'YENO0002|0') ("code=" + $r.code)
    $r = Act $ta 'DELETE' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001' } $null
    Check '이미 삭제된 프로토콜 DELETE → 404' ($r.code -eq 404) ("code=" + $r.code)
    $r = Act $ta 'UPDATE' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0001'; useYn = 'YENO0001' } $null
    Check 'UPDATE useYn=YENO0001 → 재사용' (($r.code -eq 200) -and ([string](Ed $T "SELECT USE_YN FROM ju_protocol WHERE PTL_GRP_CD='SMKA' AND PTL_CD='SMKA0001'")) -eq 'YENO0001') ("code=" + $r.code)

    Log ''; Log '===== 9. GRP_DELETE 전체 선검사 (Device + Experiment) ====='
    $r = Act $ta 'GRP_DELETE' @{ ptlGrpCd = 'GTEC' } $null
    Check 'GTEC(사용 중 장치 있음) GRP_DELETE → 409' (($r.code -eq 409) -and $r.json.code -eq 'CONFLICT') ("code=" + $r.code)
    Act $ta 'GRP_CREATE' @{ ptlGrpCd = 'SMKB'; ptlGrpNm = 'B' } $null | Out-Null
    Act $ta 'CREATE' @{ ptlGrpCd = 'SMKB'; ptlCd = 'SMKB0001'; ptlType = 'PROT0000'; ptlNm = 'b1'; packets = @(@{ packetSeq = 1; direction = 'TX' }) } $null | Out-Null
    Ed $T "INSERT INTO ju_device (DEV_CD,DEV_TYPE,DEV_FORM,DEV_COMM,PTL_GRP_CD,DEV_CH,DEV_DAT_CNT,USE_YN) VALUES ('SMKDEV1','DEVI0000','DEVF0000','DEVC0000','SMKB',1,1,'YENO0001'),('SMKDEV2','DEVI0000','DEVF0000','DEVC0000',NULL,1,1,'YENO0001')" | Out-Null
    Ed $T "INSERT INTO ju_data_group (DAT_GR_CD,DEV_CD,USE_YN,SORT_ORD) VALUES ('SMKDG1','SMKDEV2','YENO0001',0)" | Out-Null
    $exp = [string](Ed $T "INSERT INTO ju_experiment (EXP_STAT,USE_YN) VALUES ('EXPI0000','YENO0001'); SELECT LAST_INSERT_ID()")
    Ed $T "INSERT INTO ju_experiment_data_group (EXP_ID,DAT_GR_CD,SORT_ORD,START_PTL_CD,PAUSE_PTL_CD,STOP_PTL_CD,VIEW_YN,USE_YN) VALUES ($exp,'SMKDG1',0,NULL,NULL,'SMKB0001','YENO0001','YENO0001')" | Out-Null
    $stateSql = "SELECT CONCAT((SELECT USE_YN FROM ju_protocol_group WHERE PTL_GRP_CD='SMKB'),'|',(SELECT GROUP_CONCAT(CONCAT(PTL_CD,'=',USE_YN) ORDER BY PTL_CD) FROM ju_protocol WHERE PTL_GRP_CD='SMKB'),'|',(SELECT GROUP_CONCAT(USE_YN) FROM ju_protocol_packet WHERE PTL_GRP_CD='SMKB'))"
    $before = [string](Ed $T $stateSql)
    $r = Act $ta 'GRP_DELETE' @{ ptlGrpCd = 'SMKB' } $null
    Check '장치+실험 동시 참조 → 409, 메시지에 둘 다' (($r.code -eq 409) -and ($r.json.message -match 'SMKDEV1') -and ($r.json.message -match "${exp}:SMKB0001")) ("code=" + $r.code + " " + $r.json.message)
    Check '409 후 Group/Protocol/Packet 변경 없음' (([string](Ed $T $stateSql)) -eq $before) ("state=" + $before)
    $r = Act $ta 'DELETE' @{ ptlGrpCd = 'SMKB'; ptlCd = 'SMKB0001' } $null
    Check '실험 참조 프로토콜 DELETE → 409' ($r.code -eq 409) ("code=" + $r.code)
    Ed $T "UPDATE ju_device SET USE_YN='YENO0002' WHERE DEV_CD='SMKDEV1'" | Out-Null
    $r = Act $ta 'GRP_DELETE' @{ ptlGrpCd = 'SMKB' } $null
    Check '장치 해제 후에도 실험 참조로 409 (전체 선검사)' (($r.code -eq 409) -and ($r.json.message -notmatch 'SMKDEV1') -and (([string](Ed $T $stateSql)) -eq $before)) ("code=" + $r.code)
    Ed $T "UPDATE ju_experiment_data_group SET USE_YN='YENO0002' WHERE EXP_ID=$exp" | Out-Null
    $r = Act $ta 'GRP_DELETE' @{ ptlGrpCd = 'SMKB' } $null
    Check '참조 해제 후 GRP_DELETE 200 → Group·Protocol 2개·Packet 모두 논리 삭제' (($r.code -eq 200) -and (([string](Ed $T $stateSql)) -eq 'YENO0002|SMKB0000=YENO0002,SMKB0001=YENO0002|YENO0002')) ("state=" + [string](Ed $T $stateSql))
    $r = Act $ta 'CREATE' @{ ptlGrpCd = 'SMKB'; ptlCd = 'SMKB0009'; ptlType = 'PROT0000'; ptlNm = 'x' } $null
    Check '삭제된 그룹에 CREATE → 409' ($r.code -eq 409) ("code=" + $r.code)

    Log ''; Log '===== 10. 원자성 (트리거로 중간 실패 주입) ====='
    function Trig([string]$sql) { $f = Join-Path $src 'trig.sql'; [IO.File]::WriteAllText($f, "DELIMITER //`r`n$sql //`r`nDELIMITER ;`r`n", $enc); return (Fd $T $f "$src\trig_out.txt") }
    $tc = Trig "CREATE TRIGGER smk_fail_ptl_ins BEFORE INSERT ON ju_protocol FOR EACH ROW BEGIN IF NEW.PTL_GRP_CD = 'SMKX' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'smoke'; END IF; END"
    Check '트리거 생성 (ju_protocol INSERT)' ($tc -eq 0) (Get-Content "$src\trig_out.txt" -Raw)
    $r = Act $ta 'GRP_CREATE' @{ ptlGrpCd = 'SMKX'; ptlGrpNm = 'X'; ptlGrpDesc = 'x' } $null
    Check 'GRP_CREATE 기본 프로토콜 실패 → 500, 그룹·detail·다국어 모두 rollback' (($r.code -eq 500) -and ([string](Ed $T "SELECT (SELECT COUNT(*) FROM ju_protocol_group WHERE PTL_GRP_CD='SMKX')+(SELECT COUNT(*) FROM ju_protocol_group_detail WHERE PTL_GRP_CD='SMKX')+(SELECT COUNT(*) FROM ju_multi_lang WHERE RES_KEY LIKE 'PROTOCOL_GROUP.SMKX.%')")) -eq '0') ("code=" + $r.code)
    Ed $T "DROP TRIGGER IF EXISTS smk_fail_ptl_ins" | Out-Null

    Act $ta 'GRP_CREATE' @{ ptlGrpCd = 'SMKY'; ptlGrpNm = 'Y' } $null | Out-Null
    Act $ta 'CREATE' @{ ptlGrpCd = 'SMKY'; ptlCd = 'SMKY0001'; ptlType = 'PROT0000'; ptlNm = 'y1'; packets = @(@{ packetSeq = 1; direction = 'TX' }, @{ packetSeq = 2; direction = 'RX' }) } $null | Out-Null
    $tc = Trig "CREATE TRIGGER smk_fail_grp_upd BEFORE UPDATE ON ju_protocol_group FOR EACH ROW BEGIN IF NEW.PTL_GRP_CD = 'SMKY' AND NEW.USE_YN = 'YENO0002' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'smoke'; END IF; END"
    Check '트리거 생성 (ju_protocol_group UPDATE)' ($tc -eq 0) ''
    $ySql = "SELECT CONCAT((SELECT USE_YN FROM ju_protocol_group WHERE PTL_GRP_CD='SMKY'),'|',(SELECT GROUP_CONCAT(USE_YN ORDER BY PTL_CD) FROM ju_protocol WHERE PTL_GRP_CD='SMKY'),'|',(SELECT GROUP_CONCAT(USE_YN ORDER BY PACKET_SEQ) FROM ju_protocol_packet WHERE PTL_GRP_CD='SMKY'))"
    $r = Act $ta 'GRP_DELETE' @{ ptlGrpCd = 'SMKY' } $null
    Check 'GRP_DELETE 마지막 단계(그룹) 실패 → 500, Packet·Protocol 논리삭제 rollback' (($r.code -eq 500) -and (([string](Ed $T $ySql)) -eq 'YENO0001|YENO0001,YENO0001|YENO0001,YENO0001')) ("state=" + [string](Ed $T $ySql))
    Ed $T "DROP TRIGGER IF EXISTS smk_fail_grp_upd" | Out-Null
    $r = Act $ta 'GRP_DELETE' @{ ptlGrpCd = 'SMKY' } $null
    Check '트리거 제거 후 GRP_DELETE 200 → 모두 YENO0002' (($r.code -eq 200) -and (([string](Ed $T $ySql)) -eq 'YENO0002|YENO0002,YENO0002|YENO0002,YENO0002')) ("state=" + [string](Ed $T $ySql))

    $tc = Trig "CREATE TRIGGER smk_fail_pkt_ins BEFORE INSERT ON ju_protocol_packet FOR EACH ROW BEGIN IF NEW.PACKET_SEQ = 99 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'smoke'; END IF; END"
    $r = Act $ta 'CREATE' @{ ptlGrpCd = 'SMKA'; ptlCd = 'SMKA0099'; ptlType = 'PROT0000'; ptlNm = 'z'; packets = @(@{ packetSeq = 1; direction = 'TX' }, @{ packetSeq = 99; direction = 'RX' }) } $null
    Check 'CREATE 두 번째 패킷 실패 → 500, 프로토콜·detail·패킷·다국어 rollback' (($tc -eq 0) -and ($r.code -eq 500) -and ([string](Ed $T "SELECT (SELECT COUNT(*) FROM ju_protocol WHERE PTL_CD='SMKA0099')+(SELECT COUNT(*) FROM ju_protocol_detail WHERE PTL_CD='SMKA0099')+(SELECT COUNT(*) FROM ju_protocol_packet WHERE PTL_CD='SMKA0099')+(SELECT COUNT(*) FROM ju_multi_lang WHERE RES_KEY LIKE 'PROTOCOL.SMKA.SMKA0099.%')")) -eq '0') ("code=" + $r.code)
    Ed $T "DROP TRIGGER IF EXISTS smk_fail_pkt_ins" | Out-Null

    Log ''; Log '===== 11. 회귀·기동 ====='
    $r = Call 'POST' '/api/action/15/SEARCH' $ta @{ parameters = @{} }
    Check 'Device menuId 경로 SEARCH 200 (기존 배열 모양)' (($r.code -eq 200) -and ($r.raw -match '"data":\[')) ("code=" + $r.code)
    $w = Get-Content "$src\app_out.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Select-String -Pattern '\[ACTION\]'
    $w | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
    Check '기동 WARN: Handler 없는 Action 8건(Device만, PROTOCOL 없음)' ((@($w | Where-Object { $_.Line -match '8건' }).Count -ge 1) -and (@($w | Where-Object { $_.Line -match 'PROTOCOL\.' }).Count -eq 0)) ''
    $texts = (Get-Content $log -Raw) + ((Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join '')
    $hit = $false; foreach ($v in $pws.Values) { if ($texts.IndexOf([string]$v) -ge 0) { $hit = $true } }
    Check '로그에 비밀번호 원문 없음' (-not $hit) ''
    $pws = $null; $tok = $null; $ta = $null; $tm = $null; $tu = $null
}
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
foreach ($d in $T, $I) { cmd /c "$base -e `"DROP DATABASE IF EXISTS $d`"" | Out-Null }
Log ("  테스트 DB 삭제: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null
Log ("smoke: PASS " + $script:pass + " / FAIL " + $script:fail)

Log ''; Log '===== 12. 로컬 commit (push 없음) ====='
if ($script:fail -gt 0) { Stop "FAIL $($script:fail) → commit 하지 않음" }
Run $jp 'git add database juprovider.core juprovider.backend' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("  staged $n (예상 " + $files.Count + "), 기타 $other")
if ($n -ne $files.Count -or $other -ne 0) { Stop '예상 외 변경' }
if ((Run $jp "git commit -F `"$src\commit_pr2.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
Log ("결과: FAIL " + $script:fail)
Log 'PR2-DONE'

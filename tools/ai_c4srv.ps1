# C4 실서버 검증: feature/collect-c4 WAR + 테스트 DB(실제 DB 덤프 사본) 18081. 실제 DB는 mysqldump(읽기)만, 변경 검증은 테스트 DB의 테스트 데이터로.
# 비밀 값(DB 비밀번호·JWT·Client Key·사용자 비밀번호)은 로그에 쓰지 않는다. 제품 저장소 변경 없음.
param([switch]$Fix)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c4srv'
$log = Join-Path $ws ($(if ($Fix) {'ai_c4b_srv_{0}.log'} else {'ai_c4srv_{0}.log'}) -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $src | Out-Null
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0; $script:rows = @()
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) {
    $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }
    $script:rows += ("| {0} | {1} | {2} | {3} |" -f $id, $name, $note, $r); Log ("  [$r] $id $name $note")
}
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'C4SRV-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("C4 SERVER " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / WAR ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD); $h = (& git -C $jp log -1 --format=%h)
Log "  branch $b @ $h"
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($Fix) {
    if ($b -ne 'feature/collect-c4') { Stop 'feature/collect-c4 아님' }
    if (-not (Test-Path $war) -or (Get-Item $war).LastWriteTime -lt (Get-Date).AddMinutes(-30)) { Stop '방금 빌드한 WAR 없음' }
    $ct = (Get-Item $war).LastWriteTime
} else {
if ($b -ne 'feature/collect-c4' -or $h -ne 'd3a560a') { Stop 'feature/collect-c4 @ d3a560a 아님' }
if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop '작업 폴더 변경 있음' }
$ct = [DateTime]::Parse((& git -C $jp log -1 --format=%cI))
if (-not (Test-Path $war) -or (Get-Item $war).LastWriteTime -lt $ct.AddMinutes(-10)) { Stop 'C4 WAR 없음 또는 오래됨' }
}
Log ("  WAR " + (Get-Item $war).LastWriteTime.ToString('HH:mm:ss') + " (commit " + $ct.ToLocalTime().ToString('HH:mm:ss') + ")")
if ((Test-NetConnection localhost -Port 18081 -WarningAction SilentlyContinue).TcpTestSucceeded) { Stop '18081 사용 중' }

Log ''; Log '===== 2. 테스트 DB (실제 DB 덤프 사본) ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$db, [string]$sql) { return (cmd /c "$base -N -B $db -e `"$sql`" 2>&1") }
$T = 'juprovider_c4test'
function V([string]$sql) { return ([string]((Ed $T $sql) -join ' ')).Trim() }
$realSum = { (Ed 'juprovider' "CHECKSUM TABLE ju_protocol_group, ju_protocol_group_detail, ju_protocol, ju_protocol_detail, ju_protocol_packet, ju_data_group, ju_data_tag, ju_data_tag_detail, ju_device, ju_client, ju_user") -join ' ; ' }
$realBefore = & $realSum
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T; CREATE DATABASE $T CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force

Log ''; Log '===== 3. 서버 기동 (18081, 테스트 DB) ====='
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'
$env:JU_DB_URL = ($vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $T))
$env:JU_DB_USER = $vars['JU_DB_USER']; $env:JU_DB_PASSWORD = $vars['JU_DB_PASSWORD']; $env:JU_JWT_SECRET = $vars['JU_JWT_SECRET']
$env:SPRING_PROFILES_ACTIVE = $null
if ($env:JU_DB_URL -notmatch $T) { Stop '테스트 DB URL 치환 실패' }
$p1 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\app_out.txt" -RedirectStandardError "$src\app_err.txt"
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
$api = 'http://localhost:18081/juprovider'
$cb = Join-Path $src 'curl_body.txt'
function C([string]$m, [string]$path, [string]$id, [string]$key, [string]$bearer, [string]$data) {
    $a = @('-s', '-o', $cb, '-w', '%{http_code}', '-X', $m)
    if ($id) { $a += @('-H', "X-JU-Client-Id: $id") }
    if ($key) { $a += @('-H', "X-JU-Client-Key: $key") }
    if ($bearer) { $a += @('-H', "Authorization: Bearer $bearer") }
    $bf = Join-Path $src 'curl_req.json'
    if ($data) { [IO.File]::WriteAllText($bf, $data, $enc); $a += @('-H', 'Content-Type: application/json', '--data-binary', "@$bf") }
    $code = (& curl.exe @a ($api + $path))
    if ($data) { Remove-Item $bf -Force -ErrorAction SilentlyContinue }
    $body = ''; if (Test-Path $cb) { $body = (Get-Content $cb -Raw -Encoding UTF8) }
    $j = $null; try { $j = $body | ConvertFrom-Json } catch {}
    return @{ code = [string]$code; body = [string]$body; json = $j }
}
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; if ((C 'GET' '/api/health' '' '' '' '').code -eq '200') { $ready = $true; break } }
Log ("  서버 기동 " + $ready)

if ($ready) {
    Log ''; Log '===== 4. 테스트 관리자 · Client ====='
    function NewPw { -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!a1' }
    $jar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object FullName | Select-Object -Last 1
    $pw = NewPw
    $env:SMOKE_PW = $pw; $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$ws\ai_changes\ju1a\bcrypt.jsh`" 2>&1"; $env:SMOKE_PW = $null
    $hash = (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
    Ed $T ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('smoke_c4','" + $hash + "',1,'YENO0001')") | Out-Null
    Ed $T "INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT,PW_CHANGE_DT) SELECT USER_ID,'smoke_c4',0,NOW() FROM ju_user WHERE LOGIN_ID='smoke_c4'" | Out-Null
    $r = C 'POST' '/api/auth/login' '' '' '' ('{"loginId":"smoke_c4","password":"' + $pw + '"}')
    $ta = $r.json.data.accessToken; Log ("  관리자 로그인 " + $r.code)
    if (-not $ta) { Log '  로그인 실패 → 이후 검증 무효' }
    $r = C 'POST' '/api/admin/clients' '' '' $ta '{"clientId":"SMOKE_C4","clientName":"c4 sync smoke"}'
    $ck = $r.json.data.clientKey; Log ("  테스트 Client 등록 " + $r.code + " (키 발급 " + [bool]$ck + ")")
    $CID = 'SMOKE_C4'

    Log ''; Log '===== 5. 검증 ====='
    # --- 1. protocols ---
    $gN = V "SELECT COUNT(*) FROM ju_protocol_group WHERE USE_YN='YENO0001'"
    $pN = V "SELECT COUNT(*) FROM ju_protocol p JOIN ju_protocol_group g ON g.PTL_GRP_CD=p.PTL_GRP_CD AND g.USE_YN='YENO0001' WHERE p.USE_YN='YENO0001'"
    $kN = V "SELECT COUNT(*) FROM ju_protocol_packet k JOIN ju_protocol p ON p.PTL_GRP_CD=k.PTL_GRP_CD AND p.PTL_CD=k.PTL_CD AND p.USE_YN='YENO0001' JOIN ju_protocol_group g ON g.PTL_GRP_CD=k.PTL_GRP_CD AND g.USE_YN='YENO0001' WHERE k.USE_YN='YENO0001'"
    $r = C 'GET' '/api/core/sync/protocols' $CID $ck '' ''
    $items = @($r.json.items); $ip = ($items | ForEach-Object { @($_.protocols).Count } | Measure-Object -Sum).Sum; $ik = ($items | ForEach-Object { $_.protocols | ForEach-Object { @($_.packets).Count } } | Measure-Object -Sum).Sum
    Check '1-1' 'GET /sync/protocols 전체' (($r.code -eq '200') -and ([string]$items.Count -eq $gN) -and ([string]$ip -eq $pN) -and ([string]$ik -eq $kN) -and ($r.json.revision.Length -eq 64) -and (@($r.json.removed).Count -eq 0)) ("HTTP " + $r.code + ", 그룹 $($items.Count)/DB $gN, 프로토콜 $ip/$pN, 패킷 $ik/$kN, removed 0")
    $r = C 'GET' '/api/core/sync/protocols/GTEC' $CID $ck '' ''
    if (-not $r.json) { $r.json = @{ items = @(@{ ptlGrpCd = ''; protocols = @(); timeoutMs = '' }) } }
    $gp = V "SELECT COUNT(*) FROM ju_protocol WHERE PTL_GRP_CD='GTEC' AND USE_YN='YENO0001'"
    Check '1-2' 'GET /sync/protocols/GTEC' (($r.code -eq '200') -and (@($r.json.items).Count -eq 1) -and ($r.json.items[0].ptlGrpCd -eq 'GTEC') -and ([string]@($r.json.items[0].protocols).Count -eq $gp)) ("HTTP " + $r.code + ", 그룹 1, 프로토콜 " + @($r.json.items[0].protocols).Count + "/DB $gp, timeoutMs " + $r.json.items[0].timeoutMs)
    $r = C 'GET' '/api/core/sync/protocols/C4T_NONE' $CID $ck '' ''
    Check '1-3' 'GET /sync/protocols/{없는 그룹}' ($r.code -eq '404') ("HTTP " + $r.code)

    # --- 2. data-tags ---
    $tN = V "SELECT COUNT(*) FROM ju_data_tag t JOIN ju_data_group g ON g.DAT_GR_CD=t.DAT_GR_CD AND g.USE_YN='YENO0001' WHERE t.USE_YN='YENO0001'"
    $r = C 'GET' '/api/core/sync/data-tags' $CID $ck '' ''
    Check '2-1' 'GET /sync/data-tags 전체' (($r.code -eq '200') -and ([string]@($r.json.items).Count -eq $tN)) ("HTTP " + $r.code + ", 태그 " + @($r.json.items).Count + "/DB $tN")
    $sN = V "SELECT COUNT(*) FROM ju_data_tag t JOIN ju_data_group g ON g.DAT_GR_CD=t.DAT_GR_CD AND g.USE_YN='YENO0001' WHERE t.USE_YN='YENO0001' AND g.DEV_CD='SDEV_GTEC01'"
    $r = C 'GET' '/api/core/sync/data-tags?devCd=SDEV_GTEC01' $CID $ck '' ''
    $it = @($r.json.items)
    Check '2-2' 'GET /sync/data-tags?devCd=SDEV_GTEC01' (($r.code -eq '200') -and ([string]$it.Count -eq $sN) -and (@($it | Where-Object { $_.devCd -ne 'SDEV_GTEC01' }).Count -eq 0)) ("HTTP " + $r.code + ", 태그 $($it.Count)/DB $sN (" + (($it | ForEach-Object { $_.tagId }) -join ',') + ")")
    $r = C 'GET' '/api/core/sync/data-tags?devCd=C4T_NONE' $CID $ck '' ''
    Check '2-3' 'GET /sync/data-tags?devCd={없는 장치}' (($r.code -eq '200') -and (@($r.json.items).Count -eq 0)) ("HTTP " + $r.code + ", 태그 " + @($r.json.items).Count)

    # --- 3. 인증 ---
    foreach ($case in @(
        @('3-1', '정상 키', $CID, $ck, '', '200'),
        @('3-2', '헤더 누락', '', '', '', '401'),
        @('3-3', 'Client-Id 만', $CID, '', '', '401'),
        @('3-4', '잘못된 키', $CID, 'wrong-key-000', '', '401'),
        @('3-5', '없는 Client-Id', 'NO_SUCH_CLIENT', $ck, '', '401'),
        @('3-6', '관리자 JWT 만 (Client 체인 불인정)', '', '', $ta, '401'))) {
        $codes = @()
        foreach ($pth in '/api/core/sync/protocols', '/api/core/sync/protocols/GTEC', '/api/core/sync/data-tags') { $codes += (C 'GET' $pth $case[2] $case[3] $case[4] '').code }
        Check $case[0] ("인증 " + $case[1]) (@($codes | Where-Object { $_ -ne $case[5] }).Count -eq 0) ("HTTP " + ($codes -join '/') + " (기대 " + $case[5] + ")")
    }
    $r = C 'POST' '/api/core/sync/protocols' $CID $ck '' '{}'
    if ($Fix) { Check '3-7' 'POST /sync/protocols (조회 전용)' (($r.code -eq '405') -and ($r.json.success -eq $false)) ("HTTP " + $r.code + ", " + $r.json.message) }
    else { Check '3-7' '쓰기 메서드 POST /sync/protocols' ($r.code -in '403', '404', '405') ("HTTP " + $r.code + " (조회 전용, 처리 안 됨)") }

    # --- 4. USE_YN 필터·순서 (테스트 DB 테스트 데이터) ---
    $sql = @(
        "INSERT INTO ju_protocol_group (PTL_GRP_CD,POLLING_INTVAL,TIMEOUT_MS,RETRY_CNT,USE_YN,SORT_ORD) VALUES ('C4T_B',1000,1500,1,'YENO0001',-2),('C4T_A',1000,1500,1,'YENO0001',-1),('C4T_DEL',1000,1500,1,'YENO0002',-3)",
        "INSERT INTO ju_protocol_group_detail (PTL_GRP_CD,PTL_GRP_NM,PTL_GRP_NM_KEY) VALUES ('C4T_B','c4 b','C4T.B.NM'),('C4T_A','c4 a','C4T.A.NM'),('C4T_DEL','c4 del','C4T.DEL.NM')",
        "INSERT INTO ju_protocol (PTL_GRP_CD,PTL_CD,PTL_TYPE,PTL_VAL,USE_YN) VALUES ('C4T_A','P2','PROT0003','B','YENO0001'),('C4T_A','P1','PROT0003','A','YENO0001'),('C4T_A','P9','PROT0003','X','YENO0002'),('C4T_DEL','D1','PROT0003','X','YENO0001')",
        "INSERT INTO ju_protocol_packet (PTL_GRP_CD,PTL_CD,PACKET_SEQ,DIRECTION,PACKET_EXPR,USE_YN) VALUES ('C4T_A','P1',2,'RX','r','YENO0001'),('C4T_A','P1',1,'TX','t','YENO0001'),('C4T_A','P1',3,'RX','x','YENO0002'),('C4T_A','P9',1,'TX','x','YENO0001')",
        "INSERT INTO ju_device (DEV_CD,DEV_TYPE,DEV_COMM,DEV_CH,DEV_DAT_CNT,USE_YN) VALUES ('C4T_DEV','DEVI0000','DEVC0000',1,1,'YENO0001')",
        "INSERT INTO ju_data_group (DAT_GR_CD,DEV_CD,USE_YN,SORT_ORD) VALUES ('C4T_DG','C4T_DEV','YENO0001',0),('C4T_DGX','C4T_DEV','YENO0002',1)",
        "INSERT INTO ju_data_tag (DAT_GR_CD,DAT_CD,DAT_IDX,DAT_TYPE,TAG_ID,USE_YN,SORT_ORD) VALUES ('C4T_DG','T_B',1,'DATA0001','CH2','YENO0001',2),('C4T_DG','T_A',1,'DATA0001','CH1','YENO0001',1),('C4T_DG','T_DEL',1,'DATA0001','CH3','YENO0002',0),('C4T_DGX','T_X',1,'DATA0001','CH1','YENO0001',0)")
    foreach ($q in $sql) { $o = Ed $T $q; if ($LASTEXITCODE -ne 0) { Log ("  테스트 데이터 오류: " + ($o -join ' ')) } }
    $r = C 'GET' '/api/core/sync/protocols' $CID $ck '' ''
    $codes = @($r.json.items | ForEach-Object { $_.ptlGrpCd })
    $a = @($r.json.items | Where-Object { $_.ptlGrpCd -eq 'C4T_A' })[0]
    $pc = @($a.protocols | ForEach-Object { $_.ptlCd }); $sq = @(@($a.protocols | Where-Object { $_.ptlCd -eq 'P1' })[0].packets | ForEach-Object { $_.packetSeq })
    $ok = ($codes[0] -eq 'C4T_B') -and ($codes[1] -eq 'C4T_A') -and ($codes -notcontains 'C4T_DEL') -and (($pc -join ',') -eq 'P1,P2') -and (($sq -join ',') -eq '1,2')
    Check '4-1' '프로토콜 USE_YN 필터·순서' $ok ("HTTP " + $r.code + ", 그룹 앞 2개 " + ($codes[0..1] -join ',') + " (SORT_ORD), 삭제 그룹 제외 " + ($codes -notcontains 'C4T_DEL') + ", C4T_A 프로토콜 " + ($pc -join ',') + " (P9 삭제 제외), P1 패킷 " + ($sq -join ',') + " (seq3 삭제 제외)")
    $r = C 'GET' '/api/core/sync/protocols/C4T_DEL' $CID $ck '' ''
    Check '4-2' '논리삭제 그룹 단건 조회' ($r.code -eq '404') ("HTTP " + $r.code)
    $r = C 'GET' '/api/core/sync/data-tags?devCd=C4T_DEV' $CID $ck '' ''
    $tc = @($r.json.items | ForEach-Object { $_.datCd })
    Check '4-3' '데이터 태그 USE_YN 필터·순서' (($r.code -eq '200') -and (($tc -join ',') -eq 'T_A,T_B')) ("HTTP " + $r.code + ", " + ($tc -join ',') + " (T_DEL 태그·C4T_DGX 그룹 삭제 제외, SORT_ORD 순)")

    # --- 5. revision ---
    $r1 = (C 'GET' '/api/core/sync/protocols' $CID $ck '' '').json.revision
    $r2 = (C 'GET' '/api/core/sync/protocols' $CID $ck '' '').json.revision
    Ed $T "UPDATE ju_protocol_group SET TIMEOUT_MS=1600 WHERE PTL_GRP_CD='C4T_A'" | Out-Null
    $r3 = (C 'GET' '/api/core/sync/protocols' $CID $ck '' '').json.revision
    Ed $T "UPDATE ju_protocol_group SET TIMEOUT_MS=1500 WHERE PTL_GRP_CD='C4T_A'" | Out-Null
    $r4 = (C 'GET' '/api/core/sync/protocols' $CID $ck '' '').json.revision
    Check '5-1' 'protocols revision 유지·갱신' ($r1 -and ($r1 -eq $r2) -and ($r1 -ne $r3) -and ($r1 -eq $r4)) ("동일 " + ($r1 -eq $r2) + ", TIMEOUT_MS 변경 후 갱신 " + ($r1 -ne $r3) + ", 원복 후 원래 값 " + ($r1 -eq $r4) + " (" + ([string]$r1).PadRight(12).Substring(0, 12) + "…)")
    $d1 = (C 'GET' '/api/core/sync/data-tags?devCd=C4T_DEV' $CID $ck '' '').json.revision
    $d2 = (C 'GET' '/api/core/sync/data-tags?devCd=C4T_DEV' $CID $ck '' '').json.revision
    Ed $T "UPDATE ju_data_tag SET DAT_UNIT='V' WHERE DAT_GR_CD='C4T_DG' AND DAT_CD='T_A'" | Out-Null
    $d3 = (C 'GET' '/api/core/sync/data-tags?devCd=C4T_DEV' $CID $ck '' '').json.revision
    Ed $T "UPDATE ju_protocol_packet SET PACKET_EXPR='t2' WHERE PTL_GRP_CD='C4T_A' AND PTL_CD='P1' AND PACKET_SEQ=1" | Out-Null
    $r5 = (C 'GET' '/api/core/sync/protocols' $CID $ck '' '').json.revision
    Check '5-2' 'data-tags revision 유지·갱신, 패킷 변경 반영' ($d1 -and ($d1 -eq $d2) -and ($d1 -ne $d3) -and ($r5 -ne $r4)) ("동일 " + ($d1 -eq $d2) + ", DAT_UNIT 변경 후 갱신 " + ($d1 -ne $d3) + ", PACKET_EXPR 변경 후 protocols 갱신 " + ($r5 -ne $r4))

    # --- 6. Desktop 역직렬화 → CollectionPlan ---
    Log '  > c4srvplan (JuProviderApiClient → CollectionPlanBuilder)'
    $prj = Join-Path $ws 'ai_changes\c4srvplan\C4SrvPlan.csproj'
    $o = & dotnet build $prj -c Debug -v q -nologo 2>&1; $bc = $LASTEXITCODE
    foreach ($x in $o) { if ($x -match 'error|오류 [1-9]') { Log ('    ' + $x) } }
    if ($bc -eq 0) {
        $env:C4_CLIENT_ID = $CID; $env:C4_CLIENT_KEY = $ck
        $po = & dotnet run --project $prj -c Debug --no-build -- $api SDEV_GTEC01 2>&1; $pc6 = $LASTEXITCODE
        $env:C4_CLIENT_ID = $null; $env:C4_CLIENT_KEY = $null
        foreach ($x in $po) { Log ('    ' + $x) }
        $passN = @($po | Where-Object { $_ -match '^\[PASS\]' }).Count; $failN = @($po | Where-Object { $_ -match '^\[FAIL\]' }).Count
        Check '6-1' '실제 응답 → Desktop 역직렬화 → CollectionPlan' ($pc6 -eq 0) ("하위 확인 PASS $passN / FAIL $failN")
    } else { Check '6-1' '실제 응답 → Desktop 역직렬화 → CollectionPlan' $false '도구 빌드 실패' }

    if ($Fix) {
        Log '  --- 9. 기존 API 회귀 ---'
        $r = C 'GET' '/api/health' '' '' '' ''; Check '9-1' 'GET /api/health' ($r.code -eq '200') ("HTTP " + $r.code)
        $r = C 'POST' '/api/auth/login' '' '' '' '{"loginId":"smoke_c4","password":"wrong-pw-000"}'; Check '9-2' '로그인 잘못된 비밀번호' ($r.code -eq '401') ("HTTP " + $r.code)
        $r = C 'POST' '/api/auth/login' '' '' '' '{"loginId":'; Check '9-3' '로그인 JSON 형식 오류' ($r.code -eq '400') ("HTTP " + $r.code)
        $r = C 'GET' '/api/auth/me' '' '' $ta ''; Check '9-4' 'GET /api/auth/me (JWT)' ($r.code -eq '200') ("HTTP " + $r.code)
        $r = C 'GET' '/api/admin/clients' '' '' $ta ''; Check '9-5' 'GET /api/admin/clients (관리자)' ($r.code -eq '200') ("HTTP " + $r.code)
        $r = C 'GET' '/api/core/languages' '' '' $ta ''; Check '9-6' 'GET /api/core/languages' ($r.code -eq '200') ("HTTP " + $r.code)
        $r = C 'GET' '/api/core/sync/devices' $CID $ck '' ''; Check '9-7' 'GET /api/core/sync/devices (Client 키)' (($r.code -eq '200') -and (@($r.json).Count -gt 0)) ("HTTP " + $r.code + ", 장치 " + @($r.json).Count)
        $r = C 'GET' '/api/core/sync/devices/SDEV_GTEC01' $CID $ck '' ''; Check '9-8' 'GET /api/core/sync/devices/{dev}' (($r.code -eq '200') -and ($r.body -match 'SDEV_GTEC01')) ("HTTP " + $r.code)
        $r = C 'DELETE' '/api/core/sync/devices' $CID $ck '' ''; Check '9-9' 'DELETE /api/core/sync/devices (미지원)' ($r.code -eq '405') ("HTTP " + $r.code)
        $r = C 'GET' '/api/core/sync/devices' '' '' '' ''; Check '9-10' 'GET /sync/devices 무헤더' ($r.code -eq '401') ("HTTP " + $r.code)
        $r = C 'POST' '/api/action/15/SEARCH' '' '' $ta '{"parameters":{}}'; Check '9-11' 'Action 실행 POST /api/action/15/SEARCH (장치 조회)' ($r.code -eq '200') ("HTTP " + $r.code)
        $r = C 'GET' '/api/action/15/SEARCH' '' '' $ta ''; Check '9-12' 'GET /api/action/15/SEARCH (미지원 메서드)' ($r.code -eq '405') ("HTTP " + $r.code)
    }

    Log ''; Log '===== 6. 서버 로그 오류 ====='
    $err = @(Get-Content "$src\app_out.txt","$src\app_err.txt" -ErrorAction SilentlyContinue | Select-String -Pattern 'ERROR|Exception' | Select-Object -First 10)
    foreach ($x in $err) { Log ('  ' + $x.Line.Substring(0, [Math]::Min(220, $x.Line.Length))) }
    Log ("  ERROR/Exception 줄 " + $err.Count)

    Log ''; Log '===== 7. 비밀 값 ====='
    Remove-Item $cb -Force -ErrorAction SilentlyContinue
    $texts = (Get-Content $log -Raw) + ((Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join '')
    $hit = $false; foreach ($v in @($pw, $ck, $ta)) { if ($v -and $texts.IndexOf([string]$v) -ge 0) { $hit = $true } }
    Check '7-1' '로그에 비밀번호·Client Key·토큰 원문 없음' (-not $hit) ''
    $pw = $null; $ck = $null; $ta = $null
}
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T`"" | Out-Null
Log ("  테스트 DB 삭제: 남은 juprovider* = " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$realAfter = & $realSum
Check '8-1' '실제 DB 무변경 (CHECKSUM 11개 테이블)' ($realBefore -eq $realAfter) ''
$env:MYSQL_PWD = $null
Log ''; Log '===== 요약 ====='
Log '| # | 항목 | HTTP·응답 요약 | 결과 |'
Log '|---|---|---|---|'
foreach ($x in $script:rows) { Log $x }
Log ("FAIL " + $script:fail)
Log 'C4SRV-DONE'

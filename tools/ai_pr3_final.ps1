# PR-3 최종 확인 (코드 수정 없음): feature/protocol-ref@1d1c1ab 빌드 5종, 테스트 DB(+06), API smoke 12 + Protocol CRUD 최종 확인. 종료 후 DB 삭제. commit/push 없음
#
# 실제 juprovider DB는 mysqldump(읽기)만. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\pr3final'
$log = Join-Path $ws ("ai_pr3final_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'PR3F-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("PR-3 final " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD); $h = (& git -C $jp log -1 --format=%h)
Log "  브랜치 $b @ $h"
if ($b -ne 'feature/protocol-ref' -or $h -ne '1d1c1ab') { Stop '브랜치/HEAD가 feature/protocol-ref@1d1c1ab 아님' }
if (@(& git -C $jp status --porcelain).Count -ne 0) { Run $jp 'git status --short' | Out-Null; Stop '미커밋 변경 있음' }
New-Item -ItemType Directory -Force -Path $src | Out-Null
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
$bl | Select-String -Pattern '\[ERROR\]' | Select-Object -First 20 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($script:fail -gt 0 -or -not (Test-Path $war)) { Stop '빌드 실패' }

Log ''; Log '===== 3. 테스트 DB (실제 DB 덤프 사본) ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$db, [string]$sql) { return (cmd /c "$base -N -B $db -e `"$sql`" 2>&1") }
$T = 'juprovider_pr3ftest'
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
function Call([string]$m, [string]$path, [string]$tok, $body, [string]$raw) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }
    $p = @{ Uri = $api + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($raw) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes($raw) } elseif ($body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress -Depth 6)) }
    try { $r = Invoke-WebRequest @p; $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j; raw = $r.Content; hdr = $r.Headers } }
    catch {
        $code = 0; $c = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $c = $sr.ReadToEnd() } catch {} }
        $j = $null; if ($c) { try { $j = $c | ConvertFrom-Json } catch {} }
        return @{ code = $code; json = $j; raw = $c; hdr = $null }
    }
}
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; if ((Call 'GET' '/api/health' '' $null $null).code -eq 200) { $ready = $true; break } }
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
    foreach ($u in @(@('smoke_admin', 1), @('smoke_mgr', 2))) {
        $pw = NewPw; $pws[$u[0]] = $pw
        Ed $T ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('" + $u[0] + "','" + (BHash $pw) + "'," + $u[1] + ",'YENO0001')") | Out-Null
        Ed $T ("INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT,PW_CHANGE_DT) SELECT USER_ID,'" + $u[0] + "',0,NOW() FROM ju_user WHERE LOGIN_ID='" + $u[0] + "'") | Out-Null
        $r = Call 'POST' '/api/auth/login' '' @{ loginId = $u[0]; password = $pw } $null; $tok[$u[0]] = $r.json.data.accessToken
        Check ("로그인 " + $u[0]) (($r.code -eq 200) -and $tok[$u[0]]) ("code=" + $r.code)
    }
    $ta = $tok['smoke_admin']; $tm = $tok['smoke_mgr']

    
    Log ''; Log '===== 6. API smoke ====='
    foreach ($pth in '/api/core/protocol-groups', '/api/core/protocols/PROT') {
        $r = Call 'GET' $pth $ta $null $null
        Check ("레거시 $pth → 404 (AC10 제거)") ($r.code -eq 404) ("code=" + $r.code)
    }
    $r = Call 'GET' '/api/core/data-groups' $ta $null $null
    Check '/api/core/data-groups → 200 (회귀)' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010100/GRP_SEARCH' $ta @{ contractVersion = 1; parameters = @{} } $null
    Check 'executeByCode 형태 GRP_SEARCH v1 → 200 {items,total}' (($r.code -eq 200) -and ($r.raw -match '"items"')) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010100/GRP_SEARCH' $ta @{ contractVersion = 2; parameters = @{} } $null
    Check 'contractVersion 2 → 400 CONTRACT_VERSION_MISMATCH' (($r.code -eq 400) -and ($r.raw -match 'CONTRACT_VERSION_MISMATCH')) ("code=" + $r.code)
    $r = Call 'GET' '/api/auth/me' $tm $null $null
    $pm = @($r.json.data.menus | Where-Object { $_.menuCode -eq 'M02010100' })
    Check '/me smoke_mgr M02010100 permission 01 (버튼 숨김 기준)' (($pm.Count -eq 1) -and ($pm[0].permission -eq '01')) ("perm=" + $pm[0].permission)
    $r = Call 'GET' '/api/auth/me' $ta $null $null
    $pa = @($r.json.data.menus | Where-Object { $_.menuCode -eq 'M02010100' })
    Check '/me smoke_admin M02010100 permission FF, menuUrl=/console/device/protocol' (($pa.Count -eq 1) -and ($pa[0].permission -eq 'FF') -and ($pa[0].menuUrl -eq '/console/device/protocol')) ("perm=" + $pa[0].permission)
    $r = Invoke-WebRequest -Uri ($api + '/console/device/protocol') -UseBasicParsing -ErrorAction SilentlyContinue
    Check 'SPA 경로 /console/device/protocol → 200 (index.html)' ($r.StatusCode -eq 200) ("code=" + $r.StatusCode)

    Log ''; Log '===== 7. Protocol CRUD 최종 확인 (API) ====='
    function A([string]$tok, [string]$act, $p) { return (Call 'POST' ('/api/action/M02010100/' + $act) $tok @{ contractVersion = 1; parameters = $p } $null) }
    function ErrHas($r, [string]$field, [string]$code) { return @($r.json.errors | Where-Object { $_.field -eq $field -and $_.code -eq $code }).Count -ge 1 }
    function V([string]$sql) { return [string](Ed $T $sql) }
    $G = 'SMKF'; $GD = 'SMKD'; $P = 'SMKFP1'
    $r = A $tm 'GRP_SEARCH' @{}; Check '조회자 GRP_SEARCH 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = A $tm 'SEARCH' @{ ptlGrpCd = 'GTEC' }; Check '조회자 SEARCH 200' ($r.code -eq 200) ("code=" + $r.code)
    $deny = @(@('GRP_CREATE', @{ ptlGrpCd = 'MGRX'; ptlGrpNm = 'x' }), @('GRP_UPDATE', @{ ptlGrpCd = 'GTEC' }), @('GRP_DELETE', @{ ptlGrpCd = 'GTEC' }), @('CREATE', @{ ptlGrpCd = 'GTEC'; ptlCd = 'X1'; ptlType = 'PROT0000'; ptlNm = 'x' }), @('UPDATE', @{ ptlGrpCd = 'GTEC'; ptlCd = 'GTEC0000' }), @('DELETE', @{ ptlGrpCd = 'GTEC'; ptlCd = 'GTEC0000' }))
    foreach ($x in $deny) { $r = A $tm $x[0] $x[1]; Check ("조회자 " + $x[0] + " → 403") ($r.code -eq 403) ("code=" + $r.code) }

    $r = A $ta 'GRP_CREATE' @{ ptlGrpCd = $G; ptlGrpNm = 'final smoke'; pollingIntval = 500 }; Check "GRP_CREATE $G → 200" ($r.code -eq 200) ("code=" + $r.code)
    $r = A $ta 'GET' @{ ptlGrpCd = $G; ptlCd = ($G + '0000') }; Check '기본 프로토콜 {grp}0000 자동생성' (($r.code -eq 200) -and $r.json.data.ptlCd -eq ($G + '0000')) ("code=" + $r.code)
    $r = A $ta 'GRP_CREATE' @{ ptlGrpCd = $G; ptlGrpNm = 'dup' }; Check 'GRP_CREATE 중복 → 409' ($r.code -eq 409) ("code=" + $r.code)
    $r = A $ta 'GRP_UPDATE' @{ ptlGrpCd = $G; ptlGrpNm = 'final edited'; ptlGrpDesc = 'd1' }
    $r2 = A $ta 'GRP_GET' @{ ptlGrpCd = $G }; Check 'GRP_UPDATE 반영' (($r.code -eq 200) -and $r2.json.data.ptlGrpNm -eq 'final edited') ("code=" + $r.code)

    function PktCnt { return [int](Ed $T "SELECT COUNT(*) FROM ju_protocol_packet WHERE PTL_GRP_CD='$G' AND PTL_CD='$P' AND USE_YN='YENO0001'") }
    $r = A $ta 'CREATE' @{ ptlGrpCd = $G; ptlCd = $P; ptlType = 'PROT0001'; ptlNm = 'p1'; ptlDesc = 'desc1'; packets = @(@{ packetSeq = 1; direction = 'TX'; packetExpr = 'AA' }, @{ packetSeq = 2; direction = 'RX' }) }
    Check "CREATE $P 패킷 2건" (($r.code -eq 200) -and (PktCnt) -eq 2) ("code=" + $r.code)
    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; ptlNm = 'p1 edited' }; Check 'UPDATE packets 미전송 → 유지 2' (($r.code -eq 200) -and (PktCnt) -eq 2) ("code=" + $r.code)
    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; packets = @(@{ packetSeq = 5; direction = 'TX' }) }; Check 'UPDATE packets 1건 → 전체교체 1' (($r.code -eq 200) -and (PktCnt) -eq 1) ("code=" + $r.code)
    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; packets = @() }; Check 'UPDATE packets [] → 0' (($r.code -eq 200) -and (PktCnt) -eq 0) ("code=" + $r.code + " cnt=" + (PktCnt))
    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; packets = @(@{ packetSeq = 1; direction = 'TX' }, @{ packetSeq = 1; direction = 'RX' }) }
    Check '패킷 순번 중복 → 400 DUPLICATE, 무변경' (($r.code -eq 400) -and (ErrHas $r 'packets[1].packetSeq' 'DUPLICATE') -and (PktCnt) -eq 0) ("code=" + $r.code)
    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; ptlDesc = '' }
    Log ("  [INFO] ptlDesc='' 전송 → code=" + $r.code + ", DB PTL_DESC=" + (V "SELECT IFNULL(PTL_DESC,'<NULL>') FROM ju_protocol_detail WHERE PTL_GRP_CD='$G' AND PTL_CD='$P'") + " (현재 동작: 지워지지 않음)")

    $r = A $ta 'DELETE' @{ ptlGrpCd = $G; ptlCd = $P }; Check 'DELETE → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = A $ta 'SEARCH' @{ ptlGrpCd = $G }; Check 'SEARCH 기본: 삭제 프로토콜 제외' (($r.code -eq 200) -and @($r.json.data.items | Where-Object { $_.ptlCd -eq $P }).Count -eq 0) ''
    $r = A $ta 'SEARCH' @{ ptlGrpCd = $G; useYn = 'YENO0000' }; Check 'SEARCH 전체: YENO0002 표시' (@($r.json.data.items | Where-Object { $_.ptlCd -eq $P -and $_.useYn -eq 'YENO0002' }).Count -eq 1) ''
    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; useYn = 'YENO0002' }; Check 'UPDATE useYn=YENO0002 → 400 (비활성은 DELETE로만)' ($r.code -eq 400) ("code=" + $r.code)
    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; useYn = 'YENO0001' }; Check '재사용 useYn=YENO0001 → 200, 활성' (($r.code -eq 200) -and (V "SELECT USE_YN FROM ju_protocol WHERE PTL_GRP_CD='$G' AND PTL_CD='$P'") -eq 'YENO0001') ("code=" + $r.code)
    $r = A $ta 'CREATE' @{ ptlGrpCd = $G; ptlCd = $P; ptlType = 'PROT0000'; ptlNm = 'dup' }; Check 'CREATE 중복 → 409' ($r.code -eq 409) ("code=" + $r.code)

    $exp = V "SELECT edg.EXP_ID FROM ju_experiment_data_group edg JOIN ju_experiment e ON e.EXP_ID=edg.EXP_ID AND e.USE_YN='YENO0001' WHERE edg.USE_YN='YENO0001' ORDER BY edg.EXP_ID LIMIT 1"
    $dgr = V "SELECT DAT_GR_CD FROM ju_experiment_data_group WHERE EXP_ID=$exp AND USE_YN='YENO0001' ORDER BY DAT_GR_CD LIMIT 1"
    $oldPause = V "SELECT IFNULL(PAUSE_PTL_CD,'') FROM ju_experiment_data_group WHERE EXP_ID=$exp AND DAT_GR_CD='$dgr'"
    Ed $T "UPDATE ju_experiment_data_group SET PAUSE_PTL_CD='$P' WHERE EXP_ID=$exp AND DAT_GR_CD='$dgr'" | Out-Null
    $r = A $ta 'DELETE' @{ ptlGrpCd = $G; ptlCd = $P }; Check "실험($exp) 참조 프로토콜 DELETE → 409" ($r.code -eq 409) ("code=" + $r.code)
    $r = A $ta 'GRP_DELETE' @{ ptlGrpCd = $G }; Check '실험 참조 그룹 GRP_DELETE → 409' ($r.code -eq 409) ("code=" + $r.code)
    Check '409 후 그룹·프로토콜 활성 유지' ((V "SELECT CONCAT((SELECT USE_YN FROM ju_protocol_group WHERE PTL_GRP_CD='$G'),'/',(SELECT USE_YN FROM ju_protocol WHERE PTL_GRP_CD='$G' AND PTL_CD='$P'))") -eq 'YENO0001/YENO0001') ''
    Ed $T "UPDATE ju_experiment_data_group SET PAUSE_PTL_CD=NULLIF('$oldPause','') WHERE EXP_ID=$exp AND DAT_GR_CD='$dgr'" | Out-Null

    $r = A $ta 'GRP_CREATE' @{ ptlGrpCd = $GD; ptlGrpNm = 'device ref' }
    $dev = V "SELECT DEV_CD FROM ju_device WHERE USE_YN='YENO0001' ORDER BY DEV_CD LIMIT 1"
    $oldGrp = V "SELECT IFNULL(PTL_GRP_CD,'') FROM ju_device WHERE DEV_CD='$dev'"
    Ed $T "UPDATE ju_device SET PTL_GRP_CD='$GD' WHERE DEV_CD='$dev'" | Out-Null
    $r = A $ta 'GRP_DELETE' @{ ptlGrpCd = $GD }; Check "장치($dev) 참조 그룹 GRP_DELETE → 409, 활성 유지" (($r.code -eq 409) -and (V "SELECT USE_YN FROM ju_protocol_group WHERE PTL_GRP_CD='$GD'") -eq 'YENO0001') ("code=" + $r.code)
    Ed $T "UPDATE ju_device SET PTL_GRP_CD=NULLIF('$oldGrp','') WHERE DEV_CD='$dev'" | Out-Null
    $r = A $ta 'GRP_DELETE' @{ ptlGrpCd = 'GTEC' }; Check 'GTEC(실데이터 장치·실험 참조) GRP_DELETE → 409' ($r.code -eq 409) ("code=" + $r.code)

    $r = A $ta 'UPDATE' @{ ptlGrpCd = $G; ptlCd = $P; packets = @(@{ packetSeq = 1; direction = 'TX' }) }
    $r = A $ta 'GRP_DELETE' @{ ptlGrpCd = $G }; Check '참조 없음 GRP_DELETE → 200' ($r.code -eq 200) ("code=" + $r.code)
    $act = V "SELECT CONCAT((SELECT COUNT(*) FROM ju_protocol_group WHERE PTL_GRP_CD='$G' AND USE_YN='YENO0001'),'/',(SELECT COUNT(*) FROM ju_protocol WHERE PTL_GRP_CD='$G' AND USE_YN='YENO0001'),'/',(SELECT COUNT(*) FROM ju_protocol_packet WHERE PTL_GRP_CD='$G' AND USE_YN='YENO0001'))"
    Check '그룹·프로토콜·패킷 일괄 논리삭제 (활성 0/0/0)' ($act -eq '0/0/0') ("활성=" + $act)
    $r = A $ta 'GRP_SEARCH' @{}; Check 'GRP_SEARCH 기본: 삭제 그룹 제외' (@($r.json.data.items | Where-Object { $_.ptlGrpCd -eq $G }).Count -eq 0) ''
    $r = A $ta 'CREATE' @{ ptlGrpCd = $G; ptlCd = 'SMKFP2'; ptlType = 'PROT0000'; ptlNm = 'x' }; Check '삭제 그룹에 CREATE → 409' ($r.code -eq 409) ("code=" + $r.code)
    $r = A $ta 'GRP_UPDATE' @{ ptlGrpCd = $G; useYn = 'YENO0001' }; Check '그룹 재사용 → 200, 활성' (($r.code -eq 200) -and (V "SELECT USE_YN FROM ju_protocol_group WHERE PTL_GRP_CD='$G'") -eq 'YENO0001') ("code=" + $r.code)
    $r = A $ta 'GRP_DELETE' @{ ptlGrpCd = $GD }; Check '장치 참조 해제 후 GRP_DELETE → 200' ($r.code -eq 200) ("code=" + $r.code)

    $texts = (Get-Content $log -Raw) + ((Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join '')
    $hit = $false; foreach ($v in $pws.Values) { if ($texts.IndexOf([string]$v) -ge 0) { $hit = $true } }
    Check '로그에 비밀번호 원문 없음' (-not $hit) ''
    $pws = $null; $tok = $null; $ta = $null; $tm = $null
}
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T`"" | Out-Null
Log ("  테스트 DB 삭제: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null
Log ("  git status 변경: " + (@(& git -C $jp status --porcelain).Count) + "건")
Log ("결과: FAIL " + $script:fail)
Log 'PR3F-DONE'

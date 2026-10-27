# SEC-S1 Client 쓰기 경로 차단: feature/sec-s1 (← main fce5048), 코드 반영, 로컬 빌드 5종(테스트 포함),
#   테스트 DB + 18081 smoke(Client sync GET 유지, 쓰기 403, 무인증 401, Device 정의 무변경, Action 회귀), 테스트 DB 삭제, 로컬 commit. push 없음
# 실제 juprovider DB는 mysqldump(읽기)만. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\secs1'
$log = Join-Path $ws ("ai_secs1_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'SECS1-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("SEC-S1 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -ne 'feature/sec-s1') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop "현재 브랜치 $b 에 미커밋 변경 있음" }
    if ((& git -C $jp rev-parse --short origin/main) -ne 'fce5048') { Stop 'origin/main이 fce5048 아님' }
    Log ("  기존 브랜치: $b @ " + (& git -C $jp log -1 --format=%h))
    if ((Run $jp 'git checkout -b feature/sec-s1 origin/main') -ne 0) { Stop 'checkout 실패' }
}
if ((& git -C $jp log -1 --format=%h) -ne 'fce5048') { Stop 'feature/sec-s1 HEAD가 fce5048 아님 (이미 commit 됨?)' }
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    if (-not $f) { continue }
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
$T = 'juprovider_secs1test'
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T; CREATE DATABASE $T CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force

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

    
    Log ''; Log '===== 6. Smoke Client 등록 (테스트 DB) ====='
    $r = Call 'POST' '/api/admin/clients' $ta @{ clientId = 'SMOKE_SECS1'; clientName = 'sec-s1 smoke' } $null
    $ck = $r.json.data.clientKey; Check '테스트 Client 등록' (($r.code -eq 200) -and $ck) ("code=" + $r.code)
    $dev = [string](Ed $T "SELECT DEV_CD FROM ju_device WHERE USE_YN='YENO0001' ORDER BY DEV_CD LIMIT 1")
    function Sum { return ((Ed $T "SET SESSION group_concat_max_len=4194304; SELECT MD5(GROUP_CONCAT(CONCAT_WS('|',d.DEV_CD,d.DEV_TYPE,d.DEV_FORM,d.DEV_COMM,IFNULL(d.PTL_GRP_CD,''),d.DEV_CH,d.DEV_DAT_CNT,d.USE_YN,t.DEV_NM,IFNULL(t.DEV_DESC,''),IFNULL(t.DEV_CONFIG,''),IFNULL(t.DEV_EXTRA,''),IFNULL(t.DEV_DATA,'')) ORDER BY d.DEV_CD SEPARATOR '#')), COUNT(*) FROM ju_device d JOIN ju_device_detail t ON t.DEV_CD=d.DEV_CD") -join ' ') }
    $before = Sum; Log ("  device 합계(전): " + $before)
    $cb = Join-Path $src 'curl_body.txt'
    function C([string]$m, [string]$path, [string]$id, [string]$key, [string]$bearer, [string]$data) {
        $a = @('-s', '-o', $cb, '-w', '%{http_code}', '-X', $m)
        if ($id) { $a += @('-H', "X-JU-Client-Id: $id") }
        if ($key) { $a += @('-H', "X-JU-Client-Key: $key") }
        if ($bearer) { $a += @('-H', "Authorization: Bearer $bearer") }
        if ($data) { $a += @('-H', 'Content-Type: application/json', '--data', $data) }
        $code = (& curl.exe @a ($api + $path))
        $body = ''; if (Test-Path $cb) { $body = (Get-Content $cb -Raw -Encoding UTF8) }
        return @{ code = [string]$code; body = [string]$body }
    }
    $pb = '{"devCd":"' + $dev + '","devType":"HACK0001","devNm":"sec-s1 overwrite","useYn":"YENO0002"}'

    Log ''; Log '===== 7. Client 조회 유지 (GET) ====='
    $r = C 'GET' '/api/core/sync/devices' 'SMOKE_SECS1' $ck '' ''
    $cnt = [string](Ed $T "SELECT COUNT(*) FROM ju_device WHERE USE_YN='YENO0001'")
    $n = -1; try { $j = $r.body | ConvertFrom-Json; $n = $j.Count } catch {}
    Check 'GET /sync/devices (Client 키) → 200, 활성 장치 수 일치' (($r.code -eq '200') -and ([string]$n -eq $cnt)) ("code=" + $r.code + " n=$n db=$cnt")
    $r = C 'GET' ('/api/core/sync/devices/' + $dev) 'SMOKE_SECS1' $ck '' ''
    Check ("GET /sync/devices/$dev → 200") (($r.code -eq '200') -and ($r.body -match $dev)) ("code=" + $r.code)
    $r = C 'GET' '/api/core/sync/devices' '' '' '' ''
    Check 'GET 무헤더 → 401 (유지)' ($r.code -eq '401') ("code=" + $r.code)
    $r = C 'GET' '/api/core/sync/devices' '' '' $ta ''
    Check 'GET 사용자 JWT만 → 401 (유지)' ($r.code -eq '401') ("code=" + $r.code)
    $seen = [string](Ed $T "SELECT IF(LAST_SEEN_DT IS NULL,'N','Y') FROM ju_client WHERE CLIENT_ID='SMOKE_SECS1'")
    Check 'Client 인증 성공 시 LAST_SEEN_DT 갱신 (유지)' ($seen -eq 'Y') ''

    Log ''; Log '===== 8. Client 쓰기 차단 ====='
    $r = C 'PUT' ('/api/core/sync/devices/' + $dev) 'SMOKE_SECS1' $ck '' $pb
    Check 'PUT /sync/devices/{dev} (유효 Client 키) → 403' ($r.code -eq '403') ("code=" + $r.code + " body=" + $r.body)
    $r = C 'PUT' '/api/core/sync/devices/SECS1_NEW' 'SMOKE_SECS1' $ck '' $pb.Replace($dev, 'SECS1_NEW')
    Check 'PUT 신규 DEV_CD → 403' ($r.code -eq '403') ("code=" + $r.code)
    foreach ($m in 'POST', 'PATCH', 'DELETE') {
        $r = C $m ('/api/core/sync/devices/' + $dev) 'SMOKE_SECS1' $ck '' $(if ($m -ne 'DELETE') { $pb } else { '' })
        Check ("$m /sync/devices/{dev} → 403") ($r.code -eq '403') ("code=" + $r.code)
    }
    $r = C 'POST' '/api/core/sync/devices' 'SMOKE_SECS1' $ck '' $pb
    Check 'POST /sync/devices → 403' ($r.code -eq '403') ("code=" + $r.code)
    $r = C 'PUT' ('/api/core/sync/devices/' + $dev) '' '' '' $pb
    Check 'PUT 무헤더 → 401' ($r.code -eq '401') ("code=" + $r.code)
    $r = C 'PUT' ('/api/core/sync/devices/' + $dev) 'SMOKE_SECS1' 'wrong-key-000' '' $pb
    Check 'PUT 잘못된 키 → 401' ($r.code -eq '401') ("code=" + $r.code)
    $r = C 'PUT' ('/api/core/sync/devices/' + $dev) '' '' $ta $pb
    Check 'PUT 관리자 JWT → 401 (Client 체인은 JWT 불인정)' ($r.code -eq '401') ("code=" + $r.code)
    $after = Sum; Log ("  device 합계(후): " + $after)
    Check 'ju_device/ju_device_detail 무변경' ($before -eq $after) ''
    Check 'SECS1_NEW 미생성' ([string](Ed $T "SELECT COUNT(*) FROM ju_device WHERE DEV_CD='SECS1_NEW'") -eq '0') ''

    Log ''; Log '===== 9. 회귀 (관리자 Action / 기존 API) ====='
    $r = Call 'POST' '/api/action/15/SEARCH' $ta @{ parameters = @{} } $null
    Check '관리자 Device 15/SEARCH → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/GET' $ta @{ parameters = @{ devCd = $dev } } $null
    Check '관리자 Device 15/GET → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/admin/clients' $ta $null $null
    Check '/api/admin/clients (관리자) → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/languages' $ta $null $null
    Check '/api/core/languages → 200' ($r.code -eq 200) ("code=" + $r.code)

    Log ''; Log '===== 10. 비밀 값 ====='
    Remove-Item $cb -Force -ErrorAction SilentlyContinue
    $texts = (Get-Content $log -Raw) + ((Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join '')
    $hit = $false; foreach ($v in @($pws.Values) + @($ck)) { if ($v -and $texts.IndexOf([string]$v) -ge 0) { $hit = $true } }
    Check '로그에 비밀번호·Client Key 원문 없음' (-not $hit) ''
    $pws = $null; $tok = $null; $ta = $null; $tm = $null; $ck = $null
}
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T`"" | Out-Null
Log ("  테스트 DB 삭제: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null

Log ''; Log '===== 11. 로컬 commit (push 없음) ====='
if ($script:fail -gt 0) { Stop "FAIL $($script:fail) → commit 하지 않음" }
Run $jp 'git add juprovider.backend desktop/lib' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("  staged $n, 기타 $other")
if ($n -ne 4 -or $other -ne 0) { Stop '예상 외 변경' }
if ((Run $jp "git commit -F `"$src\commit_secs1.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -2' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
Log ("결과: FAIL " + $script:fail)
Log 'SECS1-DONE'

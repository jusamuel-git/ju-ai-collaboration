# JU-1B: feature/ju-1b (← feature/ju-1a), 코드 반영, 5종 빌드(테스트 포함), migration 05 테스트 DB 검증,
#        테스트 DB 대상 서버 smoke(권한·Client), Desktop smoke, 로컬 commit (push 없음)
# 실제 juprovider DB는 mysqldump(읽기)만 한다. 비밀 값(DB 비밀번호, JWT secret, 테스트 비밀번호, Client Key)은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\ju1b'
$log = Join-Path $ws ("ai_ju1b_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'JU1B-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("JU-1B " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -eq 'feature/ju-1a') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop 'feature/ju-1a 변경 있음' }
    if ((& git -C $jp log -1 --format=%h) -ne '6fb591a') { Stop 'JU-1A HEAD 불일치' }
    Run $jp 'git checkout -b feature/ju-1b' | Out-Null
} elseif ($b -ne 'feature/ju-1b') { Stop "브랜치 $b" }
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
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
Log ("  테스트: " + (($bl | Select-String 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$' | Select-Object -Last 1)))
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($script:fail -gt 0 -or -not (Test-Path $war)) { Stop '빌드 실패' }

Log ''; Log '===== 3. migration 05 테스트 DB 검증 ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$db, [string]$sql) { return (cmd /c "$base -N -B $db -e `"$sql`" 2>&1") }
function Fd([string]$db, [string]$file, [string]$out) { cmd /c "$base -B $db < `"$file`" > `"$out`" 2>&1"; return $LASTEXITCODE }
$T = 'juprovider_ju1btest'; $I = 'juprovider_ju1binst'
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
Log ("  실제 DB 덤프 exit $LASTEXITCODE")
foreach ($d in $T, $I) { cmd /c "$base -e `"DROP DATABASE IF EXISTS $d; CREATE DATABASE $d CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null }
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force
$m05 = Join-Path $jp 'database\migration\05_ju1_auth.sql'
Check '05 1회 적용' ((Fd $T $m05 "$src\05_run1.txt") -eq 0) ''
$sum1 = Ed $T 'CHECKSUM TABLE ju_auth, ju_client, ju_client_detail'
Check '05 2회 적용' ((Fd $T $m05 "$src\05_run2.txt") -eq 0) ''
$sum2 = Ed $T 'CHECKSUM TABLE ju_auth, ju_client, ju_client_detail'
Check '05 재실행 무변경 (CHECKSUM)' (($sum1 -join '|') -eq ($sum2 -join '|')) ''
$db = Join-Path $jp 'database'
$c1 = Fd $I "$db\baseline\01_ju_core_baseline.sql" "$src\inst_baseline.txt"; $c2 = Fd $I "$db\seed\02_ju_core_seed.sql" "$src\inst_seed.txt"; $c3 = Fd $I "$db\migration\03_validate_baseline.sql" "$src\inst_03.txt"
Check '신규 설치 baseline+seed+03' (($c1 -eq 0) -and ($c2 -eq 0) -and ($c3 -eq 0)) ''
Fd $T "$src\ju1b_db.sql" "$src\snap_migrated.txt" | Out-Null; Fd $I "$src\ju1b_db.sql" "$src\snap_install.txt" | Out-Null
Check '기존 DB+05 = 신규 설치 (ju_auth / ju_client 구조)' ((Get-FileHash "$src\snap_migrated.txt").Hash -eq (Get-FileHash "$src\snap_install.txt").Hash) ''
Log ("  ju_auth 1행: " + (Ed $T "SELECT CONCAT(AUTH_TYPE,' ',LEFT(AUTH_ATTR,40)) FROM ju_auth WHERE AUTH_ID=1"))
Log ("  ju_auth 4행: " + (Ed $T "SELECT CONCAT(AUTH_TYPE,' ',AUTH_ATTR) FROM ju_auth WHERE AUTH_ID=4"))

Log ''; Log '===== 4. 서버 기동 (테스트 DB) ====='
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'
$env:JU_DB_URL = ($vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $T))
$env:JU_DB_USER = $vars['JU_DB_USER']; $env:JU_DB_PASSWORD = $vars['JU_DB_PASSWORD']; $env:JU_JWT_SECRET = $vars['JU_JWT_SECRET']
$env:SPRING_PROFILES_ACTIVE = $null
Log ("  JU_DB_URL 대상 DB: " + $(if ($env:JU_DB_URL -match $T) { $T } else { 'FAIL' }))
$p1 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\app_out.txt" -RedirectStandardError "$src\app_err.txt"
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
$api = 'http://localhost:18081/juprovider'
function Call([string]$m, [string]$path, [string]$tok, $body, $hdrs) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }; if ($hdrs) { foreach ($k in $hdrs.Keys) { $hd[$k] = $hdrs[$k] } }
    $p = @{ Uri = $api + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)) }
    try { $r = Invoke-WebRequest @p; $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j } }
    catch { $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }; return @{ code = $code; json = $null } }
}
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; if ((Call 'GET' '/api/health' '' $null $null).code -eq 200) { $ready = $true; break } }
Check '서버 기동 (setenv secret, 테스트 DB)' $ready ''

Log ''; Log '===== 5. 권한 smoke ====='
function NewPw { -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!a1' }
function BHash([string]$pw) {
    $jar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object FullName | Select-Object -Last 1
    $env:SMOKE_PW = $pw; $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$ws\ai_changes\ju1a\bcrypt.jsh`" 2>&1"; $env:SMOKE_PW = $null
    return (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
}
$users = @(@('smoke_admin', 1), @('smoke_mgr', 2), @('smoke_usr', 4)); $pws = @{}; $tok = @{}
if ($ready) {
    foreach ($u in $users) {
        $pw = NewPw; $pws[$u[0]] = $pw
        Ed $T ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('" + $u[0] + "','" + (BHash $pw) + "'," + $u[1] + ",'YENO0001')") | Out-Null
        Ed $T ("INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT,PW_CHANGE_DT) SELECT USER_ID,'" + $u[0] + "',0,NOW() FROM ju_user WHERE LOGIN_ID='" + $u[0] + "'") | Out-Null
        $r = Call 'POST' '/api/auth/login' '' @{ loginId = $u[0]; password = $pw } $null; $tok[$u[0]] = $r.json.data.accessToken
        Check ("로그인 " + $u[0] + " (AUTH_ID " + $u[1] + ")") (($r.code -eq 200) -and $r.json.data.passwordChangeRequired -eq $false) ("code=" + $r.code)
    }
    $ta = $tok['smoke_admin']; $tm = $tok['smoke_mgr']; $tu = $tok['smoke_usr']
    $r = Call 'POST' '/api/action/15/SEARCH' $ta @{ parameters = @{} } $null; Check 'ADMIN(FF) 장치 SEARCH → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/CREATE' $ta @{ parameters = @{} } $null; Check 'ADMIN(FF) CREATE → 권한 통과 (핸들러 없음 400)' ($r.code -eq 400) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/SEARCH' $tm @{ parameters = @{} } $null; Check 'MANAGER(01) SEARCH → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/CREATE' $tm @{ parameters = @{} } $null; Check 'MANAGER(01) CREATE(02) → 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/DELETE' $tm @{ parameters = @{} } $null; Check 'MANAGER(01) DELETE(08) → 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/SEARCH' $tu @{ parameters = @{} } $null; Check 'USER(메뉴 없음) SEARCH → 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/NOPE' $ta @{ parameters = @{} } $null; Check '없는 Action → 400' ($r.code -eq 400) ("code=" + $r.code)
    Ed $T "UPDATE ju_auth SET AUTH_ATTR=REPLACE(AUTH_ATTR,'M0201000001','M0201000000') WHERE AUTH_ID=2" | Out-Null
    $r = Call 'POST' '/api/action/15/SEARCH' $tm @{ parameters = @{} } $null; Check 'AUTH_ATTR 비트 제거 즉시 반영 → 403' ($r.code -eq 403) ("code=" + $r.code)
    Ed $T "UPDATE ju_auth SET AUTH_ATTR=REPLACE(AUTH_ATTR,'M0201000000','M0201000001') WHERE AUTH_ID=2" | Out-Null
    $r = Call 'POST' '/api/action/15/SEARCH' $tm @{ parameters = @{} } $null; Check '비트 복구 → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/languages' $tu $null $null; Check '직접 조회 API (JWT+PW_OK) → 200' ($r.code -eq 200) ("code=" + $r.code)

    Log ''; Log '===== 6. Client 인증 smoke ====='
    $r = Call 'GET' '/api/core/sync/devices' '' $null $null; Check 'sync 무헤더 → 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/sync/devices' $ta $null $null; Check 'sync 사용자 JWT만 → 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'GET' '/api/admin/clients' $tm $null $null; Check '비어드민 /api/admin/clients → 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/admin/clients' $ta @{ clientId = 'SMOKE_PC01'; clientName = 'smoke pc' } $null
    $k1 = $r.json.data.clientKey; Check '어드민 Client 등록 → 키 1회 반환' (($r.code -eq 200) -and $k1 -and $k1.Length -ge 43) ("code=" + $r.code)
    $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$k1))).Replace('-', '').ToLower()
    $dbHash = Ed $T "SELECT KEY_HASH FROM ju_client WHERE CLIENT_ID='SMOKE_PC01'"
    Check 'DB에는 SHA-256 해시만 저장' (([string]$dbHash -eq $sha) -and ([string]$dbHash -ne [string]$k1)) ''
    $r = Call 'GET' '/api/admin/clients' $ta $null $null
    Check 'Client 목록에 키/해시 없음' (($r.code -eq 200) -and (($r.json.data | ConvertTo-Json -Compress) -notmatch 'key[Hh]ash|clientKey')) ("code=" + $r.code)
    $h = @{ 'X-JU-Client-Id' = 'SMOKE_PC01'; 'X-JU-Client-Key' = $k1 }
    $r = Call 'GET' '/api/core/sync/devices' '' $null $h; Check 'sync 올바른 Client 키 → 200' ($r.code -eq 200) ("code=" + $r.code)
    Check 'LAST_SEEN_DT 기록' ([string](Ed $T "SELECT LAST_SEEN_DT IS NOT NULL FROM ju_client WHERE CLIENT_ID='SMOKE_PC01'") -eq '1') ''
    $r = Call 'GET' '/api/core/sync/devices' '' $null @{ 'X-JU-Client-Id' = 'SMOKE_PC01'; 'X-JU-Client-Key' = 'wrong-key-value' }; Check 'sync 잘못된 키 → 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/languages' '' $null $h; Check 'Client 키로 사용자 API → 401' ($r.code -eq 401) ("code=" + $r.code)

    Log ''; Log '===== 7. Desktop smoke (JuProviderApiClient) ====='
    $env:JU_SMOKE_CLIENT_KEY = $k1
    $dc = Run (Join-Path $src 'clientsmoke') 'dotnet run -c Debug -- http://localhost:18081/juprovider/ SMOKE_PC01'
    $env:JU_SMOKE_CLIENT_KEY = $null
    Check 'Desktop 헤더 전송/무자격 401' ($dc -eq 0) ''

    $r = Call 'POST' '/api/admin/clients/SMOKE_PC01/key' $ta $null $null; $k2 = $r.json.data.clientKey
    Check '키 재발급' (($r.code -eq 200) -and $k2 -and ($k2 -ne $k1)) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/sync/devices' '' $null $h; Check '재발급 후 이전 키 → 401' ($r.code -eq 401) ("code=" + $r.code)
    $h2 = @{ 'X-JU-Client-Id' = 'SMOKE_PC01'; 'X-JU-Client-Key' = $k2 }
    $r = Call 'GET' '/api/core/sync/devices' '' $null $h2; Check '새 키 → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'DELETE' '/api/admin/clients/SMOKE_PC01' $ta $null $null; Check 'Client 사용 중지' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/sync/devices' '' $null $h2; Check '사용 중지 후 → 401' ($r.code -eq 401) ("code=" + $r.code)
    $appLog = (Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join ''
    Check '서버 로그에 Client 키 원문 없음' (($appLog.IndexOf([string]$k1) -lt 0) -and ($appLog.IndexOf([string]$k2) -lt 0)) ''
    $k1 = $null; $k2 = $null; $h = $null; $h2 = $null; $pws = $null
}
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
foreach ($d in $T, $I) { cmd /c "$base -e `"DROP DATABASE IF EXISTS $d`"" | Out-Null }
Log ("  테스트 DB 삭제: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null

Log ''; Log '===== 8. 로컬 commit (push 없음) ====='
if ($script:fail -gt 0) { Stop "FAIL $($script:fail) → commit 하지 않음" }
Run $jp 'git add database desktop juprovider.backend juprovider.core' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("  staged $n, 기타 $other")
if ($n -ne 30 -or $other -ne 0) { Stop '예상 외 변경' }
if ((Run $jp "git commit -F `"$src\commit_ju1b.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git status --short --branch' | Out-Null
Log ("결과: FAIL " + $script:fail)
Log 'JU1B-DONE'

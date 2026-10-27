# PR-1 Action Contract Core: feature/action-contract (← main fce5048), 코드 반영, 로컬 빌드 5종(테스트 포함),
#   테스트 DB + 18081 Action smoke(경로·오류 계약·회귀), 테스트 DB 삭제, 로컬 commit. push 없음
# 실제 juprovider DB는 mysqldump(읽기)만. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\pr1'
$log = Join-Path $ws ("ai_pr1_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'PR1-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("PR-1 Action Contract Core " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -eq 'main') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop 'main 변경 있음' }
    if ((& git -C $jp log -1 --format=%h) -ne 'fce5048') { Stop 'main HEAD가 fce5048 아님' }
    Run $jp 'git checkout -b feature/action-contract' | Out-Null
} elseif ($b -ne 'feature/action-contract') { Stop "브랜치 $b" }
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
$T = 'juprovider_pr1test'
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

    Log ''; Log '===== 6. 기존 menuId 경로 (Device 회귀) ====='
    $r = Call 'POST' '/api/action/15/SEARCH' $ta @{ parameters = @{} } $null
    Check '15/SEARCH 200, data 배열(기존 모양), contractVersion 없음' (($r.code -eq 200) -and ($r.raw -match '"data":\[') -and ($r.raw -notmatch 'contractVersion')) ("code=" + $r.code)
    $dev = (Ed $T "SELECT DEV_CD FROM ju_device WHERE USE_YN='YENO0001' ORDER BY DEV_CD LIMIT 1")
    $r = Call 'POST' '/api/action/15/GET' $ta @{ parameters = @{ devCd = [string]$dev } } $null
    Check ('15/GET 200 (devCd=' + $dev + ')') ($r.code -eq 200) ("code=" + $r.code + " " + $r.json.message)
    $r = Call 'POST' '/api/action/15/SEARCH' $tm @{ parameters = @{} } $null
    Check '비관리자 15/SEARCH 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/CREATE' $ta @{ parameters = @{} } $null
    Check '15/CREATE(Handler 없음) → 501 NOT_IMPLEMENTED' (($r.code -eq 501) -and $r.json.code -eq 'NOT_IMPLEMENTED') ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/NOPE' $ta @{ parameters = @{} } $null
    Check '15/NOPE(정의 없음) → 404 NOT_FOUND' (($r.code -eq 404) -and $r.json.code -eq 'NOT_FOUND') ("code=" + $r.code)
    $r = Call 'POST' '/api/action/99999/SEARCH' $ta @{ parameters = @{} } $null
    Check '없는 menuId → 404' ($r.code -eq 404) ("code=" + $r.code)

    Log ''; Log '===== 7. MNU_CD 경로 ====='
    $r = Call 'POST' '/api/action/M02010000/SEARCH' $ta @{ parameters = @{} } $null
    Check 'M02010000/SEARCH 200 + X-JU-Request-Id' (($r.code -eq 200) -and $r.hdr -and $r.hdr['X-JU-Request-Id']) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010000/CREATE' $tm @{ parameters = @{} } $null
    Check '비관리자 M02010000/CREATE → 403 FORBIDDEN (501보다 권한 먼저)' (($r.code -eq 403) -and $r.json.code -eq 'FORBIDDEN') ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010000/CREATE' $ta @{ parameters = @{} } $null
    Check '관리자 M02010000/CREATE → 501' ($r.code -eq 501) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M99999999/SEARCH' $ta @{ parameters = @{} } $null
    Check '없는 MNU_CD → 404 NOT_FOUND' (($r.code -eq 404) -and $r.json.code -eq 'NOT_FOUND') ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010100/SEARCH' $ta @{ parameters = @{} } $null
    Check 'Action 없는 메뉴(M02010100, PR-2 전) → 404' ($r.code -eq 404) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/XYZ/SEARCH' $ta @{ parameters = @{} } $null
    Check '형식 아닌 경로 → 404 (이전 500)' ($r.code -eq 404) ("code=" + $r.code)
    $cb = Join-Path $src 'noauth_body.txt'
    $cc = (& curl.exe -s -o $cb -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data '{}' "$api/api/action/M02010000/SEARCH")
    $craw = (Get-Content $cb -Raw -Encoding UTF8)
    Check '토큰 없음 → 401 UNAUTHORIZED (curl)' (($cc -eq '401') -and ($craw -match '"code":"UNAUTHORIZED"')) ("code=" + $cc + " body=" + $craw)
    $r = Call 'POST' '/api/action/M02010000/SEARCH' $ta $null '{bad json'
    Check '잘못된 JSON → 400 BAD_REQUEST' (($r.code -eq 400) -and $r.json.code -eq 'BAD_REQUEST') ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = 'Wrong-Pass-000' } $null
    Check '로그인 실패 401 + 기존 message 유지 + code' (($r.code -eq 401) -and $r.json.message -and $r.json.code -eq 'UNAUTHORIZED') ("code=" + $r.code)
    $r = Call 'GET' '/api/core/languages' $ta $null $null
    Check '기존 API 응답 모양 유지 (code/errors 필드 없음)' (($r.code -eq 200) -and ($r.raw -notmatch '"code"') -and ($r.raw -notmatch '"errors"')) ("code=" + $r.code)

    Log ''; Log '===== 8. 기동 정합성 WARN ====='
    Start-Sleep -Seconds 1
    $out = Get-Content "$src\app_out.txt" -Encoding UTF8 -ErrorAction SilentlyContinue
    $w = $out | Select-String -Pattern '\[ACTION\]'
    $w | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
    Check '기동 WARN: Handler 없는 활성 Action 8건' (@($w | Where-Object { $_.Line -match '8건' }).Count -ge 1) ''
    $texts = (Get-Content $log -Raw) + ((Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join '')
    $hit = $false; foreach ($v in $pws.Values) { if ($texts.IndexOf([string]$v) -ge 0) { $hit = $true } }
    Check '로그에 비밀번호 원문 없음' (-not $hit) ''
    $pws = $null; $tok = $null; $ta = $null; $tm = $null
}
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T`"" | Out-Null
Log ("  테스트 DB 삭제: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null

Log ''; Log '===== 9. 로컬 commit (push 없음) ====='
if ($script:fail -gt 0) { Stop "FAIL $($script:fail) → commit 하지 않음" }
Run $jp 'git add juprovider.core juprovider.backend' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("  staged $n, 기타 $other")
if ($n -ne 30 -or $other -ne 0) { Stop '예상 외 변경' }
if ((Run $jp "git commit -F `"$src\commit_pr1.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
Log ("결과: FAIL " + $script:fail)
Log 'PR1-DONE'

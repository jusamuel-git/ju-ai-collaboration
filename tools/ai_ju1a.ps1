# (1) SEC-01 commit → juproject main push
# (2) JU-1A: feature/ju-1a, 코드 반영, 5종 빌드(테스트 포함), JU_JWT_SECRET 기동 조건, 실제 DB smoke, 로컬 commit (push 없음)
# 비밀 값(DB 비밀번호, JWT secret, 테스트 비밀번호)은 읽어서 환경변수로만 넘기고 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\ju1a'
$log = Join-Path $ws ("ai_ju1a_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); Log 'JU1A-STOPPED'; exit 1 }
$jj = Join-Path $ws 'juproject'; $jp = Join-Path $ws 'juprovider'
Log ("JU-1A " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. SEC-01 commit / push (juproject) ====='
if ((& git -C $jj rev-parse --abbrev-ref HEAD) -ne 'chore/sys-seed-secret') { Stop 'juproject 브랜치' }
Run $jj 'git add AI_WORKLOG.md backend/src/JuProject.Api/appsettings.Development.json' | Out-Null
if (@(& git -C $jj status --porcelain | Where-Object { $_ -notmatch '^M  ' }).Count -ne 0) { Stop 'juproject 예상 외 변경' }
if ((Run $jj "git commit -F `"$src\commit_sec01.txt`"") -ne 0) { Stop 'SEC-01 commit 실패' }
Run $jj 'git checkout main' | Out-Null
if ((Run $jj 'git merge --ff-only chore/sys-seed-secret') -ne 0) { Stop 'ff 실패' }
if ((Run $jj 'git push origin main') -ne 0) { Stop 'push 실패' }
Run $jj 'git log --oneline -2' | Out-Null

Log ''; Log '===== 2. JU-1A 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -eq 'main') { if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop 'juprovider main 변경 있음' }; Run $jp 'git checkout -b feature/ju-1a' | Out-Null }
elseif ($b -ne 'feature/ju-1a') { Stop "juprovider 브랜치 $b" }
Run $jp 'git log -1 --oneline' | Out-Null
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null

Log ''; Log '===== 3. 로컬 빌드 5종 (backend 테스트 포함) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$sumIdx = [Array]::IndexOf($bl, '===== 요약 ====='); $bl[$sumIdx..($bl.Length - 1)] | ForEach-Object { Log ('  ' + $_) }
Check '로컬 빌드 5종' (@($bl[$sumIdx..($bl.Length - 1)] | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
$tests = $bl | Select-String 'Tests run:.*JwtConfigTest|Tests run: \d+, Failures' | Select-Object -Last 1
Log ("  테스트: " + $tests)
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if (-not (Test-Path $war)) { Stop 'WAR 없음' }

Log ''; Log '===== 4. JU_JWT_SECRET 조건 / 기동 ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$sec = $vars['JU_JWT_SECRET']
$secLen = $(if ($sec) { [Text.Encoding]::UTF8.GetByteCount($sec) } else { 0 })
Check 'setenv JU_JWT_SECRET 존재 / 32바이트 이상' ($secLen -ge 32) $(if ($sec) {'SET'} else {'MISSING'})
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD') { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
$env:SPRING_PROFILES_ACTIVE = $null

# 4-1) secret 없음 → 기동 실패해야 함
$env:JU_JWT_SECRET = $null
$p0 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18082" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\nosecret_out.txt" -RedirectStandardError "$src\nosecret_err.txt"
$exited = $p0.WaitForExit(90000); if (-not $exited) { Stop-Process -Id $p0.Id -Force }
$msg = (Get-Content "$src\nosecret_out.txt","$src\nosecret_err.txt" -Raw -ErrorAction SilentlyContinue) -join ''
Check 'secret 없음 → 기동 실패' ($exited -and ($msg -match 'JU_JWT_SECRET')) ("exited=$exited")

# 4-2) setenv의 secret으로 기동 (Tomcat과 같은 조건)
$env:JU_JWT_SECRET = $sec
$p1 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\app_out.txt" -RedirectStandardError "$src\app_err.txt"
$env:JU_JWT_SECRET = $null; $sec = $null
$base = 'http://localhost:18081/juprovider'
function Call([string]$m, [string]$path, [string]$tok, $body) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }
    $p = @{ Uri = $base + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)) }
    try { $r = Invoke-WebRequest @p; $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j; raw = $r.Content } }
    catch { $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }; return @{ code = $code; json = $null; raw = '' } }
}
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; if ((Call 'GET' '/api/health' '' $null).code -eq 200) { $ready = $true; break } }
Check 'setenv secret으로 기동 + health 200' $ready ''

Log ''; Log '===== 5. 실제 DB smoke (임시 사용자 smoke_admin, ADMIN 권한, 종료 후 삭제) ====='
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$my = "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -N -B juprovider"
function E([string]$sql) { return (cmd /c "$my -e `"$sql`" 2>&1") }
$adminBefore = E "SELECT CONCAT_WS('|',u.USER_PW_HASH,u.USE_YN,d.PW_CHANGE_DT,d.LOGIN_FAIL_CNT,d.LAST_LOGIN_DT) FROM ju_user u LEFT JOIN ju_user_detail d ON d.USER_ID=u.USER_ID WHERE u.LOGIN_ID='admin'"
function NewPw { -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!a1' }
function BHash([string]$pw) {
    $jar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object FullName | Select-Object -Last 1
    $env:SMOKE_PW = $pw
    $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$src\bcrypt.jsh`" 2>&1"
    $env:SMOKE_PW = $null
    return (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
}
if ($ready) {
    $pw1 = NewPw; $pw2 = NewPw
    $h1 = BHash $pw1
    Check 'BCrypt 해시 생성' ($h1 -match '^\$2a\$') ''
    E "DELETE d FROM ju_user_detail d JOIN ju_user u ON u.USER_ID=d.USER_ID WHERE u.LOGIN_ID='smoke_admin'; DELETE FROM ju_user WHERE LOGIN_ID='smoke_admin'" | Out-Null
    E ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('smoke_admin','" + $h1 + "',1,'YENO0001')") | Out-Null
    E "INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT) SELECT USER_ID,'smoke admin',0 FROM ju_user WHERE LOGIN_ID='smoke_admin'" | Out-Null
    function St { return (E "SELECT CONCAT_WS('|',d.LOGIN_FAIL_CNT,IFNULL(d.LAST_LOGIN_DT,'NULL'),IFNULL(d.PW_CHANGE_DT,'NULL')) FROM ju_user_detail d JOIN ju_user u ON u.USER_ID=d.USER_ID WHERE u.LOGIN_ID='smoke_admin'") }

    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = 'wrong-password-x' }
    $s = (St) -split '\|'; Check '잘못된 비밀번호 → 401, LOGIN_FAIL_CNT 1' (($r.code -eq 401) -and $s[0] -eq '1') ("code=" + $r.code + " fail=" + $s[0])
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'no_such_user_x'; password = 'whatever-123' }; Check '없는 아이디 → 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pw1 }; $t1 = $r.json.data.accessToken
    $s = (St) -split '\|'
    Check '정상 로그인 → 200, FAIL_CNT 0, LAST_LOGIN_DT 갱신' (($r.code -eq 200) -and $t1 -and $s[0] -eq '0' -and $s[1] -ne 'NULL') ("code=" + $r.code + " fail=" + $s[0])
    Check '응답: accessToken/expiresAt/user/passwordChangeRequired, authAttr 없음' (($r.json.data.expiresAt) -and ($r.json.data.user.authType -eq 'AUTH0001') -and ($r.json.data.passwordChangeRequired -eq $true) -and ($r.raw -notmatch 'authAttr')) ''
    $r = Call 'GET' '/api/auth/me' $t1 $null; Check '변경 전 /me 허용 (passwordChangeRequired=true)' (($r.code -eq 200) -and $r.json.data.passwordChangeRequired -eq $true) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/languages' $t1 $null; Check '변경 전 보호 API → 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/1/SEARCH' $t1 @{ parameters = @{} }; Check '변경 전 Action → 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/password' $t1 @{ currentPassword = 'wrong-current-x'; newPassword = $pw2 }; Check '현재 비밀번호 오류 → 400' ($r.code -eq 400) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/password' $t1 @{ currentPassword = $pw1; newPassword = 'short' }; Check '새 비밀번호 검증 오류 → 400' ($r.code -eq 400) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/password' $t1 @{ currentPassword = $pw1; newPassword = $pw2 }
    $s = (St) -split '\|'; Check '정상 변경 → 200, PW_CHANGE_DT 기록' (($r.code -eq 200) -and $s[2] -ne 'NULL') ("code=" + $r.code)
    $r = Call 'GET' '/api/auth/me' $t1 $null; Check '변경 전 JWT 재사용 /me → 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/languages' $t1 $null; Check '변경 전 JWT 재사용 보호 API → 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pw1 }; Check '이전 비밀번호 로그인 → 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pw2 }; $t2 = $r.json.data.accessToken
    Check '새 로그인 → passwordChangeRequired=false' (($r.code -eq 200) -and $r.json.data.passwordChangeRequired -eq $false) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/languages' $t2 $null; Check '변경 후 보호 API → 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/core/menus' $t2 $null; Check '변경 후 /api/core/menus → 200' ($r.code -eq 200) ("code=" + $r.code)
    E "UPDATE ju_user SET USE_YN='YENO0002' WHERE LOGIN_ID='smoke_admin'" | Out-Null
    $r = Call 'GET' '/api/auth/me' $t2 $null; Check '사용자 미사용 → 기존 토큰 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pw2 }; Check '사용자 미사용 → 로그인 401' ($r.code -eq 401) ("code=" + $r.code)
    $pw1 = $null; $pw2 = $null; $h1 = $null
}
$r = Call 'GET' '/api/core/languages' '' $null; Check '/api/core/* 무토큰 → 401' ($r.code -eq 401) ("code=" + $r.code)
$r = Call 'POST' '/api/action/1/SEARCH' '' @{ parameters = @{} }; Check '/api/action/** 무토큰 → 401' ($r.code -eq 401) ("code=" + $r.code)
$r = Call 'GET' '/api/core/sync/devices' '' $null; Check '/api/core/sync/** 무토큰 → 기존대로 200' ($r.code -eq 200) ("code=" + $r.code)
$r = Call 'GET' '/api/health' '' $null; Check '/api/health → 200' ($r.code -eq 200) ("code=" + $r.code)
$r = Call 'GET' '/' '' $null; Check '정적 Vue (/) → 200' (($r.code -eq 200) -and ($r.raw -match '<div id="app"|<!doctype html|<!DOCTYPE html')) ("code=" + $r.code)

E "DELETE d FROM ju_user_detail d JOIN ju_user u ON u.USER_ID=d.USER_ID WHERE u.LOGIN_ID='smoke_admin'; DELETE FROM ju_user WHERE LOGIN_ID='smoke_admin'" | Out-Null
$adminAfter = E "SELECT CONCAT_WS('|',u.USER_PW_HASH,u.USE_YN,d.PW_CHANGE_DT,d.LOGIN_FAIL_CNT,d.LAST_LOGIN_DT) FROM ju_user u LEFT JOIN ju_user_detail d ON d.USER_ID=u.USER_ID WHERE u.LOGIN_ID='admin'"
Check '실제 admin 행 변경 없음' ([string]$adminBefore -eq [string]$adminAfter) ''
Log ("  사용자 수: " + (E "SELECT COUNT(*) FROM ju_user"))
$env:MYSQL_PWD = $null
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }

Log ''; Log '===== 6. 로컬 commit (push 없음) ====='
if ($script:fail -gt 0) { Stop "FAIL $($script:fail) → commit 하지 않음" }
Run $jp 'git add juprovider.backend juprovider.core' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("  staged $n, 기타 $other")
if ($n -ne 21 -or $other -ne 0) { Stop '예상 외 변경' }
if ((Run $jp "git commit -F `"$src\commit_ju1a.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -2' | Out-Null
Run $jp 'git status --short --branch' | Out-Null
Log ("결과: FAIL " + $script:fail)
Log 'JU1A-DONE'

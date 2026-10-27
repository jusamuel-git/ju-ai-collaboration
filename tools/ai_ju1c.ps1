# JU-1C 1단계: feature/ju-1c (← feature/ju-1b be1a664), 코드 반영, 5종 빌드, 테스트 DB(실제 DB 덤프 + 05), 임시 사용자,
#             서버를 18081에 띄워 둔다 (브라우저 smoke용). 실제 DB 변경 없음, commit은 2단계.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\ju1c'
$log = Join-Path $ws ("ai_ju1c_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'JU1C-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("JU-1C " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -eq 'feature/ju-1b') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop 'feature/ju-1b 변경 있음' }
    if ((& git -C $jp log -1 --format=%h) -ne 'be1a664') { Stop 'JU-1B HEAD 불일치' }
    Run $jp 'git checkout -b feature/ju-1c' | Out-Null
} elseif ($b -ne 'feature/ju-1c') { Stop "브랜치 $b" }
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null

Log ''; Log '===== 2. 로컬 빌드 5종 (Vue 포함 WAR, 테스트) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Check '빌드 요약 찾기' $false '' } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | ForEach-Object { Log ('  ' + $_) }
    Check '로컬 빌드 5종' (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
}
Log ("  테스트: " + (($bl | Select-String 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$' | Select-Object -Last 1)))
$vueErr = @($bl | Select-String -CaseSensitive '\[vite\].*error|Could not resolve|ERROR').Count
Check 'Vue 빌드 오류 없음' ($vueErr -eq 0) ("matches=$vueErr")
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($script:fail -gt 0 -or -not (Test-Path $war)) { Stop '빌드 실패' }

Log ''; Log '===== 3. 테스트 DB (실제 DB 덤프 + 05) ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$sql) { return (cmd /c "$base -N -B $T -e `"$sql`" 2>&1") }
$T = 'juprovider_ju1ctest'
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T; CREATE DATABASE $T CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
cmd /c "$base $T < `"$dump`""; Log ("  적재 exit $LASTEXITCODE"); Remove-Item $dump -Force
cmd /c "$base $T < `"$jp\database\migration\05_ju1_auth.sql`" > `"$src\05.txt`" 2>&1"; Check '05 적용 (테스트 DB)' ($LASTEXITCODE -eq 0) ''

$pw = Get-Content (Join-Path $src 'testpw.json') -Raw | ConvertFrom-Json
function BHash([string]$p) {
    $jar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object FullName | Select-Object -Last 1
    $env:SMOKE_PW = $p; $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$ws\ai_changes\ju1a\bcrypt.jsh`" 2>&1"; $env:SMOKE_PW = $null
    return (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
}
foreach ($u in @(@('smoke_admin', 1, 'NULL'), @('smoke_mgr', 2, 'NOW()'), @('smoke_usr', 4, 'NOW()'))) {
    Ed ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('" + $u[0] + "','" + (BHash $pw.($u[0])) + "'," + $u[1] + ",'YENO0001')") | Out-Null
    Ed ("INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT,PW_CHANGE_DT) SELECT USER_ID,'" + $u[0] + "',0," + $u[2] + " FROM ju_user WHERE LOGIN_ID='" + $u[0] + "'") | Out-Null
}
Log ("  임시 사용자: " + ((Ed "SELECT CONCAT(u.LOGIN_ID,':',u.AUTH_ID,':',IF(d.PW_CHANGE_DT IS NULL,'pwc','ok')) FROM ju_user u JOIN ju_user_detail d ON d.USER_ID=u.USER_ID WHERE u.LOGIN_ID LIKE 'smoke%'") -join ', '))

Log ''; Log '===== 4. 서버 기동 (테스트 DB, 18081, 브라우저 smoke 후 2단계에서 종료) ====='
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'
$env:JU_DB_URL = ($vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $T))
$env:JU_DB_USER = $vars['JU_DB_USER']; $env:JU_DB_PASSWORD = $vars['JU_DB_PASSWORD']; $env:JU_JWT_SECRET = $vars['JU_JWT_SECRET']
$p1 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\app_out.txt" -RedirectStandardError "$src\app_err.txt"
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
Set-Content -Path (Join-Path $src 'app.pid') -Value $p1.Id
$api = 'http://localhost:18081/juprovider'
function Call([string]$m, [string]$path, [string]$tok, $body) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }
    $p = @{ Uri = $api + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)) }
    try { $r = Invoke-WebRequest @p; $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j; raw = $r.Content } }
    catch { $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }; return @{ code = $code; json = $null; raw = '' } }
}
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; if ((Call 'GET' '/api/health' '' $null).code -eq 200) { $ready = $true; break } }
Check '서버 기동' $ready ''

Log ''; Log '===== 5. API 확인 (/me 메뉴, SPA forward) ====='
if ($ready) {
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_mgr'; password = $pw.smoke_mgr }; $tm = $r.json.data.accessToken
    $r = Call 'GET' '/api/auth/me' $tm $null
    $m15 = @($r.json.data.menus | Where-Object { $_.menuCode -eq 'M02010000' })
    Check 'MANAGER /me 메뉴 + 권한 비트' (($r.code -eq 200) -and $r.json.data.menus.Count -gt 0 -and $m15.Count -eq 1 -and $m15[0].permission -eq '01') ("menus=" + $r.json.data.menus.Count)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pw.smoke_admin }; $ta = $r.json.data.accessToken
    $r = Call 'GET' '/api/auth/me' $ta $null
    Check '변경 전 /me 메뉴 비어 있음' (($r.code -eq 200) -and $r.json.data.passwordChangeRequired -eq $true -and @($r.json.data.menus).Count -eq 0) ''
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_usr'; password = $pw.smoke_usr }; $tu = $r.json.data.accessToken
    $r = Call 'GET' '/api/auth/me' $tu $null
    Check 'USER /me 장치관리 메뉴 없음' (($r.code -eq 200) -and @($r.json.data.menus | Where-Object { $_.menuCode -eq 'M02010000' }).Count -eq 0) ("menus=" + @($r.json.data.menus).Count)
    foreach ($p in '/login', '/password-change', '/forbidden', '/console/device/manage') {
        $r = Call 'GET' $p '' $null; Check ("SPA 직접 접근 " + $p + " → index.html") (($r.code -eq 200) -and ($r.raw -match 'id="app"')) ("code=" + $r.code)
    }
    $r = Call 'GET' '/api/core/languages' '' $null; Check 'API 무토큰은 그대로 401' ($r.code -eq 401) ("code=" + $r.code)
}
$env:MYSQL_PWD = $null
Log ("결과: FAIL " + $script:fail)
Log 'JU1C-STAGE1-DONE'

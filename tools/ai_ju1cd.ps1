# JU-1c Desktop: feature/ju-1c-desktop (← main acac1fa), 코드 반영, 로컬 빌드 5종, 테스트 DB 18081 기동,
#               online/offline smoke (DeskSmoke). 서버는 UI 확인용으로 켜 둔다 → ai_ju1cd_finish.ps1에서 종료·정리·commit
# 실제 juprovider DB는 mysqldump(읽기)만. 비밀 값(DB 비밀번호, JWT secret, 테스트 비밀번호, Client Key)은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\ju1cd'
$log = Join-Path $ws ("ai_ju1cd_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'JU1CD-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'; $app = Join-Path $jp 'desktop\app'
Log ("JU-1c Desktop " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$opf = Join-Path $src 'server.pid'
if (Test-Path $opf) { Stop-Process -Id ([int](Get-Content $opf)) -Force -ErrorAction SilentlyContinue; Remove-Item $opf -Force; Start-Sleep -Seconds 3; Log '  이전 18081 서버 종료' }

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -eq 'main') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop 'main 변경 있음' }
    if ((& git -C $jp log -1 --format=%h) -ne 'acac1fa') { Stop 'main HEAD가 acac1fa 아님' }
    Run $jp 'git checkout -b feature/ju-1c-desktop' | Out-Null
} elseif ($b -ne 'feature/ju-1c-desktop') { Stop "브랜치 $b" }
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    if (-not $f) { continue }
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null

Log ''; Log '===== 2. 로컬 빌드 5종 ====='
foreach ($pn in 'juprovider.client', 'juprovider.terminal') { Get-Process -Name $pn -ErrorAction SilentlyContinue | ForEach-Object { Log ("  실행 중인 $pn 종료 (PID " + $_.Id + ")"); Stop-Process -Id $_.Id -Force } }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Check '빌드 요약 찾기' $false '' } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | ForEach-Object { Log ('  ' + $_) }
    Check '로컬 빌드 5종' (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
}
$bl | Select-String -Pattern 'error CS\d+|warning CS\d+' | Select-Object -First 15 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($script:fail -gt 0 -or -not (Test-Path $war)) { Stop '빌드 실패' }
Check 'Client exe 갱신' ((Get-Item (Join-Path $app 'juprovider.client.exe')).LastWriteTime -ge $now) ''

Log ''; Log '===== 3. 테스트 DB (실제 DB 덤프 사본) ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$db, [string]$sql) { return (cmd /c "$base -N -B $db -e `"$sql`" 2>&1") }
$T = 'juprovider_ju1cdtest'
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
Log ("  실제 DB 덤프 exit $LASTEXITCODE")
cmd /c "$base -e `"DROP DATABASE IF EXISTS $T; CREATE DATABASE $T CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force
Check '테스트 DB에 ju_client 존재(05 적용 상태)' ([string](Ed $T "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$T' AND TABLE_NAME='ju_client'") -eq '1') ''

Log ''; Log '===== 4. 서버 기동 (18081, 테스트 DB) ====='
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'
$env:JU_DB_URL = ($vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $T))
$env:JU_DB_USER = $vars['JU_DB_USER']; $env:JU_DB_PASSWORD = $vars['JU_DB_PASSWORD']; $env:JU_JWT_SECRET = $vars['JU_JWT_SECRET']
$env:SPRING_PROFILES_ACTIVE = $null
Log ("  JU_DB_URL 대상 DB: " + $(if ($env:JU_DB_URL -match $T) { $T } else { 'FAIL' }))
if ($env:JU_DB_URL -notmatch $T) { Stop '테스트 DB URL 치환 실패' }
$p1 = Start-Process $java -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\app_out.txt" -RedirectStandardError "$src\app_err.txt"
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
Set-Content -Path (Join-Path $src 'server.pid') -Value $p1.Id
$api = 'http://localhost:18081/juprovider'
function Call([string]$m, [string]$path, [string]$tok, $body) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }
    $p = @{ Uri = $api + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)) }
    try { $r = Invoke-WebRequest @p; $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j } }
    catch { $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }; return @{ code = $code; json = $null } }
}
$ready = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; if ((Call 'GET' '/api/health' '' $null).code -eq 200) { $ready = $true; break } }
Check '서버 기동' $ready ''
if (-not $ready) { Stop '서버 기동 실패' }

Log ''; Log '===== 5. smoke 사용자·Client ====='
function NewPw { -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!a1' }
function BHash([string]$pw) {
    $jar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object FullName | Select-Object -Last 1
    $env:SMOKE_PW = $pw; $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$ws\ai_changes\ju1a\bcrypt.jsh`" 2>&1"; $env:SMOKE_PW = $null
    return (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
}
$pws = @{}
foreach ($u in @(@('smoke_admin', 1, 'NOW()'), @('smoke_mgr', 2, 'NOW()'), @('smoke_usr', 4, 'NOW()'), @('smoke_new', 4, 'NULL'))) {
    $pw = NewPw; $pws[$u[0]] = $pw
    Ed $T ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('" + $u[0] + "','" + (BHash $pw) + "'," + $u[1] + ",'YENO0001')") | Out-Null
    Ed $T ("INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT,PW_CHANGE_DT) SELECT USER_ID,'" + $u[0] + "',0," + $u[2] + " FROM ju_user WHERE LOGIN_ID='" + $u[0] + "'") | Out-Null
}
Check 'smoke 사용자 4명' ([string](Ed $T "SELECT COUNT(*) FROM ju_user WHERE LOGIN_ID LIKE 'smoke\_%'") -eq '4') ''
$r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pws['smoke_admin'] }; $ta = $r.json.data.accessToken
Check '어드민 로그인' (($r.code -eq 200) -and $ta) ("code=" + $r.code)
$r = Call 'POST' '/api/admin/clients' $ta @{ clientId = 'SMOKE_DESK01'; clientName = 'ju-1c desktop smoke' }; $ck = $r.json.data.clientKey
Check 'Client SMOKE_DESK01 등록' (($r.code -eq 200) -and $ck) ("code=" + $r.code)

Log ''; Log '===== 6. Desktop online/offline smoke ====='
$sm = Join-Path $src 'smoke'
$c = Run $sm 'dotnet build -c Debug -v q -nologo'
$sbin = Join-Path $sm 'bin\Debug\net10.0-windows'
New-Item -ItemType Directory -Force -Path (Join-Path $sbin 'config') | Out-Null
Copy-Item (Join-Path $app 'config\template.accdb') (Join-Path $sbin 'config\template.accdb') -Force
$env:JU_SMOKE_CLIENT_KEY = $ck; $env:JU_SMOKE_PW_USR = $pws['smoke_usr']; $env:JU_SMOKE_PW_USR2 = (NewPw); $env:JU_SMOKE_PW_NEW = $pws['smoke_new']
$dc = Run $sbin "DeskSmoke.exe $api/ SMOKE_DESK01"
foreach ($k in 'JU_SMOKE_CLIENT_KEY','JU_SMOKE_PW_USR','JU_SMOKE_PW_USR2','JU_SMOKE_PW_NEW') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
Check 'Desktop smoke (DeskSmoke exit 0)' (($c -eq 0) -and ($dc -eq 0)) ''
$secretHit = $false
$texts = @((Get-Content $log -Raw), (Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join '')
foreach ($v in @($ck) + @($pws.Values)) { foreach ($t in $texts) { if ($t -and $v -and $t.IndexOf([string]$v) -ge 0) { $secretHit = $true } } }
Check '로그(스크립트·서버)에 비밀번호·Client 키 원문 없음' (-not $secretHit) ''
$ck = $null; $ta = $null; $pws = $null
$env:MYSQL_PWD = $null
Log ("결과: FAIL " + $script:fail + "  (18081 서버는 UI 확인용으로 실행 중 → ai_ju1cd_finish.ps1)")
Log 'JU1CD-STAGE1-DONE'

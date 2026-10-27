# PR-3 Protocol Vue (1/2): feature/protocol-ref (157635a), 코드 반영, 로컬 빌드 5종, 테스트 DB(+06) + 18081 기동, API smoke.
#   서버는 브라우저 smoke를 위해 계속 실행. 종료·DB 삭제·commit은 ai_pr3_finish.ps1. push 없음
# 실제 juprovider DB는 mysqldump(읽기)만. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\pr3'
$log = Join-Path $ws ("ai_pr3_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'PR3-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("PR-3 Protocol Vue " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -ne 'feature/protocol-ref') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop "현재 브랜치 $b 에 미커밋 변경 있음" }
    Log ("  기존 브랜치: $b @ " + (& git -C $jp log -1 --format=%h))
    if ((Run $jp 'git checkout feature/protocol-ref') -ne 0) { Stop 'checkout 실패' }
}
if ((& git -C $jp log -1 --format=%h) -ne '157635a') { Stop 'feature/protocol-ref HEAD가 157635a 아님' }
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
$T = 'juprovider_pr3test'
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

    Log ''; Log '===== 7. 브라우저 smoke 준비 ====='
    $cred = Join-Path $src 'smoke_cred.txt'
    [IO.File]::WriteAllText($cred, ("smoke_admin=" + $pws['smoke_admin'] + "`r`nsmoke_mgr=" + $pws['smoke_mgr'] + "`r`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $src 'server.pid'), [string]$p1.Id, $enc)
    $texts = (Get-Content $log -Raw) + ((Get-Content "$src\app_out.txt","$src\app_err.txt" -Raw -ErrorAction SilentlyContinue) -join '')
    $hit = $false; foreach ($v in $pws.Values) { if ($texts.IndexOf([string]$v) -ge 0) { $hit = $true } }
    Check '로그에 비밀번호 원문 없음' (-not $hit) ''
    Log ("  서버 실행 중 PID " + $p1.Id + " — 브라우저 smoke 후 ai_pr3_finish.ps1 실행")
    $pws = $null; $tok = $null; $ta = $null; $tm = $null
} else {
    Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
    cmd /c "$base -e `"DROP DATABASE IF EXISTS $T`"" | Out-Null
}
$env:MYSQL_PWD = $null
Log ("결과: FAIL " + $script:fail)
Log 'PR3-READY'

# PC-B 재현 검증: origin/feature/protocol-ref @157635a 를 별도 worktree(workspace_verify)에서 빌드·테스트·06·HTTP smoke
# 기존 workspace\juprovider·juproject(미커밋 변경)는 건드리지 않는다. 제품 코드 수정·commit·push 없음. 실제 DB는 mysqldump(읽기)만
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$home0 = 'C:\MyData\MyDev\workspace'
$ws  = 'C:\MyData\MyDev\workspace_verify'
New-Item -ItemType Directory -Force -Path $ws | Out-Null
$src = Join-Path $ws 'pcb_work'
New-Item -ItemType Directory -Force -Path $src | Out-Null
$log = Join-Path $home0 ("ai_pcb_extra_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0; $script:pass = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) { $script:pass++; 'PASS' } else { $script:fail++; 'FAIL' }); Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'PCBX-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("PC-B verify " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " / " + $env:COMPUTERNAME)

Log ''; Log '===== 테스트 DB ====='
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
function Ed([string]$db, [string]$sql) { return (cmd /c "$base -N -B $db -e `"$sql`" 2>&1") }
function Fd([string]$db, [string]$file, [string]$out) { cmd /c "$base -B $db < `"$file`" > `"$out`" 2>&1"; return $LASTEXITCODE }
$T = 'juprovider_pcbxtest'; $I = 'juprovider_pcbxinst'
$dump = Join-Path $src 'juprovider_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 --single-transaction --routines --triggers juprovider > `"$dump`" 2>&1"
foreach ($d in $T, $I) { cmd /c "$base -e `"DROP DATABASE IF EXISTS $d; CREATE DATABASE $d CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null }
cmd /c "$base $T < `"$dump`""; Log ("  $T 적재 exit $LASTEXITCODE"); Remove-Item $dump -Force
$db = Join-Path $jp 'database'
foreach ($m in '04_ju0_install_fix.sql','05_ju1_auth.sql','06_protocol_actions.sql') { Check ("테스트 DB에 " + $m) ((Fd $T "$db\migration\$m" "$src\x_$m.txt") -eq 0) '' }
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
Check '검증 WAR 존재 (worktree 빌드 산출물)' (Test-Path $war) ''
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
        $env:SMOKE_PW = $pw; $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$home0\ai_changes\ju1a\bcrypt.jsh`" 2>&1"; $env:SMOKE_PW = $null
        return (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
    }
    $tok = @{}; $pws = @{}
    foreach ($u in @(@('smoke_admin', 1), @('smoke_mgr', 2))) {
        $pw = NewPw; $pws[$u[0]] = $pw
        Ed $T ("INSERT INTO ju_user (LOGIN_ID,USER_PW_HASH,AUTH_ID,USE_YN) VALUES ('" + $u[0] + "','" + (BHash $pw) + "'," + $u[1] + ",'YENO0001')") | Out-Null
        Ed $T ("INSERT INTO ju_user_detail (USER_ID,USER_NM,LOGIN_FAIL_CNT,PW_CHANGE_DT) SELECT USER_ID,'" + $u[0] + "',0,NOW() FROM ju_user WHERE LOGIN_ID='" + $u[0] + "'") | Out-Null
        $r = Call 'POST' '/api/auth/login' '' @{ loginId = $u[0]; password = $pw }; $tok[$u[0]] = $r.json.data.accessToken
        Check ("로그인 " + $u[0]) (($r.code -eq 200) -and $tok[$u[0]]) ("code=" + $r.code)
    }
    $ta = $tok['smoke_admin']; $tm = $tok['smoke_mgr']
    Log ''; Log '===== Device 회귀·501 (보완) ====='
    $dev = (Ed $T "SELECT DEV_CD FROM ju_device WHERE USE_YN='YENO0001' ORDER BY DEV_CD LIMIT 1")
    $r = Call 'POST' '/api/action/15/SEARCH' $ta @{ parameters = @{} }
    Check 'Device 15/SEARCH 200 (배열 모양, contractVersion 없음)' (($r.code -eq 200) -and ($r.raw -match '"data":\[') -and ($r.raw -notmatch 'contractVersion')) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/GET' $ta @{ parameters = @{ devCd = [string]$dev } }
    Check ('Device 15/GET 200 (devCd=' + $dev + ')') (($r.code -eq 200) -and $r.json.data) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010000/GET' $ta @{ parameters = @{ devCd = [string]$dev } }
    Check 'Device M02010000/GET (MNU_CD 경로) 200' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/CREATE' $ta @{ parameters = @{} }
    Check 'Handler 없는 DEVICE.CREATE → 501 NOT_IMPLEMENTED' (($r.code -eq 501) -and $r.json.code -eq 'NOT_IMPLEMENTED') ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010000/STOP' $ta @{ parameters = @{} }
    Check 'MNU_CD 경로 DEVICE.STOP → 501' ($r.code -eq 501) ("code=" + $r.code)
    $r = Call 'POST' '/api/action/M02010000/CREATE' $tm @{ parameters = @{} }
    Check '비관리자 M02010000/CREATE → 403 (501보다 권한 먼저)' (($r.code -eq 403) -and $r.json.code -eq 'FORBIDDEN') ("code=" + $r.code)
    $r = Call 'POST' '/api/action/15/SEARCH' $tm @{ parameters = @{} }
    Check '비관리자 Device SEARCH 200' ($r.code -eq 200) ("code=" + $r.code)
    $pws = $null; $tok = $null; $ta = $null; $tm = $null
}
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
foreach ($d in $T, $I) { cmd /c "$base -e `"DROP DATABASE IF EXISTS $d`"" | Out-Null }
Log ("  테스트 DB 삭제: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null
Log ("결과: FAIL " + $script:fail + " (PASS " + $script:pass + ")")
Log 'PCBX-DONE'

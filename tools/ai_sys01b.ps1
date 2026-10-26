# SYS-01 B: 수작업 migration 반영 → Release/Frontend 빌드 → juproject_migtest(실제 DB 덤프)에서 Up/검증/smoke/Down/비교/재Up
# 실제 juproject DB는 mysqldump(읽기)만 한다. commit/push 없음. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\sys01b'
$out = Join-Path $src 'out'; New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = Join-Path $ws ("ai_sys01b_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd, [string]$shown) { if (-not $shown) { $shown = $cmd }; Log ("> " + $shown); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
$jj = Join-Path $ws 'juproject'; $be = Join-Path $jj 'backend'
$bin = 'C:\Program Files\MariaDB 10.6\bin'

# 접속 정보 (user-secrets) - 값은 기록하지 않음
$sec = Get-ChildItem "$env:APPDATA\Microsoft\UserSecrets\*\secrets.json" | Where-Object { (Get-Content $_ -Raw) -match 'ConnectionStrings' } | Select-Object -First 1
$cs = (Get-Content $sec.FullName -Raw | ConvertFrom-Json).'ConnectionStrings:Default'
$kv = @{}; foreach ($p in $cs -split ';') { if ($p -match '^\s*([^=]+?)\s*=\s*(.*)$') { $kv[$matches[1].ToLower()] = $matches[2] } }
$h = $kv['server']; $port = $kv['port']; if (-not $port) { $port = '3306' }; $u = $kv['user']; if (-not $u) { $u = $kv['user id'] }; if (-not $u) { $u = $kv['uid'] }
$pw = $kv['password']; if (-not $pw) { $pw = $kv['pwd'] }
$realDb = $kv['database']; $testDb = 'juproject_migtest'
$csTest = ($cs -replace '(?i)(database\s*=\s*)[^;]+', ('${1}' + $testDb))
$env:MYSQL_PWD = $pw
$my = "`"$bin\mysql.exe`" -h $h -P $port -u $u --default-character-set=utf8mb4"
function Q([string]$file, [string]$tag) { cmd /c "$my -B $testDb < `"$src\$file`" > `"$out\$tag.txt`" 2>&1"; Log ("  snapshot $tag ($file) exit $LASTEXITCODE") }
function E([string]$sql) { $o = cmd /c "$my -N -B $testDb -e `"$sql`" 2>&1"; return $o }

Log ("SYS-01 B " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " real=$realDb test=$testDb branch=" + (& git -C $jj rev-parse --abbrev-ref HEAD))
if ((& git -C $jj rev-parse --abbrev-ref HEAD) -ne 'feature/sys-01') { Log '중단: 브랜치'; exit 1 }

# 0) 수작업 migration 반영
$mig = Join-Path $be 'src\JuProject.Infrastructure\Persistence\Migrations\20261026063158_SysCoreSchema.cs'
Copy-Item (Join-Path $src '20261026063158_SysCoreSchema.cs') $mig -Force; (Get-Item $mig).LastWriteTime = Get-Date

Log ''; Log '===== 1. Backend Release build ====='
$c = Run $be 'dotnet build JuProject.slnx -c Release -nologo -v q'
Check 'backend Release build' ($c -eq 0) ''
Log ''; Log '===== 2. Frontend lint/build ====='
$fe = Join-Path $jj 'frontend'
$c1 = Run $fe 'npm ci --no-audit --no-fund'; $c2 = Run $fe 'npm run lint'; $c3 = Run $fe 'npm run build'
Check 'frontend ci/lint/build' (($c1 -eq 0) -and ($c2 -eq 0) -and ($c3 -eq 0)) ''
if ($script:fail -gt 0) { Log '중단: 빌드 실패'; $env:MYSQL_PWD = $null; exit 1 }

Log ''; Log '===== 3. 실제 DB 덤프 → juproject_migtest ====='
$dump = Join-Path $src 'juproject_dump.sql'
cmd /c "`"$bin\mysqldump.exe`" -h $h -P $port -u $u --default-character-set=utf8mb4 --single-transaction --routines --triggers $realDb > `"$dump`" 2>&1"
Log ("  dump exit $LASTEXITCODE, " + (Get-Item $dump).Length + ' bytes')
cmd /c "$my -e `"DROP DATABASE IF EXISTS $testDb; CREATE DATABASE $testDb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`""
cmd /c "$my $testDb < `"$dump`""
Log ("  load exit $LASTEXITCODE")
Remove-Item $dump -Force; Log '  덤프 파일 삭제'
Q 's_struct.sql' '0_orig_struct'; Q 's_data_tb.sql' '0_orig_data'

# EF/API가 migtest를 쓰도록 (환경변수, 로그에 쓰지 않음)
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:ConnectionStrings__Default = $csTest
$env:Seed__AdminPassword = ''
$ef = 'dotnet ef database update {0} --project src\JuProject.Infrastructure --startup-project src\JuProject.Api --configuration Release --no-build'

Log ''; Log '===== 4. Up ====='
$c = Run $be ($ef -f 'SysCoreSchema')
Check 'Up exit 0' ($c -eq 0) ''
Q 's_struct.sql' '1_up_struct'; Q 's_data_sys.sql' '1_up_data'

Log ''; Log '===== 5. API smoke (migtest) ====='
function NewPw { -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!a1' }
function IdHash([string]$p) {
    $salt = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($p, $salt, 100000, [Security.Cryptography.HashAlgorithmName]::SHA256)
    $sub = $kdf.GetBytes(32); $o = New-Object byte[] 61; $o[0] = 1
    $be4 = { param($v, $i) $o[$i] = [byte](($v -shr 24) -band 255); $o[$i+1] = [byte](($v -shr 16) -band 255); $o[$i+2] = [byte](($v -shr 8) -band 255); $o[$i+3] = [byte]($v -band 255) }
    & $be4 1 1; & $be4 100000 5; & $be4 16 9
    [Array]::Copy($salt, 0, $o, 13, 16); [Array]::Copy($sub, 0, $o, 29, 32); return [Convert]::ToBase64String($o)
}
$pa = NewPw; $pu = NewPw
foreach ($x in @(@('smoke_admin', $pa, 'ADMIN'), @('smoke_user', $pu, 'USER'))) {
    $hash = IdHash $x[1]
    E ("INSERT INTO sys_user (login_id,password_hash,user_name,use_yn,created_at,auth_id) SELECT '" + $x[0] + "','" + $hash + "','" + $x[0] + "','Y',UTC_TIMESTAMP(6),auth_id FROM sys_auth WHERE auth_code='" + $x[2] + "'") | Out-Null
}
$api = Start-Process dotnet -ArgumentList 'run --project src\JuProject.Api -c Release --no-build --no-launch-profile --urls http://localhost:5199' -WorkingDirectory $be -PassThru -WindowStyle Hidden -RedirectStandardOutput "$out\api_stdout.txt" -RedirectStandardError "$out\api_stderr.txt"
$base = 'http://localhost:5199'
function Call([string]$m, [string]$path, [string]$tok, $body) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }
    $p = @{ Uri = $base + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)) }
    try { $r = Invoke-WebRequest @p; $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j } }
    catch { $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }; return @{ code = $code; json = $null } }
}
$ready = $false
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 750; $r = Call 'GET' '/api/auth/me' '' $null; if ($r.code -eq 401) { $ready = $true; break } }
Check 'API 기동' $ready ''
if ($ready) {
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pa }
    $ta = $r.json.accessToken; Check 'ADMIN 로그인' (($r.code -eq 200) -and $ta -and $r.json.user.roleCode -eq 'ADMIN') ("code=" + $r.code + " roleCode=" + $r.json.user.roleCode)
    $r = Call 'GET' '/api/auth/me' $ta $null; Check 'ADMIN /me' ($r.json.roleCode -eq 'ADMIN') ("code=" + $r.code)
    $r = Call 'GET' '/api/users?page=1&size=50' $ta $null
    $roles = ($r.json.items | ForEach-Object { $_.roleCode } | Sort-Object -Unique) -join ','
    Check '사용자 목록' (($r.code -eq 200) -and $r.json.totalCount -ge 5) ("code=" + $r.code + " total=" + $r.json.totalCount + " roles=" + $roles)
    $r = Call 'POST' '/api/users' $ta @{ loginId = 'smoke_new'; password = (NewPw); userName = 'smoke new'; roleCode = 'USER' }
    $nid = $r.json.userId; Check '사용자 생성(USER)' (($r.code -eq 201) -and $r.json.roleCode -eq 'USER') ("code=" + $r.code)
    $r = Call 'PUT' "/api/users/$nid" $ta @{ userName = 'smoke new2'; roleCode = 'ADMIN' }; Check '사용자 수정(→ADMIN)' (($r.code -eq 200) -and $r.json.roleCode -eq 'ADMIN') ("code=" + $r.code)
    $r = Call 'GET' "/api/users/$nid" $ta $null; Check '사용자 상세' ($r.json.roleCode -eq 'ADMIN') ("code=" + $r.code)
    $r = Call 'POST' '/api/users' $ta @{ loginId = 'smoke_bad'; password = (NewPw); userName = 'bad'; roleCode = 'NOPE' }; Check '없는 roleCode 거부' ($r.code -eq 400) ("code=" + $r.code)
    $r = Call 'DELETE' "/api/users/$nid" $ta $null; Check '사용자 삭제' ($r.code -eq 204) ("code=" + $r.code)
    $r = Call 'GET' '/api/code-groups' $ta $null; Check '코드그룹 조회(ADMIN)' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/code-groups/USE_STATUS/codes' $ta $null; Check '코드 조회(ADMIN)' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_user'; password = $pu }
    $tu = $r.json.accessToken; Check 'USER 로그인' (($r.code -eq 200) -and $r.json.user.roleCode -eq 'USER') ("code=" + $r.code + " roleCode=" + $r.json.user.roleCode)
    $r = Call 'GET' '/api/auth/me' $tu $null; Check 'USER /me' ($r.json.roleCode -eq 'USER') ("code=" + $r.code)
    $r = Call 'GET' '/api/code-groups' $tu $null; Check '코드그룹 조회(USER)' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/code-groups/USE_STATUS/codes' $tu $null; Check '코드 조회(USER)' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/users' $tu $null; Check 'USER→사용자 목록 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/code-groups' $tu @{ groupCode = 'X'; groupName = 'X'; sortOrder = 1 }; Check 'USER→코드그룹 등록 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_user'; password = 'wrong-password' }; Check '잘못된 비밀번호 401' ($r.code -eq 401) ("code=" + $r.code)
    # 9-a: USER 권한 미사용 → USER 로그인 불가, 관리자 목록에는 그대로 보임
    E "UPDATE sys_auth SET use_yn='N' WHERE auth_code='USER'" | Out-Null
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_user'; password = $pu }; Check '권한 미사용 → USER 로그인 401' ($r.code -eq 401) ("code=" + $r.code)
    $r = Call 'GET' '/api/users?page=1&size=50' $ta $null
    $seen = @($r.json.items | Where-Object { $_.loginId -eq 'smoke_user' }).Count
    Check '권한 미사용 사용자도 관리 목록에 표시' (($r.code -eq 200) -and $seen -eq 1) ("code=" + $r.code + " total=" + $r.json.totalCount)
    E "UPDATE sys_auth SET use_yn='Y' WHERE auth_code='USER'" | Out-Null
}
Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue
Get-Process dotnet -ErrorAction SilentlyContinue | Where-Object { $_.Path -and (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match 'JuProject.Api' } | Stop-Process -Force -ErrorAction SilentlyContinue
E "DELETE FROM sys_user WHERE login_id LIKE 'smoke\_%'" | Out-Null
Log ("  smoke 사용자 정리: 남은 smoke 행 " + (E "SELECT COUNT(*) FROM sys_user WHERE login_id LIKE 'smoke\_%'"))
$pa = $null; $pu = $null

Log ''; Log '===== 6. Down (→ InitialCreate) ====='
$c = Run $be ($ef -f 'InitialCreate')
Check 'Down exit 0' ($c -eq 0) ''
Q 's_struct.sql' '2_down_struct'; Q 's_data_tb.sql' '2_down_data'
Check 'Down 구조 = 원본' ((Get-FileHash "$out\2_down_struct.txt").Hash -eq (Get-FileHash "$out\0_orig_struct.txt").Hash) ''
Check 'Down 데이터 = 원본' ((Get-FileHash "$out\2_down_data.txt").Hash -eq (Get-FileHash "$out\0_orig_data.txt").Hash) ''

Log ''; Log '===== 7. 재Up ====='
$c = Run $be ($ef -f 'SysCoreSchema')
Check '재Up exit 0' ($c -eq 0) ''
Q 's_struct.sql' '3_reup_struct'; Q 's_data_sys.sql' '3_reup_data'
Check '재Up 구조 = 1차 Up' ((Get-FileHash "$out\3_reup_struct.txt").Hash -eq (Get-FileHash "$out\1_up_struct.txt").Hash) ''

$env:MYSQL_PWD = $null; $env:ConnectionStrings__Default = $null
Run $jj 'git status --short' | Out-Null
Log ("결과: FAIL " + $script:fail)
Log 'SYS01B-DONE'

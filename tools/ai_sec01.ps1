# SEC-01: juproject Seed 평문 제거 (별도 브랜치, commit 없음) + user-secrets 이전 + 빌드 + 로그인 smoke
#         + JU-1A 사전조사용 juprovider DB 읽기 조회. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\sec01'
$log = Join-Path $ws ("ai_sec01_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'SEC01-STOPPED'; exit 1 }
$jj = Join-Path $ws 'juproject'; $be = Join-Path $jj 'backend'; $api = Join-Path $be 'src\JuProject.Api'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
Log ("SEC-01 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

# 1) 브랜치
$b = (& git -C $jj rev-parse --abbrev-ref HEAD)
if ($b -eq 'main') { if (@(& git -C $jj status --porcelain).Count -ne 0) { Stop 'main 변경 있음' }; Run $jj 'git checkout -b chore/sys-seed-secret' | Out-Null }
elseif ($b -ne 'chore/sys-seed-secret') { Stop "브랜치 $b" }
Run $jj 'git log -1 --oneline' | Out-Null

# 2) 기존 값 → user-secrets (값은 기록하지 않음)
$devJson = Join-Path $api 'appsettings.Development.json'
$old = (Get-Content $devJson -Raw | ConvertFrom-Json).Seed.AdminPassword
$sec = Get-ChildItem "$env:APPDATA\Microsoft\UserSecrets\*\secrets.json" | Where-Object { (Get-Content $_ -Raw) -match 'ConnectionStrings' } | Select-Object -First 1
$sj = Get-Content $sec.FullName -Raw | ConvertFrom-Json
if ($old) {
    Push-Location $api; cmd /c "dotnet user-secrets set `"Seed:AdminPassword`" `"$old`" >nul 2>&1"; $c = $LASTEXITCODE; Pop-Location
    Log ("  user-secrets Seed:AdminPassword 설정 exit $c")
}
$sj = Get-Content $sec.FullName -Raw | ConvertFrom-Json
Log ("  user-secrets 키: " + (($sj.PSObject.Properties | ForEach-Object { $_.Name + '=' + $(if ($_.Value) {'SET'} else {'EMPTY'}) }) -join ', '))

# 3) 실제 admin 비밀번호가 공개 값과 같은지 (해시 검증만, 값/해시 미기록)
$cs = $sj.'ConnectionStrings:Default'
$kv = @{}; foreach ($p in $cs -split ';') { if ($p -match '^\s*([^=]+?)\s*=\s*(.*)$') { $kv[$matches[1].ToLower()] = $matches[2] } }
$u = $kv['user']; if (-not $u) { $u = $kv['user id'] }; if (-not $u) { $u = $kv['uid'] }
$env:MYSQL_PWD = $kv['password']; if (-not $env:MYSQL_PWD) { $env:MYSQL_PWD = $kv['pwd'] }
$my = "`"$bin\mysql.exe`" -h $($kv['server']) -u $u --default-character-set=utf8mb4 -N -B $($kv['database'])"
function E([string]$sql) { return (cmd /c "$my -e `"$sql`" 2>&1") }
function IdVerify([string]$hash, [string]$pw) {
    $o = [Convert]::FromBase64String($hash); if ($o[0] -ne 1) { return $false }
    $rd = { param($i) ([int]$o[$i] -shl 24) -bor ([int]$o[$i+1] -shl 16) -bor ([int]$o[$i+2] -shl 8) -bor [int]$o[$i+3] }
    $prf = & $rd 1; $it = & $rd 5; $sl = & $rd 9
    $alg = @([Security.Cryptography.HashAlgorithmName]::SHA1, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.HashAlgorithmName]::SHA512)[$prf]
    $salt = $o[13..(12 + $sl)]; $sub = $o[(13 + $sl)..($o.Length - 1)]
    $k = (New-Object Security.Cryptography.Rfc2898DeriveBytes($pw, [byte[]]$salt, $it, $alg)).GetBytes($sub.Length)
    return ([Convert]::ToBase64String($k) -eq [Convert]::ToBase64String([byte[]]$sub))
}
$ah = E "SELECT password_hash FROM sys_user WHERE login_id='admin'"
if ($ah -and $old) { Log ("  admin 계정 비밀번호 = 공개되었던 Seed 값: " + (IdVerify ([string]$ah) $old)) } else { Log '  admin 계정 없음 또는 Seed 값 없음' }
$old = $null; $ah = $null

# 4) 파일 반영
Copy-Item (Join-Path $src 'appsettings.Development.json') $devJson -Force; (Get-Item $devJson).LastWriteTime = Get-Date
Copy-Item (Join-Path $src 'AI_WORKLOG.md') (Join-Path $jj 'AI_WORKLOG.md') -Force
Run $jj 'git status --short' | Out-Null
Run $jj 'git diff --stat' | Out-Null
Check 'Seed 키가 추적 파일에서 제거' (@(& git -C $jj grep -l 'AdminPassword' -- '*.json').Count -eq 0) ''

# 5) 빌드
Check 'backend Release build' ((Run $be 'dotnet build JuProject.slnx -c Release -nologo -v q') -eq 0) ''
$fe = Join-Path $jj 'frontend'
Check 'frontend ci/lint/build' (((Run $fe 'npm ci --no-audit --no-fund') -eq 0) -and ((Run $fe 'npm run lint') -eq 0) -and ((Run $fe 'npm run build') -eq 0)) ''

# 6) 로그인 smoke (Development, user-secrets 사용, 실제 DB, 임시 사용자)
function NewPw { -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!a1' }
function IdHash([string]$p) {
    $salt = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    $sub = (New-Object Security.Cryptography.Rfc2898DeriveBytes($p, $salt, 100000, [Security.Cryptography.HashAlgorithmName]::SHA256)).GetBytes(32)
    $o = New-Object byte[] 61; $o[0] = 1
    $w = { param($v, $i) $o[$i] = [byte](($v -shr 24) -band 255); $o[$i+1] = [byte](($v -shr 16) -band 255); $o[$i+2] = [byte](($v -shr 8) -band 255); $o[$i+3] = [byte]($v -band 255) }
    & $w 1 1; & $w 100000 5; & $w 16 9; [Array]::Copy($salt, 0, $o, 13, 16); [Array]::Copy($sub, 0, $o, 29, 32); return [Convert]::ToBase64String($o)
}
$pa = NewPw; $pu = NewPw
foreach ($x in @(@('smoke_admin', $pa, 'ADMIN'), @('smoke_user', $pu, 'USER'))) {
    E ("INSERT INTO sys_user (login_id,password_hash,user_name,use_yn,created_at,auth_id) SELECT '" + $x[0] + "','" + (IdHash $x[1]) + "','" + $x[0] + "','Y',UTC_TIMESTAMP(6),auth_id FROM sys_auth WHERE auth_code='" + $x[2] + "'") | Out-Null
}
$before = E "SELECT COUNT(*) FROM sys_user"
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$proc = Start-Process dotnet -ArgumentList 'run --project src\JuProject.Api -c Release --no-build --no-launch-profile --urls http://localhost:5199' -WorkingDirectory $be -PassThru -WindowStyle Hidden -RedirectStandardOutput "$src\api_stdout.txt" -RedirectStandardError "$src\api_stderr.txt"
$base = 'http://localhost:5199'
function Call([string]$m, [string]$path, [string]$tok, $body) {
    $hd = @{}; if ($tok) { $hd['Authorization'] = "Bearer $tok" }
    $p = @{ Uri = $base + $path; Method = $m; Headers = $hd; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($body) { $p['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)) }
    try { $r = Invoke-WebRequest @p; $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }; return @{ code = [int]$r.StatusCode; json = $j } }
    catch { $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }; return @{ code = $code; json = $null } }
}
$ready = $false
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 750; if ((Call 'GET' '/api/auth/me' '' $null).code -eq 401) { $ready = $true; break } }
Check 'API 기동 (Development + user-secrets)' $ready ''
if ($ready) {
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pa }; $ta = $r.json.accessToken
    Check 'ADMIN 로그인' (($r.code -eq 200) -and $r.json.user.roleCode -eq 'ADMIN') ("code=" + $r.code)
    Check 'ADMIN /me' ((Call 'GET' '/api/auth/me' $ta $null).json.roleCode -eq 'ADMIN') ''
    Check 'ADMIN 사용자 목록' ((Call 'GET' '/api/users' $ta $null).code -eq 200) ''
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_user'; password = $pu }; $tu = $r.json.accessToken
    Check 'USER 로그인' (($r.code -eq 200) -and $r.json.user.roleCode -eq 'USER') ("code=" + $r.code)
    Check 'USER /me' ((Call 'GET' '/api/auth/me' $tu $null).json.roleCode -eq 'USER') ''
    Check 'USER 코드그룹 조회' ((Call 'GET' '/api/code-groups' $tu $null).code -eq 200) ''
    Check 'USER→사용자 목록 403' ((Call 'GET' '/api/users' $tu $null).code -eq 403) ''
}
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" | Where-Object { $_.CommandLine -match 'JuProject.Api' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$after = E "SELECT COUNT(*) FROM sys_user"
Check '기동 시 시드가 사용자를 추가하지 않음' ($before -eq $after) ("$before → $after")
E "DELETE FROM sys_user WHERE login_id IN ('smoke_admin','smoke_user')" | Out-Null
Log ("  smoke 정리 후 사용자 수: " + (E "SELECT COUNT(*) FROM sys_user"))
$pa = $null; $pu = $null

# 7) JU-1A 사전조사: juprovider DB 읽기 조회
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
Log ("  setenv 키: " + (($vars.Keys | Sort-Object | ForEach-Object { $_ + '=' + $(if ($vars[$_]) {'SET'} else {'EMPTY'}) }) -join ', '))
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
cmd /c "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -B juprovider < `"$src\ju1a_inspect.sql`" > `"$src\ju1a_inspect.txt`" 2>&1"
Log ("  juprovider 조회 exit $LASTEXITCODE")
$env:MYSQL_PWD = $null
Log ("결과: FAIL " + $script:fail)
Log 'SEC01-DONE'

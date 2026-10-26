# SYS-01 C (사용자 승인 2026-10-26 15:41): 실제 juproject DB 백업 → Up → 검증 → smoke → commit → main push → migtest 삭제
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$b   = Join-Path $ws 'ai_changes\sys01b'
$src = Join-Path $ws 'ai_changes\sys01c'
$out = Join-Path $src 'out'; New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = Join-Path $ws ("ai_sys01c_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $name $note") }
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'SYS01C-STOPPED'; exit 1 }
$jj = Join-Path $ws 'juproject'; $be = Join-Path $jj 'backend'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$sec = Get-ChildItem "$env:APPDATA\Microsoft\UserSecrets\*\secrets.json" | Where-Object { (Get-Content $_ -Raw) -match 'ConnectionStrings' } | Select-Object -First 1
$cs = (Get-Content $sec.FullName -Raw | ConvertFrom-Json).'ConnectionStrings:Default'
$kv = @{}; foreach ($p in $cs -split ';') { if ($p -match '^\s*([^=]+?)\s*=\s*(.*)$') { $kv[$matches[1].ToLower()] = $matches[2] } }
$h = $kv['server']; $port = $kv['port']; if (-not $port) { $port = '3306' }; $u = $kv['user']; if (-not $u) { $u = $kv['user id'] }; if (-not $u) { $u = $kv['uid'] }
$pw = $kv['password']; if (-not $pw) { $pw = $kv['pwd'] }
$db = $kv['database']
$env:MYSQL_PWD = $pw
$my = "`"$bin\mysql.exe`" -h $h -P $port -u $u --default-character-set=utf8mb4"
function Q([string]$file, [string]$tag) { cmd /c "$my -B $db < `"$b\$file`" > `"$out\$tag.txt`" 2>&1"; Log ("  snapshot $tag exit $LASTEXITCODE") }
function E([string]$sql) { return (cmd /c "$my -N -B $db -e `"$sql`" 2>&1") }

Log ("SYS-01 C " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " db=$db branch=" + (& git -C $jj rev-parse --abbrev-ref HEAD))
if ((& git -C $jj rev-parse --abbrev-ref HEAD) -ne 'feature/sys-01') { Stop '브랜치' }
$hist = E "SELECT GROUP_CONCAT(MigrationId) FROM __efmigrationshistory"
Log ("  현재 history: $hist")
if ($hist -notmatch '^20261022081635_InitialCreate$') { Stop '예상과 다른 migration 상태' }

Log ''; Log '===== 1. 백업 ====='
$bk = 'C:\MyData\MyDev\backup'; New-Item -ItemType Directory -Force -Path $bk | Out-Null
$bf = Join-Path $bk ("juproject_{0}_before_sys01.sql" -f (Get-Date -Format 'yyyyMMdd_HHmm'))
cmd /c "`"$bin\mysqldump.exe`" -h $h -P $port -u $u --default-character-set=utf8mb4 --single-transaction --routines --triggers --databases $db > `"$bf`" 2>`"$bf.err`""
$c = $LASTEXITCODE; $tail = Get-Content $bf -Tail 1
Log ("  $bf (" + (Get-Item $bf).Length + " bytes, exit $c, $tail)")
if ($c -ne 0 -or $tail -notmatch 'Dump completed') { Stop '백업 실패' }
Remove-Item "$bf.err" -Force
Q 's_struct.sql' '0_real_orig_struct'; Q 's_data_tb.sql' '0_real_orig_data'

Log ''; Log '===== 2. Up (실제 DB) ====='
$env:ASPNETCORE_ENVIRONMENT = 'Development'; $env:Seed__AdminPassword = ''
$c = Run $be 'dotnet build JuProject.slnx -c Release -nologo -v q'
if ($c -ne 0) { Stop 'build 실패' }
$c = Run $be 'dotnet ef database update SysCoreSchema --project src\JuProject.Infrastructure --startup-project src\JuProject.Api --configuration Release --no-build'
Check 'Up exit 0' ($c -eq 0) ''
if ($c -ne 0) { Stop 'Up 실패 (백업으로 복구)' }

Log ''; Log '===== 3. 검증 ====='
Q 's_struct.sql' '1_real_up_struct'; Q 's_data_sys.sql' '1_real_up_data'
Check '구조 = migtest Up 구조' ((Get-FileHash "$out\1_real_up_struct.txt").Hash -eq (Get-FileHash "$b\out\1_up_struct.txt").Hash) ''
$orig = (Get-Content "$out\0_real_orig_data.txt" -Raw).Replace('#tb_', '#sys_').TrimEnd()
$upAll = Get-Content "$out\1_real_up_data.txt" -Raw
$up = $upAll.Substring(0, $upAll.IndexOf('#check')).TrimEnd()
Check '기존 데이터·role→auth 매핑 = 원본' ($orig -eq $up) ''
$chk = (Get-Content "$out\1_real_up_data.txt") | Select-String -Pattern '^\d+\t\d+\t\d+\t\d+$' | Select-Object -First 1
Log ("  users / auth_null / auth_orphan / audit_by_set = " + $chk)
Log ("  role 분포: " + ((E "SELECT a.auth_code, COUNT(*) FROM sys_user u JOIN sys_auth a ON a.auth_id=u.auth_id GROUP BY 1 ORDER BY 1") -join ' / '))
Log ("  history: " + (E "SELECT GROUP_CONCAT(MigrationId ORDER BY MigrationId) FROM __efmigrationshistory"))
Log ("  auth_id: " + (E "SELECT CONCAT(COLUMN_TYPE,' nullable=',IS_NULLABLE) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='sys_user' AND COLUMN_NAME='auth_id'"))

Log ''; Log '===== 4. API smoke (실제 DB, 임시 smoke 사용자 → 종료 후 삭제) ====='
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
    E ("INSERT INTO sys_user (login_id,password_hash,user_name,use_yn,created_at,auth_id) SELECT '" + $x[0] + "','" + (IdHash $x[1]) + "','" + $x[0] + "','Y',UTC_TIMESTAMP(6),auth_id FROM sys_auth WHERE auth_code='" + $x[2] + "'") | Out-Null
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
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_admin'; password = $pa }; $ta = $r.json.accessToken
    Check 'ADMIN 로그인' (($r.code -eq 200) -and $r.json.user.roleCode -eq 'ADMIN') ("code=" + $r.code)
    $r = Call 'GET' '/api/auth/me' $ta $null; Check 'ADMIN /me' ($r.json.roleCode -eq 'ADMIN') ("code=" + $r.code)
    $r = Call 'GET' '/api/users?page=1&size=50' $ta $null
    $orig3 = @($r.json.items | Where-Object { $_.loginId -notlike 'smoke_*' })
    Check '사용자 목록 (기존 3명 ADMIN 1/USER 2)' (($r.code -eq 200) -and $orig3.Count -eq 3 -and @($orig3 | Where-Object { $_.roleCode -eq 'ADMIN' }).Count -eq 1 -and @($orig3 | Where-Object { $_.roleCode -eq 'USER' }).Count -eq 2) ("code=" + $r.code + " total=" + $r.json.totalCount)
    $r = Call 'GET' '/api/code-groups' $ta $null; Check '코드그룹 조회' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/code-groups/USE_STATUS/codes' $ta $null; Check '코드 조회' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'POST' '/api/auth/login' '' @{ loginId = 'smoke_user'; password = $pu }; $tu = $r.json.accessToken
    Check 'USER 로그인' (($r.code -eq 200) -and $r.json.user.roleCode -eq 'USER') ("code=" + $r.code)
    $r = Call 'GET' '/api/auth/me' $tu $null; Check 'USER /me' ($r.json.roleCode -eq 'USER') ("code=" + $r.code)
    $r = Call 'GET' '/api/code-groups' $tu $null; Check 'USER 코드그룹 조회' ($r.code -eq 200) ("code=" + $r.code)
    $r = Call 'GET' '/api/users' $tu $null; Check 'USER→사용자 목록 403' ($r.code -eq 403) ("code=" + $r.code)
    $r = Call 'POST' '/api/code-groups' $tu @{ groupCode = 'X'; groupName = 'X'; sortOrder = 1 }; Check 'USER→코드그룹 등록 403' ($r.code -eq 403) ("code=" + $r.code)
}
Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" | Where-Object { $_.CommandLine -match 'JuProject.Api' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
E "DELETE FROM sys_user WHERE login_id IN ('smoke_admin','smoke_user')" | Out-Null
Log ("  smoke 사용자 삭제 후 남은 행: " + (E "SELECT COUNT(*) FROM sys_user WHERE login_id LIKE 'smoke%'") + ", 전체 사용자: " + (E "SELECT COUNT(*) FROM sys_user"))
$pa = $null; $pu = $null
if ($script:fail -gt 0) { Stop "검증 FAIL $($script:fail) (commit 하지 않음)" }

Log ''; Log '===== 5~6. commit → main → push ====='
Run $jj 'git add backend' | Out-Null
$n = @(& git -C $jj diff --cached --name-only).Count; $other = @(& git -C $jj status --porcelain | Where-Object { $_ -notmatch '^[AM] ' }).Count
Log ("  staged $n files, 기타 변경 $other")
if ($n -ne 35 -or $other -ne 0) { Stop '예상 외 변경 (35개 아님)' }
if ((Run $jj "git commit -F `"$src\commit_msg.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jj 'git checkout main' | Out-Null
Run $jj 'git pull --ff-only origin main' | Out-Null
if ((Run $jj 'git merge --ff-only feature/sys-01') -ne 0) { Stop 'ff 실패' }
if ((Run $jj 'git push origin main') -ne 0) { Stop 'push 실패' }
Run $jj 'git fetch origin' | Out-Null
Run $jj 'git status --short --branch' | Out-Null
Run $jj 'git log --oneline -3' | Out-Null

$env:MYSQL_PWD = $null
Log ("결과: FAIL " + $script:fail)
Log 'SYS01C-DONE'

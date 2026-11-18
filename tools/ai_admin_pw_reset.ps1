# [승인 후에만 실행] admin 비밀번호 임시 재설정 (DB 직접 수정). 11/18 기준 미실행.
# - 임시 비밀번호는 이 창에서 사용자가 직접 입력 (화면·로그에 남지 않음). BCrypt 해시는 PC-B 에서 생성.
# - 기존 해시는 로컬 백업 폴더에만 보관 (git·보고서에 쓰지 않음). 되돌리기: 백업 폴더의 restore_admin.sql 실행.
# - PW_CHANGE_DT=NULL 로 두어 다음 로그인에서 비밀번호 변경을 강제한다. LOGIN_FAIL_CNT=0.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_admin_pw_reset_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$api = 'http://localhost:8081/juprovider'
$LOGIN = 'admin'
Log ("admin pw reset " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
function Q([string]$sql) { $f = Join-Path $ws 'ai_pwr_q.sql'; [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`n$sql`n", $enc); $o = @(cmd /c "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -N -B juprovider < `"$f`" 2>&1"); $x = $LASTEXITCODE; Remove-Item $f -Force; return @{ out = $o; code = $x } }
$n = (Q "SELECT COUNT(*) FROM ju_user WHERE LOGIN_ID='$LOGIN'").out[0]
if ($n -ne '1') { Log "중단: $LOGIN 사용자 $n"; $env:MYSQL_PWD = $null; exit 1 }
$s1 = Read-Host '  새 임시 비밀번호 (8자 이상, 화면에 표시되지 않음)' -AsSecureString
$s2 = Read-Host '  한 번 더' -AsSecureString
function Plain($s) { $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) } }
$p1 = Plain $s1; $p2 = Plain $s2
if ($p1 -ne $p2 -or $p1.Length -lt 8) { Log '중단: 두 입력이 다르거나 8자 미만'; $p1 = $null; $p2 = $null; $env:MYSQL_PWD = $null; exit 1 }
$p2 = $null
# 백업 (로컬 전용)
$bd = Join-Path 'C:\MyData\MyDev\backup' ('admin_pw_' + (Get-Date -Format 'yyyyMMdd_HHmmss')); New-Item -ItemType Directory -Force -Path $bd | Out-Null
$old = (Q "SELECT CONCAT('UPDATE ju_user SET USER_PW_HASH=''', USER_PW_HASH, ''' WHERE LOGIN_ID=''$LOGIN'';') FROM ju_user WHERE LOGIN_ID='$LOGIN'").out[0]
$oldD = (Q "SELECT CONCAT('UPDATE ju_user_detail SET LOGIN_FAIL_CNT=', d.LOGIN_FAIL_CNT, ', PW_CHANGE_DT=', IFNULL(CONCAT('''', d.PW_CHANGE_DT, ''''), 'NULL'), ' WHERE USER_ID=', d.USER_ID, ';') FROM ju_user_detail d JOIN ju_user u ON u.USER_ID=d.USER_ID WHERE u.LOGIN_ID='$LOGIN'").out[0]
[IO.File]::WriteAllText((Join-Path $bd 'restore_admin.sql'), "$old`r`n$oldD`r`n", $enc)
Log ("  B-1 기존 값 백업 $bd\restore_admin.sql (로컬 전용)")
# BCrypt 해시 (spring-security-crypto, 서버와 같은 라이브러리)
$jar = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object FullName | Select-Object -Last 1
$env:SMOKE_PW = $p1; $o = cmd /c "`"$env:JAVA_HOME\bin\jshell.exe`" --class-path `"$($jar.FullName)`" `"$ws\ai_changes\ju1a\bcrypt.jsh`" 2>&1"; $env:SMOKE_PW = $null
$hash = (($o | Where-Object { $_ -match '^HASH=' }) -replace '^HASH=', '')
if ($hash -notmatch '^\$2[aby]\$\d\d\$.{53}$') { Log '중단: 해시 생성 실패'; $p1 = $null; $env:MYSQL_PWD = $null; exit 1 }
$u = Q "UPDATE ju_user SET USER_PW_HASH='$hash' WHERE LOGIN_ID='$LOGIN'; UPDATE ju_user_detail d JOIN ju_user u ON u.USER_ID=d.USER_ID SET d.LOGIN_FAIL_CNT=0, d.PW_CHANGE_DT=NULL WHERE u.LOGIN_ID='$LOGIN';"
$hash = $null
Log ("  R-1 DB 갱신 exit " + $u.code)
$body = (@{ loginId = $LOGIN; password = $p1 } | ConvertTo-Json -Compress); $p1 = $null
try { $r = Invoke-WebRequest "$api/api/auth/login" -Method POST -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8' -UseBasicParsing; $j = $r.Content | ConvertFrom-Json; Log ("  R-2 임시 비밀번호 로그인 " + [int]$r.StatusCode + ", 변경 필요 " + $j.data.passwordChangeRequired) } catch { Log ("  R-2 로그인 실패 " + $_.Exception.Message) }
$body = $null; $env:MYSQL_PWD = $null
Log '  다음: 웹 화면에서 admin 로그인 → 비밀번호 변경 화면에서 최종 비밀번호 설정'
Log 'ADMIN-PW-RESET-DONE'

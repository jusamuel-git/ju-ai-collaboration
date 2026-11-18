# 11/18 상태 조사 (읽기 전용 + 8081 이 꺼져 있으면 배포된 WAR 그대로 Tomcat 기동만).
# 비밀번호 해시·Client Key 는 출력하지 않는다 (형식·길이만).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_1118_status_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$api = 'http://localhost:8081/juprovider'
function Health { try { $r = Invoke-WebRequest "$api/api/health" -UseBasicParsing -TimeoutSec 8; return [int]$r.StatusCode } catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }; return -1 } }
function Cat { return @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' }) }
Log ("11/18 status " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$os = Get-CimInstance Win32_OperatingSystem
Log ("  S-1 마지막 부팅 " + $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm'))
$c = Cat
Log ("  S-2 8081 listen " + @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count + ", catalina 프로세스 " + $c.Count + ", health " + (Health))
foreach ($p in $c) { $par = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue; Log ("    PID " + $p.ProcessId + " 시작 " + $p.CreationDate.ToString('MM-dd HH:mm') + " 부모 " + $(if ($par) { $par.Name } else { '(종료됨)' })) }
$js = Get-Service Jenkins -ErrorAction SilentlyContinue
Log ("  S-3 Jenkins 서비스 " + $js.Status)
$jd = 'C:\ProgramData\Jenkins\.jenkins\jobs\juprovider-ai\builds'
Get-ChildItem $jd -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' } | Sort-Object { [int]$_.Name } -Descending | Select-Object -First 3 | ForEach-Object {
    $t = Get-Content (Join-Path $_.FullName 'build.xml') -Raw -ErrorAction SilentlyContinue
    Log ("    #" + $_.Name + " " + $(if ($t -match '<result>(\w+)</result>') { $matches[1] } else { '?' }) + " " + $_.CreationTime.ToString('MM-dd HH:mm'))
}
# Windows 이벤트: 11/15 이후 java 관련 종료·로그오프
$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = [datetime]'2026-11-15'; Id = 1074, 6006, 6008, 41, 42, 1 } -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { $_.TimeCreated.ToString('MM-dd HH:mm') + ' id' + $_.Id })
Log ("  S-4 시스템 종료·절전 이벤트(11/15~): " + $(if ($ev.Count) { $ev -join ', ' } else { '없음' }))

if ((Health) -ne 200 -and (Cat).Count -eq 0) {
    Log '  S-5 8081 꺼짐 → 배포된 WAR 그대로 기동 (catalina.bat run, 숨김 창: 창 닫힘으로 중지되지 않게)'
    $env:CATALINA_HOME = $tc
    Start-Process cmd.exe -ArgumentList '/c', "`"$tc\bin\catalina.bat`" run" -WindowStyle Hidden
    $env:CATALINA_HOME = $null
    $h = -1; for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 3; $h = Health; if ($h -eq 200) { break } }
    $c = Cat
    Log ("    기동 후 health $h, PID " + (($c | ForEach-Object { $_.ProcessId }) -join ','))
}
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
function Q([string]$sql) { $f = Join-Path $ws 'ai_1118_q.sql'; [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`n$sql`n", $enc); $o = @(cmd /c "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -N -B juprovider < `"$f`" 2>&1"); Remove-Item $f -Force; return $o }
Log '  S-6 사용자 (해시는 형식·길이만):'
Q "SELECT CONCAT_WS(' | ', u.USER_ID, u.LOGIN_ID, u.USE_YN, a.AUTH_TYPE, CONCAT('hash ', LEFT(u.USER_PW_HASH,4), '..', LENGTH(u.USER_PW_HASH)), CONCAT('fail ', IFNULL(d.LOGIN_FAIL_CNT,'-')), CONCAT('pwchg ', IFNULL(DATE_FORMAT(d.PW_CHANGE_DT,'%Y-%m-%d %H:%i'),'NULL'))) FROM ju_user u LEFT JOIN ju_auth a ON a.AUTH_ID=u.AUTH_ID LEFT JOIN ju_user_detail d ON d.USER_ID=u.USER_ID ORDER BY u.USER_ID" | ForEach-Object { Log ('    ' + $_) }
$ll = Q "SELECT CONCAT('last login ', IFNULL(DATE_FORMAT(d.LAST_LOGIN_DT,'%Y-%m-%d %H:%i'),'-')) FROM ju_user u LEFT JOIN ju_user_detail d ON d.USER_ID=u.USER_ID ORDER BY u.USER_ID"
Log ('    ' + ($ll -join ' / '))
Log ("  S-7 ju_client: " + ((Q "SELECT IFNULL(GROUP_CONCAT(CONCAT(CLIENT_ID,':',USE_YN)),'(없음)') FROM ju_client") -join ' '))
$cj = 'C:\MyData\MyDev\workspace\juprovider\desktop\app\config\client.json'
Log ("  S-8 client.json: " + $(if (Test-Path $cj) { '있음' } else { '없음' }))
$env:MYSQL_PWD = $null
Log ("  S-9 최종 8081 health " + (Health))
Log 'STATUS-1118-DONE'

# C5 다음 단계 조사 (11/18, 읽기 전용): GTEC 프로토콜 정의 덤프 · Tomcat 서비스 전환 사전 조건.
# DB·서비스·파일 변경 없음. 비밀 값은 출력하지 않는다 (setenv 는 이름만).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$out = Join-Path $ws 'ai_changes\c5n'; New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = Join-Path $ws ("ai_c5n_survey_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
Log ("C5n survey " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== A. GTEC 정의 (읽기) ====='
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$qs = [ordered]@{
  'protocol_group.tsv' = "SELECT * FROM ju_protocol_group WHERE PTL_GRP_CD='GTEC'"
  'protocol.tsv'       = "SELECT * FROM ju_protocol WHERE PTL_GRP_CD='GTEC' ORDER BY PTL_CD"
  'packet.tsv'         = "SELECT * FROM ju_protocol_packet WHERE PTL_GRP_CD='GTEC' ORDER BY PTL_CD"
  'device.tsv'         = "SELECT * FROM ju_device WHERE PTL_GRP_CD='GTEC' OR DEV_CD LIKE '%GTEC%'"
  'data_tag.tsv'       = "SELECT * FROM ju_data_tag WHERE DEV_CD LIKE '%GTEC%'"
  'channel_map.tsv'    = "SELECT * FROM ju_data_channel_map"
  'codes.tsv'          = "SELECT GRP_CD, CD, CD_NM FROM ju_com_code WHERE GRP_CD IN ('PTLT','PROL','PACT') ORDER BY GRP_CD, CD"
}
foreach ($k in $qs.Keys) {
    $f = Join-Path $out 'q.sql'; [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`n" + $qs[$k] + ";`n", $enc)
    $o = @(cmd /c "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -B juprovider < `"$f`" 2>&1"); Remove-Item $f -Force
    [IO.File]::WriteAllLines((Join-Path $out $k), $o, $enc)
    Log ("  $k " + ($o.Count - 1) + "행")
}
$env:MYSQL_PWD = $null

Log '===== B. Tomcat 서비스 전환 사전 조건 ====='
Log ("  B-1 서비스 실행 파일: tomcat10.exe " + (Test-Path "$tc\bin\tomcat10.exe") + ", tomcat10w.exe " + (Test-Path "$tc\bin\tomcat10w.exe") + ", service.bat " + (Test-Path "$tc\bin\service.bat"))
$sb = Get-Content "$tc\bin\service.bat" -ErrorAction SilentlyContinue
$sb | Select-String -Pattern 'SERVICE_NAME=|DISPLAYNAME=|ServiceUser|--Startup|setenv|JvmMx|JvmMs|--Jvm |StartMode|StopMode|--Classpath|PR_|set "JAVA_HOME|JRE_HOME|--LogPath|--StdOutput|--Environment|JvmOptions' | ForEach-Object { Log ('    ' + $_.Line.Trim()) }
Log ("  B-2 기존 Tomcat 서비스: " + ((@(Get-Service | Where-Object { $_.Name -match 'tomcat' -or $_.DisplayName -match 'tomcat' }) | ForEach-Object { $_.Name + '/' + $_.Status }) -join ', '))
$names = @(Get-Content "$tc\bin\setenv.bat" | ForEach-Object { if ($_ -match '^\s*set\s+"?([A-Za-z_]+)=') { $matches[1] } })
Log ("  B-3 setenv.bat 변수 이름: " + ($names -join ', '))
foreach ($n in 'JAVA_HOME', 'JRE_HOME', 'CATALINA_HOME', 'JU_TOMCAT_HOME') { Log ("    {0}: Machine='{1}' User='{2}'" -f $n, [Environment]::GetEnvironmentVariable($n, 'Machine'), [Environment]::GetEnvironmentVariable($n, 'User')) }
$sx = Get-Content "$tc\conf\server.xml" -Raw
Log ("  B-4 server.xml Server port/shutdown: " + $(if ($sx -match '<Server port="(-?\d+)" shutdown="([^"]+)"') { $matches[1] + ' / 명령 ' + $(if ($matches[2] -eq 'SHUTDOWN') { '기본값' } else { '변경됨' }) } else { '?' }))
foreach ($d in 'logs', 'webapps', 'work', 'temp', 'conf') {
    $acl = (icacls "$tc\$d" 2>&1 | Select-Object -First 8 | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' ; '
    Log ("  B-5 $d ACL: " + $acl.Substring(0, [Math]::Min(300, $acl.Length)))
}
$js = Get-CimInstance Win32_Service -Filter "Name='Jenkins'"
Log ("  B-6 Jenkins 계정 " + $js.StartName + ", 상태 " + $js.State)
$c = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina|tomcat' })
Log ("  B-7 현재 Tomcat java 프로세스 " + $c.Count + " " + (($c | ForEach-Object { 'PID ' + $_.ProcessId + ' 시작 ' + $_.CreationDate.ToString('MM-dd HH:mm') }) -join ', ') + ", 8081 listen " + @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count)
$jv = @(Get-ChildItem 'C:\MyData\MyTool\jdk' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + $(if (Test-Path ($_.FullName + '\bin\server\jvm.dll')) { '(jvm.dll)' } else { '' }) })
Log ("  B-8 JDK 폴더: " + ($jv -join ', '))
Log ("  B-9 관리자 권한으로 실행 중: " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Log 'C5N-SURVEY-DONE'

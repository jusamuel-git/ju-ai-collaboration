# PC-B 사전 점검 (읽기 전용 + git fetch): Git 상태·remote, 환경 측정, setenv 변수 존재(값 미기록), 로컬 DB 상태
# 제품 코드·DB·환경변수를 바꾸지 않는다. checkout 하지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_pcb_precheck_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
Log ("PC-B precheck " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " / " + $env:COMPUTERNAME)

foreach ($repo in 'juprovider', 'juproject') {
    $d = Join-Path $ws $repo
    Log ''; Log "===== Git: $repo ====="
    Run $d 'git remote -v' | Out-Null
    Run $d 'git status --short --branch' | Out-Null
    Run $d 'git stash list' | Out-Null
    Run $d 'git log --oneline -3' | Out-Null
    Run $d 'git fetch origin --prune' | Out-Null
    Run $d 'git branch -a --format=%(refname:short)=%(objectname:short)' | Out-Null
    Run $d 'git log --oneline -1 origin/main' | Out-Null
}
$jp = Join-Path $ws 'juprovider'
Run $jp 'git log --oneline --first-parent origin/feature/protocol-ref -4' | Out-Null
Run $jp 'git merge-base --is-ancestor origin/main origin/feature/protocol-ref' | Out-Null

Log ''; Log '===== 환경 ====='
Log ("COMPUTERNAME=" + $env:COMPUTERNAME)
foreach ($s in 'Process', 'User', 'Machine') {
    foreach ($k in 'JAVA_HOME', 'MAVEN_HOME', 'M2_HOME', 'VCPKG_ROOT') { $v = [Environment]::GetEnvironmentVariable($k, $s); if ($v) { Log ("  [$s] $k=$v") } }
}
Log '  PATH(java/mvn/dotnet/node/git/mysql/cmake 관련):'
($env:PATH -split ';') | Where-Object { $_ -match 'jdk|java|maven|dotnet|node|nvm|git|mariadb|mysql|cmake|vcpkg' } | ForEach-Object { Log ('    ' + $_) }
foreach ($c in 'java -version', 'where java', 'mvn -v', 'where mvn', 'dotnet --list-sdks', 'node -v', 'npm -v', 'git --version', 'cmake --version', 'where vcpkg') { Run $ws $c | Out-Null }
$gj = Join-Path $jp 'global.json'; if (Test-Path $gj) { Log ('  juprovider global.json: ' + ((Get-Content $gj -Raw) -replace '\s+', ' ')) }
$gj2 = Join-Path $ws 'juproject\global.json'; if (Test-Path $gj2) { Log ('  juproject global.json: ' + ((Get-Content $gj2 -Raw) -replace '\s+', ' ')) }
$ms = Join-Path $env:USERPROFILE '.m2\settings.xml'; Log ("  ~/.m2/settings.xml 존재: " + (Test-Path $ms))
$m2c = Get-ChildItem "$env:USERPROFILE\.m2\repository\org\springframework\security\spring-security-crypto" -Recurse -Filter '*.jar' -ErrorAction SilentlyContinue | Select-Object -First 3
Log ("  ~/.m2 spring-security-crypto jar: " + (@($m2c | ForEach-Object { $_.FullName }) -join ', '))
$m2t = Get-ChildItem 'C:\MyData\MyTool\maven\repository\org\springframework\security\spring-security-crypto' -Recurse -Filter '*.jar' -ErrorAction SilentlyContinue | Select-Object -First 3
Log ("  MyTool\maven\repository spring-security-crypto jar: " + (@($m2t | ForEach-Object { $_.FullName }) -join ', '))
$mvnSettings = 'C:\MyData\MyTool\maven\apache-maven-3.9.11\conf\settings.xml'
if (Test-Path $mvnSettings) { $lr = Select-String -Path $mvnSettings -Pattern '<localRepository>' | Select-Object -First 1; Log ("  maven conf localRepository: " + $(if ($lr) { $lr.Line.Trim() } else { '(기본)' })) }

Log ''; Log '===== Tomcat setenv (변수 이름·존재만) ====='
$se = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat'
$vars = @{}
if (Test-Path $se) { foreach ($l in Get-Content $se) { if ($l -match '^\s*set\s+"?([A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } } }
foreach ($k in ($vars.Keys | Sort-Object)) { $v = $vars[$k]; Log ("  $k : " + $(if ($k -match 'PASSWORD|SECRET|KEY') { 'SET (len ' + $v.Length + ')' } elseif ($k -eq 'JU_DB_URL') { ($v -replace '(password|pwd)=[^&;]*', '$1=***') } else { $v })) }
Log ("  JU_JWT_SECRET 32바이트 이상: " + ($vars['JU_JWT_SECRET'] -and [Text.Encoding]::UTF8.GetByteCount($vars['JU_JWT_SECRET']) -ge 32))

Log ''; Log '===== MariaDB / 로컬 DB (읽기) ====='
$bin = 'C:\Program Files\MariaDB 10.6\bin'
Log ("  mysql.exe: " + (Test-Path "$bin\mysql.exe"))
Get-Service | Where-Object { $_.Name -match 'maria|mysql|redis|jenkins|tomcat' } | ForEach-Object { Log ("  service " + $_.Name + " " + $_.Status) }
if ($vars['JU_DB_USER'] -and (Test-Path "$bin\mysql.exe")) {
    $env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
    $base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -N -B"
    foreach ($q in "SELECT VERSION()", "SHOW DATABASES",
                   "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME IN ('ju_client','ju_menu_action')",
                   "SELECT CONCAT('ju_menu_action=',(SELECT COUNT(*) FROM juprovider.ju_menu_action),' users=',(SELECT COUNT(*) FROM juprovider.ju_user),' auth1=',(SELECT LEFT(AUTH_ATTR,30) FROM juprovider.ju_auth WHERE AUTH_ID=1))",
                   "SELECT CONCAT('ju_client=',COUNT(*)) FROM juprovider.ju_client") {
        Log ("> " + $q); (cmd /c "$base -e `"$q`" 2>&1") | ForEach-Object { Log ('  ' + $_) }
    }
    Log '> 권한 (TRIGGER 등)'; (cmd /c "$base -e `"SHOW GRANTS`" 2>&1") | ForEach-Object { Log ('  ' + ($_ -replace "IDENTIFIED BY PASSWORD '[^']*'", "IDENTIFIED BY PASSWORD '***'")) }
    $env:MYSQL_PWD = $null
}
Log ''; Log ("포트 18081 사용 중: " + [bool](Get-NetTCPConnection -LocalPort 18081 -State Listen -ErrorAction SilentlyContinue))
Log ("포트 8081 사용 중: " + [bool](Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue))
Log 'PRECHECK-DONE'

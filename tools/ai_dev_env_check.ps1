# 개발 환경 검증 (DEV_ENVIRONMENT_STANDARD.md 기준) - 읽기 전용
#
# 설치/삭제/환경변수 변경을 하지 않는다. secret은 값이 아니라 SET/MISSING만 출력한다.
#
# 실행 (기본 = 검증):
#   powershell -ExecutionPolicy Bypass -File C:\MyData\MyDev\workspace\ai_dev_env_check.ps1
# 기준 PC(PC-A)에서 기준 버전 기록:
#   powershell -ExecutionPolicy Bypass -File C:\MyData\MyDev\workspace\ai_dev_env_check.ps1 -Baseline
#   → workspace\dev_env_baseline.json 에 PC-A 실제 버전을 저장 (다른 PC는 이 파일과 비교)
#
# 결과: workspace\ai_dev_env_check_<컴퓨터이름>.log
# 판정: PASS = 기준과 같음 / WARN = 동작은 하지만 기준과 다름 / FAIL = 없음 또는 기준 버전과 맞지 않음

param(
    [switch]$Baseline,
    [string]$Workspace = 'C:\MyData\MyDev\workspace'
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$LogPath      = Join-Path $Workspace ("ai_dev_env_check_{0}.log" -f $env:COMPUTERNAME)
$BaselinePath = Join-Path $Workspace 'dev_env_baseline.json'
$Utf8NoBom    = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($LogPath, '', $Utf8NoBom)

function Log([string]$text) {
    Write-Host $text
    [IO.File]::AppendAllText($LogPath, $text + "`r`n", $Utf8NoBom)
}

# ---------------------------------------------------------------
# 기준값 (PC-A DESKTOP-CE5BGKK). 경로는 PC-A 기준 위치이며,
# 다른 PC는 같은 위치를 권장하되 환경변수가 올바르면 WARN으로 허용한다.
# ---------------------------------------------------------------
$Std = [ordered]@{
    Workspace = 'C:\MyData\MyDev\workspace'
    Jdk       = 'C:\MyData\MyDev\jdk\jdk-21.0.1'
    Maven     = 'C:\MyData\MyDev\maven\apache-maven-3.9.11'
    Vcpkg     = 'C:\MyData\MyTool\vcpkg'
    Tomcat    = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
    Dotnet    = 'C:\Program Files\dotnet'
    Node      = 'C:\Program Files\nodejs'
    CMake     = 'C:\Program Files\CMake'
    MariaDB   = 'C:\Program Files\MariaDB 10.6'
    Git       = 'C:\Program Files\Git'
    Redis     = 'C:\Program Files\Redis'
    Jenkins   = 'C:\Program Files\Jenkins'
}

# 고정 기준 버전 (정규식). 나머지 Tool은 dev_env_baseline.json(PC-A 실측)과 비교한다.
$FixedVersion = @{
    'JDK'       = '^21\.0\.1$'
    'Maven'     = '^3\.9\.11$'
    'Tomcat'    = '^10\.1\.52$'
    '.NET SDK'  = '^10\.0\.4\d\d$'
    'MariaDB'   = '^10\.6\.'
}

$BaselineData = @{}
if (-not $Baseline -and (Test-Path $BaselinePath)) {
    try {
        $json = Get-Content $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $json.versions.PSObject.Properties) { $BaselineData[$p.Name] = $p.Value }
    } catch { }
}

$Results = New-Object System.Collections.ArrayList
$Actuals = [ordered]@{}

function Add-Result($tool, $expectedVersion, $actualVersion, $expectedPath, $actualPath, $status, $note) {
    [void]$Results.Add([pscustomobject]@{
        Tool            = $tool
        ExpectedVersion = $expectedVersion
        ActualVersion   = $actualVersion
        ExpectedPath    = $expectedPath
        ActualPath      = $actualPath
        Result          = $status
        Note            = $note
    })
}

function First-Line($value) {
    if ($null -eq $value) { return '' }
    return ((@($value) | ForEach-Object { "$_" }) | Where-Object { $_.Trim() } | Select-Object -First 1)
}

function Invoke-Quiet([scriptblock]$block) {
    try { return (& $block 2>&1 | ForEach-Object { "$_" }) } catch { return $null }
}

function Get-EnvBoth([string]$name) {
    return @{
        User    = [Environment]::GetEnvironmentVariable($name, 'User')
        Machine = [Environment]::GetEnvironmentVariable($name, 'Machine')
    }
}

# 버전 판정: 고정 기준 → baseline → 기록만
function Judge-Version([string]$tool, [string]$actual) {
    if (-not $actual) { return @('?', 'FAIL', '버전 확인 실패') }
    if ($FixedVersion.ContainsKey($tool)) {
        $pattern = $FixedVersion[$tool]
        if ($actual -match $pattern) { return @($pattern, 'PASS', '') }
        return @($pattern, 'FAIL', '기준 버전과 다름')
    }
    if ($BaselineData.ContainsKey($tool)) {
        $expected = $BaselineData[$tool]
        if ($actual -eq $expected) { return @($expected, 'PASS', '') }
        return @($expected, 'WARN', 'PC-A 기준 버전과 다름')
    }
    return @('(PC-A 기준값 없음)', 'WARN', '-Baseline으로 기준값을 먼저 기록')
}

function Judge-Path([string]$expected, [string]$actual) {
    if (-not $actual) { return 'FAIL' }
    if ($expected -and ($actual.TrimEnd('\') -ieq $expected.TrimEnd('\'))) { return 'PASS' }
    return 'WARN'
}

function Worst([string[]]$statuses) {
    if ($statuses -contains 'FAIL') { return 'FAIL' }
    if ($statuses -contains 'WARN') { return 'WARN' }
    return 'PASS'
}

function Check-Tool([string]$tool, [string]$expectedPath, [string]$actualPath, [string]$actualVersion, [string]$extraNote) {
    $v = Judge-Version $tool $actualVersion
    $pathStatus = Judge-Path $expectedPath $actualPath
    $status = Worst @($v[1], $pathStatus)
    $notes = @($v[2], $extraNote) | Where-Object { $_ }
    if ($pathStatus -eq 'WARN') { $notes += '경로가 PC-A 기준과 다름' }
    if ($pathStatus -eq 'FAIL') { $notes += '설치 위치를 찾지 못함' }
    $Actuals[$tool] = $actualVersion
    Add-Result $tool $v[0] $actualVersion $expectedPath $actualPath $status (($notes | Select-Object -Unique) -join '; ')
}

Log ("개발 환경 검증 - {0} / {1} / {2}" -f $env:COMPUTERNAME, $env:USERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Log ("모드: {0}" -f $(if ($Baseline) { 'Baseline 기록 (PC-A)' } else { '검증' }))
Log ("PC-A 기준값 파일: {0}" -f $(if ($BaselineData.Count -gt 0) { $BaselinePath } else { '없음' }))

# ---------------------------------------------------------------
# 1. Workspace / 저장소
# ---------------------------------------------------------------
$ws = if (Test-Path $Std.Workspace) { $Std.Workspace } else { $null }
Add-Result 'Workspace' '' '' $Std.Workspace $ws $(if ($ws) {'PASS'} else {'FAIL'}) ''
foreach ($repo in 'juprovider', 'juproject') {
    $rp = Join-Path $Std.Workspace $repo
    if (Test-Path (Join-Path $rp '.git')) {
        $branch = First-Line (Invoke-Quiet { git -C $rp rev-parse --abbrev-ref HEAD })
        $head   = First-Line (Invoke-Quiet { git -C $rp rev-parse --short HEAD })
        $dirty  = @(Invoke-Quiet { git -C $rp status --porcelain }).Where({ $_ }).Count
        Add-Result ("repo " + $repo) '' ("{0} {1}" -f $branch, $head) $rp $rp 'PASS' ("변경 파일 {0}개" -f $dirty)
    } else {
        Add-Result ("repo " + $repo) '' '' $rp '' 'FAIL' 'clone 없음'
    }
}

# ---------------------------------------------------------------
# 2. Portable Tool (환경변수 기준)
# ---------------------------------------------------------------
# JDK
$jdkHome = $env:JAVA_HOME; if (-not $jdkHome) { $jdkHome = $Std.Jdk }
$javaExe = Join-Path $jdkHome 'bin\java.exe'
$jdkVer = $null
if (Test-Path $javaExe) {
    $line = First-Line (Invoke-Quiet { cmd /c "`"$javaExe`" -version 2>&1" })
    if ($line -match 'version "([^"]+)"') { $jdkVer = $Matches[1] }
} else { $jdkHome = $null }
Check-Tool 'JDK' $Std.Jdk $jdkHome $jdkVer $(if (-not $env:JAVA_HOME) {'JAVA_HOME 없음 (기준 경로로 확인)'})

# Maven
$mvnHome = $env:MAVEN_HOME; if (-not $mvnHome) { $mvnHome = $Std.Maven }
$mvnCmd = Join-Path $mvnHome 'bin\mvn.cmd'
$mvnVer = $null
if (Test-Path $mvnCmd) {
    $saved = $env:JAVA_HOME
    if ($jdkHome) { $env:JAVA_HOME = $jdkHome }
    $line = First-Line (Invoke-Quiet { cmd /c "`"$mvnCmd`" -v 2>&1" })
    $env:JAVA_HOME = $saved
    if ($line -match 'Apache Maven (\S+)') { $mvnVer = $Matches[1] }
} else { $mvnHome = $null }
Check-Tool 'Maven' $Std.Maven $mvnHome $mvnVer $(if (-not $env:MAVEN_HOME) {'MAVEN_HOME 없음 (기준 경로로 확인)'})

# Tomcat
$tcHome = $env:JU_TOMCAT_HOME; if (-not $tcHome) { $tcHome = $Std.Tomcat }
$tcVer = $null
$rn = Join-Path $tcHome 'RELEASE-NOTES'
if (Test-Path $rn) {
    $m = Select-String -Path $rn -Pattern 'Apache Tomcat Version (\S+)' | Select-Object -First 1
    if ($m) { $tcVer = $m.Matches[0].Groups[1].Value }
} elseif (-not (Test-Path (Join-Path $tcHome 'bin\startup.bat'))) { $tcHome = $null }
Check-Tool 'Tomcat' $Std.Tomcat $tcHome $tcVer $(if (-not $env:JU_TOMCAT_HOME) {'JU_TOMCAT_HOME 없음 (기준 경로로 확인)'})

# vcpkg
$vcHome = $env:VCPKG_ROOT; if (-not $vcHome) { $vcHome = $Std.Vcpkg }
$vcExe = Join-Path $vcHome 'vcpkg.exe'
$vcVer = $null
if (Test-Path $vcExe) {
    $line = First-Line (Invoke-Quiet { & $vcExe version })
    if ($line -match 'version\s+(\S+)') { $vcVer = $Matches[1] } else { $vcVer = $line }
} elseif (Test-Path $vcHome) {
    $vcVer = '(vcpkg.exe 없음 - bootstrap 전)'
} else { $vcHome = $null }
Check-Tool 'vcpkg' $Std.Vcpkg $vcHome $vcVer $(if (-not $env:VCPKG_ROOT) {'VCPKG_ROOT 없음 (기준 경로로 확인)'})

# ---------------------------------------------------------------
# 3. 설치형 Tool (PATH 기준)
# ---------------------------------------------------------------
function Where-First([string]$name) {
    $r = & where.exe $name 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (First-Line $r)
}
function Parent-Of([string]$file, [int]$levels) {
    if (-not $file) { return $null }
    $p = $file
    for ($i = 0; $i -lt $levels; $i++) { $p = Split-Path $p }
    return $p
}

# .NET SDK
$dotnetExe = Where-First 'dotnet'
$sdks = @(Invoke-Quiet { dotnet --list-sdks }) | Where-Object { $_ -match '^\d' }
$sdk10 = $sdks | ForEach-Object { ($_ -split ' ')[0] } | Where-Object { $_ -match '^10\.0\.4\d\d$' } | Sort-Object { [version]$_ } | Select-Object -Last 1
Check-Tool '.NET SDK' $Std.Dotnet (Parent-Of $dotnetExe 1) $sdk10 ("설치된 SDK: " + (($sdks | ForEach-Object { ($_ -split ' ')[0] }) -join ', '))

# Node / npm
$nodeExe = Where-First 'node'
$nodeVer = (First-Line (Invoke-Quiet { node --version })) -replace '^v', ''
Check-Tool 'Node' $Std.Node (Parent-Of $nodeExe 1) $nodeVer 'Vue Maven 빌드는 frontend-maven-plugin 자체 Node(v22.14.0) 사용'
$npmVer = First-Line (Invoke-Quiet { cmd /c 'npm --version 2>&1' })
Check-Tool 'npm' $Std.Node (Parent-Of (Where-First 'npm') 1) $npmVer ''

# CMake
$cmakeExe = Where-First 'cmake'
$cmakeVer = $null
$line = First-Line (Invoke-Quiet { cmake --version })
if ($line -match 'version\s+(\S+)') { $cmakeVer = $Matches[1] }
Check-Tool 'CMake' $Std.CMake (Parent-Of $cmakeExe 2) $cmakeVer ''

# Git
$gitExe = Where-First 'git'
$gitVer = $null
$line = First-Line (Invoke-Quiet { git --version })
if ($line -match 'git version\s+(\S+)') { $gitVer = $Matches[1] }
Check-Tool 'Git' $Std.Git (Parent-Of $gitExe 2) $gitVer ''

# MariaDB (프로그램만. 데이터 위치는 PC별 허용)
$mysqlExe = Join-Path $Std.MariaDB 'bin\mysql.exe'
$mariaHome = $null; $mariaVer = $null
if (Test-Path $mysqlExe) {
    $mariaHome = $Std.MariaDB
} else {
    $w = Where-First 'mysql'
    if ($w) { $mysqlExe = $w; $mariaHome = Parent-Of $w 2 }
}
if ($mariaHome) {
    $line = First-Line (Invoke-Quiet { & $mysqlExe --version })
    if ($line -match '(\d+\.\d+\.\d+)-MariaDB') { $mariaVer = $Matches[1] } elseif ($line -match 'Distrib (\d+\.\d+\.\d+)') { $mariaVer = $Matches[1] }
}
$mariaSvc = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'maria|mysql' } | Select-Object -First 1
Check-Tool 'MariaDB' $Std.MariaDB $mariaHome $mariaVer $(if ($mariaSvc) { "서비스 {0} ({1})" -f $mariaSvc.Name, $mariaSvc.State } else { '서비스 없음' })

# Redis
$redisExe = Join-Path $Std.Redis 'redis-server.exe'
$redisHome = $null; $redisVer = $null
if (Test-Path $redisExe) {
    $redisHome = $Std.Redis
    $line = First-Line (Invoke-Quiet { & $redisExe --version })
    if ($line -match 'v=(\S+)') { $redisVer = $Matches[1] } else { $redisVer = $line }
}
Check-Tool 'Redis' $Std.Redis $redisHome $redisVer ''

# Jenkins
$jsvc = Get-CimInstance Win32_Service -Filter "Name='Jenkins'" -ErrorAction SilentlyContinue
$jVer = $null
$jcfg = 'C:\ProgramData\Jenkins\.jenkins\config.xml'
if (Test-Path $jcfg) {
    $m = Select-String -Path $jcfg -Pattern '<version>([^<]+)</version>' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { $jVer = $m.Matches[0].Groups[1].Value }
}
$jNote = if ($jsvc) { "서비스 {0}, 계정 {1}" -f $jsvc.State, $jsvc.StartName } else { '서비스 없음' }
if ($jsvc -and $jsvc.StartName -ne 'LocalSystem') { $jNote += ' (기준: LocalSystem)' }
Check-Tool 'Jenkins' $Std.Jenkins $(if ($jsvc) { $Std.Jenkins }) $jVer $jNote

# Visual Studio / VS Code (기록용)
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vsVer = $null; $vsPath = $null
if (Test-Path $vswhere) {
    $vsVer  = First-Line (Invoke-Quiet { & $vswhere -latest -property installationVersion })
    $vsPath = First-Line (Invoke-Quiet { & $vswhere -latest -property installationPath })
}
Check-Tool 'Visual Studio' 'C:\Program Files\Microsoft Visual Studio\18\Community' $vsPath $vsVer ''
$codeVer = First-Line (Invoke-Quiet { cmd /c 'code --version 2>&1' })
$codePath = Parent-Of (Where-First 'code') 2
Check-Tool 'VS Code' (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code') $codePath $codeVer ''

# ---------------------------------------------------------------
# 4. 개발자 환경변수 (User 기본)
# ---------------------------------------------------------------
$EnvExpected = [ordered]@{
    'JU_WORKSPACE'   = $Std.Workspace
    'JAVA_HOME'      = $Std.Jdk
    'MAVEN_HOME'     = $Std.Maven
    'VCPKG_ROOT'     = $Std.Vcpkg
    'JU_TOMCAT_HOME' = $Std.Tomcat
}
foreach ($k in $EnvExpected.Keys) {
    $e = Get-EnvBoth $k
    $expected = $EnvExpected[$k]
    $actual = if ($e.User) { $e.User } elseif ($e.Machine) { $e.Machine } else { '' }
    $scope = if ($e.User -and $e.Machine) { 'User+Machine' } elseif ($e.User) { 'User' } elseif ($e.Machine) { 'Machine' } else { '없음' }
    $status = 'PASS'; $note = "범위: $scope"
    if (-not $actual) { $status = 'WARN'; $note = '미설정 (User 변수로 설정 권장)' }
    elseif (-not (Test-Path $actual)) { $status = 'FAIL'; $note += '; 경로 없음' }
    elseif ($actual.TrimEnd('\') -ine $expected.TrimEnd('\')) { $status = 'WARN'; $note += '; PC-A 기준과 다름' }
    if ($e.User -and $e.Machine -and ($e.User.TrimEnd('\') -ine $e.Machine.TrimEnd('\'))) { $status = Worst @($status, 'WARN'); $note += '; User와 Machine 값이 다름' }
    Add-Result ("env " + $k) '' '' $expected $actual $status $note
}

# ---------------------------------------------------------------
# 5. PATH 충돌
# ---------------------------------------------------------------
function Check-PathFirst([string]$name, [string]$toolHome, [string]$label) {
    $all = @(& where.exe $name 2>$null)
    if (-not $all -or $all.Count -eq 0) { Add-Result ("PATH " + $name) '' '' $label '' 'WARN' 'PATH에 없음'; return }
    $first = $all[0]
    $status = 'PASS'; $note = ("후보 {0}개" -f $all.Count)
    if ($toolHome -and -not $first.StartsWith($toolHome.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { $status = 'WARN'; $note += '; 첫 번째 항목이 기준 위치가 아님' }
    if ($all.Count -gt 1) { $note += ('; 전체: ' + ($all -join ' | ')) }
    Add-Result ("PATH " + $name) '' '' $label $first $status $note
}
Check-PathFirst 'java'  $jdkHome 'JAVA_HOME\bin'
Check-PathFirst 'mvn'   $mvnHome 'MAVEN_HOME\bin'
Check-PathFirst 'node'  $Std.Node $Std.Node
Check-PathFirst 'dotnet' $Std.Dotnet $Std.Dotnet

# ---------------------------------------------------------------
# 6. global.json 해석 (저장소에 있을 때만)
# ---------------------------------------------------------------
foreach ($repo in 'juprovider', 'juproject') {
    $rp = Join-Path $Std.Workspace $repo
    if (Test-Path (Join-Path $rp 'global.json')) {
        Push-Location $rp
        $resolved = First-Line (Invoke-Quiet { dotnet --version })
        Pop-Location
        $st = if ($resolved -match '^10\.0\.4\d\d$') { 'PASS' } else { 'FAIL' }
        Add-Result ("global.json " + $repo) '10.0.4xx' $resolved $rp $rp $st '저장소 global.json 기준 SDK'
    }
}

# ---------------------------------------------------------------
# 7. Secret / Local Config (값은 출력하지 않음)
# ---------------------------------------------------------------
$setenv = Join-Path $tcHome 'bin\setenv.bat'
if ($tcHome -and (Test-Path $setenv)) {
    $content = Get-Content $setenv -Raw
    foreach ($k in 'JU_DB_URL', 'JU_DB_USER', 'JU_DB_PASSWORD', 'JU_JWT_SECRET') {
        $isSet = $content -match ("(?im)^\s*set\s+`"?{0}=(?!\s*`"?\s*$)(?!__SET_ME__)" -f $k)
        $sev = if ($isSet) { 'PASS' } elseif ($k -eq 'JU_JWT_SECRET') { 'WARN' } else { 'FAIL' }
        Add-Result ("secret " + $k) '' $(if ($isSet) {'SET'} else {'MISSING'}) 'Tomcat bin\setenv.bat' $setenv $sev ''
    }
} else {
    Add-Result 'secret setenv.bat' '' 'MISSING' 'Tomcat bin\setenv.bat' '' 'FAIL' 'setenv.bat 없음'
}

$apiProj = Join-Path $Std.Workspace 'juproject\backend\src\JuProject.Api\JuProject.Api.csproj'
if (Test-Path $apiProj) {
    $m = Select-String -Path $apiProj -Pattern '<UserSecretsId>([^<]+)</UserSecretsId>' | Select-Object -First 1
    if ($m) {
        $sid = $m.Matches[0].Groups[1].Value
        $sf = Join-Path $env:APPDATA ("Microsoft\UserSecrets\{0}\secrets.json" -f $sid)
        $keys = @()
        if (Test-Path $sf) {
            try {
                $j = Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json
                $keys = @($j.PSObject.Properties.Name)
            } catch { }
        }
        foreach ($k in 'ConnectionStrings:Default', 'Jwt:SigningKey') {
            $isSet = $keys -contains $k
            Add-Result ("secret juproject " + $k) '' $(if ($isSet) {'SET'} else {'MISSING'}) 'dotnet user-secrets' $sf $(if ($isSet) {'PASS'} else {'WARN'}) '로컬 실행·migration에 필요 (Jenkins 빌드에는 불필요)'
        }
    }
}

# ---------------------------------------------------------------
# 결과
# ---------------------------------------------------------------
Log ''
$table = $Results | Format-Table Tool, ExpectedVersion, ActualVersion, Result, ActualPath, Note -AutoSize -Wrap | Out-String -Width 400
foreach ($l in ($table -split "`r?`n")) { Log $l }

$pass = @($Results | Where-Object Result -eq 'PASS').Count
$warn = @($Results | Where-Object Result -eq 'WARN').Count
$fail = @($Results | Where-Object Result -eq 'FAIL').Count
Log ("합계: PASS {0} / WARN {1} / FAIL {2}" -f $pass, $warn, $fail)

if ($Baseline) {
    $data = [ordered]@{
        computer = $env:COMPUTERNAME
        recordedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        versions = $Actuals
    }
    [IO.File]::WriteAllText($BaselinePath, ($data | ConvertTo-Json -Depth 4), $Utf8NoBom)
    Log ("PC-A 기준값 저장: " + $BaselinePath)
}
Log ("로그: " + $LogPath)

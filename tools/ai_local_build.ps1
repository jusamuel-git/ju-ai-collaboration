# 로컬 빌드 확인 (DEV_ENVIRONMENT_STANDARD.md 11장 2단계)
#
# 배포, DB 변경, git 변경을 하지 않는다. 빌드 산출물(target, bin, obj, dist, node_modules)만 생긴다.
# juprovider.core는 개발자 Maven 저장소(%USERPROFILE%\.m2)에 install된다 (Jenkins 저장소와 별개).
# 첫 실행은 Maven/npm/NuGet 의존성과 Vue 빌드용 Node(v22.14.0)를 내려받으므로 인터넷이 필요하다.
#
#   powershell -ExecutionPolicy Bypass -File C:\MyData\MyDev\workspace\ai_local_build.ps1
#   (desktop 빌드 제외: -SkipDesktop)
#
# 결과: workspace\ai_local_build_<컴퓨터이름>.log

param(
    [switch]$SkipDesktop,
    [string]$Workspace = 'C:\MyData\MyDev\workspace'
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$LogPath   = Join-Path $Workspace ("ai_local_build_{0}.log" -f $env:COMPUTERNAME)
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($LogPath, '', $Utf8NoBom)

function Log([string]$text) {
    Write-Host $text
    [IO.File]::AppendAllText($LogPath, $text + "`r`n", $Utf8NoBom)
}

$Summary = New-Object System.Collections.ArrayList

function Step([string]$name, [string]$dir, [string]$command, [string]$expectFile) {
    Log ''
    Log ('===== ' + $name + ' =====')
    Log ('위치: ' + $dir)
    Log ('명령: ' + $command)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if (-not (Test-Path $dir)) {
        Log '폴더 없음'
        [void]$Summary.Add([pscustomobject]@{ Step = $name; Result = 'FAIL'; Seconds = 0; Note = '폴더 없음' })
        return $false
    }
    Push-Location $dir
    cmd /c "$command 2>&1" | ForEach-Object { Log ('  ' + $_) }
    $code = $LASTEXITCODE
    Pop-Location
    $sw.Stop()
    $note = "exit $code"
    $ok = ($code -eq 0)
    if ($ok -and $expectFile) {
        $full = Join-Path $dir $expectFile
        if (-not (Test-Path $full)) { $ok = $false; $note += "; 산출물 없음: $expectFile" } else { $note += "; 산출물 확인: $expectFile" }
    }
    [void]$Summary.Add([pscustomobject]@{ Step = $name; Result = $(if ($ok) {'PASS'} else {'FAIL'}); Seconds = [int]$sw.Elapsed.TotalSeconds; Note = $note })
    return $ok
}

Log ("로컬 빌드 확인 - {0} / {1} / {2}" -f $env:COMPUTERNAME, $env:USERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Log ("JAVA_HOME={0}" -f $env:JAVA_HOME)
foreach ($repo in 'juprovider', 'juproject') {
    $rp = Join-Path $Workspace $repo
    $b = (& git -C $rp rev-parse --abbrev-ref HEAD 2>$null)
    $h = (& git -C $rp rev-parse --short HEAD 2>$null)
    $d = @(& git -C $rp status --porcelain 2>$null).Count
    Log ("{0}: {1} {2} (변경 파일 {3}개)" -f $repo, $b, $h, $d)
}

$jp = Join-Path $Workspace 'juprovider'
$jj = Join-Path $Workspace 'juproject'

# juprovider
$coreOk = Step 'juprovider.core install' $jp 'mvn -B -f juprovider.core\pom.xml clean install' 'juprovider.core\target'
if ($coreOk) {
    Step 'juprovider.backend + Vue (WAR)' (Join-Path $jp 'juprovider.backend') 'mvn -B clean package -Pvue' 'target\juprovider.war' | Out-Null
} else {
    [void]$Summary.Add([pscustomobject]@{ Step = 'juprovider.backend + Vue (WAR)'; Result = 'SKIP'; Seconds = 0; Note = 'core install 실패' })
}
if (-not $SkipDesktop) {
    Step 'juprovider desktop' $jp 'dotnet build desktop\JuProvider.Desktop.slnx -c Debug' '' | Out-Null
}

# juproject
Step 'juproject backend' $jj 'dotnet build backend\JuProject.slnx -c Release' '' | Out-Null
$fe = Join-Path $jj 'frontend'
if (Step 'juproject frontend npm ci' $fe 'npm ci' 'node_modules') {
    Step 'juproject frontend lint' $fe 'npm run lint' '' | Out-Null
    Step 'juproject frontend build' $fe 'npm run build' 'dist\index.html' | Out-Null
} else {
    [void]$Summary.Add([pscustomobject]@{ Step = 'juproject frontend lint/build'; Result = 'SKIP'; Seconds = 0; Note = 'npm ci 실패' })
}

Log ''
Log '===== 요약 ====='
$table = $Summary | Format-Table Step, Result, Seconds, Note -AutoSize -Wrap | Out-String -Width 300
foreach ($l in ($table -split "`r?`n")) { Log $l }
Log ("로그: " + $LogPath)

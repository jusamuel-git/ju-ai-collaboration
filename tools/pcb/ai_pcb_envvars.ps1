# 환경변수·vcpkg·CMake·VS 확인 (읽기 전용, 값은 경로 변수만 출력)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$log = Join-Path 'C:\MyData\MyDev\workspace' ("ai_pcb_envvars_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("ENVVARS " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
foreach ($n in 'JU_WORKSPACE', 'VCPKG_ROOT', 'JU_TOMCAT_HOME', 'JAVA_HOME', 'MAVEN_HOME') {
    $u = [Environment]::GetEnvironmentVariable($n, 'User'); $m = [Environment]::GetEnvironmentVariable($n, 'Machine'); $pr = [Environment]::GetEnvironmentVariable($n, 'Process')
    Log ("  {0,-15} User=[{1}] Machine=[{2}] Process=[{3}]" -f $n, $u, $m, $pr)
}
$vc = 'C:\MyData\MyTool\vcpkg-master\vcpkg.exe'
Log ("  vcpkg-master\vcpkg.exe: " + (Test-Path $vc) + " / " + ((cmd /c "`"$vc`" version 2>&1") | Select-Object -First 1))
Log ("  where vcpkg: " + ((cmd /c 'where vcpkg 2>&1') -join ' | '))
Log ("  cmake: " + ((cmd /c 'cmake --version 2>&1') | Select-Object -First 1) + " / where: " + ((cmd /c 'where cmake 2>&1') -join ' | '))
$vsw = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsw) { foreach ($l in (& $vsw -all -format value -property installationVersion)) { Log ("  VS installationVersion: " + $l) }; foreach ($l in (& $vsw -all -format value -property displayName)) { Log ("  VS: " + $l) } }
Log 'ENVVARS-DONE'

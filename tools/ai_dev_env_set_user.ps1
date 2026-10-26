# 개발자 User 환경변수 설정 (DEV_ENVIRONMENT_STANDARD.md 기준)
#
# 기본은 미리보기(Dry run): 현재 값과 충돌 여부만 보여 주고 아무것도 바꾸지 않는다.
# -Apply를 붙이면 "비어 있는 User 변수"만 설정한다. Machine에 같은 값이 이미 있으면(OK-MACHINE) User에 중복으로 만들지 않는다. 이미 다른 값이 있으면 바꾸지 않고 CONFLICT로 보고한다.
# Machine 변수와 PATH는 바꾸지 않는다. Jenkins(LocalSystem)는 User 변수를 보지 않으므로 영향이 없다.
#
#   powershell -ExecutionPolicy Bypass -File C:\MyData\MyDev\workspace\ai_dev_env_set_user.ps1
#   powershell -ExecutionPolicy Bypass -File C:\MyData\MyDev\workspace\ai_dev_env_set_user.ps1 -Apply
#
# 다른 PC(PC-B)에서는 실제 설치 위치가 다르면 아래 값을 그 PC 경로로 바꿔서 실행한다.

param([switch]$Apply)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Wanted = [ordered]@{
    'JU_WORKSPACE'   = 'C:\MyData\MyDev\workspace'
    'JAVA_HOME'      = 'C:\MyData\MyDev\jdk\jdk-21.0.1'
    'MAVEN_HOME'     = 'C:\MyData\MyDev\maven\apache-maven-3.9.11'
    'VCPKG_ROOT'     = 'C:\MyData\MyTool\vcpkg'
    'JU_TOMCAT_HOME' = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
}

Write-Host ("모드: {0}" -f $(if ($Apply) { '적용 (비어 있는 User 변수만)' } else { '미리보기 - 변경 없음' }))
Write-Host ''

foreach ($name in $Wanted.Keys) {
    $want = $Wanted[$name]
    $user = [Environment]::GetEnvironmentVariable($name, 'User')
    $machine = [Environment]::GetEnvironmentVariable($name, 'Machine')
    $exists = Test-Path $want

    $state =
        if (-not $exists) { 'PATH-MISSING' }
        elseif ($user -and ($user.TrimEnd('\') -ieq $want.TrimEnd('\'))) { 'OK' }
        elseif ($user) { 'CONFLICT' }
        elseif ($machine -and ($machine.TrimEnd('\') -ieq $want.TrimEnd('\'))) { 'OK-MACHINE' }
        else { 'TO-SET' }

    $note = ''
    if ($machine) {
        $note = if ($machine.TrimEnd('\') -ieq $want.TrimEnd('\')) { 'Machine 값 동일' } else { "Machine 값 다름: $machine (User가 우선)" }
    }

    Write-Host ("{0,-15} {1,-12} 기준={2}" -f $name, $state, $want)
    if ($user -and $state -ne 'OK') { Write-Host ("                현재 User={0}" -f $user) }
    if ($note) { Write-Host ("                {0}" -f $note) }

    if ($Apply -and $state -eq 'TO-SET') {
        [Environment]::SetEnvironmentVariable($name, $want, 'User')
        Write-Host '                → User 변수 설정함'
    }
}

Write-Host ''
Write-Host 'PATH는 바꾸지 않았다. java/mvn이 PATH에서 JAVA_HOME/MAVEN_HOME과 다른 위치를 먼저 찾는지는 ai_dev_env_check.ps1의 PATH 항목으로 확인한다.'
if ($Apply) { Write-Host '새로 연 터미널/VS/VS Code부터 적용된다.' }

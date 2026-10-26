# ENV-0: feature/env-0 branch 생성 + 상태 기록 + 환경검사 + 로컬 빌드
# commit/push, stash 변경, DB 변경, 배포를 하지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_env0_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) {
    Log ("> [" + $dir + "] " + $cmd)
    Push-Location $dir
    cmd /c "$cmd 2>&1" | ForEach-Object { Log ('  ' + $_) }
    Log ("  (exit " + $LASTEXITCODE + ")")
    Pop-Location
}
Log ("ENV-0 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)
foreach ($r in 'juprovider','juproject') {
    $p = Join-Path $ws $r
    Log ''; Log ("===== " + $r + " =====")
    Run $p 'git config --get core.autocrlf'
    Run $p 'git rev-parse --abbrev-ref HEAD'
    $exists = (& git -C $p branch --list feature/env-0)
    if ($exists) { Run $p 'git checkout feature/env-0' } else { Run $p 'git checkout -b feature/env-0' }
    Run $p 'git rev-parse --abbrev-ref HEAD'
    Run $p 'git log -1 --oneline'
    Run $p 'git status --short'
    Run $p 'git diff --stat'
    Run $p 'git stash list'
    Run $p 'git log origin/main -1 --oneline'
    Run $p 'dotnet --version'
}
Run $ws 'dotnet --list-sdks'
Log ''; Log '===== 환경검사 (ai_dev_env_check.ps1) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_dev_env_check.ps1') *>&1 | Out-Null
Log ("  결과: ai_dev_env_check_" + $env:COMPUTERNAME + ".log")
Log ''; Log '===== 로컬 빌드 (ai_local_build.ps1) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
Log ("  결과: ai_local_build_" + $env:COMPUTERNAME + ".log")
foreach ($r in 'juprovider','juproject') { Run (Join-Path $ws $r) 'git status --short' }
Log 'ENV0-DONE'

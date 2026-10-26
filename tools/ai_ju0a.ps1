# ENV-0 로컬 commit + main 로컬 fast-forward, JU-0A 브랜치 생성·파일 적용·로컬 빌드
# push 하지 않는다. DB 변경 없음. stash 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_ju0a_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) {
    Log ("> [" + (Split-Path $dir -Leaf) + "] " + $cmd)
    Push-Location $dir; cmd /c "$cmd 2>&1" | ForEach-Object { Log ('  ' + $_) }; $c = $LASTEXITCODE; Log ("  (exit $c)"); Pop-Location; return $c
}
$msgFile = Join-Path $ws 'ai_changes\ju0a\env0_commit_msg.txt'
Log ("JU-0A " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
foreach ($r in 'juprovider','juproject') {
    $p = Join-Path $ws $r
    Log ''; Log "===== ENV-0 commit: $r ====="
    $b = (& git -C $p rev-parse --abbrev-ref HEAD)
    if ($b -ne 'feature/env-0') { Log "중단: 현재 브랜치 $b (feature/env-0 아님)"; exit 1 }
    Run $p 'git add -A' | Out-Null
    Run $p "git commit -F `"$msgFile`"" | Out-Null
    Run $p 'git checkout main' | Out-Null
    if ((Run $p 'git merge --ff-only feature/env-0') -ne 0) { Log '중단: ff-only merge 실패'; exit 1 }
    Run $p 'git log --oneline -2' | Out-Null
    Run $p 'git status --short' | Out-Null
}
$jp = Join-Path $ws 'juprovider'
Log ''; Log '===== JU-0A 브랜치 + 파일 ====='
Run $jp 'git checkout -b feature/ju-0a' | Out-Null
$src = Join-Path $ws 'ai_changes\ju0a\database'
Copy-Item -Path (Join-Path $src '*') -Destination (Join-Path $jp 'database') -Recurse -Force
Run $jp 'git status --short' | Out-Null
Run $jp 'git diff --stat' | Out-Null
Log ''; Log '===== 로컬 빌드 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
Log ("  결과: ai_local_build_" + $env:COMPUTERNAME + ".log")
foreach ($r in 'juprovider','juproject') { Run (Join-Path $ws $r) 'git status --short --branch' | Out-Null }
Log 'JU0A-DONE'

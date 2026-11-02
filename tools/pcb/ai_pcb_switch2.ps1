# PC-B 전환 2단계: autocrlf=true, 로컬 변경 백업 브랜치·패치 보존, origin feature 브랜치 복원, PC-A 기준 브랜치 체크아웃, 빌드 5종·테스트, C5a 실서버 회귀(테스트 DB).
# push·main 병합·배포·실제 DB 변경 없음. 삭제 없음. 비밀 값 출력 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$bk = 'C:\MyData\MyDev\backup\pcb_20261102'
$log = Join-Path $ws ("ai_pcb_switch2_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
New-Item -ItemType Directory -Force -Path $bk | Out-Null
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'SWITCH2-STOPPED'; exit 1 }
$env:GIT_TERMINAL_PROMPT = '0'
Log ("PC-B SWITCH 2 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)

Log ''; Log '===== 1. git core.autocrlf ====='
Log ("  전: " + ((cmd /c 'git config --global core.autocrlf 2>&1') -join ''))
Run $ws 'git config --global core.autocrlf true' | Out-Null
Log ("  후: " + ((cmd /c 'git config --global core.autocrlf 2>&1') -join ''))

$plan = [ordered]@{
    'juprovider' = @{ target = 'feature/collect-c5'; expect = '854da5c' }
    'juproject'  = @{ target = 'feature/user-role-filter'; expect = 'f0d5467' }
}
foreach ($name in $plan.Keys) {
    $p = Join-Path $ws $name
    Log ''; Log ("===== 2. $name 보존 · 복원 =====")
    Run $p 'git fetch origin --prune' | Out-Null
    $cur = (& git -C $p rev-parse --abbrev-ref HEAD); $head = (& git -C $p rev-parse --short HEAD)
    $dirty = @(& git -C $p status --porcelain)
    Log ("  현재 $cur @ $head, 로컬 변경 " + $dirty.Count)
    if ($dirty.Count -gt 0) {
        $tag = ($cur -replace '[\\/]', '-')
        $patch = Join-Path $bk "$name`_$tag`_tracked.patch"
        cmd /c "git -C `"$p`" diff --binary HEAD > `"$patch`""
        $list = Join-Path $bk "$name`_$tag`_status.txt"
        [IO.File]::WriteAllLines($list, $dirty, $enc)
        $zip = Join-Path $bk "$name`_$tag`_untracked.zip"
        $un = @(& git -C $p ls-files --others --exclude-standard)
        if ($un.Count -gt 0) { Push-Location $p; Compress-Archive -Path $un -DestinationPath $zip -Force; Pop-Location }
        Log ("  백업 파일: " + (Split-Path $patch -Leaf) + " (" + (Get-Item $patch).Length + " B), status 목록, untracked " + $un.Count + "개 zip")
        $bb = "backup/pcb-20261102-$tag"
        if ((Run $p "git checkout -q -b $bb") -ne 0) { Stop "$name 백업 브랜치 생성 실패" }
        Run $p 'git add -A' | Out-Null
        if ((Run $p "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -q -m `"backup: PC-B uncommitted work on $cur (2026-11-02, local only)`"") -ne 0) { Stop "$name 백업 커밋 실패" }
        Log ("  백업 브랜치 $bb @ " + (& git -C $p rev-parse --short HEAD) + " (원래 $cur @ $head 위)")
    }
    if (@(& git -C $p status --porcelain).Count -ne 0) { Stop "$name 작업 폴더가 깨끗하지 않음" }
    # origin 의 모든 브랜치를 로컬 추적 브랜치로 (없는 것만 생성, 있는 것은 fast-forward 만)
    $wt = @(& git -C $p worktree list --porcelain | Where-Object { $_ -match '^branch ' } | ForEach-Object { $_ -replace '^branch refs/heads/', '' })
    foreach ($rb in @(& git -C $p for-each-ref --format='%(refname:short)' refs/remotes/origin)) {
        if ($rb -eq 'origin/HEAD' -or $rb -eq 'origin') { continue }
        $lb = $rb.Substring(7)
        $has = @(& git -C $p branch --list $lb).Count -gt 0
        if (-not $has) { Run $p "git branch --track $lb $rb" | Out-Null; continue }
        $l = (& git -C $p rev-parse $lb); $r = (& git -C $p rev-parse $rb)
        if ($l -eq $r) { Log "  $lb = $rb"; continue }
        cmd /c "git -C `"$p`" merge-base --is-ancestor $lb $rb"
        if ($LASTEXITCODE -ne 0) { Log "  $lb : origin 과 갈라짐 → 그대로 둠(보고)"; continue }
        if ($wt -contains $lb) { Log "  $lb : 다른 worktree 에 체크아웃 → 그대로 둠(보고, origin 보다 뒤)"; continue }
        Run $p "git branch -f $lb $rb" | Out-Null
        Run $p "git branch --set-upstream-to=$rb $lb" | Out-Null
    }
    $t = $plan[$name].target
    if ((Run $p "git checkout -q $t") -ne 0) { Stop "$name $t 체크아웃 실패" }
    $h = (& git -C $p rev-parse --short HEAD)
    Log ("  체크아웃 $t @ $h (PC-A 기준 " + $plan[$name].expect + ") " + $(if ($h -eq $plan[$name].expect) { 'OK' } else { 'DIFF' }))
    if ($h -ne $plan[$name].expect) { Stop "$name HEAD 불일치" }
    Run $p 'git branch -vv --no-color' | Out-Null
}

Log ''; Log '===== 3. C5a 상태 ====='
$jp = Join-Path $ws 'juprovider'
Log ("  feature/collect-c5 부모: " + (& git -C $jp log -1 --format='%p' feature/collect-c5) + " (기대 14d1ab9 66e9255)")
Log ("  integration-1 이후 C5 커밋: " + (& git -C $jp rev-list --count feature/integration-1..feature/collect-c5) + ", C5a 이후 추가 커밋: 0 기대 → origin 과 동일 " + ((& git -C $jp rev-parse feature/collect-c5) -eq (& git -C $jp rev-parse origin/feature/collect-c5)))
Log ("  migration: " + ((Get-ChildItem (Join-Path $jp 'database\migration') -Name) -join ', '))

Log ''; Log '===== 4. 빌드 5종 + 테스트 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
$bfail = 0
if ($si -lt 0) { Log '  빌드 요약 없음'; $bfail++ } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
    if (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -ne 0) { $bfail++ }
}
$bl | Select-String -Pattern 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$|통과!|실패!|Passed!|Failed!|\[ERROR\]|error CS|error NU|테스트 실행' | Select-Object -First 40 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }

Log ''; Log '===== 5. C5a 실서버 회귀 (테스트 DB 사본 + 06, 18081) ====='
if ($bfail -eq 0) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_c4srv.ps1') -Merge *>&1 | Out-Null
    $sl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_c5a_srv_{0}.log" -f $env:COMPUTERNAME)) -ErrorAction SilentlyContinue
    $ri = [Array]::IndexOf($sl, '===== 요약 =====')
    if ($ri -ge 0) { $sl[$ri..($sl.Length - 1)] | ForEach-Object { Log ('  ' + $_) } } else { $sl | Select-Object -Last 25 | ForEach-Object { Log ('  ' + $_) } }
} else { Log '  빌드 실패 → 생략' }

Log ''; Log '===== 6. 환경 재점검 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_dev_env_check.ps1') *>&1 | Out-Null
$el = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_dev_env_check_{0}.log" -f $env:COMPUTERNAME))
$el | Where-Object { $_ -match 'WARN|FAIL|합계' } | ForEach-Object { Log ('  ' + $_.Trim()) }
Log ("  COM 포트: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))
Log 'SWITCH2-DONE'

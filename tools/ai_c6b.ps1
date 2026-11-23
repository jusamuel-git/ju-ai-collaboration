# C6b Client 수집 설정 동기화: feature/c6b-client (기준 2fe4dca = C6a) 에 파일 반영 → 빌드 5종 + Desktop 테스트 + C6b 테스트 상세
# → 모두 PASS 면 commit + feature 브랜치 push (11/23 지시). main 병합·DB·WAR·서비스 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$src = Join-Path $ws 'ai_changes\c6b'
$log = Join-Path $ws ("ai_c6b_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { if ($x -notmatch 'LF will be replaced|original line endings') { Log ('  ' + $x) } }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'C6B-STOPPED'; exit 1 }
$lock = 'juprovider.frontvue/package-lock.json'
Log ("C6b " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 1. 브랜치 / 파일 ====='
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
$cur = (& git -C $jp rev-parse --abbrev-ref HEAD); $head = (& git -C $jp log -1 --format=%h)
Log "  현재 $cur @ $head"
if ($cur -ne 'feature/c6b-client' -or $head -ne '2fe4dca') { Stop "feature/c6b-client @ 2fe4dca 가 아님" }
$st = @(& git -C $jp status --porcelain --untracked-files=all | Where-Object { $p = $_.Substring(3).Trim('"'); ($p -ne $lock) -and ($files -notcontains $p) })
if ($st.Count) { Stop ('예상 밖 변경: ' + ($st -join ', ')) }
$now = Get-Date
foreach ($f in $files) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run 'git status --short' | Out-Null
Run 'git diff --stat' | Out-Null
foreach ($p in 'desktop/app/config/connections.json', 'desktop/app/cache/plans/plan_SDEV_GTEC01.json', 'desktop/app/config/client.json') {
    $ig = (& git -C $jp check-ignore $p); Log ("  git 제외 확인 $p → " + $(if ($ig) { '제외됨' } else { '!! 제외 안 됨' }))
    if (-not $ig) { Stop "$p 가 git 제외 경로가 아님" }
}

Log ''; Log '===== 2. 로컬 빌드 5종 + 테스트 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Stop '빌드 요약 없음' }
$sum = $bl[$si..($bl.Length - 1)]
$sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
$bl | Select-String -Pattern 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$|(통과|실패)!.*' | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$bl | Select-String -Pattern 'error CS|warning CS' | Select-Object -First 30 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$buildOk = (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0)

Log ''; Log '===== 3. C6a·C6b 테스트 상세 ====='
$tc = Run 'dotnet test desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug --no-build --filter "FullyQualifiedName~C6bClientTests|FullyQualifiedName~C6aTerminalTests" --logger "console;verbosity=normal"'
if (-not $buildOk -or $tc -ne 0) { Stop '빌드·테스트 FAIL → commit 하지 않음' }

Log ''; Log '===== 4. commit + push ====='
foreach ($f in $files) { if ((Run "git add -- `"$f`"") -ne 0) { Stop "add 실패 $f" } }
$msgFile = Join-Path $ws 'ai_c6b_commitmsg.txt'
[IO.File]::WriteAllText($msgFile, "feat(desktop): C6b client plan sync to terminal`n`n- DevicePlanSyncService: per device sync/protocols/{grp}, data-tags, data-map with client key -> DEVICE_PLAN_SYNC`n- Offline plan cache (app/cache/plans, server responses only, no secrets); server failure/401 -> cache`n- PC connections.json (app/config) -> ConnectionJson, overrides server DEV_CONFIG; virtual devices stay legacy unless listed`n- Client logs DEVICE_RUNTIME_STATE / ACTION_RESULT / DATA_VALUES (UI in C6c)`n- Tests: C6bClientTests incl. real ApiClient header check and named-pipe E2E to terminal`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01FuvmaMYDsqg8KmRxK7aHch`n", $enc)
if ((Run "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -q -F `"$msgFile`"") -ne 0) { Stop 'commit 실패' }
Remove-Item $msgFile -Force
$c6b = (& git -C $jp log -1 --format=%h)
Run 'git show --stat --format=%h%x20%s HEAD' | Out-Null
if ((Run 'git push -u origin feature/c6b-client') -ne 0) { Stop 'push 실패' }
Run 'git fetch -q origin' | Out-Null
$rh = (& git -C $jp rev-parse --short origin/feature/c6b-client)
Log "  C6b commit $c6b, origin/feature/c6b-client $rh, origin/main $(& git -C $jp rev-parse --short origin/main)"
if ($rh -ne $c6b) { Stop 'push 결과 불일치' }
Run 'git status --short' | Out-Null
Log 'C6B-DONE'

# C6a 확인 → 테스트 재실행 → commit → 원격 push → feature/c6b-client 생성 (11/23 사용자 지시).
# main 병합·DB·WAR·서비스 변경 없음. package-lock.json 은 커밋에서 제외.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_c6a_commit_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'C6A-COMMIT-STOPPED'; exit 1 }
$files = @(
 'desktop/juprovider.terminal/Program.cs',
 'desktop/juprovider.terminal/Runtime/DeviceRuntimeManager.cs',
 'desktop/juprovider.terminal/Runtime/CollectionIpcMapper.cs',
 'desktop/juprovider.terminal/Runtime/TerminalMessageRouter.cs',
 'desktop/lib/juprovider.lib.ipc/Messages/IpcMessageTypes.cs',
 'desktop/lib/juprovider.lib.ipc/Messages/CollectionIpcMessages.cs',
 'desktop/lib/juprovider.lib.protocol/Runtime/CollectionRuntime.cs',
 'desktop/tests/juprovider.tests.protocol/juprovider.tests.protocol.csproj',
 'desktop/tests/juprovider.tests.protocol/C6aTerminalTests.cs')
Log ("C6a commit " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 1. 브랜치·변경 확인 ====='
$cur = (& git -C $jp rev-parse --abbrev-ref HEAD); $head = (& git -C $jp log -1 --format=%h)
Log "  현재 $cur @ $head"
$st = @(& git -C $jp status --porcelain --untracked-files=all)
$st | ForEach-Object { Log ('  ' + $_) }
$extra = @($st | Where-Object { $p = $_.Substring(3).Trim('"'); ($p -ne 'juprovider.frontvue/package-lock.json') -and ($files -notcontains $p) })
if ($cur -eq 'feature/c6a-terminal' -and $head -eq '4915759') {
    if ($extra.Count) { Stop ('예상 밖 변경: ' + ($extra -join ', ')) }
    $missing = @($files | Where-Object { -not ($st | Where-Object { $_.Substring(3).Trim('"') -eq $_ }) })
    $missing = @($files | Where-Object { $f = $_; -not @($st | Where-Object { $_.Substring(3).Trim('"') -eq $f }).Count })
    if ($missing.Count) { Stop ('변경이 없는 파일: ' + ($missing -join ', ')) }
    $resume = $false
} elseif ($cur -eq 'feature/c6a-terminal') {
    Log '  이미 commit 됨 → push 단계부터'; $resume = $true
} else { Stop "feature/c6a-terminal 이 아님 ($cur)" }

if (-not $resume) {
    Log '===== 2. 빌드·테스트 재확인 ====='
    if ((Run 'dotnet build desktop\JuProvider.Desktop.slnx -c Debug -v q -nologo') -ne 0) { Stop 'Desktop 빌드 실패' }
    if ((Run 'dotnet test desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug --no-build') -ne 0) { Stop 'Desktop 테스트 실패' }

    Log '===== 3. commit ====='
    foreach ($f in $files) { if ((Run "git add -- `"$f`"") -ne 0) { Stop "add 실패 $f" } }
    $msgFile = Join-Path $ws 'ai_c6a_commitmsg.txt'
    [IO.File]::WriteAllText($msgFile, "feat(desktop): C6a terminal collection engine`n`n- CollectionRuntime: CollectionPlan + LinkSupervisor + DeviceSession (server-first plan, auto reconnect, STOP before close)`n- IPC: DEVICE_PLAN_SYNC, DEVICE_ACTION(_RESULT), DATA_VALUES, DEVICE_RUNTIME_STATE (no client key in IPC)`n- Terminal: DeviceRuntimeManager collection path, TerminalMessageRouter (serialized sends); legacy virtual devices unchanged`n- Tests: 8 C6a tests incl. virtual GTEC full cycle with reconnect and named-pipe E2E (Desktop 197/197)`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01FuvmaMYDsqg8KmRxK7aHch`n", $enc)
    if ((Run "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -q -F `"$msgFile`"") -ne 0) { Stop 'commit 실패' }
    Remove-Item $msgFile -Force
}
$c6a = (& git -C $jp log -1 --format=%h)
Log "  C6a commit $c6a"
Run 'git show --stat --format=%h%x20%s HEAD' | Out-Null

Log '===== 4. push ====='
if ((Run 'git push -u origin feature/c6a-terminal') -ne 0) { Stop 'push 실패' }
Run 'git fetch -q origin' | Out-Null
$rh = (& git -C $jp rev-parse --short origin/feature/c6a-terminal)
Log "  origin/feature/c6a-terminal $rh"
if ($rh -ne $c6a) { Stop 'push 결과 불일치' }

Log '===== 5. feature/c6b-client 생성 ====='
& git -C $jp rev-parse --verify -q feature/c6b-client | Out-Null
if ($LASTEXITCODE -eq 0) { Log '  이미 있음' } else { if ((Run 'git checkout -b feature/c6b-client') -ne 0) { Stop 'c6b 브랜치 생성 실패' } }
Log ("  현재 " + (& git -C $jp rev-parse --abbrev-ref HEAD) + " @ " + (& git -C $jp log -1 --format=%h) + ", main " + (& git -C $jp rev-parse --short origin/main))
Run 'git status --short' | Out-Null
Log 'C6A-COMMIT-DONE'

# C6c Desktop 장치 수집 화면 (11/23 승인): C6b 확인 → feature/c6c-desktop-ui 생성 → 파일 반영
# → 서버 SDEV_GTEC01 DEV_CONFIG 확인(Client Key, 읽기만) → PC-B connections.json(COM3, git 제외) → 빌드 5종 + 테스트
# → 모두 PASS 면 commit + feature 브랜치 push. main 병합·DB·WAR·Tomcat 서비스 변경 없음. 키는 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$src = Join-Path $ws 'ai_changes\c6c'
$app = Join-Path $jp 'desktop\app'
$tcHome = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$log = Join-Path $ws ("ai_c6c_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { if ($x -notmatch 'LF will be replaced|original line endings') { Log ('  ' + $x) } }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { $script:key = $null; Log ("중단: " + $why); Log 'C6C-STOPPED'; exit 1 }
function Git1([string]$a) { return @(cmd /c "git -C `"$jp`" $a 2>nul")[0] }
$lock = 'juprovider.frontvue/package-lock.json'
$branch = 'feature/c6c-desktop-ui'
$base = 'f915996'
Log ("C6c " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 1. C6b 상태 ====='
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
cmd /c "git -C `"$jp`" fetch -q origin 2>&1" | Out-Null
$cur = Git1 'rev-parse --abbrev-ref HEAD'; $head = Git1 'log -1 --format=%h'
$rb = Git1 'rev-parse --short origin/feature/c6b-client'
Log "  현재 $cur @ $head, origin/feature/c6b-client $rb, origin/main $(Git1 'rev-parse --short origin/main')"
Run 'git log -3 --format="%h %s"' | Out-Null
if ($rb -ne $base) { Stop "origin/feature/c6b-client 가 $base 아님" }
if (-not (($cur -eq 'feature/c6b-client' -or $cur -eq $branch) -and $head -eq $base)) { Stop "feature/c6b-client(또는 $branch) @ $base 가 아님" }
$st = @(& git -C $jp status --porcelain --untracked-files=all | Where-Object { $p = $_.Substring(3).Trim('"'); ($p -ne $lock) -and ($files -notcontains $p) })
if ($st.Count) { Stop ('예상 밖 변경: ' + ($st -join ', ')) }

Log ''; Log '===== 2. C6c 브랜치 ====='
if ($cur -ne $branch) {
    if (Git1 "rev-parse --verify --quiet refs/heads/$branch") { Stop "$branch 가 이미 있음 (다른 위치)" }
    if ((Run "git switch -c $branch") -ne 0) { Stop '브랜치 생성 실패' }
}
Log "  $(Git1 'rev-parse --abbrev-ref HEAD') @ $(Git1 'log -1 --format=%h')"
$now = Get-Date
foreach ($f in $files) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run 'git status --short' | Out-Null
Run 'git diff --stat' | Out-Null

Log ''; Log '===== 3. 서버 SDEV_GTEC01 DEV_CONFIG (Client Key 로 sync/devices 읽기만) ====='
$cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $app 'config\client.json') | ConvertFrom-Json
$server = ([string]$cfg.ServerUrl).TrimEnd('/')
Log ("  client.json ServerUrl=$server ClientId=" + $cfg.ClientId + " 키 " + $(if ($cfg.ClientKey) { '있음' } else { '없음' }))
function Health { try { return [int](Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 ($server + '/api/health')).StatusCode } catch { return -1 } }
$h = Health
if ($h -ne 200) {
    $cat = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' })
    Log ("  health 응답 없음 (catalina 프로세스 " + $cat.Count + ") → 배포된 WAR 그대로 Tomcat 기동 (배포·서비스 변경 없음)")
    if ($cat.Count -eq 0) {
        $env:CATALINA_HOME = $tcHome; Start-Process cmd.exe -ArgumentList '/c', "`"$tcHome\bin\startup.bat`"" -WindowStyle Hidden; $env:CATALINA_HOME = $null
        for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 3; $h = Health; if ($h -eq 200) { break } }
    }
}
Log "  health HTTP $h"
$serverCfg = $null
if ($h -eq 200) {
    $script:key = [string]$cfg.ClientKey
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 ($server + '/api/core/sync/devices') -Headers @{ 'X-JU-Client-Id' = [string]$cfg.ClientId; 'X-JU-Client-Key' = $script:key }
        $devs = @([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json)
        Log ("  sync/devices HTTP " + [int]$r.StatusCode + ", 장치 " + $devs.Count + ": " + (($devs | ForEach-Object { $_.devCd }) -join ','))
        $g = $devs | Where-Object { $_.devCd -eq 'SDEV_GTEC01' } | Select-Object -First 1
        if ($g) {
            Log ("  SDEV_GTEC01 devType=" + $g.devType + " devComm=" + $g.devComm + " ptlGrpCd=" + $g.ptlGrpCd + " useYn=" + $g.useYn + " devCh=" + $g.devCh)
            Log ("  SDEV_GTEC01 DEV_CONFIG = " + $(if ($g.devConfig) { [string]$g.devConfig } else { '(없음)' }))
            $serverCfg = $g.devConfig
        } else { Log '  SDEV_GTEC01 없음' }
    } catch { Log ("  sync/devices 실패: " + $_.Exception.Message) }
    $script:key = $null
} else { Log '  서버 응답 없음 → DEV_CONFIG 미확인' }

Log ''; Log '===== 4. PC-B connections.json (COM3, git 제외) ====='
Log ("  포트 목록: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))
$conn = Join-Path $app 'config\connections.json'
if (Test-Path $conn) { Log '  기존 파일 있음 (그대로 둠)' }
else {
    [IO.File]::WriteAllText($conn, "{`r`n  `"SDEV_GTEC01`": { `"transport`": `"SERIAL`", `"portName`": `"COM3`", `"baudRate`": 115200 }`r`n}`r`n", $enc)
    Log '  새로 만듦'
}
Get-Content -Encoding UTF8 $conn | ForEach-Object { Log ('    ' + $_) }
try { $lc = (Get-Content -Raw -Encoding UTF8 $conn | ConvertFrom-Json).SDEV_GTEC01 } catch { $lc = $null; Log '  !! JSON 형식 오류' }
$sp = $null; try { if ($serverCfg) { $sp = ([string]$serverCfg | ConvertFrom-Json).portName } } catch {}
Log ("  우선순위: 로컬 portName=" + $lc.portName + " / 서버 DEV_CONFIG portName=" + $(if ($sp) { $sp } else { '-' }) + " → 연결 시 로컬 사용 (앱 화면·로그 ConnectionSource=local 로 확인)")
foreach ($p in 'desktop/app/config/connections.json', 'desktop/app/cache/plans/plan_SDEV_GTEC01.json', 'desktop/app/config/client.json') {
    $ig = (& git -C $jp check-ignore $p); Log ("  git 제외 확인 $p → " + $(if ($ig) { '제외됨' } else { '!! 제외 안 됨' }))
    if (-not $ig) { Stop "$p 가 git 제외 경로가 아님" }
}

Log ''; Log '===== 5. 로컬 빌드 5종 + 테스트 ====='
$running = @(Get-Process -Name 'juprovider.client', 'juprovider.terminal' -ErrorAction SilentlyContinue)
if ($running.Count) { Stop ('Desktop 앱 실행 중 (빌드 파일 잠김): ' + (($running | ForEach-Object { $_.ProcessName }) -join ', ') + ' → 닫고 다시 실행') }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Stop '빌드 요약 없음' }
$sum = $bl[$si..($bl.Length - 1)]
$sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
$bl | Select-String -Pattern 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$|(통과|실패)!.*' | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$bl | Select-String -Pattern 'error CS|warning CS|\[실패\]|\[FAIL\]|Assert\.' | Select-Object -First 40 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$buildOk = (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0)

Log ''; Log '===== 6. C6a·C6b·C6c 테스트 상세 ====='
$tr = Run 'dotnet test desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug --no-build --filter "FullyQualifiedName~C6cClientTests|FullyQualifiedName~C6bClientTests|FullyQualifiedName~C6aTerminalTests" --logger "console;verbosity=normal"'
if (-not $buildOk -or $tr -ne 0) { Stop '빌드·테스트 FAIL → commit 하지 않음' }
foreach ($e in 'juprovider.client.exe', 'juprovider.terminal.exe') { Log ("  앱 $e " + $(if (Test-Path (Join-Path $app $e)) { (Get-Item (Join-Path $app $e)).LastWriteTime.ToString('MM-dd HH:mm:ss') } else { '!! 없음' })) }

Log ''; Log '===== 7. commit + push ====='
foreach ($f in $files) { if ((Run "git add -- `"$f`"") -ne 0) { Stop "add 실패 $f" } }
$msgFile = Join-Path $ws 'ai_c6c_commitmsg.txt'
[IO.File]::WriteAllText($msgFile, "feat(desktop): C6c device collection screen in client`n`n- MainForm: device list, connect/disconnect, START/STOP, CH values with TAG_ID/quality/time, state, warnings, event log`n- CollectionMonitor: per-device view state from DEVICE_STATUS / RUNTIME_STATE / ACTION_RESULT / DATA_VALUES (TAG_ID from plan data-tags)`n- Program: route terminal messages to monitor, send UI commands, remove TEMP TEST VDEV_GTEC01 connect/disconnect`n- Tests: C6cClientTests (monitor unit, named-pipe E2E incl. link drop and recovery); fix CS8601 in C6bClientTests`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01FuvmaMYDsqg8KmRxK7aHch`n", $enc)
if ((Run "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -q -F `"$msgFile`"") -ne 0) { Stop 'commit 실패' }
Remove-Item $msgFile -Force
$c6c = Git1 'log -1 --format=%h'
Run 'git show --stat --format=%h%x20%s HEAD' | Out-Null
if ((Run "git push -u origin $branch") -ne 0) { Stop 'push 실패' }
Run 'git fetch -q origin' | Out-Null
$rh = Git1 "rev-parse --short origin/$branch"
Log "  C6c commit $c6c, origin/$branch $rh, origin/main $(Git1 'rev-parse --short origin/main')"
if ($rh -ne $c6c) { Stop 'push 결과 불일치' }
Run 'git status --short' | Out-Null
Log 'C6C-DONE'

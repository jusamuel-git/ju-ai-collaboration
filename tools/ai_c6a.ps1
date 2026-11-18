# C6a Terminal 수집 엔진: feature/c6a-terminal (기준 4915759 = main = c5d) 에 변경 파일 반영 → 빌드 5종 + Desktop 테스트 + C6a 테스트 상세.
# commit·push 없음 (사용자). DB·서버·서비스 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$src = Join-Path $ws 'ai_changes\c6a'
$log = Join-Path $ws ("ai_c6a_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'C6A-STOPPED'; exit 1 }
$lock = 'juprovider.frontvue/package-lock.json'
Log ("C6a " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
$cur = (& git -C $jp rev-parse --abbrev-ref HEAD); $head = (& git -C $jp log -1 --format=%h)
Log "  현재 $cur @ $head"
if ($head -ne '4915759') { Stop "기준 커밋이 4915759 아님 ($head)" }
$resume = ($cur -eq 'feature/c6a-terminal')
$st = @(& git -C $jp status --porcelain | Where-Object { $l = $_; ($l -notmatch [regex]::Escape($lock)) -and -not ($resume -and @($files | Where-Object { $l.EndsWith($_) -or $l.Contains('Runtime/') }).Count) })
& git -C $jp status --porcelain | ForEach-Object { Log ('  ' + $_) }
if ($st.Count -ne 0) { Stop '작업 폴더 변경 있음' }
if (-not $resume) {
    & git -C $jp rev-parse --verify -q feature/c6a-terminal | Out-Null
    if ($LASTEXITCODE -eq 0) { Stop 'feature/c6a-terminal 이미 있음' }
    if ((Run $jp 'git checkout -b feature/c6a-terminal') -ne 0) { Stop 'checkout 실패' }
} else { Log '  feature/c6a-terminal (commit 없음) 이어서 진행' }
$now = Get-Date
foreach ($f in $files) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null
Run $jp 'git diff --stat' | Out-Null
$client = @(& git -C $jp status --porcelain -- desktop/juprovider.client desktop/lib/juprovider.lib.data)
Log ("  Client·lib.data 변경 " + $client.Count + "건 (0 이어야 함: 로그인 경로 무변경)")

Log ''; Log '===== 2. 로컬 빌드 5종 + 테스트 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -ge 0) { $bl[$si..($bl.Length - 1)] | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) } } else { Log '  요약 없음' }
$bl | Select-String -Pattern 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$|(통과|실패)!.*|Passed!.*|Failed!.*' | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$bl | Select-String -Pattern ' error |error CS|warning CS.*(C6a|Collection|Router|Runtime)' | Select-Object -First 30 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }

Log ''; Log '===== 3. C6a 테스트 상세 ====='
$tp = Get-ChildItem (Join-Path $jp 'desktop\tests') -Recurse -Filter 'juprovider.tests.protocol.csproj' | Select-Object -First 1
Run $jp ("dotnet test `"" + $tp.FullName + "`" -c Debug --no-build --filter `"FullyQualifiedName~C6aTerminalTests`" --logger `"console;verbosity=normal`"") | Out-Null

Log ''; Log '===== 4. 최종 상태 ====='
Run $jp 'git status --short' | Out-Null
Log ("  HEAD " + (& git -C $jp log -1 --format=%h) + " (commit 없음)")
Log 'C6A-DONE'

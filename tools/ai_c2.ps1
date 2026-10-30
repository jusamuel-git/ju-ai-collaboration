# C2: feature/collect-c2 (← feature/collect-c1 5723b03), Transport·시뮬레이터·재연결 + 테스트.
# 빌드 5종 + desktop 테스트. PASS면 로컬 commit. push 없음. 서버·DB 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c2'
$log = Join-Path $ws ("ai_c2_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'C2-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("C2 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -ne 'feature/collect-c2') {
    if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop "현재 브랜치 $b 에 미커밋 변경 있음" }
    if ((& git -C $jp rev-parse --short feature/collect-c1) -ne '5723b03') { Stop 'feature/collect-c1이 5723b03 아님' }
    if ((Run $jp 'git checkout -b feature/collect-c2 feature/collect-c1') -ne 0) { Stop 'checkout 실패' }
}
if ((& git -C $jp log -1 --format=%h) -ne '5723b03') { Stop 'feature/collect-c2 HEAD가 5723b03 아님 (이미 commit?)' }
foreach ($f in Get-Content (Join-Path $src 'deletelist.txt')) { if ($f -and (Test-Path (Join-Path $jp $f))) { Run $jp "git rm -q $f" | Out-Null } }
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    if (-not $f) { continue }
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null

Log ''; Log '===== 2. 로컬 빌드 5종 + desktop 테스트 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
$fail = 0
if ($si -lt 0) { Log '  빌드 요약 없음'; $fail++ } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | ForEach-Object { Log ('  ' + $_) }
    if (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -ne 0) { $fail++ }
    if (@($sum | Select-String 'desktop test').Count -eq 0) { Log '  desktop test 단계 없음'; $fail++ }
}
$bl | Select-String -Pattern 'Tests run: \d+, Failures|Passed!|Failed!|통과|실패!|error CS|warning CS|\[FAIL\]' | Select-Object -First 60 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }

Log ''; Log '===== 3. 변경 범위 확인 ====='
Run $jp 'git add -A desktop' | Out-Null
$names = @(& git -C $jp diff --cached --name-only)
$outside = @($names | Where-Object { $_ -notmatch '^desktop/(lib/juprovider\.lib\.protocol/|tests/juprovider\.tests\.protocol/|JuProvider\.Desktop\.slnx$)' })
$other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AMD]  ' })
Log ("  staged " + $names.Count + ", 범위 밖 " + $outside.Count + ", 기타 " + $other.Count)
$outside | ForEach-Object { Log ('  범위 밖: ' + $_) }; $other | ForEach-Object { Log ('  기타: ' + $_) }
if ($names.Count -ne 16 -or $outside.Count -ne 0 -or $other.Count -ne 0) { $fail++ }

Log ''; Log '===== 4. 로컬 commit (push 없음) ====='
if ($fail -gt 0) { Run $jp 'git reset -q' | Out-Null; Stop "FAIL $fail → commit 하지 않음 (변경은 작업 폴더에 유지)" }
if ((Run $jp "git commit -F `"$src\commit_c2.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -2' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
Log 'C2-DONE'

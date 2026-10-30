# C4b: feature/collect-c4 (d3a560a) 위에 405 처리 별도 commit. 빌드 5종 + 실서버(테스트 DB) 회귀 → PASS면 로컬 commit. push 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c4b'
$log = Join-Path $ws ("ai_c4b_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'C4B-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("C4b " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/collect-c4') { Stop 'feature/collect-c4 아님' }
if ((& git -C $jp log -1 --format=%h) -ne 'd3a560a') { Stop 'HEAD가 d3a560a 아님 (이미 commit?)' }
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    if (-not $f) { continue }
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null

Log ''; Log '===== 2. 로컬 빌드 5종 + 테스트 ====='
$fail = 0
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Log '  빌드 요약 없음'; $fail++ } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
    if (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -ne 0) { $fail++ }
}
$bl | Select-String -Pattern 'Tests run: \d+, Failures|통과!|실패!|\[ERROR\]|error CS' | Select-Object -First 30 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
if ($fail -gt 0) { Run $jp 'git status --short' | Out-Null; Stop '빌드 실패 (변경은 작업 폴더에 유지)' }

Log ''; Log '===== 3. 실서버 회귀 (테스트 DB, ai_c4srv.ps1 -Fix) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_c4srv.ps1') -Fix *>&1 | Out-Null
$sl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_c4b_srv_{0}.log" -f $env:COMPUTERNAME))
$ri = [Array]::IndexOf($sl, '===== 요약 =====')
if ($ri -ge 0) { $sl[$ri..($sl.Length - 1)] | ForEach-Object { Log ('  ' + $_) } } else { Log '  서버 요약 없음'; $fail++ }
if (-not ($sl -contains 'FAIL 0')) { $fail++ }

Log ''; Log '===== 4. 변경 범위 ====='
Run $jp 'git add -A juprovider.backend' | Out-Null
$names = @(& git -C $jp diff --cached --name-only)
$other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' })
Log ("  staged " + $names.Count + ", 기타 " + $other.Count); $names | ForEach-Object { Log ('  ' + $_) }
if ($names.Count -ne 2 -or $other.Count -ne 0) { $fail++ }

Log ''; Log '===== 5. 로컬 commit (push 없음) ====='
if ($fail -gt 0) { Run $jp 'git reset -q' | Out-Null; Stop "FAIL $fail → commit 하지 않음" }
if ((Run $jp "git commit -F `"$src\commit_c4b.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
Log 'C4B-DONE'

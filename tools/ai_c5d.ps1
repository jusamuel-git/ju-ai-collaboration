# C5d: feature/collect-c5c(6e744be) → feature/collect-c5d. Desktop 서버 설정 우선·data-map 매핑 → 빌드 5종 + 테스트(가상 GTEC 포함) → 실서버 회귀(-C5d, 서버값 계획)
#      → 모두 PASS 면 로컬 commit + patch. 실장비 회귀는 run_ai_c5d_probe.cmd (COM3 연결 후 따로). push·실제 DB 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5d'
$log = Join-Path $ws ("ai_c5d_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$script:fail = 0; $script:rows = @()
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) {
    $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }
    $script:rows += ("| {0} | {1} | {2} | {3} |" -f $id, $name, $note, $r); Log ("  [$r] $id $name $note")
}
function Stop([string]$why) { Log ("중단: " + $why); Log 'C5D-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
$lock = 'juprovider.frontvue/package-lock.json'  # 빌드(npm)가 고치는 파일: 건드리지 않고 commit 에서 제외
Log ("C5d " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 브랜치 / 파일 ====='
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
$cur = (& git -C $jp rev-parse --abbrev-ref HEAD); $head = (& git -C $jp log -1 --format=%h)
Log "  현재 $cur @ $head"
$c5c = (& git -C $jp rev-parse --short feature/collect-c5c); Log "  feature/collect-c5c $c5c"
if ($c5c -ne '6e744be') { Stop 'feature/collect-c5c 가 6e744be 아님' }
$resume = ($cur -eq 'feature/collect-c5d') -and ($head -eq '6e744be')
if ($resume) { Run $jp 'git reset -q' | Out-Null }
$st = @(& git -C $jp status --porcelain | Where-Object { $l = $_; ($l -notmatch [regex]::Escape($lock)) -and -not ($resume -and @($files | Where-Object { $l.EndsWith($_) -or $l.EndsWith(($_ -replace '[^/]+$', '')) }).Count -gt 0) })
& git -C $jp status --porcelain | ForEach-Object { Log ('  ' + $_) }
if ($st.Count -ne 0) { Stop '작업 폴더 변경 있음' }
if (-not $resume) {
    if ($cur -ne 'feature/collect-c5c' -or $head -ne '6e744be') { Stop 'feature/collect-c5c @ 6e744be 에서 시작해야 함' }
    & git -C $jp rev-parse --verify -q feature/collect-c5d | Out-Null
    if ($LASTEXITCODE -eq 0) { Stop 'feature/collect-c5d 이미 있음' }
    if ((Run $jp 'git checkout -b feature/collect-c5d') -ne 0) { Stop 'checkout 실패' }
} else { Log '  feature/collect-c5d (commit 없음) 이어서 진행' }
$now = Get-Date
foreach ($f in $files) {
    $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jp 'git status --short' | Out-Null
Run $jp 'git diff --stat' | Out-Null

Log ''; Log '===== 2. 로컬 빌드 5종 + 테스트 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$blf = Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME)
$bl = Get-Content -Encoding UTF8 $blf
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Check 'G-1' '빌드 5종' $false '요약 없음' } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
    Check 'G-1' '빌드 5종 + 테스트' (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
}
$bl | Select-String -Pattern 'Tests run: \d+, Failures|통과!|실패!|\[ERROR\]|error CS|FAILED|Assert' | Select-Object -First 60 | ForEach-Object { Log ('  ' + $_.Line.Trim().Substring(0, [Math]::Min(300, $_.Line.Trim().Length))) }
$t34 = @($bl | Select-String -Pattern 'Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: \d+$' | Select-Object -Last 1)
if ($t34.Count -gt 0) { Log ("  서버 테스트 합계: " + $t34[0].Line.Trim()) }
if ($script:fail -gt 0) { Stop '빌드·테스트 FAIL → 실서버 검증 생략 (변경은 작업 폴더에 유지)' }

Log ''; Log '===== 3. 실서버 회귀 + C5c API + 서버값 계획 (테스트 DB + 06 + 08, ai_c4srv.ps1 -C5d) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_c4srv.ps1') -C5d *>&1 | Out-Null
$sl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_c5d_srv_{0}.log" -f $env:COMPUTERNAME))
$sl | Where-Object { $_ -match '적용\(테스트 DB\)|서버 기동|ERROR/Exception|서버 응답 저장|\[(PASS|FAIL)\] |계획 경고' } | ForEach-Object { Log ('  ' + $_.Trim()) }
$ri = [Array]::IndexOf($sl, '===== 요약 =====')
if ($ri -ge 0) { $sl[$ri..($sl.Length - 1)] | ForEach-Object { Log ('  ' + $_) } }
Check 'G-2' '실서버 회귀 + C5c API + 서버값 계획(6-1 c5d)' (($ri -ge 0) -and ($sl -contains 'FAIL 0')) ''

Log ''; Log '===== 4. 변경 범위 · 로컬 commit (push 없음) ====='
foreach ($f in $files) { Run $jp ("git add -- `"$f`"") | Out-Null }
$names = @(& git -C $jp diff --cached --name-only)
$other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' -and $_ -notmatch [regex]::Escape($lock) })
Log ("  staged " + $names.Count + ", 기타 " + $other.Count); $other | ForEach-Object { Log ('  기타 ' + $_) }
Check 'G-3' ("변경 범위 = C5d " + $files.Count + "개 파일") (($names.Count -eq $files.Count) -and ($other.Count -eq 0)) ''
Log ''; Log '===== 요약 ====='
Log '| # | 항목 | 결과 요약 | 판정 |'
Log '|---|---|---|---|'
foreach ($x in $script:rows) { Log $x }
Log ("FAIL " + $script:fail)
if ($script:fail -gt 0) { Run $jp 'git reset -q' | Out-Null; Stop "FAIL $($script:fail) → commit 하지 않음 (변경은 작업 폴더에 유지)" }
# PC-B 에 git 사용자 설정이 없음 → 기존 commit 과 같은 작성자를 이 commit 에만 지정 (설정 변경 없음)
if ((Run $jp "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -F `"$src\commit_c5d.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
cmd /c "git -C `"$jp`" format-patch -1 --stdout > `"$src\c5d_result.patch`""
Log ("  patch " + (Get-Item "$src\c5d_result.patch").Length + " bytes")
Log 'C5D-DONE'

# C5a: feature/collect-c5 = feature/integration-1(14d1ab9) + merge feature/collect-c4(66e9255). 충돌 해결, 빌드 5종, 서버(테스트 DB+06)·Desktop 회귀 → PASS면 로컬 merge commit. push·DB 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5a'
$log = Join-Path $ws ("ai_c5a_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'C5A-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
function NormHash([string]$ref, [string]$path) {
    $tmp = Join-Path $src 'show.tmp'
    cmd /c "git -C `"$jp`" show ${ref}:$path > `"$tmp`" 2>nul"
    $b = [IO.File]::ReadAllBytes($tmp); Remove-Item $tmp -Force
    $t = (New-Object System.Text.UTF8Encoding($false)).GetString($b)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    $t = $t.Replace("`r`n", "`n")
    $h = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t))
    return (-join ($h | ForEach-Object { $_.ToString('x2') })).Substring(0, 16)
}
Log ("C5a " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log ''; Log '===== 1. 사전 확인 ====='
if (@(& git -C $jp status --porcelain).Count -ne 0) { Stop '작업 폴더 변경 있음' }
$i1 = (& git -C $jp rev-parse --short feature/integration-1); $c4 = (& git -C $jp rev-parse --short feature/collect-c4)
Log "  integration-1 $i1, collect-c4 $c4"
if ($i1 -ne '14d1ab9') { Stop 'feature/integration-1 이 14d1ab9 아님' }
if ($c4 -ne '66e9255') { Stop 'feature/collect-c4 가 66e9255 아님' }
$expect = @{
  'desktop/lib/juprovider.lib.data/Api/JuProviderApiClient.cs' = 'c11428988083eb7f'
  'juprovider.backend/src/main/java/com/asdp/juprovider/JuProviderApplication.java' = 'e4bab29637a2e18b'
  'juprovider.backend/src/main/java/com/asdp/juprovider/exception/GlobalExceptionHandler.java' = '68f8a9a4d63a18cc'
}
foreach ($k in $expect.Keys) { $h = NormHash 'feature/integration-1' $k; Log "  base $k $h"; if ($h -ne $expect[$k]) { Stop "integration-1 의 $k 가 해결안 기준과 다름" } }
$mb = (& git -C $jp merge-base feature/integration-1 feature/collect-c4); Log ("  merge-base " + (& git -C $jp log -1 --format='%h %s' $mb))

Log ''; Log '===== 2. 브랜치 · 병합 ====='
$exists = @(& git -C $jp branch --list feature/collect-c5).Count -gt 0
if ($exists) {
    if ((& git -C $jp rev-parse --short feature/collect-c5) -ne '14d1ab9') { Stop 'feature/collect-c5 가 이미 진행됨 (14d1ab9 아님)' }
    if ((Run $jp 'git checkout -q feature/collect-c5') -ne 0) { Stop 'checkout 실패' }
} else {
    if ((Run $jp 'git checkout -q -b feature/collect-c5 feature/integration-1') -ne 0) { Stop 'checkout 실패' }
}
Run $jp 'git merge --no-ff --no-commit feature/collect-c4' | Out-Null
$conf = @(& git -C $jp diff --name-only --diff-filter=U)
Log ("  충돌 " + $conf.Count + ": " + ($conf -join ', '))
$want = @('desktop/lib/juprovider.lib.data/Api/JuProviderApiClient.cs', 'juprovider.backend/src/main/java/com/asdp/juprovider/JuProviderApplication.java')
if (@(Compare-Object ($conf | Sort-Object) ($want | Sort-Object)).Count -ne 0) { Run $jp 'git merge --abort' | Out-Null; Stop '예상과 다른 충돌' }
$auto = @(& git -C $jp diff --cached --name-only | Where-Object { $conf -notcontains $_ })
Log ("  자동 병합 파일 " + $auto.Count)
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    if (-not $f) { continue }
    $to = Join-Path $jp $f.Replace('/', '\')
    Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force
    Run $jp "git add -- $f" | Out-Null
}
$left = @(& git -C $jp diff --name-only --diff-filter=U)
$markers = @(& git -C $jp grep -n -e '^<<<<<<< ' -e '^>>>>>>> ' -- desktop juprovider.core juprovider.backend)
Log ("  남은 충돌 " + $left.Count + ", 충돌 표시 " + $markers.Count)
if ($left.Count -ne 0 -or $markers.Count -ne 0) { Run $jp 'git merge --abort' | Out-Null; Stop '충돌 해결 실패' }
Run $jp 'git diff --cached --stat feature/integration-1' | Select-Object -Last 1 | Out-Null

Log ''; Log '===== 3. 빌드 5종 + 테스트 ====='
$fail = 0
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Log '  빌드 요약 없음'; $fail++ } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
    if (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -ne 0) { $fail++ }
}
$bl | Select-String -Pattern 'Tests run: \d+, Failures|통과!|실패!|\[ERROR\]|error CS' | Select-Object -First 40 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
if ($fail -gt 0) { Run $jp 'git merge --abort' | Out-Null; Stop '빌드 실패 → merge 취소' }

Log ''; Log '===== 4. 서버 회귀 (테스트 DB + 06, ai_c4srv.ps1 -Merge) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_c4srv.ps1') -Merge *>&1 | Out-Null
$sl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_c5a_srv_{0}.log" -f $env:COMPUTERNAME))
$ri = [Array]::IndexOf($sl, '===== 요약 =====')
if ($ri -ge 0) { $sl[$ri..($sl.Length - 1)] | ForEach-Object { Log ('  ' + $_) } } else { Log '  서버 요약 없음'; $sl | Select-Object -Last 15 | ForEach-Object { Log ('  ' + $_) }; $fail++ }
if (-not ($sl -contains 'FAIL 0')) { $fail++ }

Log ''; Log '===== 5. 로컬 merge commit (push 없음) ====='
$other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AMDR]  ' })
Log ("  미스테이징·추적 안 된 변경 " + $other.Count); $other | ForEach-Object { Log ('  ' + $_) }
if ($other.Count -ne 0) { $fail++ }
if ($fail -gt 0) { Run $jp 'git merge --abort' | Out-Null; Stop "FAIL $fail → merge 취소 (feature/collect-c5 = integration-1 그대로)" }
if ((Run $jp "git commit -F `"$src\merge_c5a.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline --graph -6' | Out-Null
Run $jp 'git diff --stat feature/integration-1 HEAD' | Out-Null
Log ("  collect-c4 대비 차이 파일: " + ((& git -C $jp diff --name-only feature/collect-c4 HEAD -- desktop juprovider.core juprovider.backend database | Measure-Object).Count))
Log 'C5A-DONE'

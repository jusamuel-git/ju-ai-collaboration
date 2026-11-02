# PC-A 포맷 전: juprovider 로컬 전용 feature 브랜치 9개를 origin 에 같은 이름으로 push (main 제외, force 없음).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$jp = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_handover_push_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$env:GIT_TERMINAL_PROMPT = '0'
Log ("HANDOVER PUSH " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$expect = [ordered]@{
  'feature/collect-c1' = '5723b03'; 'feature/collect-c2' = '332c229'; 'feature/collect-c3' = 'ad9fda3'
  'feature/collect-c4' = '66e9255'; 'feature/collect-c5' = '854da5c'; 'feature/integration-1' = '14d1ab9'
  'feature/protocol-ref' = '1d1c1ab'; 'feature/sec-s1' = '4187280'; 'feature/web-01' = '60bc008'
}
if (@(& git -C $jp status --porcelain).Count -ne 0) { Log '중단: 작업 폴더 변경 있음'; exit 1 }
foreach ($b in $expect.Keys) { $h = (& git -C $jp rev-parse --short $b); if ($h -ne $expect[$b]) { Log "중단: $b = $h (기대 $($expect[$b]))"; exit 1 } }
Run 'git fetch origin --prune' | Out-Null
$fail = 0
foreach ($b in $expect.Keys) {
    if ((Run "git push origin refs/heads/${b}:refs/heads/${b}") -ne 0) { $fail++ }
}
Run 'git fetch origin --prune' | Out-Null
Log ''; Log '===== 확인 ====='
foreach ($b in $expect.Keys) {
    $r = (& git -C $jp rev-parse --short "origin/$b" 2>$null)
    $n = (& git -C $jp rev-list --count $b --not --remotes)
    $ok = ($r -eq $expect[$b]) -and ([int]$n -eq 0)
    if (-not $ok) { $fail++ }
    Log ("  [{0}] {1} 로컬 {2} / origin {3} / 원격 없는 커밋 {4}" -f $(if ($ok) {'PASS'} else {'FAIL'}), $b, $expect[$b], $r, $n)
}
$m = (& git -C $jp rev-parse --short origin/main); Log ("  origin/main " + $m + " (변경 없음 기대 fce5048)")
if ($m -ne 'fce5048') { $fail++ }
Log ("FAIL " + $fail)
Log 'PUSH-DONE'

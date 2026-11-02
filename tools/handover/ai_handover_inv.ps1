# PC-A 포맷 전 인수인계 조사 (읽기 전용). 비밀 값 출력 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_handover_inv_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function G([string]$repo, [string]$a) { $o = cmd /c "git -C `"$repo`" $a 2>&1"; foreach ($x in $o) { Log ('    ' + $x) } }
Log ("HANDOVER INVENTORY " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)
Log ''; Log '===== workspace 최상위 ====='
Get-ChildItem $ws -Directory | ForEach-Object { Log ('  [D] ' + $_.Name + $(if (Test-Path (Join-Path $_.FullName '.git')) { '  (git)' } else { '' })) }
Log ("  파일 " + @(Get-ChildItem $ws -File).Count + "개")
$repos = @(Get-ChildItem $ws -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.git') })
foreach ($rp in @('C:\MyData\MyDev\ju-ai-collaboration')) { if (Test-Path (Join-Path $rp '.git')) { $repos += Get-Item $rp } }
foreach ($r in $repos) {
    $p = $r.FullName
    Log ''; Log ("===== repo " + $p + " =====")
    Log '  -- remote'; G $p 'remote -v'
    Log '  -- 현재 브랜치 / 상태'; G $p 'rev-parse --abbrev-ref HEAD'; G $p 'status --porcelain'
    Log '  -- 브랜치 (upstream·ahead/behind)'; G $p 'branch -vv --no-color'
    Log '  -- 원격에 없는 커밋이 있는 브랜치'
    $bs = @(cmd /c "git -C `"$p`" for-each-ref --format=%(refname:short) refs/heads")
    foreach ($b in $bs) {
        $n = (cmd /c "git -C `"$p`" rev-list --count $b --not --remotes 2>nul")
        if ([int]$n -gt 0) { Log ("    " + $b + " : 원격 없는 커밋 " + $n + " (" + (cmd /c "git -C `"$p`" log -1 --format=%h_%s $b") + ")") }
    }
    Log '  -- stash'; G $p 'stash list'
    Log '  -- 추적 안 된 파일 (ignored 제외) 개수'; Log ('    ' + @(cmd /c "git -C `"$p`" ls-files --others --exclude-standard").Count)
}
Log ''; Log 'INV-DONE'

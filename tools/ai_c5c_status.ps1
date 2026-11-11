# C5c 재개 전 상태 점검 (읽기 전용: git fetch 외 변경 없음)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5c_status_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function G([string]$repo, [string]$args2) { $o = cmd /c "git -C `"$repo`" $args2 2>&1"; foreach ($x in $o) { Log ('  ' + $x) } }
Log ("C5c status " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)
foreach ($r in @('juprovider', 'juproject')) {
    $p = Join-Path $ws $r
    Log ''; Log "===== $r ====="
    G $p 'fetch -q origin'
    G $p 'branch --show-current'
    G $p 'log --oneline -3'
    Log '  -- status'; G $p 'status --porcelain'
    Log '  -- local branches (HEAD, upstream, ahead/behind)'
    G $p "for-each-ref --sort=-committerdate --format=`"%(refname:short) %(objectname:short) %(committerdate:iso) %(upstream:short) %(upstream:track)`" refs/heads"
    Log '  -- origin branches'
    G $p "for-each-ref --format=`"%(refname:short) %(objectname:short)`" refs/remotes/origin"
    Log '  -- stash'; G $p 'stash list'
    Log '  -- worktrees'; G $p 'worktree list'
}
$jp = Join-Path $ws 'juprovider'
Log ''; Log '===== C5b 이후 / C5c 흔적 ====='
G $jp 'log --oneline feature/collect-c5b -5'
G $jp 'log --oneline --all --since=2026-11-02 --format="%h %cd %d %s" --date=iso'
G $jp 'branch -a --list "*c5c*"'
Log '  -- c8474c6 tree'; G $jp 'rev-parse c8474c6^{tree}'
Log ''; Log '===== 환경 ====='
foreach ($c in @('java -version', 'mvn -v', 'dotnet --version', 'node -v', 'npm -v', 'git --version')) {
    $o = cmd /c "$c 2>&1" | Select-Object -First 1; Log ("  $c : $o")
}
Log ("  COM ports: " + (([System.IO.Ports.SerialPort]::GetPortNames()) -join ','))
Log ("  8081: " + ((Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count) + " listen")
Log ("  MariaDB service: " + ((Get-Service | Where-Object { $_.Name -match 'maria|mysql' } | ForEach-Object { $_.Name + '=' + $_.Status }) -join ','))
Log 'C5C-STATUS-DONE'

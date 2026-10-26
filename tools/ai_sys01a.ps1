# SYS-01 A: feature/sys-01 브랜치, 코드 적용, EF migration 생성(파일만). DB 변경 없음, commit 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\sys01a'
$log = Join-Path $ws ("ai_sys01a_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'SYS01A-STOPPED'; exit 1 }
$jj = Join-Path $ws 'juproject'
Log ("SYS-01 A " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Run $jj 'git fetch origin' | Out-Null
$b = (& git -C $jj rev-parse --abbrev-ref HEAD)
if ($b -eq 'main') {
    if (@(& git -C $jj status --porcelain).Count -ne 0) { Stop 'main에 변경 있음' }
    if ((Run $jj 'git checkout -b feature/sys-01') -ne 0) { Stop 'branch 실패' }
} elseif ($b -ne 'feature/sys-01') { Stop "브랜치 $b" }
Run $jj 'git log -1 --oneline' | Out-Null
$now = Get-Date
foreach ($f in Get-Content (Join-Path $src 'filelist.txt')) {
    $from = Join-Path $src ('src\' + $f.Replace('/', '\')); $to = Join-Path $jj $f.Replace('/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item $from $to -Force; (Get-Item $to).LastWriteTime = $now
}
Run $jj 'git status --short' | Out-Null
$be = Join-Path $jj 'backend'
Run $be 'dotnet tool restore' | Out-Null
$mig = Join-Path $be 'src\JuProject.Infrastructure\Persistence\Migrations'
if (-not (Get-ChildItem $mig -Filter '*_SysCoreSchema.cs' -ErrorAction SilentlyContinue)) {
    Run $be 'dotnet ef migrations add SysCoreSchema --project src\JuProject.Infrastructure --startup-project src\JuProject.Api --output-dir Persistence\Migrations' | Out-Null
}
Get-ChildItem $mig | ForEach-Object { Log ('  migration file: ' + $_.Name) }
Run $jj 'git status --short' | Out-Null
Log 'SYS01A-DONE'

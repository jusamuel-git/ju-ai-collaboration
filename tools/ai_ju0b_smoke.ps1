# JU-0B smoke 재실행 (terminal 프로젝트를 강제 재빌드). DB 접근 없음 (devices.tsv 재사용)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$smoke = Join-Path $ws 'ai_changes\ju0b\smoke'
$log = Join-Path $ws ("ai_ju0b_smoke_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$jp = Join-Path $ws 'juprovider'
Log ("JU-0B smoke " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " branch=" + (& git -C $jp rev-parse --abbrev-ref HEAD))
Run $jp 'git diff' | Out-Null
Run $smoke 'dotnet build -c Debug --no-incremental -v q -nologo' | Out-Null
Run $smoke 'dotnet run -c Debug --no-build -- "..\devices.tsv"' | Out-Null
Log 'SMOKE-DONE'

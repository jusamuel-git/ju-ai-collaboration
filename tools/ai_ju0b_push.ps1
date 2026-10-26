# JU-0B commit → main ff → juprovider main push (JU-0A+0B), 테스트 DB 3개 삭제 (사용자 승인 2026-10-26 15:12)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_ju0b_push_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'PUSH-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
Log ("JU-0B commit/push " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-0b') { Stop '브랜치가 feature/ju-0b 아님' }
$st = @(& git -C $jp status --porcelain)
if ($st.Count -ne 1 -or $st[0] -notmatch 'DeviceRuntimeManager.cs') { Stop ('예상 외 변경: ' + ($st -join ', ')) }
Run $jp 'git add desktop/juprovider.terminal/Runtime/DeviceRuntimeManager.cs' | Out-Null
if ((Run $jp "git commit -F `"$ws\ai_changes\ju0b\commit_ju0b_msg.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git checkout main' | Out-Null
if ((Run $jp 'git merge --ff-only feature/ju-0b') -ne 0) { Stop 'ff 실패' }
Run $jp 'git log --oneline origin/main..main' | Out-Null
if ((Run $jp 'git push origin main') -ne 0) { Stop 'push 실패' }
Run $jp 'git fetch origin' | Out-Null
Run $jp 'git status --short --branch' | Out-Null
Run $jp 'git log --oneline -4' | Out-Null

Log ''; Log '===== 테스트 DB 삭제 ====='
$setenv = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat'
$vars = @{}
foreach ($l in Get-Content $setenv) { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u " + $vars['JU_DB_USER']
Run $ws "$base -e `"DROP DATABASE IF EXISTS juprovider_installtest; DROP DATABASE IF EXISTS juprovider_migtest; DROP DATABASE IF EXISTS juprovider_realtest; SHOW DATABASES LIKE 'juprovider%';`"" | Out-Null
$env:MYSQL_PWD = $null
Log 'PUSH-DONE'

# WEB-01 (2/2): 18081 종료, 테스트 DB 삭제, smoke 자격 파일 삭제, 로컬 commit (push 없음)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\web01'
$log = Join-Path $ws ("ai_web01_finish_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$jp = Join-Path $ws 'juprovider'
Log ("WEB-01 finish " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$pidf = Join-Path $src 'server.pid'
if (Test-Path $pidf) { $id = [int](Get-Content $pidf); Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; Log "  서버 종료 PID $id"; Remove-Item $pidf -Force }
Remove-Item (Join-Path $src 'smoke_cred.txt') -Force -ErrorAction SilentlyContinue
Log ("  자격 파일 남음: " + (Test-Path (Join-Path $src 'smoke_cred.txt')))
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4"
cmd /c "$base -e `"DROP DATABASE IF EXISTS juprovider_webtest`"" | Out-Null
Log ("  테스트 DB 삭제: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/web-01' -or (& git -C $jp log -1 --format=%h) -ne '1d1c1ab') { Log '중단: 브랜치/HEAD 다름'; Log 'WEB-STOPPED'; exit 1 }
Run $jp 'git add juprovider.frontvue' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("  staged $n, 기타 $other")
if ($n -ne 7 -or $other -ne 0) { Log '중단: 예상 외 변경'; Run $jp 'git status --short' | Out-Null; Log 'WEB-STOPPED'; exit 1 }
if ((Run $jp "git commit -F `"$src\commit_web01.txt`"") -ne 0) { Log 'WEB-STOPPED'; exit 1 }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
Log 'WEB-DONE'

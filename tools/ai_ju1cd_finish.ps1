# JU-1c Desktop 마무리: 18081 종료, Client 종료, 테스트 DB 삭제, (stage1 FAIL 0이면) 로컬 commit. push 없음
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'; $src = Join-Path $ws 'ai_changes\ju1cd'; $jp = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_ju1cd_finish_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) { Log ("> " + $cmd); Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'JU1CD-FINISH-STOPPED'; exit 1 }
Log ("JU-1c Desktop finish " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$pf = Join-Path $src 'server.pid'
if (Test-Path $pf) { Stop-Process -Id ([int](Get-Content $pf)) -Force -ErrorAction SilentlyContinue; Remove-Item $pf -Force; Log '  18081 종료' }
foreach ($pn in 'juprovider.client', 'juprovider.terminal') { Get-Process -Name $pn -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force; Log "  $pn 종료" } }
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER'])"
cmd /c "$base -e `"DROP DATABASE IF EXISTS juprovider_ju1cdtest`"" | Out-Null
Log ("  남은 DB: " + ((cmd /c "$base -N -B -e `"SHOW DATABASES LIKE 'juprovider%'`"") -join ', '))
$env:MYSQL_PWD = $null
$s1 = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_ju1cd_{0}.log" -f $env:COMPUTERNAME))
if (-not ($s1 -match 'JU1CD-STAGE1-DONE') -or -not ($s1 -match '^결과: FAIL 0')) { Stop 'stage1 FAIL 0 아님 → commit 하지 않음' }
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-1c-desktop') { Stop '브랜치 불일치' }
Run $jp 'git add desktop' | Out-Null
$n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
Log ("  staged $n, 기타 $other")
if ($n -ne 10 -or $other -ne 0) { Stop '예상 외 변경' }
if ((Run $jp "git commit -F `"$src\commit_ju1cd.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git log --oneline -3' | Out-Null
Run $jp 'git diff --stat HEAD~1' | Out-Null
Run $jp 'git status --short --branch' | Out-Null
Log 'JU1CD-FINISH-DONE'

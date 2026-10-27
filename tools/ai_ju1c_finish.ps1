# JU-1C 2단계: 서버 종료, 테스트 DB 삭제, 테스트 비밀번호 파일 삭제, (browser_ok 파일이 있으면) 로컬 commit
$ErrorActionPreference = 'Continue'
$ws  = 'C:\MyData\MyDev\workspace'; $src = Join-Path $ws 'ai_changes\ju1c'; $jp = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_ju1c_finish_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c }
$pidFile = Join-Path $src 'app.pid'
if (Test-Path $pidFile) { Stop-Process -Id ([int](Get-Content $pidFile)) -Force -ErrorAction SilentlyContinue; Remove-Item $pidFile -Force; Log '서버 종료' }
Start-Sleep -Seconds 3
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$o = cmd /c "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) -N -B -e `"DROP DATABASE IF EXISTS juprovider_ju1ctest; SHOW DATABASES LIKE 'juprovider%';`" 2>&1"
$env:MYSQL_PWD = $null
Log ("DB: " + ($o -join ', '))
Remove-Item (Join-Path $src 'testpw.json') -Force -ErrorAction SilentlyContinue
Log ("testpw.json 삭제: " + (-not (Test-Path (Join-Path $src 'testpw.json'))))
if (Test-Path (Join-Path $src 'browser_ok.txt')) {
    if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-1c') { Log '중단: 브랜치'; exit 1 }
    Run 'git add juprovider.backend juprovider.frontvue' | Out-Null
    $n = @(& git -C $jp diff --cached --name-only).Count; $other = @(& git -C $jp status --porcelain | Where-Object { $_ -notmatch '^[AM]  ' }).Count
    Log ("staged $n, 기타 $other")
    if ($n -eq 12 -and $other -eq 0) { Run "git commit -F `"$src\commit_ju1c.txt`"" | Out-Null } else { Log '중단: 예상 외 변경' }
    Run 'git log --oneline -4' | Out-Null
    Run 'git status --short --branch' | Out-Null
} else { Log 'browser_ok 없음 → commit 안 함' }
Log 'FINISH-DONE'

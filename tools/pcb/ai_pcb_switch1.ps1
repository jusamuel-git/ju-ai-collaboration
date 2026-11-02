# PC-B 전환 1단계 (조사): 환경 점검 + git fetch·브랜치/커밋 비교 + 로컬 변경 확인. 제품 코드·DB 변경 없음. 비밀 값 출력 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_pcb_switch1_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function G([string]$repo, [string]$a) { $o = cmd /c "git -C `"$repo`" $a 2>&1"; foreach ($x in $o) { Log ('    ' + $x) } }
$env:GIT_TERMINAL_PROMPT = '0'
Log ("PC-B SWITCH 1 " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)

Log ''; Log '===== 1. 환경 점검 (ai_dev_env_check.ps1, 읽기 전용) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_dev_env_check.ps1') *>&1 | Out-Null
$el = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_dev_env_check_{0}.log" -f $env:COMPUTERNAME))
$si = -1; for ($i = 0; $i -lt $el.Count; $i++) { if ($el[$i] -match '요약|SUMMARY') { $si = $i } }
if ($si -ge 0) { $el[$si..($el.Count - 1)] | ForEach-Object { Log ('  ' + $_) } } else { $el | Select-Object -Last 60 | ForEach-Object { Log ('  ' + $_) } }

Log ''; Log '===== 2. 추가 점검 ====='
Log ("  dotnet SDK: " + ((cmd /c 'dotnet --list-sdks 2>&1') -join ' | '))
foreach ($p in 'juprovider', 'juproject') { $gj = Join-Path $ws "$p\global.json"; if (Test-Path $gj) { Log ("  $p global.json: " + ((Get-Content $gj -Raw) -replace '\s+', ' ')) } }
Log ("  java: " + ((cmd /c 'java -version 2>&1') -join ' | '))
Log ("  JAVA_HOME: " + $env:JAVA_HOME)
Log ("  mvn: " + ((cmd /c 'mvn -v 2>&1') | Select-Object -First 1))
Log ("  node/npm: " + ((cmd /c 'node -v 2>&1') -join '') + " / " + ((cmd /c 'npm -v 2>&1') -join ''))
Log ("  git: " + ((cmd /c 'git --version 2>&1') -join '') + ", autocrlf=" + ((cmd /c 'git config --global core.autocrlf 2>&1') -join ''))
foreach ($n in 'MariaDB', 'MySQL', 'Jenkins') { $s = Get-CimInstance Win32_Service -Filter "Name like '%$n%'" -ErrorAction SilentlyContinue; foreach ($x in $s) { Log ("  service " + $x.Name + ": " + $x.State + " / " + $x.StartMode) } }
$sb = Get-ChildItem 'C:\MyData\MyTool\tomcat' -Recurse -Filter 'setenv.bat' -ErrorAction SilentlyContinue | Select-Object -First 3
foreach ($f in $sb) {
    $keys = @(Get-Content $f.FullName | Where-Object { $_ -match '^\s*set\s+"?(JU_[A-Z_]+)=' } | ForEach-Object { if ($_ -match 'set\s+"?(JU_[A-Z_]+)=(.*)$') { $matches[1] + $(if ($matches[2].Trim('"', ' ')) { '=SET' } else { '=EMPTY' }) } })
    Log ("  setenv " + $f.FullName + ": " + ($keys -join ', '))
}
if (-not $sb) { Log '  setenv.bat 없음 (C:\MyData\MyTool\tomcat 아래)' }
Log ("  bcrypt.jsh: " + (Test-Path (Join-Path $ws 'ai_changes\ju1a\bcrypt.jsh')))
Log ("  COM 포트: " + ([System.IO.Ports.SerialPort]::GetPortNames() -join ', '))
Log ("  포트 8081/18081 사용: " + (Test-NetConnection localhost -Port 8081 -WarningAction SilentlyContinue).TcpTestSucceeded + "/" + (Test-NetConnection localhost -Port 18081 -WarningAction SilentlyContinue).TcpTestSucceeded)

Log ''; Log '===== 3. git ====='
foreach ($name in 'juprovider', 'juproject') {
    $p = Join-Path $ws $name
    Log ''; Log ("--- $name ---")
    if (-not (Test-Path (Join-Path $p '.git'))) { Log '  git 저장소 없음'; continue }
    Log '  remote'; G $p 'remote -v'
    Log '  현재 브랜치'; G $p 'rev-parse --abbrev-ref HEAD'
    Log '  로컬 변경 (status --porcelain)'; G $p 'status --porcelain'
    Log '  stash'; G $p 'stash list'
    Log '  fetch'; G $p 'fetch origin --prune'
    Log '  원격 브랜치 (HEAD, 날짜, 제목)'; G $p 'for-each-ref --sort=refname --format="%(refname:short) %(objectname:short) %(committerdate:short) %(subject)" refs/remotes/origin'
    Log '  로컬 브랜치 (upstream 비교)'; G $p 'branch -vv --no-color'
    Log '  원격에 없는 로컬 커밋'
    foreach ($b in @(cmd /c "git -C `"$p`" for-each-ref --format=%(refname:short) refs/heads")) {
        $n = (cmd /c "git -C `"$p`" rev-list --count $b --not --remotes 2>nul"); if ([int]$n -gt 0) { Log ("    $b : $n") }
    }
}
Log ''; Log 'SWITCH1-DONE'

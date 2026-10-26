# JU-0A: 실제 DB 백업 → 04 적용 → 검증 → 로컬 commit (+ main ff)
# JU-0B: feature/ju-0b, DeviceRuntimeManager 정정, 로컬 빌드, Virtual Device smoke (변경 전/후)
# push 하지 않는다. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\ju0b'
$log = Join-Path $ws ("ai_ju0b_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$dir, [string]$cmd) {
    Log ("> " + $cmd)
    Push-Location $dir; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location
    foreach ($x in $o) { Log ('  ' + $x) }; Log ("  (exit $c)"); return $c
}
$jp  = Join-Path $ws 'juprovider'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$setenv = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat'
$vars = @{}
foreach ($l in Get-Content $setenv) { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$dbHost = 'localhost'; $dbPort = '3306'
if ($vars['JU_DB_URL'] -match '//([^:/]+)(:(\d+))?/') { $dbHost = $matches[1]; if ($matches[3]) { $dbPort = $matches[3] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']; $user = $vars['JU_DB_USER']
$base = "`"$bin\mysql.exe`" -h $dbHost -P $dbPort -u $user --default-character-set=utf8mb4"
function Stop([string]$why) { Log ("중단: " + $why); $env:MYSQL_PWD = $null; Log 'JU0B-STOPPED'; exit 1 }

Log ("JU-0A 적용 + JU-0B " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$b = (& git -C $jp rev-parse --abbrev-ref HEAD)
if ($b -ne 'feature/ju-0a') { Stop "브랜치 $b" }
Run $jp 'git status --short' | Out-Null

Log ''; Log '===== 1. 실제 DB 백업 ====='
$bk = 'C:\MyData\MyDev\backup'; New-Item -ItemType Directory -Force -Path $bk | Out-Null
$bf = Join-Path $bk ("juprovider_{0}_before_04.sql" -f (Get-Date -Format 'yyyyMMdd_HHmm'))
cmd /c "`"$bin\mysqldump.exe`" -h $dbHost -P $dbPort -u $user --default-character-set=utf8mb4 --single-transaction --routines --triggers --databases juprovider > `"$bf`" 2>`"$bf.err`""
$c = $LASTEXITCODE; $size = (Get-Item $bf).Length
$tail = (Get-Content $bf -Tail 1)
Log ("  backup: $bf ($size bytes, exit $c, 마지막 줄: $tail)")
if ($c -ne 0 -or $size -lt 10000 -or $tail -notmatch 'Dump completed') { Stop '백업 실패' }
Remove-Item "$bf.err" -Force

Log ''; Log '===== 2. 실제 DB 04 적용 ====='
$snap = Join-Path $ws 'ai_changes\ju0a_db\ju0a_snapshot.sql'
cmd /c "$base -B juprovider < `"$snap`" > `"$src\REAL_before.txt`" 2>&1"
$c = Run $ws "$base juprovider < `"$jp\database\migration\04_ju0_install_fix.sql`""
if ($c -ne 0) { Stop '04 실행 오류 (백업으로 복구 가능)' }
cmd /c "$base -B juprovider < `"$snap`" > `"$src\REAL_after.txt`" 2>&1"
$same = ((Get-FileHash "$src\REAL_after.txt").Hash -eq (Get-FileHash "$src\A_install.txt").Hash)
Log ("  적용 후 스냅샷 = 신규 설치 스냅샷: " + $same)
if (-not $same) { Stop '적용 결과가 신규 설치와 다름 (commit 하지 않음)' }

Log ''; Log '===== 3. JU-0A commit (로컬) ====='
Run $jp 'git add database' | Out-Null
if ((Run $jp "git commit -F `"$src\commit_ju0a_msg.txt`"") -ne 0) { Stop 'commit 실패' }
Run $jp 'git checkout main' | Out-Null
if ((Run $jp 'git merge --ff-only feature/ju-0a') -ne 0) { Stop 'main ff 실패' }
Run $jp 'git log --oneline -3' | Out-Null

Log ''; Log '===== 4. JU-0B: smoke (변경 전 코드) ====='
$devFile = Join-Path $src 'devices.tsv'
cmd /c "$base -N -B juprovider -e `"SELECT DEV_CD,DEV_TYPE,DEV_FORM,DEV_COMM,PTL_GRP_CD,DEV_CH,DEV_DAT_CNT,USE_YN FROM ju_device ORDER BY DEV_CD`" > `"$devFile`""
$env:MYSQL_PWD = $null
Get-Content $devFile | ForEach-Object { Log ('  device: ' + $_) }
$smoke = Join-Path $src 'smoke'
Run $smoke 'dotnet run -c Debug -- "..\devices.tsv"' | Out-Null

Log ''; Log '===== 5. JU-0B 브랜치 + 변경 ====='
Run $jp 'git checkout -b feature/ju-0b' | Out-Null
Copy-Item (Join-Path $src 'DeviceRuntimeManager.cs') (Join-Path $jp 'desktop\juprovider.terminal\Runtime\DeviceRuntimeManager.cs') -Force
Run $jp 'git status --short' | Out-Null
Run $jp 'git diff --stat' | Out-Null

Log ''; Log '===== 6. smoke (변경 후) ====='
$sc = Run $smoke 'dotnet run -c Debug -- "..\devices.tsv"'
Log ("  SMOKE exit $sc")

Log ''; Log '===== 7. 로컬 빌드 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
Log ("  결과: ai_local_build_" + $env:COMPUTERNAME + ".log")
Run $jp 'git status --short --branch' | Out-Null
Log 'JU0B-DONE'

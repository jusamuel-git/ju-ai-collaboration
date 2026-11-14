# C5c 배포 1단계 (11/14 사용자 승인): 백업(WAR·DB) → main fast-forward(4915759) → push. Jenkins 빌드는 별도.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5c_deploy_go_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Halt([string]$why) { $env:MYSQL_PWD = $null; Log ("중단: " + $why); Log 'C5C-DEPLOY-GO-STOPPED'; exit 1 }
$jp = Join-Path $ws 'juprovider'
function Git([string]$a) { return @(cmd /c "git -C `"$jp`" $a 2>&1") }
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
Log ("C5c deploy go " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== A. 사전 확인 ====='
Git 'fetch -q origin' | ForEach-Object { Log ('  ' + $_) }
$om = @(Git 'rev-parse --short origin/main')[0]; $oc = @(Git 'rev-parse --short origin/feature/collect-c5d')[0]; $lm = @(Git 'rev-parse --short main')[0]
Log "  origin/main $om, origin/c5d $oc, local main $lm"
$already = ($om -eq '4915759')
if (-not $already -and ($om -ne 'fce5048' -or $oc -ne '4915759' -or $lm -ne 'fce5048')) { Halt '브랜치 값이 사전 검증과 다름' }
$st = @(Git 'status --porcelain' | Where-Object { $_ -and ($_ -notmatch 'package-lock.json') })
if ($st.Count) { Halt ('작업 폴더 변경: ' + ($st -join ', ')) }

Log '===== B. 백업 ====='
$bd = Join-Path 'C:\MyData\MyDev\backup' ('c5c_deploy_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $bd | Out-Null
$war0 = Join-Path $tc 'webapps\juprovider.war'
$wb = Join-Path $bd 'juprovider_20261025.war'
Copy-Item $war0 $wb -Force
$wh = (Get-FileHash $wb -Algorithm SHA256).Hash
Log ("  B-1 WAR 백업 $wb SHA256 " + $wh.Substring(0, 16) + $(if ($wh.StartsWith('DBAF8738B0D7F42F')) { ' (사전 검증과 같음)' } else { ' (다름!)' }))
if (-not $wh.StartsWith('DBAF8738B0D7F42F')) { Halt '배포 WAR 가 사전 검증 때와 다름' }
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$df = Join-Path $bd 'juprovider_before_c5c_deploy.sql'
& "$bin\mysqldump.exe" -h localhost -u $vars['JU_DB_USER'] --default-character-set=utf8mb4 --single-transaction --routines --triggers --hex-blob "--result-file=$df" juprovider 2>&1 | ForEach-Object { Log ('  ' + $_) }
$ok = ($LASTEXITCODE -eq 0) -and (Test-Path $df) -and ((Get-Item $df).Length -gt 50000)
$cmp = Join-Path $bd 'snap_before.sql'
& "$bin\mysqldump.exe" -h localhost -u $vars['JU_DB_USER'] --default-character-set=utf8mb4 --skip-comments --skip-dump-date --order-by-primary --skip-extended-insert --routines --triggers "--result-file=$cmp" juprovider 2>&1 | Out-Null
$env:MYSQL_PWD = $null
$dh = (Get-FileHash $cmp -Algorithm SHA256).Hash.Substring(0, 16)
Log ("  B-2 DB 덤프 " + (Get-Item $df).Length + " bytes, exit ok $ok, 비교용 해시 $dh (사전 검증 12CD3AA09A237DBC)")
if (-not $ok) { Halt 'DB 백업 실패' }
(Get-FileHash $df -Algorithm SHA256).Hash + '  ' + (Split-Path $df -Leaf) | Set-Content (Join-Path $bd 'sha256.txt')

Log '===== C. main fast-forward → push ====='
if ($already) { Log '  origin/main 이미 4915759 — 생략' } else {
    Git 'checkout -q main' | ForEach-Object { Log ('  ' + $_) }
    Git 'merge --ff-only origin/feature/collect-c5d' | ForEach-Object { Log ('  ' + $_) }
    $nm = @(Git 'rev-parse --short main')[0]
    if ($nm -ne '4915759') { Git 'checkout -q feature/collect-c5d' | Out-Null; Halt "ff 병합 결과 $nm" }
    Git 'push origin main' | ForEach-Object { Log ('  ' + $_) }
    Git 'fetch -q origin' | Out-Null
    $om = @(Git 'rev-parse --short origin/main')[0]
    Git 'checkout -q feature/collect-c5d' | ForEach-Object { Log ('  ' + $_) }
    if ($om -ne '4915759') { Halt "push 후 origin/main $om" }
}
Log ("  C-1 origin/main " + @(Git 'rev-parse --short origin/main')[0] + ", 작업 폴더 " + @(Git 'rev-parse --abbrev-ref HEAD')[0])
Log ("  backup " + $bd)
Log 'C5C-DEPLOY-GO-DONE'

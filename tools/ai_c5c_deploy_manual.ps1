# C5c 수동 배포 (11/14 사용자 승인 "c5d로 배포, 8081 기동"). Jenkinsfile 7~10단계와 같은 순서.
# Health 실패 시 백업 WAR 로 자동 복구. 실제 DB 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5c_deploy_manual_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) { $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }; Log ("  [$r] $id $name $note") }
$jp = Join-Path $ws 'juprovider'
function Git([string]$a) { return @(cmd /c "git -C `"$jp`" $a 2>&1") }
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$api = 'http://localhost:8081/juprovider'
$wa = Join-Path $tc 'webapps'
$bk = 'C:\MyData\MyDev\backup\c5c_deploy_20261114_220358'
$oldWar = Join-Path $bk 'juprovider_20261025.war'
function Http([string]$method, [string]$url, [string]$body) {
    try {
        $p = @{ Uri = $url; Method = $method; UseBasicParsing = $true; TimeoutSec = 15 }
        if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json; charset=utf-8' }
        $r = Invoke-WebRequest @p; return @{ code = [int]$r.StatusCode; body = [string]$r.Content }
    } catch { $c = -1; if ($_.Exception.Response) { $c = [int]$_.Exception.Response.StatusCode }; return @{ code = $c; body = '' } }
}
function WaitUp([int]$sec) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $h = @{ code = -1; body = '' }
    while ($sw.Elapsed.TotalSeconds -lt $sec) { $h = Http 'GET' "$api/api/health" ''; if ($h.code -eq 200) { break }; Start-Sleep -Seconds 3 }
    return @{ h = $h; s = [int]$sw.Elapsed.TotalSeconds }
}
function Catalina { return @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' }) }
function TStart { $env:CATALINA_HOME = $tc; Start-Process cmd.exe -ArgumentList '/c', "`"$tc\bin\startup.bat`"" -WindowStyle Hidden; Start-Sleep -Seconds 3 }
function TStop {
    $env:CATALINA_HOME = $tc; cmd /c "`"$tc\bin\shutdown.bat`" >nul 2>&1"
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; if (@(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count -eq 0 -and (Catalina).Count -eq 0) { return } }
    Catalina | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep -Seconds 2
}
function CleanApp { Remove-Item (Join-Path $wa 'juprovider') -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $wa 'juprovider.war') -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $tc 'work\Catalina\localhost\juprovider') -Recurse -Force -ErrorAction SilentlyContinue }
function Restore([string]$why) {
    Log ("===== 복구: " + $why + " =====")
    TStop; CleanApp
    Copy-Item $oldWar (Join-Path $wa 'juprovider.war') -Force
    TStart; $w = WaitUp 180
    Log ("  복구 후 health HTTP " + $w.h.code + ", " + $w.s + "초")
    Log 'C5C-DEPLOY-MANUAL-RESTORED'; exit 1
}
Log ("C5c manual deploy " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 1. 확인 ====='
$head = @(Git 'rev-parse --short HEAD')[0]; $om = @(Git 'rev-parse --short origin/main')[0]
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
$wh = $(if (Test-Path $war) { (Get-FileHash $war -Algorithm SHA256).Hash } else { '' })
Log "  작업 폴더 HEAD $head, origin/main $om, 후보 WAR SHA256 $($wh.Substring(0, [Math]::Min(16, $wh.Length)))"
if ($head -ne '4915759' -or $om -ne '4915759' -or -not $wh.StartsWith('EC80C07DA99241E4')) { Log '중단: 후보 WAR·커밋이 사전 검증과 다름'; Log 'C5C-DEPLOY-MANUAL-STOPPED'; exit 1 }
if (-not (Test-Path $oldWar) -or -not (Get-FileHash $oldWar -Algorithm SHA256).Hash.StartsWith('DBAF8738B0D7F42F')) { Log '중단: 복구용 백업 WAR 없음'; Log 'C5C-DEPLOY-MANUAL-STOPPED'; exit 1 }
Log ("  8081 listen " + @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count + ", catalina 프로세스 " + (Catalina).Count)

Log '===== 2. Tomcat 중지 · 현재 WAR 백업 (Jenkins 와 같은 위치) ====='
TStop
$jb = Join-Path $tc ('backup\juprovider-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.war')
Copy-Item (Join-Path $wa 'juprovider.war') $jb -Force
Log "  $jb"

Log '===== 3. 배포 (정리 → 복사 → startup.bat) ====='
CleanApp
Copy-Item $war (Join-Path $wa 'juprovider.war') -Force
$t0 = Get-Date
TStart
$w = WaitUp 180
$hj = $null; try { $hj = $w.h.body | ConvertFrom-Json } catch {}
$okH = ($w.h.code -eq 200) -and ($hj.success -eq $true) -and ($hj.data.status -eq 'UP')
Check 'D-1' 'health (success=true, status=UP)' $okH ("HTTP " + $w.h.code + ", " + $w.s + "초")
if (-not $okH) { Restore 'health 실패' }

Log '===== 4. 배포 후 확인 ====='
$r = Http 'POST' "$api/api/auth/login" '{"loginId":"c5cdep_no_user","password":"wrong-pw-000"}'; Check 'D-2' '없는 사용자 로그인 401' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/api/core/sync/devices" ''; Check 'D-3' 'sync/devices 키 없음 401' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/api/core/sync/data-map?devCd=SDEV_GTEC01" ''; Check 'D-4' 'sync/data-map 키 없음 401' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/api/core/languages" ''; Check 'D-5' 'JWT 없는 languages 401' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/" ''; Check 'D-6' '공개 홈 GET /' ($r.code -eq 200) ("HTTP " + $r.code)
$r = Http 'GET' "$api/console/protocols" ''; Check 'D-7' '콘솔 직접 URL' ($r.code -eq 200) ("HTTP " + $r.code)
$errs = @(Get-ChildItem (Join-Path $tc 'logs') -File | Where-Object { $_.LastWriteTime -ge $t0 -and $_.Name -notmatch 'access' } | ForEach-Object { Get-Content $_.FullName -Encoding UTF8 } | Select-String -Pattern 'SEVERE|ERROR|Exception' | ForEach-Object { $_.Line })
Check 'D-8' 'Tomcat 로그 SEVERE/ERROR/Exception' ($errs.Count -eq 0) ("" + $errs.Count + "건")
$errs | Select-Object -First 6 | ForEach-Object { Log ('    ' + $_.Substring(0, [Math]::Min(220, $_.Length))) }
$dw = (Get-FileHash (Join-Path $wa 'juprovider.war') -Algorithm SHA256).Hash.Substring(0, 16)
Check 'D-9' '배포 WAR = 후보 WAR' ($dw -eq 'EC80C07DA99241E4') $dw
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$sn = Join-Path $bk 'snap_after_deploy.sql'
& "$bin\mysqldump.exe" -h localhost -u $vars['JU_DB_USER'] --default-character-set=utf8mb4 --skip-comments --skip-dump-date --order-by-primary --skip-extended-insert --routines --triggers "--result-file=$sn" juprovider 2>&1 | Out-Null
$env:MYSQL_PWD = $null
$dh = (Get-FileHash $sn -Algorithm SHA256).Hash.Substring(0, 16)
$note = "덤프 $dh (배포 전 12CD3AA09A237DBC)"
if ($dh -ne '12CD3AA09A237DBC') {
    $a = @(Get-Content (Join-Path $bk 'snap_before.sql') -Encoding UTF8 | Where-Object { $_ -match '^INSERT INTO' }); $b = @(Get-Content $sn -Encoding UTF8 | Where-Object { $_ -match '^INSERT INTO' })
    $note += ' · 바뀐 행: ' + ((@(Compare-Object $a $b | ForEach-Object { if ($_.InputObject -match '^INSERT INTO `([^`]+)`') { $matches[1] + $_.SideIndicator } }) | Group-Object | ForEach-Object { $_.Name + ' x' + $_.Count }) -join ', ')
}
Log ("  [INFO] D-10 실제 DB " + $note)
$p = Catalina
Log ("  [INFO] D-11 Tomcat PID " + $(if ($p.Count) { $p[0].ProcessId } else { '-' }) + ", 8081 listen " + @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count)
Log ("FAIL " + $script:fail)
Log 'C5C-DEPLOY-MANUAL-DONE'

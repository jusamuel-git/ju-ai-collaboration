# C5d 연결 준비 (11/17 승인): PC-B Desktop Client 등록·키 발급 → Client Key 인증·동기화 검증 → COM3 회귀 준비.
# 관리자 계정은 이 창에서 사용자가 직접 입력한다 (비밀번호는 화면·로그에 남지 않음).
# Client Key 는 desktop\app\config\client.json 에만 저장한다 (git 제외 경로). 로그에는 키 존재·길이만 쓴다.
# DB 구조 변경·배포 없음. DB 는 읽기만 (Client 등록은 서버 관리자 API 로만).
param([string]$ClientId = 'PCB-DESKTOP-01')
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5d_connect_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0; $script:rows = @()
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) {
    $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }
    $script:rows += ("| {0} | {1} | {2} | {3} |" -f $id, $name, $note, $r); Log ("  [$r] $id $name $note")
}
function Info([string]$id, [string]$name, [string]$note) { $script:rows += ("| {0} | {1} | {2} | INFO |" -f $id, $name, $note); Log ("  [INFO] $id $name $note") }
function Done([string]$mark) {
    $script:tok = $null; $script:key = $null; $env:MYSQL_PWD = $null; $env:C4_CLIENT_ID = $null; $env:C4_CLIENT_KEY = $null
    Log ''; Log '===== 요약 ====='; Log '| # | 항목 | 내용 | 결과 |'; Log '|---|---|---|---|'
    foreach ($x in $script:rows) { Log $x }
    Log ("FAIL " + $script:fail); Log $mark
}
$jp = Join-Path $ws 'juprovider'
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$api = 'http://localhost:8081/juprovider'
$cfgDir = Join-Path $jp 'desktop\app\config'
$cfg = Join-Path $cfgDir 'client.json'
function Http([string]$m, [string]$path, [hashtable]$h, [string]$body) {
    try {
        $p = @{ Uri = $api + $path; Method = $m; UseBasicParsing = $true; TimeoutSec = 20 }
        if ($h) { $p.Headers = $h }
        if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json; charset=utf-8' }
        $r = Invoke-WebRequest @p
        $j = $null; try { $j = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json } catch {}
        return @{ code = [int]$r.StatusCode; json = $j; raw = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) }
    } catch {
        $c = -1; $j = $null
        if ($_.Exception.Response) { $c = [int]$_.Exception.Response.StatusCode; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream(), [Text.Encoding]::UTF8); $j = $sr.ReadToEnd() | ConvertFrom-Json } catch {} }
        return @{ code = $c; json = $j; raw = '' }
    }
}
function Bearer { return @{ Authorization = ('Bearer ' + $script:tok) } }
function CK([string]$id, [string]$k) { $h = @{}; if ($id) { $h['X-JU-Client-Id'] = $id }; if ($k) { $h['X-JU-Client-Key'] = $k }; return $h }
Log ("C5d connect " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME + " ClientId=" + $ClientId)

# ---------------------------------------------------------------- 0
Log ''; Log '===== 0. 사전 확인 ====='
$h = Http 'GET' '/api/health' $null ''
if ($h.code -ne 200) {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('MM-dd HH:mm')
    $cat = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' })
    Log ("  8081 응답 없음 (마지막 부팅 $boot, catalina 프로세스 " + $cat.Count + ") → 배포된 WAR 그대로 Tomcat 기동")
    if ($cat.Count -eq 0) {
        $env:CATALINA_HOME = $tc; Start-Process cmd.exe -ArgumentList '/c', "`"$tc\bin\startup.bat`"" -WindowStyle Hidden; $env:CATALINA_HOME = $null
        for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 3; $h = Http 'GET' '/api/health' $null ''; if ($h.code -eq 200) { break } }
    }
    Info 'P-0' 'Tomcat 재기동 (배포 변경 없음)' ("부팅 $boot, 기동 후 HTTP " + $h.code)
}
Check 'P-1' '8081 health' (($h.code -eq 200) -and ($h.json.data.status -eq 'UP')) ("HTTP " + $h.code)
$head = (@(cmd /c "git -C `"$jp`" rev-parse --short HEAD 2>&1"))[0]
Check 'P-2' '작업 폴더 = 배포 커밋 4915759' ($head -eq '4915759') $head
$exe = Join-Path $jp 'desktop\app\juprovider.client.exe'
Info 'P-3' 'Desktop 실행 파일 (desktop\app)' $(if (Test-Path $exe) { 'juprovider.client.exe ' + (Get-Item $exe).LastWriteTime.ToString('MM-dd HH:mm') } else { '없음' })
$ign = (@(cmd /c "git -C `"$jp`" check-ignore desktop/app/config/client.json 2>&1"))[0]
Check 'P-4' 'client.json 이 git 제외 경로' ($ign -eq 'desktop/app/config/client.json') $ign
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
function V([string]$sql) { $f = Join-Path $ws 'ai_c5d_connect_q.sql'; [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`n$sql`n", $enc); $o = cmd /c "`"$bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -N -B juprovider < `"$f`" 2>&1"; Remove-Item $f -Force; return (([string]($o -join ' ')).Trim()) }
$cl0 = V "SELECT IFNULL(GROUP_CONCAT(CONCAT(CLIENT_ID,':',USE_YN,':',IFNULL(DATE_FORMAT(LAST_SEEN_DT,'%m/%d %H:%i'),'-')) ORDER BY CLIENT_ID),'(없음)') FROM ju_client"
Info 'C-0' '기존 Client 등록 (DB, 키 해시 제외)' $cl0
$haveCfg = Test-Path $cfg
$old = $null; if ($haveCfg) { try { $old = Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
Info 'C-0b' '기존 client.json' $(if ($old) { 'ClientId=' + $old.ClientId + ', ServerUrl=' + $old.ServerUrl + ', 키 ' + $(if ($old.ClientKey) {'있음'} else {'없음'}) } elseif ($haveCfg) { '읽기 실패' } else { '없음' })
if ($script:fail -gt 0) { Done 'C5D-CONNECT-STOPPED'; exit 1 }

# ---------------------------------------------------------------- 1
Log ''; Log '===== 1. 관리자 로그인 (이 창에서 직접 입력) ====='
$lid = Read-Host '  관리자 아이디'
$sp = Read-Host '  비밀번호 (화면에 표시되지 않음)' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sp)
$pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
$body = (@{ loginId = $lid; password = $pw } | ConvertTo-Json -Compress)
$pw = $null
$r = Http 'POST' '/api/auth/login' $null $body
$body = $null
$script:tok = $r.json.data.accessToken
Check 'A-1' '관리자 로그인' (($r.code -eq 200) -and [bool]$script:tok) ("HTTP " + $r.code + $(if ($r.json.message -and $r.code -ne 200) { ' ' + $r.json.message } else { '' }))
if (-not $script:tok) { Done 'C5D-CONNECT-STOPPED'; exit 1 }
Info 'A-2' '비밀번호 변경 필요' ([string]$r.json.data.passwordChangeRequired)
if ($r.json.data.passwordChangeRequired -eq $true) {
    Log '  비밀번호 변경이 필요합니다 (임시 비밀번호 상태). 새 비밀번호를 이 창에서 정합니다 (8자 이상, 화면에 표시되지 않음).'
    $n1 = Read-Host '  새 비밀번호' -AsSecureString; $n2 = Read-Host '  새 비밀번호 한 번 더' -AsSecureString
    function Plain($s) { $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) } }
    $q1 = Plain $n1; $q2 = Plain $n2; $cur = Plain $sp
    if ($q1 -ne $q2 -or $q1.Length -lt 8) { $q1 = $null; $q2 = $null; $cur = $null; Check 'A-2b' '새 비밀번호 입력' $false '두 입력이 다르거나 8자 미만'; Done 'C5D-CONNECT-STOPPED'; exit 1 }
    $pc = Http 'POST' '/api/auth/password' (Bearer) ((@{ currentPassword = $cur; newPassword = $q1 } | ConvertTo-Json -Compress))
    Check 'A-2b' '비밀번호 변경 (POST /api/auth/password, 제품 기능)' ($pc.code -eq 200) ("HTTP " + $pc.code + $(if ($pc.code -ne 200 -and $pc.json.message) { ' ' + $pc.json.message } else { '' }))
    if ($pc.code -eq 200) {
        $r = Http 'POST' '/api/auth/login' $null ((@{ loginId = $lid; password = $q1 } | ConvertTo-Json -Compress))
        $script:tok = $r.json.data.accessToken
        Check 'A-2c' '새 비밀번호로 다시 로그인 (변경 필요 해제)' (($r.code -eq 200) -and ($r.json.data.passwordChangeRequired -ne $true)) ("HTTP " + $r.code)
    }
    $q1 = $null; $q2 = $null; $cur = $null; $n1 = $null; $n2 = $null
    if ($script:fail -gt 0) { Done 'C5D-CONNECT-STOPPED'; exit 1 }
}
$sp = $null
$me = Http 'GET' '/api/auth/me' (Bearer) ''
Info 'A-3' '/api/auth/me' ("HTTP " + $me.code + ", 권한 " + $me.json.data.authType)

# ---------------------------------------------------------------- 2
Log ''; Log '===== 2. Client 등록 상태 확인 → 등록 또는 재발급 ====='
$ls = Http 'GET' '/api/admin/clients' (Bearer) ''
Check 'C-1' '관리자 Client 목록 조회' ($ls.code -eq 200) ("HTTP " + $ls.code + ", " + @($ls.json.data).Count + "개: " + ((@($ls.json.data) | ForEach-Object { $_.clientId + '/' + $_.useYn }) -join ', '))
if ($ls.code -ne 200) { Done 'C5D-CONNECT-STOPPED'; exit 1 }
$ex = @($ls.json.data) | Where-Object { $_.clientId -eq $ClientId } | Select-Object -First 1
$reuse = $false
if ($ex -and $old -and $old.ClientId -eq $ClientId -and $old.ClientKey) {
    $t = Http 'GET' '/api/core/sync/devices' (CK $ClientId $old.ClientKey) ''
    if ($t.code -eq 200) { $reuse = $true; $script:key = $old.ClientKey }
    Info 'C-2' '기존 등록 + 로컬 키 재사용 시험' ("HTTP " + $t.code)
}
if ($reuse) { Info 'C-3' 'Client 키' '기존 키 유효 → 새로 발급하지 않음' }
else {
    if ($ex) { $iss = Http 'POST' ("/api/admin/clients/" + $ClientId + "/key") (Bearer) ''; $how = '재발급 (기존 등록 있음, 로컬 키 없음/무효)' }
    else { $iss = Http 'POST' '/api/admin/clients' (Bearer) ((@{ clientId = $ClientId; clientName = 'PC-B Desktop'; clientDescription = 'PC-B JuProvider Desktop (C5d)' } | ConvertTo-Json -Compress)); $how = '신규 등록' }
    $script:key = $iss.json.data.clientKey
    Check 'C-3' ("Client 키 발급: " + $how) (($iss.code -eq 200) -and [bool]$script:key -and ($iss.json.data.clientId -eq $ClientId)) ("HTTP " + $iss.code + ", 키 길이 " + ([string]$script:key).Length)
    if (-not $script:key) { Done 'C5D-CONNECT-STOPPED'; exit 1 }
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    if ($haveCfg) { Copy-Item $cfg ($cfg + '.bak_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force }
    $json = ([ordered]@{ ServerUrl = "$api/"; ClientId = $ClientId; ClientKey = $script:key } | ConvertTo-Json)
    [IO.File]::WriteAllText($cfg, $json, $enc); $json = $null
    $rb = Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    Check 'C-4' 'client.json 저장 (desktop\app\config, 키는 이 파일에만)' (($rb.ClientId -eq $ClientId) -and ($rb.ClientKey -eq $script:key) -and ($rb.ServerUrl -eq "$api/")) ("ServerUrl " + $rb.ServerUrl); $rb = $null
}
$cl1 = V "SELECT CONCAT(CLIENT_ID,':',USE_YN) FROM ju_client WHERE CLIENT_ID='$ClientId'"
Check 'C-5' 'DB 에 Client 등록·사용 중' ($cl1 -eq "$($ClientId):YENO0001") $cl1

# ---------------------------------------------------------------- 3
Log ''; Log '===== 3. Client Key 인증 · 동기화 API ====='
$k = $script:key
$r = Http 'GET' '/api/core/sync/devices' (CK $ClientId $k) ''
$devDb = V "SELECT COUNT(*) FROM ju_device WHERE USE_YN='YENO0001'"
Check 'K-1' 'sync/devices (정상 키) = Desktop 로그인 동기화 대상' (($r.code -eq 200) -and (@($r.json).Count -gt 0)) ("HTTP " + $r.code + ", 장치 " + @($r.json).Count + " (DB 사용 중 $devDb): " + ((@($r.json) | Where-Object { $_ } | ForEach-Object { $_.devCd }) -join ','))
$codes = @()
foreach ($c in @(@('키 틀림', $ClientId, ($k.Substring(0, $k.Length - 2) + 'zz')), @('키 없음', $ClientId, ''), @('Id 없음', '', $k), @('없는 Id', 'NO_SUCH_CLIENT', $k))) { $codes += ($c[0] + ' ' + (Http 'GET' '/api/core/sync/devices' (CK $c[1] $c[2]) '').code) }
Check 'K-2' '잘못된 자격 → 401 (키 틀림·키 없음·Id 없음·없는 Id)' (@($codes | Where-Object { $_ -notmatch ' 401$' }).Count -eq 0) ($codes -join ', ')
$r = Http 'GET' '/api/core/sync/devices' (Bearer) ''; Check 'K-3' 'JWT 만으로 sync → 401' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'POST' '/api/core/sync/protocols' (CK $ClientId $k) '{}'; Check 'K-4' '쓰기 메서드 → 403' ($r.code -eq 403) ("HTTP " + $r.code)
$sd = Join-Path $ws 'ai_changes\c5d_real\server'; New-Item -ItemType Directory -Force -Path $sd | Out-Null
$okAll = $true; $notes = @()
foreach ($pair in @(@('protocols_all.json', '/api/core/sync/protocols'), @('protocols_GTEC.json', '/api/core/sync/protocols/GTEC'), @('data_tags.json', '/api/core/sync/data-tags?devCd=SDEV_GTEC01'), @('data_map.json', '/api/core/sync/data-map?devCd=SDEV_GTEC01'))) {
    $x = Http 'GET' $pair[1] (CK $ClientId $k) ''
    if ($x.code -ne 200) { $okAll = $false }
    if ($pair[0] -ne 'protocols_all.json') { [IO.File]::WriteAllText((Join-Path $sd $pair[0]), $x.raw, $enc) }
    $notes += ($pair[1] + ' ' + $x.code)
}
Check 'K-5' 'sync/protocols·GTEC·data-tags·data-map 200 (GTEC 응답은 COM3 회귀용으로 저장)' $okAll ($notes -join ', ')
$g = (Get-Content (Join-Path $sd 'protocols_GTEC.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items[0]
Check 'K-6' 'GTEC 수집 설정 (sync 응답)' (($g.cmdGapMs -eq 200) -and ($g.initDelayMs -eq 500) -and ((@($g.initRoutine) -join ',') -eq 'GTEC0301,GTEC0001,GTEC0002,GTEC0100')) ("간격 " + $g.cmdGapMs + ", 대기 " + $g.initDelayMs + ", 루틴 " + (@($g.initRoutine) -join ',') + ", frameRule " + [bool]$g.frameRule)
$dm = (Get-Content (Join-Path $sd 'data_map.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items
Check 'K-7' 'data-map SDEV_GTEC01 4채널' (@($dm).Count -eq 4) ((@($dm) | ForEach-Object { $_.channelKey + '>' + $_.datCd }) -join ', ')
# Desktop 라이브러리(JuProviderApiClient → CollectionPlanBuilder) 로 실서버 응답 검증. 키는 환경변수로만 전달
$prj = Join-Path $ws 'ai_changes\c4srvplan\C4SrvPlan.csproj'
$o = & dotnet build $prj -c Debug -v q -nologo 2>&1; $bc = $LASTEXITCODE
if ($bc -eq 0) {
    $env:C4_CLIENT_ID = $ClientId; $env:C4_CLIENT_KEY = $k
    $po = & dotnet run --project $prj -c Debug --no-build -- "$api/" SDEV_GTEC01 c5d 2>&1; $pc = $LASTEXITCODE
    $env:C4_CLIENT_ID = $null; $env:C4_CLIENT_KEY = $null
    foreach ($x in $po) { Log ('    ' + $x) }
    Check 'K-8' 'Desktop 라이브러리로 실서버 동기화 → 서버값 CollectionPlan' ($pc -eq 0) ("PASS " + @($po | Where-Object { $_ -match '^\[PASS\]' }).Count + " / FAIL " + @($po | Where-Object { $_ -match '^\[FAIL\]' }).Count)
} else { $o | Where-Object { $_ -match 'error' } | Select-Object -First 5 | ForEach-Object { Log ('    ' + $_) }; Check 'K-8' 'Desktop 라이브러리 검증 도구 빌드' $false "exit $bc" }
$seen = V "SELECT IFNULL(DATE_FORMAT(LAST_SEEN_DT,'%m/%d %H:%i'),'-') FROM ju_client WHERE CLIENT_ID='$ClientId'"
Info 'K-9' 'ju_client LAST_SEEN_DT' $seen
$k = $null

# ---------------------------------------------------------------- 4
Log ''; Log '===== 4. COM3 실장비 회귀 준비 (실행은 하지 않음) ====='
$ports = @([System.IO.Ports.SerialPort]::GetPortNames())
Info 'R-1' '시리얼 포트' $(if ($ports.Count) { $ports -join ', ' } else { '없음' })
$pp = Join-Path $ws 'ai_changes\c5dprobe\GtecProbe5d.csproj'
$o = & dotnet build $pp -c Debug -v q -nologo 2>&1; $bc = $LASTEXITCODE
Check 'R-2' '실장비 도구(GtecProbe5d) 빌드' ($bc -eq 0) "exit $bc"
Check 'R-3' '실서버 응답 파일 준비 (ai_changes\c5d_real\server)' ((@('protocols_GTEC.json', 'data_tags.json', 'data_map.json') | Where-Object { (Test-Path (Join-Path $sd $_)) -and ((Get-Item (Join-Path $sd $_)).Length -gt 50) }).Count -eq 3) $sd
Info 'R-4' 'COM3 연결' $(if ($ports -contains 'COM3') { 'COM3 있음 → 회귀 실행 가능' } else { 'COM3 없음 → 장비 연결 후 실행 (미검증)' })
Done 'C5D-CONNECT-DONE'

# C5c 서버 배포 사전 검증 (2026-11-14). 실제 WAR 교체·main 병합·실제 DB 변경 없음.
#  1 브랜치 포함 관계  2 실제 DB 06·08 상태(읽기)  3 현재 8081·WAR·setenv(이름만)  4 Jenkins(읽기)  5 Desktop 설정
#  6 빌드 5종(feature/collect-c5d)  7 실서버 회귀(ai_c4srv.ps1 -C5d, 테스트 DB)  8 Tomcat 배포·복구 리허설(별도 CATALINA_BASE 18082, 테스트 DB)
#  9 실제 DB·8081 무변경 확인
# 비밀 값(DB 비밀번호·JWT secret·Client Key·사용자 비밀번호)은 로그에 쓰지 않는다 (이름·길이 판정만).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$src = Join-Path $ws 'ai_changes\c5cdep'
$log = Join-Path $ws ("ai_c5c_deploy_pre_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $src | Out-Null
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
$script:fail = 0; $script:rows = @()
function Check([string]$id, [string]$name, [bool]$ok, [string]$note) {
    $r = $(if ($ok) {'PASS'} else {'FAIL'}); if (-not $ok) { $script:fail++ }
    $script:rows += ("| {0} | {1} | {2} | {3} |" -f $id, $name, $note, $r); Log ("  [$r] $id $name $note")
}
function Info([string]$id, [string]$name, [string]$note) { $script:rows += ("| {0} | {1} | {2} | INFO |" -f $id, $name, $note); Log ("  [INFO] $id $name $note") }
function Summary {
    Log ''; Log '===== 요약 ====='
    Log '| # | 항목 | 내용 | 결과 |'; Log '|---|---|---|---|'
    foreach ($x in $script:rows) { Log $x }
    Log ("FAIL " + $script:fail)
}
function Halt([string]$why) { Log ("중단: " + $why); Cleanup; $env:MYSQL_PWD = $null; Summary; Log 'C5C-DEP-PRE-STOPPED'; exit 1 }
function Git([string]$a) { return @(cmd /c "git -C `"$jp`" $a 2>&1") }

$jp = Join-Path $ws 'juprovider'
$tc = 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52'
$bin = 'C:\Program Files\MariaDB 10.6\bin'
$lock = 'juprovider.frontvue/package-lock.json'
$tb = Join-Path $src 'tcbase'
$TD = 'juprovider_c5cdep'
$script:tbPid = $null
function Cleanup {
    if (Test-Path $tb) {
        $env:CATALINA_HOME = $tc; $env:CATALINA_BASE = $tb
        if (@(Get-NetTCPConnection -LocalPort 18082 -State Listen -ErrorAction SilentlyContinue).Count -gt 0) { cmd /c "`"$tc\bin\shutdown.bat`" >nul 2>&1"; Start-Sleep -Seconds 5 }
        Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tb) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        $env:CATALINA_BASE = $null; $env:CATALINA_HOME = $null
    }
    foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
    if ($script:base) { cmd /c "$($script:base) -e `"DROP DATABASE IF EXISTS $TD`"" | Out-Null }
}
Log ("C5c deploy precheck " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " " + $env:COMPUTERNAME)

# ---------------------------------------------------------------- 1
Log ''; Log '===== 1. 배포 후보 브랜치 · 포함 관계 ====='
Git 'fetch -q origin' | ForEach-Object { Log ('  ' + $_) }
$cur = @(Git 'rev-parse --abbrev-ref HEAD')[0]; $head = @(Git 'log -1 --format=%h')[0]
Log "  현재 $cur @ $head"
$exp = [ordered]@{ 'main' = 'fce5048'; 'feature/collect-c5b' = 'c8474c6'; 'feature/collect-c5c' = '6e744be'; 'feature/collect-c5d' = '4915759' }
$okRef = $true
foreach ($k in $exp.Keys) {
    $l = @(Git "rev-parse --short $k")[0]; $o = @(Git "rev-parse --short origin/$k")[0]
    Log ("  {0,-22} local {1} / origin {2} (기대 {3})" -f $k, $l, $o, $exp[$k])
    if ($l -ne $exp[$k] -or $o -ne $exp[$k]) { $okRef = $false }
}
Check 'B-1' '브랜치 HEAD = 기록값 (local·origin)' $okRef 'main fce5048 · c5b c8474c6 · c5c 6e744be · c5d 4915759'
$anc = @()
foreach ($p in @('main feature/collect-c5b', 'feature/collect-c5b feature/collect-c5c', 'feature/collect-c5c feature/collect-c5d', 'feature/integration-1 feature/collect-c5d', 'feature/sec-s1 feature/collect-c5d', 'feature/web-01 feature/collect-c5d', 'feature/protocol-ref feature/collect-c5d', 'feature/collect-c4 feature/collect-c5d')) {
    $a, $b = $p.Split(' '); cmd /c "git -C `"$jp`" merge-base --is-ancestor origin/$a origin/$b" | Out-Null
    $anc += ("{0}⊂{1}:{2}" -f $a, $b, $(if ($LASTEXITCODE -eq 0) {'Y'} else {'N'}))
}
Log ('  ' + ($anc -join ', '))
Check 'B-2' 'c5b ⊂ c5c ⊂ c5d, 이전 단계(INT-1·SEC-S1·WEB·PR·C4) 모두 c5d 에 포함' (@($anc | Where-Object { $_ -match ':N$' }).Count -eq 0) ''
$behind = @(Git 'rev-list --count origin/feature/collect-c5d..origin/main')[0]; $ahead = @(Git 'rev-list --count origin/main..origin/feature/collect-c5d')[0]
Check 'B-3' 'main → c5d fast-forward 가능 (main 이 c5d 에 없는 commit 0)' ($behind -eq '0') "main 뒤 $ahead commit, main 만의 commit $behind"
$srv = @(Git 'diff --stat origin/feature/collect-c5c origin/feature/collect-c5d -- juprovider.core juprovider.backend juprovider.frontvue')
Log '  c5c → c5d 서버 쪽 변경:'; $srv | ForEach-Object { Log ('    ' + $_) }
$hasRegex = @(Git 'show --stat --format=%h origin/feature/collect-c5d -- juprovider.core/src/main') -match 'ProtocolRules.java'
Check 'B-4' '서버 배포 후보 = c5d @ 4915759 (C5c + regex 보완 D3 포함)' ([bool]$hasRegex) 'regex 보완(ProtocolRules.java)은 c5d 에만 있음 → c5c 브랜치 단독 배포 시 D3 누락'
$jf = @(Git 'diff --name-only origin/main origin/feature/collect-c5d -- Jenkinsfile juprovider.backend/pom.xml juprovider.core/pom.xml juprovider.frontvue/package.json juprovider.backend/src/main/resources/application.yml')
Check 'B-5' 'Jenkinsfile·pom·package.json·application.yml 변경 없음 (main 대비)' ($jf.Count -eq 0) ($jf -join ', ')
$migs = @(Git 'ls-tree --name-only origin/feature/collect-c5d database/migration/') | ForEach-Object { Split-Path $_ -Leaf }
Info 'B-6' 'c5d migration 파일' ($migs -join ', ')
# 작업 폴더를 c5d 로
$st = @(Git 'status --porcelain' | Where-Object { $_ -and ($_ -notmatch [regex]::Escape($lock)) })
Git 'status --porcelain' | ForEach-Object { Log ('  status ' + $_) }
if ($st.Count -ne 0) { Halt '작업 폴더 변경 있음 (package-lock 제외)' }
if ($cur -ne 'feature/collect-c5d') { Git 'checkout -q feature/collect-c5d' | ForEach-Object { Log ('  ' + $_) } }
$cur = @(Git 'rev-parse --abbrev-ref HEAD')[0]; $head = @(Git 'log -1 --format=%h')[0]
if ($cur -ne 'feature/collect-c5d' -or $head -ne '4915759') { Halt "c5d checkout 실패: $cur @ $head" }
Log "  작업 폴더 → $cur @ $head"

# ---------------------------------------------------------------- 2
Log ''; Log '===== 2. 실제 DB 06·08 상태 (읽기만) ====='
$vars = @{}
foreach ($l in Get-Content (Join-Path $tc 'bin\setenv.bat')) { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']; $U = $vars['JU_DB_USER']
$script:base = "`"$bin\mysql.exe`" -h localhost -u $U --default-character-set=utf8mb4"
function Q([string]$db, [string]$sql) {
    $f = Join-Path $src 'q.sql'
    [IO.File]::WriteAllText($f, "SET NAMES utf8mb4;`n" + $sql + "`n", $enc)
    $o = cmd /c "$($script:base) -N -B $db < `"$f`" 2>&1"; Remove-Item $f -Force
    return @($o)
}
function Q1([string]$db, [string]$sql) { return ([string]((Q $db $sql) -join ' ')).Trim() }
$dumpCmp = @('-h', 'localhost', '-u', $U, '--default-character-set=utf8mb4', '--skip-comments', '--skip-dump-date', '--order-by-primary', '--skip-extended-insert', '--routines', '--triggers')
function Snap([string]$db, [string]$name) { $f = Join-Path $src ("snap_$name.sql"); & "$bin\mysqldump.exe" @dumpCmp "--result-file=$f" $db 2>&1 | Out-Null; return $f }
function HashOf([string]$f) { return (Get-FileHash $f -Algorithm SHA256).Hash.Substring(0, 16) }
$n6 = Q1 'juprovider' "SELECT CONCAT(COUNT(*), '/', SUM(a.USE_YN='YENO0001')) FROM ju_menu_action a JOIN ju_menu m ON m.MNU_ID=a.MNU_ID WHERE m.MNU_CD='M02010100'"
Check 'D-1' '06 적용 (M02010100 Action 10/활성 10)' ($n6 -eq '10/10') $n6
$v1 = Q1 'juprovider' "SELECT CONCAT_WS('|',(SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND COLUMN_NAME IN ('FRAME_RULE','CMD_GAP_MS','INIT_ROUTINE','INIT_DELAY_MS','PTL_ROLES','PTL_ACTION','EXPECT_RULE','IDEMPOTENT_YN')),(SELECT COUNT(*) FROM ju_protocol WHERE PTL_ROLES IS NOT NULL),(SELECT COUNT(*) FROM ju_data_channel_map),(SELECT CMD_GAP_MS FROM ju_protocol_group WHERE PTL_GRP_CD='GTEC'),(SELECT COUNT(*) FROM ju_com_code WHERE GRP_CD IN ('PROL','PACT')),(SELECT COUNT(*) FROM ju_mig08_bak_protocol))"
Check 'D-2' '08 적용 (컬럼 8·정정 7·매핑 4·간격 200·코드 7·백업 7)' ($v1 -eq '8|7|4|200|7|7') $v1
$s07 = Q1 'juprovider' "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_schema_version'"
Info 'D-3' '07(ju_schema_version) — c5d 에 07 파일 없음, 적용 대상 아님' "테이블 $s07"
$sNow = Snap 'juprovider' 'now'; $hNow = HashOf $sNow
$same = ($hNow -eq '12CD3AA09A237DBC')
$note = "덤프 $hNow (C5e 적용 직후 12CD3AA09A237DBC)"
if (-not $same) {
    $old = Join-Path $ws 'ai_changes\c5e\snap_after.sql'
    if (Test-Path $old) {
        $a = @(Get-Content $old -Encoding UTF8 | Where-Object { $_ -match '^INSERT INTO `([^`]+)`' }); $b = @(Get-Content $sNow -Encoding UTF8 | Where-Object { $_ -match '^INSERT INTO `([^`]+)`' })
        $d = @(Compare-Object $a $b | ForEach-Object { if ($_.InputObject -match '^INSERT INTO `([^`]+)`') { $matches[1] + $_.SideIndicator } } | Group-Object | ForEach-Object { $_.Name + ' x' + $_.Count })
        $note += ' · 바뀐 행(테이블별, 값은 기록 안 함): ' + ($d -join ', ')
    } else { $note += ' · 적용 직후 스냅숏 없음' }
}
Info 'D-4' '적용 직후 대비 실제 DB 변화 (8081 구 WAR 가 계속 사용 중)' $note
$cl = @(Q 'juprovider' "SELECT CONCAT(CLIENT_ID, ':', USE_YN, ':', IFNULL(DATE_FORMAT(LAST_SEEN_DT,'%m/%d %H:%i'),'-')) FROM ju_client ORDER BY CLIENT_ID" | Where-Object { $_ })
Info 'D-5' 'Desktop Client 등록 (ju_client, 키 해시는 출력 안 함)' ("" + $cl.Count + "개: " + ($cl -join ', '))
$us = Q1 'juprovider' "SELECT CONCAT(COUNT(*), ' / 어드민 ', SUM(a.AUTH_TYPE='AUTH0001'), ' / 활성 ', SUM(u.USE_YN='YENO0001')) FROM ju_user u JOIN ju_auth a ON a.AUTH_ID=u.AUTH_ID"
$af = Q1 'juprovider' "SELECT CONCAT(IFNULL(SUM(AUTH_ATTR REGEXP '`"M[0-9]{8}`"'),0), '/', COUNT(AUTH_ATTR)) FROM ju_auth"
Check 'D-6' '05 인증 데이터 (사용자·어드민 존재, AUTH_ATTR 11자리 형식)' (($us -match '/ 어드민 [1-9]') -and ($af -match '^0/')) "사용자 $us, AUTH_ATTR 9자리(미변환)/전체 $af"
$left0 = @(Q '' "SHOW DATABASES LIKE 'juprovider%'" | Where-Object { $_ })
Info 'D-7' '남은 DB' ($left0 -join ', ')

# ---------------------------------------------------------------- 3
Log ''; Log '===== 3. 현재 8081 · 배포 WAR · setenv ====='
$procs = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' -and $_.CommandLine -notmatch 'c5cdep' })
$pid0 = $(if ($procs.Count) { $procs[0].ProcessId } else { 0 })
Info 'T-1' '8081 Tomcat' ("listen " + @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count + ", PID $pid0" + $(if ($procs.Count) { ', 시작 ' + $procs[0].CreationDate.ToString('MM/dd HH:mm') } else { '' }))
$war0 = Join-Path $tc 'webapps\juprovider.war'
$warHash = ''
if (Test-Path $war0) {
    $wi = Get-Item $war0; $warHash = (Get-FileHash $war0 -Algorithm SHA256).Hash
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($war0)
    $names = @($z.Entries | ForEach-Object { $_.FullName })
    $pp = $z.Entries | Where-Object { $_.FullName -match 'META-INF/maven/.*/pom.properties$' } | Select-Object -First 1
    $ver = ''; if ($pp) { $sr = New-Object IO.StreamReader($pp.Open()); $ver = (($sr.ReadToEnd() -split "`n") | Where-Object { $_ -match '^(artifactId|version)=' }) -join ' '; $sr.Close() }
    $z.Dispose()
    $has = foreach ($c in 'config/SecurityConfig', 'config/JwtConfig', 'security/ClientKeyAuthenticationFilter', 'controller/AuthController', 'controller/ProtocolSyncController') { $c.Split('/')[-1] + '=' + [bool]($names -contains "WEB-INF/classes/com/asdp/juprovider/$c.class") }
    Info 'T-2' '배포 WAR (복구 대상)' ($wi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + ", " + $wi.Length + " bytes, SHA256 " + $warHash.Substring(0, 16) + ", " + $ver.Trim())
    Info 'T-3' '배포 WAR 구성 (인증 클래스 유무)' ($has -join ', ')
} else { Check 'T-2' '배포 WAR 있음' $false $war0 }
$names = @(Get-Content (Join-Path $tc 'bin\setenv.bat') | ForEach-Object { if ($_ -match '^\s*set\s+"?([A-Za-z_]+)=') { $matches[1] } })
Info 'T-4' 'setenv.bat 변수 이름 (값은 기록 안 함)' ($names -join ', ')
$jl = ([string]$vars['JU_JWT_SECRET']).Length
Check 'T-5' 'JU_JWT_SECRET 있음·32바이트 이상 (c5d 기동 필수)' ([Text.Encoding]::UTF8.GetByteCount([string]$vars['JU_JWT_SECRET']) -ge 32) $(if ($jl -gt 0) {'설정됨'} else {'없음'})
Check 'T-6' 'JU_DB_URL·JU_DB_USER·JU_DB_PASSWORD 있음' (($vars['JU_DB_URL']) -and ($vars['JU_DB_USER']) -and ($vars['JU_DB_PASSWORD'])) ''
$bkd = Join-Path $tc 'backup'
$bks = @(Get-ChildItem $bkd -Filter '*.war' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { $_.Name + ' ' + $_.LastWriteTime.ToString('MM/dd') })
Info 'T-7' 'Tomcat backup 폴더 (Jenkins WAR 백업 위치)' $(if (Test-Path $bkd) { "" + @(Get-ChildItem $bkd -Filter '*.war').Count + "개 " + ($bks -join ', ') } else { '폴더 없음' })
$free = [Math]::Round((Get-PSDrive C).Free / 1GB, 1)
Check 'T-8' '디스크 여유' ($free -gt 5) "$free GB"
$ctx = Join-Path $tc 'conf\Catalina\localhost'
Info 'T-9' 'conf\Catalina\localhost 컨텍스트 파일' $(if (Test-Path $ctx) { (@(Get-ChildItem $ctx | ForEach-Object { $_.Name }) -join ', ') } else { '없음' })

# ---------------------------------------------------------------- 4
Log ''; Log '===== 4. Jenkins (읽기만) ====='
$svc = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'jenkins' -or $_.DisplayName -match 'jenkins' })
foreach ($s in $svc) { Info 'J-1' 'Jenkins 서비스' ($s.Name + ' ' + $s.State + ' ' + $s.StartMode + ' 계정 ' + $s.StartName) }
if ($svc.Count -eq 0) { Info 'J-1' 'Jenkins 서비스' '없음' }
$homes = @()
foreach ($s in $svc) {
    $exe = ([string]$s.PathName).Trim('"').Split('"')[0]; $xml = Join-Path (Split-Path $exe) 'jenkins.xml'
    if (Test-Path $xml) { $t = Get-Content $xml -Raw; if ($t -match 'JENKINS_HOME"\s+value="([^"]+)"') { $homes += [Environment]::ExpandEnvironmentVariables($matches[1]) } }
}
$homes += @($env:JENKINS_HOME, "$env:ProgramData\Jenkins\.jenkins", "$env:LOCALAPPDATA\Jenkins\.jenkins", "$env:USERPROFILE\.jenkins", 'C:\Windows\System32\config\systemprofile\AppData\Local\Jenkins\.jenkins', 'C:\Windows\ServiceProfiles\LocalService\AppData\Local\Jenkins\.jenkins') | Where-Object { $_ }
$jh = $null
foreach ($h in $homes) { try { if (Test-Path (Join-Path $h 'config.xml') -ErrorAction Stop) { $jh = $h; break } } catch { Log ("  접근 불가: $h") } }
try { $jr = Invoke-WebRequest 'http://localhost:8080/login' -UseBasicParsing -TimeoutSec 10; $jc = [int]$jr.StatusCode } catch { $jc = $(if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { -1 }) }
Info 'J-2' 'Jenkins HTTP 8080 /login' "HTTP $jc"
if ($jh) {
    $cfg = Get-Content (Join-Path $jh 'config.xml') -Raw
    $jv = $(if ($cfg -match '<version>([^<]+)</version>') { $matches[1] } else { '?' })
    $ev = @([regex]::Matches($cfg, '<string>([A-Z_]+)</string>\s*<string>([^<]*)</string>') | ForEach-Object { $n = $_.Groups[1].Value; $n + '=' + $(if ($n -match 'HOME$|PATH$') { $_.Groups[2].Value } else { '(설정됨)' }) })
    Info 'J-3' 'JENKINS_HOME · 버전 · 전역 환경변수' ("$jh · $jv · " + ($ev -join ', '))
    foreach ($j in @(Get-ChildItem (Join-Path $jh 'jobs') -Directory -ErrorAction SilentlyContinue)) {
        $cx = Join-Path $j.FullName 'config.xml'; if (-not (Test-Path $cx)) { continue }
        $t = Get-Content $cx -Raw
        $urls = @([regex]::Matches($t, '<url>([^<]+)</url>') | ForEach-Object { $_.Groups[1].Value }) -join ' '
        $brs = @([regex]::Matches($t, '<hudson.plugins.git.BranchSpec>\s*<name>([^<]+)</name>') | ForEach-Object { $_.Groups[1].Value }) -join ','
        $sp = $(if ($t -match '<scriptPath>([^<]+)</scriptPath>') { $matches[1] } else { '' })
        $trg = @([regex]::Matches($t, '<(hudson\.triggers\.\w+|com\.cloudbees\.jenkins\.\w+|org\.jenkinsci\.plugins\.\w+Trigger\w*)[ >]') | ForEach-Object { $_.Groups[1].Value.Split('.')[-1] }) -join ','
        $spec = @([regex]::Matches($t, '<spec>([^<]*)</spec>') | ForEach-Object { $_.Groups[1].Value }) -join ' | '
        $dis = $(if ($t -match '<disabled>true</disabled>') { ' (disabled)' } else { '' })
        $root = $(if ($t -match '<\?xml[^>]*>\s*<([\w.-]+)') { $matches[1] } else { '?' })
        Info 'J-4' ("job " + $j.Name + $dis) ("$root · scm $urls · branch $brs · script $sp · trigger [$trg] $spec")
        $bd = @(Get-ChildItem (Join-Path $j.FullName 'builds') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' } | Sort-Object { [int]$_.Name } -Descending | Select-Object -First 3)
        foreach ($b in $bd) {
            $bx = Join-Path $b.FullName 'build.xml'; if (-not (Test-Path $bx)) { continue }
            $t2 = Get-Content $bx -Raw
            $res = $(if ($t2 -match '<result>(\w+)</result>') { $matches[1] } else { '?' })
            $ts = $(if ($t2 -match '<timestamp>(\d+)</timestamp>') { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$matches[1]).LocalDateTime.ToString('yyyy-MM-dd HH:mm') } else { '?' })
            $sha = $(if ($t2 -match '<SHA1>([0-9a-f]{7})[0-9a-f]{33}</SHA1>') { $matches[1] } else { '?' })
            Log ("    #" + $b.Name + " $res $ts rev $sha")
        }
    }
} else { Info 'J-3' 'JENKINS_HOME' ('찾지 못함 또는 접근 불가: ' + (($homes | Select-Object -Unique) -join '; ')) }

# ---------------------------------------------------------------- 5
Log ''; Log '===== 5. Desktop 설정 (PC-B) ====='
$cj = Join-Path $jp 'desktop\app\config\client.json'
if (Test-Path $cj) {
    try {
        $o = Get-Content $cj -Raw -Encoding UTF8 | ConvertFrom-Json
        $kv = @($o.PSObject.Properties | ForEach-Object { $_.Name + '=' + $(if ($_.Name -match 'Url$|Id$') { [string]$_.Value } else { '(값 생략)' }) })
        Info 'K-1' 'client.json (Url·Id 만)' ($kv -join ', ')
        $cid = @($o.PSObject.Properties | Where-Object { $_.Name -match 'ClientId$' } | ForEach-Object { [string]$_.Value })[0]
        if ($cid) { $reg = Q1 'juprovider' "SELECT COUNT(*) FROM ju_client WHERE CLIENT_ID='$($cid -replace "'", '')' AND USE_YN='YENO0001'"; Info 'K-2' 'client.json ClientId 가 실제 DB 에 등록·사용 중' "$cid → $reg" }
    } catch { Info 'K-1' 'client.json' ('읽기 실패 ' + $_.Exception.Message) }
} else { Info 'K-1' 'client.json' '없음' }

# ---------------------------------------------------------------- 6
Log ''; Log '===== 6. 빌드 5종 + 테스트 (feature/collect-c5d) ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Check 'G-1' '빌드 5종' $false '요약 없음' } else {
    $sum = $bl[$si..($bl.Length - 1)]; $sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
    Check 'G-1' '빌드 5종 + 테스트' (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0) ''
}
$t34 = @($bl | Select-String -Pattern 'Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: \d+$')
Info 'G-2' '서버 테스트 합계 (core·backend)' (($t34 | ForEach-Object { $_.Line.Trim() -replace '^\[\w+\]\s*', '' }) -join ' / ')
$dn = @($bl | Select-String -Pattern '(통과|실패)!.*' | ForEach-Object { $_.Matches[0].Value })
Info 'G-3' 'Desktop 테스트' ($dn -join ' / ')
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($script:fail -gt 0 -or -not (Test-Path $war)) { Halt '빌드 FAIL → 이후 검증 생략' }
$wh = (Get-FileHash $war -Algorithm SHA256).Hash
Info 'G-4' '후보 WAR' ((Get-Item $war).Length.ToString() + " bytes, SHA256 " + $wh.Substring(0, 16) + " (Jenkins 빌드는 별도 산출물)")

# ---------------------------------------------------------------- 7
Log ''; Log '===== 7. 실서버 회귀 + Client Key/JWT (ai_c4srv.ps1 -C5d, 테스트 DB = 실제 DB 사본) ====='
$env:MYSQL_PWD = $null
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_c4srv.ps1') -C5d *>&1 | Out-Null
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$sl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_c5d_srv_{0}.log" -f $env:COMPUTERNAME))
$ri = [Array]::IndexOf($sl, '===== 요약 =====')
if ($ri -lt 0) { Check 'R-0' '실서버 회귀' $false ('요약 없음: ' + ($sl | Select-Object -Last 3) -join ' ') } else {
    $rr = $sl[$ri..($sl.Length - 1)]
    $rr | Where-Object { $_ -match '^\| [0-9]' } | ForEach-Object { Log ('  ' + $_) }
    $pN = @($rr | Where-Object { $_ -match '\| PASS \|$' }).Count; $fN = @($rr | Where-Object { $_ -match '\| FAIL \|$' }).Count
    $dupe = @($sl | Select-String '06 적용\(테스트 DB\) exit|08 적용\(테스트 DB\) exit' | ForEach-Object { $_.Line.Trim() }) -join ', '
    Check 'R-1' '실서버 회귀 전체 (인증·Client Key·JWT·Action·sync·C5c API·서버값 계획)' (($fN -eq 0) -and ($pN -gt 50)) "PASS $pN / FAIL $fN"
    Info 'R-2' '06·08 재실행 (이미 적용된 실제 DB 사본에)' $dupe
    $auth = @($rr | Where-Object { $_ -match '^\| (9-(2|3|4|5|7|10)|11-6|10-1|7-1) \|' } | ForEach-Object { ($_ -split '\|')[1].Trim() + ':' + ($_ -split '\|')[-2].Trim() })
    Info 'R-3' '인증 관련 항목' ($auth -join ', ')
}

# ---------------------------------------------------------------- 8
Log ''; Log '===== 8. Tomcat 배포·복구 리허설 (별도 CATALINA_BASE, 18082, 테스트 DB) ====='
foreach ($p in 18082, 18005) { if (@(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue).Count -gt 0) { Halt "$p 사용 중" } }
if (Test-Path $tb) { Remove-Item $tb -Recurse -Force }
foreach ($d in 'logs_candidate', 'logs_restore') { Remove-Item (Join-Path $src $d) -Recurse -Force -ErrorAction SilentlyContinue }
foreach ($d in 'conf', 'bin', 'logs', 'temp', 'webapps', 'work') { New-Item -ItemType Directory -Force -Path (Join-Path $tb $d) | Out-Null }
Get-ChildItem (Join-Path $tc 'conf') -File | Copy-Item -Destination (Join-Path $tb 'conf')
$sx = Join-Path $tb 'conf\server.xml'
$x = Get-Content $sx -Raw -Encoding UTF8
$x = $x -replace 'port="8081"', 'port="18082"' -replace 'port="8005"', 'port="18005"' -replace 'port="8009"', 'port="18009"' -replace 'port="8443"', 'port="18443"' -replace 'port="8080"', 'port="18080"' -replace 'redirectPort="8443"', 'redirectPort="18443"'
[IO.File]::WriteAllText($sx, $x, $enc)
$ports = @([regex]::Matches($x, '(?<!redirect)port="(\d+)"') | ForEach-Object { $_.Groups[1].Value }) -join ','
Log "  server.xml 포트 → $ports"
if ($ports -match '(^|,)(8005|8081|8080|8009|8443)(,|$)') { Halt 'server.xml 포트 변경 실패' }
# setenv: JU_* 는 이 프로세스 환경으로만 넘기고 파일에 쓰지 않는다. 그 외(JRE_HOME 등) 줄만 복사
$se = @(Get-Content (Join-Path $tc 'bin\setenv.bat') | Where-Object { $_ -notmatch '^\s*set\s+"?JU_' })
[IO.File]::WriteAllLines((Join-Path $tb 'bin\setenv.bat'), $se)
Log ("  setenv(리허설): JU_* 제외 " + $se.Count + "줄 복사")
cmd /c "$($script:base) -e `"DROP DATABASE IF EXISTS $TD; CREATE DATABASE $TD CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`"" | Out-Null
$dump = Join-Path $src 'rehearsal_dump.sql'
& "$bin\mysqldump.exe" -h localhost -u $U --default-character-set=utf8mb4 --single-transaction --routines --triggers --hex-blob "--result-file=$dump" juprovider 2>&1 | Out-Null
cmd /c "$($script:base) $TD < `"$dump`"" | Out-Null; $lx = $LASTEXITCODE; Remove-Item $dump -Force
Check 'H-0' '리허설 DB = 실제 DB 사본 (06·08 적용 상태)' (($lx -eq 0) -and ((Q1 $TD "SELECT COUNT(*) FROM ju_data_channel_map") -eq '4')) "적재 exit $lx"
Copy-Item $war0 (Join-Path $src 'old.war') -Force
function TStart {
    $env:CATALINA_HOME = $tc; $env:CATALINA_BASE = $tb
    $env:JU_DB_URL = ($vars['JU_DB_URL'] -replace '(jdbc:mariadb://[^/]+/)juprovider', ('${1}' + $TD))
    $env:JU_DB_USER = $vars['JU_DB_USER']; $env:JU_DB_PASSWORD = $vars['JU_DB_PASSWORD']; $env:JU_JWT_SECRET = $vars['JU_JWT_SECRET']
    if ($env:JU_DB_URL -notmatch $TD) { Halt '리허설 DB URL 치환 실패' }
    Start-Process cmd.exe -ArgumentList '/c', "`"$tc\bin\startup.bat`"" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
    $env:CATALINA_BASE = $null; $env:CATALINA_HOME = $null
}
function TStop {
    $env:CATALINA_HOME = $tc; $env:CATALINA_BASE = $tb
    cmd /c "`"$tc\bin\shutdown.bat`" >nul 2>&1"
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; if (@(Get-NetTCPConnection -LocalPort 18082 -State Listen -ErrorAction SilentlyContinue).Count -eq 0) { break } }
    $left = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tb) })
    $left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $env:CATALINA_BASE = $null; $env:CATALINA_HOME = $null
    Start-Sleep -Seconds 2
    return ($left.Count -eq 0)
}
function Http([string]$method, [string]$url, [string]$body) {
    try {
        $p = @{ Uri = $url; Method = $method; UseBasicParsing = $true; TimeoutSec = 15 }
        if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json; charset=utf-8' }
        $r = Invoke-WebRequest @p; return @{ code = [int]$r.StatusCode; body = [string]$r.Content }
    } catch {
        $c = -1; $b = ''
        if ($_.Exception.Response) { $c = [int]$_.Exception.Response.StatusCode; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream(), [Text.Encoding]::UTF8); $b = $sr.ReadToEnd() } catch {} }
        return @{ code = $c; body = $b }
    }
}
function WaitUp([int]$sec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $sec) { $h = Http 'GET' "$api/api/health" ''; if ($h.code -eq 200) { return @{ h = $h; s = [int]$sw.Elapsed.TotalSeconds } }; Start-Sleep -Seconds 2 }
    return @{ h = $h; s = [int]$sw.Elapsed.TotalSeconds }
}
function TLogErr { $t0 = $script:tStart; return @(Get-ChildItem (Join-Path $tb 'logs') -File | Where-Object { $_.Name -notmatch 'access' } | ForEach-Object { Get-Content $_.FullName -Encoding UTF8 } | Select-String -Pattern 'SEVERE|ERROR|Exception' | ForEach-Object { $_.Line }) }
$api = 'http://localhost:18082/juprovider'

Log '  -- 8-1 후보 WAR(c5d) 배포 (Jenkins 7~10단계와 같은 순서: 정리 → 복사 → startup.bat → health) --'
Copy-Item $war (Join-Path $tb 'webapps\juprovider.war') -Force
TStart
$w = WaitUp 180
$hj = $null; try { $hj = $w.h.body | ConvertFrom-Json } catch {}
Check 'H-1' '후보 WAR Tomcat 기동 · health (Jenkins 기준 success=true, status=UP)' (($w.h.code -eq 200) -and ($hj.success -eq $true) -and ($hj.data.status -eq 'UP')) ("HTTP " + $w.h.code + ", " + $w.s + "초")
$r = Http 'POST' "$api/api/auth/login" '{"loginId":"c5cdep_no_user","password":"wrong-pw-000"}'; Check 'H-2' '없는 사용자 로그인 → 401 (main 기준)' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/api/core/sync/devices" ''; Check 'H-3' 'sync/devices 키 없음 → 401 (현재 배포본 200 해소)' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/api/core/sync/data-map?devCd=SDEV_GTEC01" ''; Check 'H-4' 'sync/data-map 키 없음 → 401' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/api/core/languages" ''; Check 'H-5' 'JWT 없는 /api/core/languages → 401' ($r.code -eq 401) ("HTTP " + $r.code)
$r = Http 'GET' "$api/" ''; Check 'H-6' '공개 홈 GET /' ($r.code -eq 200) ("HTTP " + $r.code)
$r = Http 'GET' "$api/console/protocols" ''; Info 'H-7' '콘솔 경로 직접 접근 (SPA)' ("HTTP " + $r.code)
$e1 = TLogErr
Check 'H-8' 'Tomcat 로그 SEVERE/ERROR/Exception (후보 WAR)' ($e1.Count -eq 0) ("" + $e1.Count + "건")
$e1 | Select-Object -First 6 | ForEach-Object { Log ('    ' + $_.Substring(0, [Math]::Min(220, $_.Length))) }
$stopOk = TStop
Check 'H-9' 'shutdown.bat 로 정상 종료' $stopOk ''
Copy-Item (Join-Path $tb 'logs') (Join-Path $src 'logs_candidate') -Recurse -Force

Log '  -- 8-2 복구 리허설: 백업 WAR(현재 배포본)로 되돌림 --'
Remove-Item (Join-Path $tb 'webapps\juprovider') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $tb 'webapps\juprovider.war') -Force
Get-ChildItem (Join-Path $tb 'logs') -File | Remove-Item -Force
Get-ChildItem (Join-Path $tb 'work') | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $src 'old.war') (Join-Path $tb 'webapps\juprovider.war') -Force
TStart
$w = WaitUp 180
Check 'H-10' '백업 WAR 로 복구 → health 200 (06·08 DB 에서)' ($w.h.code -eq 200) ("HTTP " + $w.h.code + ", " + $w.s + "초")
$r = Http 'GET' "$api/api/core/sync/devices" ''; Check 'H-11' '복구본 확인 (구 WAR 동작: sync/devices 키 없이 200)' ($r.code -eq 200) ("HTTP " + $r.code)
$e2 = TLogErr
Info 'H-12' 'Tomcat 로그 SEVERE/ERROR/Exception (복구본)' ("" + $e2.Count + "건")
$stopOk = TStop
Copy-Item (Join-Path $tb 'logs') (Join-Path $src 'logs_restore') -Recurse -Force

Log '  -- 8-3 정리 --'
Remove-Item $tb -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $src 'old.war') -Force -ErrorAction SilentlyContinue
cmd /c "$($script:base) -e `"DROP DATABASE IF EXISTS $TD`"" | Out-Null
$left = @(Q '' "SHOW DATABASES LIKE 'juprovider%'" | Where-Object { $_ })
Check 'H-13' '리허설 정리 (18082 닫힘, 임시 DB·폴더 삭제)' ((@(Get-NetTCPConnection -LocalPort 18082 -State Listen -ErrorAction SilentlyContinue).Count -eq 0) -and -not (Test-Path $tb) -and ($left.Count -eq $left0.Count)) ("남은 DB " + ($left -join ', '))

# ---------------------------------------------------------------- 9
Log ''; Log '===== 9. 실제 환경 무변경 ====='
$hEnd = HashOf (Snap 'juprovider' 'end')
Check 'Z-1' '실제 DB 덤프 = 2절 시작 시점' ($hEnd -eq $hNow) "$hNow → $hEnd"
$procs = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'catalina' -and $_.CommandLine -notmatch 'c5cdep' })
$pid1 = $(if ($procs.Count) { $procs[0].ProcessId } else { 0 })
$h8081 = (Http 'GET' 'http://localhost:8081/juprovider/api/health' '').code
Check 'Z-2' '8081 그대로 (같은 프로세스, health 200)' (($pid1 -eq $pid0) -and ($h8081 -eq 200)) "PID $pid0 → $pid1, HTTP $h8081"
Check 'Z-3' '배포 WAR 그대로' ((Get-FileHash $war0 -Algorithm SHA256).Hash -eq $warHash) ''
$mh = @(Git 'rev-parse --short main')[0]; $om = @(Git 'rev-parse --short origin/main')[0]
Check 'Z-4' 'main 그대로 (local·origin fce5048)' (($mh -eq 'fce5048') -and ($om -eq 'fce5048')) "$mh / $om"
Get-ChildItem $src -Filter 'snap_*.sql' -ErrorAction SilentlyContinue | Remove-Item -Force
$env:MYSQL_PWD = $null
Summary
Log 'C5C-DEP-PRE-DONE'

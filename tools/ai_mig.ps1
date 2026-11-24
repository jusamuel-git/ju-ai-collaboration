# 로컬 DB 마이그레이션 개선 (11/24 승인): feature/local-db-migration (← 4409ade)
# DROP 재생성 제거, SCHEMA_VERSION 순차 마이그레이션, 백업·실패 복구, 지원하지 않는 스키마 오류.
# 파일 반영 → 빌드 5종 + 테스트 → 실제 앱(기존 설치 v1 재실행 · 신규 설치 · v0 DB 복사본 마이그레이션) → commit + push
# 사용자 DB(app\data)는 덮어쓰지 않는다(행 수·생성 시각 확인, v0 시험은 임시 폴더의 복사본). 서버·DB·WAR·Tomcat 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$src = Join-Path $ws 'ai_changes\mig'
$app = Join-Path $jp 'desktop\app'
$userDb = Join-Path $app 'data\juprovider.accdb'
$log = Join-Path $ws ("ai_mig_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { if ($x -notmatch 'LF will be replaced|original line endings') { Log ('  ' + $x) } }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'MIG-STOPPED'; exit 1 }
function Git1([string]$a) { return @(cmd /c "git -C `"$jp`" $a 2>nul")[0] }
function FileHash16([string]$p) { if (Test-Path $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 16) } else { return '(없음)' } }
function DbQuery([string]$db, [string]$sql) { $cn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$db;"); try { $cn.Open(); $c = $cn.CreateCommand(); $c.CommandText = $sql; return $c.ExecuteScalar() } catch { return ('ERR ' + $_.Exception.Message) } finally { $cn.Close(); [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool() } }
function DbExec([string]$db, [string]$sql) { $cn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$db;"); try { $cn.Open(); $c = $cn.CreateCommand(); $c.CommandText = $sql; [void]$c.ExecuteNonQuery(); return 'OK' } catch { return ('ERR ' + $_.Exception.Message) } finally { $cn.Close(); [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool() } }
function DbSummary([string]$db) { return ('LOCAL_DEVICE ' + (DbQuery $db 'SELECT COUNT(*) FROM LOCAL_DEVICE') + ', LOCAL_USER ' + (DbQuery $db 'SELECT COUNT(*) FROM LOCAL_USER') + ', SCHEMA_VERSION ' + (DbQuery $db "SELECT INFO_VALUE FROM LOCAL_SCHEMA_INFO WHERE INFO_KEY='SCHEMA_VERSION'")) }
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
$lock = 'juprovider.frontvue/package-lock.json'
$branch = 'feature/local-db-migration'; $base = '4409ade'
Log ("MIG " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 0. 상태 ====='
cmd /c "git -C `"$jp`" fetch -q origin 2>&1" | Out-Null
$cur = Git1 'rev-parse --abbrev-ref HEAD'; $head = Git1 'log -1 --format=%h'
Log "  $cur @ $head, origin/feature/local-db-template $(Git1 'rev-parse --short origin/feature/local-db-template'), origin/main $(Git1 'rev-parse --short origin/main')"
if (-not (($cur -eq 'feature/local-db-template' -or $cur -eq $branch) -and $head -eq $base)) { Stop "feature/local-db-template(또는 $branch) @ $base 가 아님" }
$st = @(& git -C $jp status --porcelain --untracked-files=all | Where-Object { $p = $_.Substring(3).Trim('"'); ($p -ne $lock) -and ($files -notcontains $p) })
if ($st.Count) { Stop ('예상 밖 변경: ' + ($st -join ', ')) }
foreach ($n in 'juprovider.client', 'juprovider.terminal') { foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) { Log "  $n PID $($p.Id) 종료 (빌드 잠금 방지)"; [void]$p.CloseMainWindow(); Start-Sleep -Seconds 3; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } }
$userCreated = (Get-Item $userDb).CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
Log ("  사용자 DB: " + (DbSummary $userDb) + ", 생성 시각 $userCreated")
if ($cur -ne $branch) {
    if (Git1 "rev-parse --verify --quiet refs/heads/$branch") { Stop "$branch 가 이미 있음" }
    if ((Run "git switch -c $branch") -ne 0) { Stop '브랜치 생성 실패' }
}
$now = Get-Date
foreach ($f in $files) { $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null; Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = $now }
Run 'git status --short' | Out-Null
Run 'git diff --stat' | Out-Null
$drop = @(Select-String -Path (Join-Path $jp 'desktop\lib\juprovider.lib.data\Local\*.cs') -Pattern 'DROP TABLE' | ForEach-Object { "$($_.Filename):$($_.LineNumber) $($_.Line.Trim())" })
Log ("  코드의 DROP TABLE: " + $(if ($drop.Count) { $drop -join ' | ' } else { '없음' }))

Log ''; Log '===== 1. 빌드 5종 + 테스트 ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Stop '빌드 요약 없음' }
$sum = $bl[$si..($bl.Length - 1)]
$sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
$bl | Select-String -Pattern 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$|(통과|실패)!.*' | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$bl | Select-String -Pattern 'error CS|warning CS|error MSB|\[실패\]|\[FAIL\]|Assert\.|실패 JuProvider' | Select-Object -First 60 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$buildOk = (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0)
$tr = Run 'dotnet test desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug --no-build --filter "FullyQualifiedName~LocalMigrationTests|FullyQualifiedName~LocalTemplateTests" --logger "console;verbosity=normal"'
Log ("  템플릿 해시 저장소 " + (FileHash16 (Join-Path $jp 'desktop\resources\template.accdb')) + " / app\config " + (FileHash16 (Join-Path $app 'config\template.accdb')) + " (4409ade 와 같아야 함: FE2B566F8D3281E2)")
if (-not $buildOk -or $tr -ne 0) { Stop '빌드·테스트 FAIL → commit 하지 않음' }

Log ''; Log '===== 2. 실제 앱 ====='
function AppRun([string]$dir, [string]$label) {
    $lf = Join-Path $dir ("logs\client_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
    $before = if (Test-Path $lf) { @(Get-Content -Encoding UTF8 $lf).Count } else { 0 }
    $p = Start-Process -FilePath (Join-Path $dir 'juprovider.client.exe') -WorkingDirectory $dir -PassThru
    Start-Sleep -Seconds 10
    $lines = if (Test-Path $lf) { @(Get-Content -Encoding UTF8 $lf | Select-Object -Skip $before) } else { @() }
    $lines | Where-Object { $_ -match '\[LOCAL DB' } | ForEach-Object { Log "  [$label] $_" }
    if (-not $p.HasExited) { [void]$p.CloseMainWindow(); Start-Sleep -Seconds 2; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
    [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool()
    return $lines
}
# 2-1 기존 설치(v1) 재실행: 마이그레이션 없음
$l1 = AppRun $app '기존 설치 v1'
$ok1 = (($l1 -match 'schema v1').Count -gt 0) -and (($l1 -match '마이그레이션 완료').Count -eq 0)
Log ("  사용자 DB 실행 후: " + (DbSummary $userDb) + ", 생성 시각 " + (Get-Item $userDb).CreationTime.ToString('yyyy-MM-dd HH:mm:ss') + $(if ((Get-Item $userDb).CreationTime.ToString('yyyy-MM-dd HH:mm:ss') -eq $userCreated) { ' (그대로)' } else { ' !! 바뀜' }))
# 2-2 임시 app 복사본 (client.json·connections.json·logs·cache·data 제외)
$tmpApp = Join-Path $src 'app_copy'
function FreshCopy { if (Test-Path $tmpApp) { Remove-Item $tmpApp -Recurse -Force }; robocopy $app $tmpApp /E /XD (Join-Path $app 'data') (Join-Path $app 'logs') (Join-Path $app 'cache') /XF client.json connections.json /NFL /NDL /NJH /NJS /NP | Out-Null }
FreshCopy
$l2 = AppRun $tmpApp '신규 설치'
$fdb = Join-Path $tmpApp 'data\juprovider.accdb'
Log ("  신규 DB: " + (DbSummary $fdb) + ", backup 폴더 " + $(if (Test-Path (Join-Path $tmpApp 'data\backup')) { '있음' } else { '없음' }))
$ok2 = (($l2 -match 'schema v1').Count -gt 0) -and -not (Test-Path (Join-Path $tmpApp 'data\backup'))
# 2-3 v0 DB (사용자 DB 의 복사본에서 LOCAL_SCHEMA_INFO 를 지움) → 앱이 백업 후 v1 로 마이그레이션, 데이터 보존
FreshCopy
New-Item -ItemType Directory -Force -Path (Join-Path $tmpApp 'data') | Out-Null
Copy-Item $userDb $fdb
Log ("  v0 준비 (복사본): DROP LOCAL_SCHEMA_INFO " + (DbExec $fdb 'DROP TABLE LOCAL_SCHEMA_INFO') + ", " + (DbSummary $fdb))
$l3 = AppRun $tmpApp 'v0 → v1'
$bk = @(Get-ChildItem (Join-Path $tmpApp 'data\backup') -Filter '*.accdb' -ErrorAction SilentlyContinue)
Log ("  마이그레이션 후: " + (DbSummary $fdb) + ", 백업 " + $bk.Count + "개 " + (($bk | ForEach-Object { $_.Name }) -join ','))
if ($bk.Count) { Log ("  백업 내용: LOCAL_DEVICE " + (DbQuery $bk[0].FullName 'SELECT COUNT(*) FROM LOCAL_DEVICE') + ", LOCAL_SCHEMA_INFO " + (DbQuery $bk[0].FullName 'SELECT COUNT(*) FROM LOCAL_SCHEMA_INFO')) }
$ok3 = (($l3 -match 'schema v1').Count -gt 0) -and (($l3 -match '마이그레이션 완료').Count -gt 0) -and ($bk.Count -eq 1) -and ((DbQuery $fdb 'SELECT COUNT(*) FROM LOCAL_DEVICE') -eq (DbQuery $userDb 'SELECT COUNT(*) FROM LOCAL_DEVICE'))
# 2-4 상위 버전 DB → 앱은 열지 않음(오류), 데이터 그대로
Log ("  v9 준비 (복사본): " + (DbExec $fdb "UPDATE LOCAL_SCHEMA_INFO SET INFO_VALUE='9' WHERE INFO_KEY='SCHEMA_VERSION'"))
$l4 = AppRun $tmpApp '상위 버전 v9'
Log ("  상위 버전 후: " + (DbSummary $fdb))
$ok4 = (($l4 -match 'LOCAL DB ERROR.*newer').Count -gt 0) -and ((DbQuery $fdb 'SELECT COUNT(*) FROM LOCAL_DEVICE') -eq (DbQuery $userDb 'SELECT COUNT(*) FROM LOCAL_DEVICE'))
Remove-Item $tmpApp -Recurse -Force -ErrorAction SilentlyContinue
Log "  앱 확인: 기존 v1 $ok1, 신규 $ok2, v0→v1 $ok3, 상위 버전 거부 $ok4"
if (-not ($ok1 -and $ok2 -and $ok3 -and $ok4)) { Stop '앱 확인 실패' }

Log ''; Log '===== 3. commit + push ====='
foreach ($f in $files) { if ((Run "git add -- `"$f`"") -ne 0) { Stop "add 실패 $f" } }
$msgFile = Join-Path $ws 'ai_mig_commitmsg.txt'
[IO.File]::WriteAllText($msgFile, "feat(desktop): local DB schema-version migrations without DROP/recreate`n`n- LocalSchema: v1 table definitions and ordered migrations (v0 -> v1 baseline: create missing tables, add missing columns, keep key-mismatched tables as *_LEGACY_<time>)`n- LocalDatabase: read SCHEMA_VERSION, refuse newer schema / missing path / v1 mismatch without touching data, back up to data\\backup before migrating, apply steps in order and record version per step, restore backup on failure`n- Client logs the migration backup path`n- Tests: LocalMigrationTests (legacy v0 data kept, old LOCAL_USER columns, sequential v1->v3, failure restore, unsupported schema); template tests updated`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01FuvmaMYDsqg8KmRxK7aHch`n", $enc)
if ((Run "git -c user.name=JU -c user.email=jusamuel@gmail.com commit -q -F `"$msgFile`"") -ne 0) { Stop 'commit 실패' }
Remove-Item $msgFile -Force
$h = Git1 'log -1 --format=%h'
Run 'git show --stat --format=%h%x20%s HEAD' | Out-Null
if ((Run "git push -u origin $branch") -ne 0) { Stop 'push 실패' }
Run 'git fetch -q origin' | Out-Null
$rh = Git1 "rev-parse --short origin/$branch"
Log "  commit $h, origin/$branch $rh, origin/main $(Git1 'rev-parse --short origin/main')"
if ($rh -ne $h) { Stop 'push 결과 불일치' }
Run 'git status --short' | Out-Null
Log 'MIG-DONE'

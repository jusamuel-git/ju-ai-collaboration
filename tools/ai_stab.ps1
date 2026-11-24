# C6 안정화 (11/24 승인): feature/c6-stabilize (← 69433f9)
# 백업 정책(30일·10개·최신 1개·조사용 보호), LEGACY 표 이력·상태(자동 삭제 없음), Client 오류 안내 구분.
# 파일 반영 → 빌드 5종 + 테스트 → 실제 앱(기존 설치 · 신규 설치 · v0 복사본 업그레이드+정리+LEGACY · 상위 버전 · 파일 잠금) → commit + push
# 사용자 DB(app\data)는 덮어쓰지 않는다(행 수·생성 시각 확인, v0 시험은 임시 폴더의 복사본). 서버·DB·WAR·Tomcat 변경 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$src = Join-Path $ws 'ai_changes\stab'
$app = Join-Path $jp 'desktop\app'
$userDb = Join-Path $app 'data\juprovider.accdb'
$log = Join-Path $ws ("ai_stab_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { if ($x -notmatch 'LF will be replaced|original line endings') { Log ('  ' + $x) } }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'STAB-STOPPED'; exit 1 }
function Git1([string]$a) { return @(cmd /c "git -C `"$jp`" $a 2>nul")[0] }
function FileHash16([string]$p) { if (Test-Path $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 16) } else { return '(없음)' } }
function DbQuery([string]$db, [string]$sql) { $cn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$db;"); try { $cn.Open(); $c = $cn.CreateCommand(); $c.CommandText = $sql; return $c.ExecuteScalar() } catch { return ('ERR ' + $_.Exception.Message) } finally { $cn.Close(); [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool() } }
function DbExec([string]$db, [string]$sql) { $cn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$db;"); try { $cn.Open(); $c = $cn.CreateCommand(); $c.CommandText = $sql; [void]$c.ExecuteNonQuery(); return 'OK' } catch { return ('ERR ' + $_.Exception.Message) } finally { $cn.Close(); [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool() } }
function DbSummary([string]$db) { return ('LOCAL_DEVICE ' + (DbQuery $db 'SELECT COUNT(*) FROM LOCAL_DEVICE') + ', LOCAL_USER ' + (DbQuery $db 'SELECT COUNT(*) FROM LOCAL_USER') + ', SCHEMA_VERSION ' + (DbQuery $db "SELECT INFO_VALUE FROM LOCAL_SCHEMA_INFO WHERE INFO_KEY='SCHEMA_VERSION'")) }
$files = @(Get-Content (Join-Path $src 'filelist.txt') | Where-Object { $_ })
$lock = 'juprovider.frontvue/package-lock.json'
$branch = 'feature/c6-stabilize'; $base = '69433f9'
Log ("STAB " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 0. 상태 ====='
cmd /c "git -C `"$jp`" fetch -q origin 2>&1" | Out-Null
$cur = Git1 'rev-parse --abbrev-ref HEAD'; $head = Git1 'log -1 --format=%h'
Log "  $cur @ $head, origin/feature/local-db-migration $(Git1 'rev-parse --short origin/feature/local-db-migration'), origin/main $(Git1 'rev-parse --short origin/main')"
if (-not (($cur -eq 'feature/local-db-migration' -or $cur -eq $branch) -and $head -eq $base)) { Stop "feature/local-db-migration(또는 $branch) @ $base 가 아님" }
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
$tr = Run 'dotnet test desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug --no-build --filter "FullyQualifiedName~LocalStabilizeTests|FullyQualifiedName~LocalMigrationTests|FullyQualifiedName~LocalTemplateTests" --logger "console;verbosity=normal"'
Log ("  템플릿 해시 저장소 " + (FileHash16 (Join-Path $jp 'desktop\resources\template.accdb')) + " / app\config " + (FileHash16 (Join-Path $app 'config\template.accdb')) + " (바뀌지 않아야 함: FE2B566F8D3281E2)")
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
# 2-3 v0 업그레이드 (사용자 DB 복사본): 스키마 정보 삭제 + LOCAL_USER 를 이전 구성(LOGIN_ID 키, 1행)으로 + 오래된 정상 백업 11개 → 백업·정리·LEGACY 기록
FreshCopy
New-Item -ItemType Directory -Force -Path (Join-Path $tmpApp 'data\backup') | Out-Null
Copy-Item $userDb $fdb
Log ("  v0 준비 (복사본): " + (DbExec $fdb 'DROP TABLE LOCAL_SCHEMA_INFO') + ' / ' + (DbExec $fdb 'DROP TABLE LOCAL_USER') + ' / ' + (DbExec $fdb 'CREATE TABLE LOCAL_USER (LOGIN_ID VARCHAR(50) NOT NULL, USER_NM VARCHAR(50), CONSTRAINT PK_LOCAL_USER PRIMARY KEY (LOGIN_ID))') + ' / ' + (DbExec $fdb "INSERT INTO LOCAL_USER (LOGIN_ID, USER_NM) VALUES ('legacy-user', 'test')"))
for ($i = 1; $i -le 11; $i++) { [IO.File]::WriteAllText((Join-Path $tmpApp ('data\backup\juprovider_v0_' + (Get-Date).AddDays(-$i).ToString('yyyyMMdd_HHmmss_fff') + '.accdb')), 'dummy') }
Log "  정상 백업(가짜 파일) 11개, 1~11일 전"
$l3 = AppRun $tmpApp 'v0 → v1'
$l3 | Where-Object { $_ -match 'LOCAL DB (BACKUP|LEGACY)' } | ForEach-Object { Log "  [v0 → v1] $_" }
$bk = @(Get-ChildItem (Join-Path $tmpApp 'data\backup') -Filter '*.accdb' -ErrorAction SilentlyContinue)
Log ("  업그레이드 후: " + (DbSummary $fdb) + ", 백업 폴더 정상 백업 " + $bk.Count + "개")
Log ("  LEGACY 이력 행 " + (DbQuery $fdb "SELECT COUNT(*) FROM LOCAL_SCHEMA_INFO WHERE INFO_KEY LIKE 'LEGACY:%'"))
$ok3 = (($l3 -match 'schema v1').Count -gt 0) -and (($l3 -match '마이그레이션 완료').Count -gt 0) -and (($l3 -match 'LOCAL DB BACKUP.*삭제 2').Count -gt 0) -and ($bk.Count -eq 10) -and (($l3 -match 'LOCAL DB LEGACY\] LOCAL_USER_LEGACY_\d+ 원본=LOCAL_USER 행=1 상태=verified').Count -gt 0) -and ((DbQuery $fdb 'SELECT COUNT(*) FROM LOCAL_DEVICE') -eq (DbQuery $userDb 'SELECT COUNT(*) FROM LOCAL_DEVICE'))
# 2-4 재실행: 마이그레이션·정리 없음, LEGACY 그대로
$l3b = AppRun $tmpApp '업그레이드 후 재실행'
$ok3b = (($l3b -match '마이그레이션 완료|LOCAL DB BACKUP').Count -eq 0) -and (($l3b -match 'LOCAL DB LEGACY\].*상태=verified').Count -gt 0)
# 2-5 상위 버전 → SCHEMA_NEWER
Log ("  v9 준비 (복사본): " + (DbExec $fdb "UPDATE LOCAL_SCHEMA_INFO SET INFO_VALUE='9' WHERE INFO_KEY='SCHEMA_VERSION'"))
$l4 = AppRun $tmpApp '상위 버전 v9'
$ok4 = (($l4 -match 'LOCAL DB ERROR:SCHEMA_NEWER').Count -gt 0) -and ((DbQuery $fdb 'SELECT COUNT(*) FROM LOCAL_DEVICE') -eq (DbQuery $userDb 'SELECT COUNT(*) FROM LOCAL_DEVICE'))
# 2-6 DB 파일 잠금 → FILE_ACCESS
Log ("  v1 로 되돌림 (복사본): " + (DbExec $fdb "UPDATE LOCAL_SCHEMA_INFO SET INFO_VALUE='1' WHERE INFO_KEY='SCHEMA_VERSION'"))
$fs = [IO.File]::Open($fdb, 'Open', 'ReadWrite', 'None')
try { $l5 = AppRun $tmpApp '파일 잠금' } finally { $fs.Close() }
$ok5 = (($l5 -match 'LOCAL DB ERROR:FILE_ACCESS').Count -gt 0)
Log ("  잠금 해제 후: " + (DbSummary $fdb))
Remove-Item $tmpApp -Recurse -Force -ErrorAction SilentlyContinue
Log "  앱 확인: 기존 $ok1, 신규 $ok2, v0 업그레이드·정리·LEGACY $ok3, 재실행 $ok3b, 상위 버전 안내 $ok4, 파일 잠금 안내 $ok5"
if (-not ($ok1 -and $ok2 -and $ok3 -and $ok3b -and $ok4 -and $ok5)) { Stop '앱 확인 실패' }

Log ''; Log '===== 3. commit + push ====='
foreach ($f in $files) { if ((Run "git add -- `"$f`"") -ne 0) { Stop "add 실패 $f" } }
$msgFile = Join-Path $ws 'ai_stab_commitmsg.txt'
[IO.File]::WriteAllText($msgFile, "feat(desktop): C6 stabilization - backup retention, legacy table history, client DB error guidance`n`n- LocalBackupPolicy: after a successful migration delete normal backups older than 30 days or beyond 10 (newest always kept); backup\\incident, .keep-marked and unknown files are never deleted; result logged`n- Failed migration backups are moved to backup\\incident (restored / restore-failed) so cleanup never removes them`n- LocalLegacyTables: *_LEGACY_* history in LOCAL_SCHEMA_INFO (source, rows, copied, verified, time) and status listing; no drop`n- LocalDatabaseSchemaException kinds; client LocalDbErrorGuide with distinct messages and log codes (SCHEMA_NEWER, SCHEMA_UNSUPPORTED, MIGRATION_RESTORED, MIGRATION_RESTORE_FAILED, TEMPLATE_MISSING, FILE_ACCESS)`n- Tests: LocalStabilizeTests`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01FuvmaMYDsqg8KmRxK7aHch`n", $enc)
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
Log 'STAB-DONE'

# 11/24 사후 수정: 해시 함수 H 가 PowerShell 별칭 h(Get-History)와 겹쳐 빈 값이 됨 → FileHash16, Inspect 단순화 (실행본은 수정 전, 결과는 ai_tpl_verify 로 보완)
# 로컬 DB 표준 템플릿 (11/24 승인): feature/local-db-template (← C6c 01d1775)
# A. 코드 반영 → 코드 스키마로 template.accdb 생성(ADOX+LocalDatabase) → desktop/resources 에 둠
# B. csproj(빌드 시 app\config 로 복사) → 템플릿 내용 점검 → 빌드 5종 + 테스트 → 앱 확인(기존 설치 재실행·신규 설치) → commit + push
# 사용자 DB(app\data\juprovider.accdb)는 덮어쓰지 않는다(해시로 확인). 서버·DB·WAR·Tomcat 변경 없음. 비밀 값 기록 없음.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$src = Join-Path $ws 'ai_changes\tpl'
$app = Join-Path $jp 'desktop\app'
$res = Join-Path $jp 'desktop\resources\template.accdb'
$userDb = Join-Path $app 'data\juprovider.accdb'
$log = Join-Path $ws ("ai_tpl_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function Run([string]$cmd) { Log ("> " + $cmd); Push-Location $jp; $o = cmd /c "$cmd 2>&1"; $c = $LASTEXITCODE; Pop-Location; foreach ($x in $o) { if ($x -notmatch 'LF will be replaced|original line endings') { Log ('  ' + $x) } }; Log ("  (exit $c)"); return $c }
function Stop([string]$why) { Log ("중단: " + $why); Log 'TPL-STOPPED'; exit 1 }
function Git1([string]$a) { return @(cmd /c "git -C `"$jp`" $a 2>nul")[0] }
function FileHash16([string]$p) { if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash.Substring(0, 16) } else { return '(없음)' } }
function Put([string]$f) { $to = Join-Path $jp $f.Replace('/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null; Copy-Item (Join-Path $src ('src\' + $f.Replace('/', '\'))) $to -Force; (Get-Item $to).LastWriteTime = Get-Date }
function Inspect([string]$db) {
    try {
        $cn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$db;")
        $cn.Open()
        foreach ($t in 'LOCAL_DEVICE', 'LOCAL_SCHEMA_INFO', 'LOCAL_SYNC_STATE', 'LOCAL_USER') {
            try { $cmd = $cn.CreateCommand(); $cmd.CommandText = "SELECT COUNT(*) FROM [$t]"; Log ("    $t 행 " + $cmd.ExecuteScalar()) } catch { Log ("    $t 없음: " + $_.Exception.Message) }
        }
        $cn.Close()
    } catch { Log ('    !! 열기 실패: ' + $_.Exception.Message) }
    [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool()
}
$filesA = @(Get-Content (Join-Path $src 'filelist_a.txt') | Where-Object { $_ })
$csproj = 'desktop/juprovider.client/juprovider.client.csproj'
$resRel = 'desktop/resources/template.accdb'
$all = $filesA + @($csproj, $resRel)
$lock = 'juprovider.frontvue/package-lock.json'
$branch = 'feature/local-db-template'; $base = '01d1775'
Log ("TPL " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Log '===== 0. 상태 ====='
cmd /c "git -C `"$jp`" fetch -q origin 2>&1" | Out-Null
$cur = Git1 'rev-parse --abbrev-ref HEAD'; $head = Git1 'log -1 --format=%h'
Log "  $cur @ $head, origin/feature/c6c-desktop-ui $(Git1 'rev-parse --short origin/feature/c6c-desktop-ui'), origin/main $(Git1 'rev-parse --short origin/main')"
if (-not (($cur -eq 'feature/c6c-desktop-ui' -or $cur -eq $branch) -and $head -eq $base)) { Stop "feature/c6c-desktop-ui(또는 $branch) @ $base 가 아님" }
$st = @(& git -C $jp status --porcelain --untracked-files=all | Where-Object { $p = $_.Substring(3).Trim('"'); ($p -ne $lock) -and ($all -notcontains $p) })
if ($st.Count) { Stop ('예상 밖 변경: ' + ($st -join ', ')) }
$userDbHash = FileHash16 $userDb
Log "  사용자 DB $userDb 해시 $userDbHash, 현재 app\config\template.accdb 해시 $(FileHash16 (Join-Path $app 'config\template.accdb')) (11/23 임시 파일)"
foreach ($n in 'juprovider.client', 'juprovider.terminal') {
    foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) { Log "  $n PID $($p.Id) 종료 (빌드 파일 잠금 방지, 11/24 검증용으로 띄운 것)"; [void]$p.CloseMainWindow(); Start-Sleep -Seconds 3; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
}
if ($cur -ne $branch) {
    if (Git1 "rev-parse --verify --quiet refs/heads/$branch") { Stop "$branch 가 이미 있음" }
    if ((Run "git switch -c $branch") -ne 0) { Stop '브랜치 생성 실패' }
}

Log ''; Log '===== A. 코드 반영 + 코드 스키마로 템플릿 생성 ====='
foreach ($f in $filesA) { Put $f }
if (Test-Path $res) { Stop "$res 가 이미 있음 (덮어쓰지 않음)" }
$gen = Join-Path $src 'gen'; if (Test-Path $gen) { Remove-Item $gen -Recurse -Force }; New-Item -ItemType Directory -Path $gen | Out-Null
$out = Join-Path $gen 'template.accdb'
if ((Run 'dotnet build desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug -v q -nologo') -ne 0) { Stop '생성용 빌드 실패' }
$env:JU_TEMPLATE_OUT = $out
$g = Run 'dotnet test desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug --no-build --filter "FullyQualifiedName~LocalTemplateTests.Generate_Template_When_Requested" --logger "console;verbosity=normal"'
$env:JU_TEMPLATE_OUT = $null
if ($g -ne 0 -or -not (Test-Path $out)) { Stop '템플릿 생성 실패' }
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path (Split-Path $res) | Out-Null
Copy-Item $out $res
Log ("  생성 → $resRel " + (Get-Item $res).Length + " B, 해시 " + (FileHash16 $res))
Log '  템플릿 내용 (테이블·행 수·PK·인덱스·컬럼):'
Inspect $res

Log ''; Log '===== B. 빌드 시 app\config 복사 + 빌드 5종 + 테스트 ====='
Put $csproj
Run 'git status --short' | Out-Null
Run 'git diff --stat' | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
if ($si -lt 0) { Stop '빌드 요약 없음' }
$sum = $bl[$si..($bl.Length - 1)]
$sum | Where-Object { $_.Trim() } | ForEach-Object { Log ('  ' + $_) }
$bl | Select-String -Pattern 'Tests run: \d+, Failures: \d+, Errors: \d+, Skipped: \d+$|(통과|실패)!.*' | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$bl | Select-String -Pattern 'error CS|warning CS|error MSB|warning MSB|\[실패\]|\[FAIL\]|Assert\.' | Select-Object -First 40 | ForEach-Object { Log ('  ' + $_.Line.Trim()) }
$buildOk = (@($sum | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -eq 0)
$tr = Run 'dotnet test desktop\tests\juprovider.tests.protocol\juprovider.tests.protocol.csproj -c Debug --no-build --filter "FullyQualifiedName~LocalTemplateTests|FullyQualifiedName~C6cClientTests|FullyQualifiedName~C6bClientTests" --logger "console;verbosity=normal"'
$shipped = Join-Path $app 'config\template.accdb'
Log "  app\config\template.accdb 해시 $(FileHash16 $shipped) / 저장소 $(FileHash16 $res) → $(if ((FileHash16 $shipped) -eq (FileHash16 $res)) { '같음' } else { '!! 다름' })"
Log "  사용자 DB 해시 빌드 후 $(FileHash16 $userDb) → $(if ((FileHash16 $userDb) -eq $userDbHash) { '변경 없음' } else { '!! 바뀜' })"
if (-not $buildOk -or $tr -ne 0) { Stop '빌드·테스트 FAIL → commit 하지 않음' }
if ((FileHash16 $shipped) -ne (FileHash16 $res)) { Stop 'app\config 복사 불일치' }
if ((FileHash16 $userDb) -ne $userDbHash) { Stop '사용자 DB 가 빌드 중 바뀜' }

Log ''; Log '===== C. 실제 앱 확인 ====='
function AppRun([string]$dir, [string]$label) {
    $lf = Join-Path $dir ("logs\client_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
    $before = if (Test-Path $lf) { @(Get-Content -Encoding UTF8 $lf).Count } else { 0 }
    $p = Start-Process -FilePath (Join-Path $dir 'juprovider.client.exe') -WorkingDirectory $dir -PassThru
    Start-Sleep -Seconds 10
    $lines = if (Test-Path $lf) { @(Get-Content -Encoding UTF8 $lf | Select-Object -Skip $before) } else { @() }
    $lines | Where-Object { $_ -match '\[LOCAL DB' } | ForEach-Object { Log "  [$label] $_" }
    if (-not $p.HasExited) { [void]$p.CloseMainWindow(); Start-Sleep -Seconds 2; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
    return ($lines -match '\[LOCAL DB\] .* schema v1').Count -gt 0
}
# C-1 기존 설치(PC-B, 11/23 빈 ACCDB 에서 시작한 DB) 재실행 → 스키마 정보 추가, 데이터 보존
$devBefore = $null
try { $cn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$userDb;"); $cn.Open(); $c = $cn.CreateCommand(); $c.CommandText = 'SELECT COUNT(*) FROM LOCAL_DEVICE'; $devBefore = $c.ExecuteScalar(); $cn.Close(); [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool() } catch { Log ('  LOCAL_DEVICE 확인 실패 ' + $_.Exception.Message) }
Log "  기존 DB LOCAL_DEVICE 행 $devBefore (실행 전)"
$ok1 = AppRun $app '기존 설치'
$ok1b = AppRun $app '재실행'
Log '  기존 DB 실행 후:'; Inspect $userDb
# C-2 신규 설치: app 을 임시 폴더로 복사(config\client.json·connections.json·data·logs·cache 제외) 후 실행 → data 새로 생성
$fresh = Join-Path $src 'fresh_app'
if (Test-Path $fresh) { Remove-Item $fresh -Recurse -Force }
robocopy $app $fresh /E /XD (Join-Path $app 'data') (Join-Path $app 'logs') (Join-Path $app 'cache') /XF client.json connections.json /NFL /NDL /NJH /NJS /NP | Out-Null
Log ("  신규 설치 폴더: data " + $(if (Test-Path (Join-Path $fresh 'data')) { '있음' } else { '없음' }) + ", template " + (FileHash16 (Join-Path $fresh 'config\template.accdb')))
$ok2 = AppRun $fresh '신규 설치'
$fdb = Join-Path $fresh 'data\juprovider.accdb'
Log ("  신규 DB " + $(if (Test-Path $fdb) { (Get-Item $fdb).Length.ToString() + ' B' } else { '!! 없음' }))
if (Test-Path $fdb) { Inspect $fdb }
Remove-Item $fresh -Recurse -Force -ErrorAction SilentlyContinue
Log "  템플릿 해시 실행 후 $(FileHash16 $shipped) (변경 없어야 함)"
if (-not ($ok1 -and $ok1b -and $ok2)) { Stop '앱 확인 실패 (LOCAL DB schema v1 로그 없음)' }

Log ''; Log '===== D. commit + push ====='
foreach ($f in $all) { if ((Run "git add -- `"$f`"") -ne 0) { Stop "add 실패 $f" } }
$msgFile = Join-Path $ws 'ai_tpl_commitmsg.txt'
[IO.File]::WriteAllText($msgFile, "feat(desktop): standard local DB template (schema v1)`n`n- desktop/resources/template.accdb: schema-only template generated from LocalDatabase code (LOCAL_USER, LOCAL_DEVICE, LOCAL_SYNC_STATE, LOCAL_SCHEMA_INFO; no user data)`n- client csproj copies it to app\\config\\template.accdb on build; app\\data DB is never overwritten`n- LocalDatabase: schema version (LOCAL_SCHEMA_INFO), path ctor, CreateTemplateAsync (ADOX), copy via temp file without overwrite, refuse newer schema`n- Client logs schema version; .gitattributes marks *.accdb binary`n- LocalTemplateTests: template matches code and has no data, new install, existing install/rerun keeps data, pre-standard DB upgrade, newer schema refused, DB reset`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_01FuvmaMYDsqg8KmRxK7aHch`n", $enc)
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
Log 'TPL-DONE'

# 통합 검증용 로컬 실행: feature/ju-1c WAR를 18081에서 실제 juprovider DB로 실행 (Tomcat 8081의 main은 그대로)
# 실제 DB에 05가 적용된 뒤 실행한다. 종료: ai_ju1_local_stop.ps1
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'; $jp = Join-Path $ws 'juprovider'
$log = Join-Path $ws ("ai_ju1_local_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
if ((& git -C $jp rev-parse --abbrev-ref HEAD) -ne 'feature/ju-1c') { Log '중단: 브랜치가 feature/ju-1c 아님'; exit 1 }
Log ("HEAD: " + (& git -C $jp log -1 --oneline))
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'ai_local_build.ps1') *>&1 | Out-Null
$bl = Get-Content -Encoding UTF8 (Join-Path $ws ("ai_local_build_{0}.log" -f $env:COMPUTERNAME))
$si = [Array]::IndexOf($bl, '===== 요약 =====')
$bad = ($si -lt 0) -or (@($bl[$si..($bl.Length - 1)] | Select-String -CaseSensitive '\bFAIL\b|\bSKIP\b').Count -gt 0)
if ($si -ge 0) { $bl[$si..($bl.Length - 1)] | ForEach-Object { Log ('  ' + $_) } }
$war = Join-Path $jp 'juprovider.backend\target\juprovider.war'
if ($bad -or -not (Test-Path $war)) { Log '중단: 로컬 빌드 5종 PASS 아님'; exit 1 }
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_[A-Z_]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
$env:SPRING_PROFILES_ACTIVE = $null
Log ("대상 DB: " + $(if ($vars['JU_DB_URL'] -match '/juprovider(\?|$)') { 'juprovider (실제)' } else { '확인 필요' }))
$p = Start-Process (Join-Path $env:JAVA_HOME 'bin\java.exe') -ArgumentList "-jar `"$war`" --server.port=18081" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$ws\ai_ju1_local_app_out.txt" -RedirectStandardError "$ws\ai_ju1_local_app_err.txt"
foreach ($k in 'JU_DB_URL','JU_DB_USER','JU_DB_PASSWORD','JU_JWT_SECRET') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
Set-Content -Path (Join-Path $ws 'ai_ju1_local.pid') -Value $p.Id
$ok = $false
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 1; try { if ((Invoke-WebRequest 'http://localhost:18081/juprovider/api/health' -UseBasicParsing).StatusCode -eq 200) { $ok = $true; break } } catch {} }
Log ("서버 18081: " + $(if ($ok) { 'UP  →  http://localhost:18081/juprovider/' } else { 'FAIL (ai_ju1_local_app_err.txt 확인)' }))

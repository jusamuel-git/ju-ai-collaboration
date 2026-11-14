# C5c 배포 사전 검증 보충 (읽기 전용): Jenkins 가 볼 환경변수·도구 설정, 8081 중지 시점
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5c_deploy_env_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C5c deploy env " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
foreach ($n in 'JU_TOMCAT_HOME', 'JAVA_HOME', 'MAVEN_HOME', 'M2_HOME', 'JU_WORKSPACE') {
    Log ("  E-1 {0}: Machine='{1}' User='{2}'" -f $n, [Environment]::GetEnvironmentVariable($n, 'Machine'), [Environment]::GetEnvironmentVariable($n, 'User'))
}
$jh = 'C:\ProgramData\Jenkins\.jenkins'
foreach ($f in 'hudson.model.JDK.xml', 'hudson.tasks.Maven.xml', 'jenkins.model.JenkinsLocationConfiguration.xml') {
    $p = Join-Path $jh $f
    if (Test-Path $p) { $t = Get-Content $p -Raw; $nm = @([regex]::Matches($t, '<name>([^<]+)</name>\s*<home>([^<]*)</home>') | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value }); Log ("  E-2 $f : " + ($nm -join ', ')) } else { Log ("  E-2 $f : 없음") }
}
$cfg = Get-Content (Join-Path $jh 'config.xml') -Raw
$gp = $(if ($cfg -match '(?s)<globalNodeProperties>(.*?)</globalNodeProperties>') { $matches[1] } elseif ($cfg -match '<globalNodeProperties/>') { '(비어 있음)' } else { '(태그 없음)' })
$gpNames = @([regex]::Matches($gp, '<string>([^<]+)</string>') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match '^[A-Z_]+$' })
Log ("  E-3 Jenkins globalNodeProperties 변수 이름: " + $(if ($gpNames.Count) { $gpNames -join ', ' } else { $gp.Substring(0, [Math]::Min(60, $gp.Length)) }))
$ws2 = Join-Path $jh 'workspace\juprovider-ai'
Log ("  E-4 Jenkins workspace juprovider-ai: " + $(if (Test-Path $ws2) { 'WAR ' + [bool](Test-Path (Join-Path $ws2 'juprovider.backend\target\juprovider.war')) } else { '없음' }))
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Log ("  E-5 마지막 부팅 " + $boot.ToString('yyyy-MM-dd HH:mm'))
$tl = Get-ChildItem 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\logs' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 4 | ForEach-Object { $_.Name + ' ' + $_.LastWriteTime.ToString('MM-dd HH:mm') }
Log ("  E-6 Tomcat 최근 로그 " + ($tl -join ', '))
$last = Get-ChildItem 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\logs' -Filter 'catalina.*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($last) { Get-Content $last.FullName -Tail 4 -Encoding UTF8 | ForEach-Object { Log ('    ' + $_.Substring(0, [Math]::Min(200, $_.Length))) } }
Log ("  E-7 8081 listen " + @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count)
Log 'C5C-DEP-ENV-DONE'

# C5c 배포 상태 확인 (읽기 전용): Jenkins 전역 변수·juprovider-ai 빌드·8081
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c5c_deploy_status_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("C5c deploy status " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$jh = 'C:\ProgramData\Jenkins\.jenkins'
$cfg = Get-Content (Join-Path $jh 'config.xml') -Raw
$gp = @([regex]::Matches($cfg, '<string>([A-Z_]+)</string>\s*<string>([^<]*)</string>') | ForEach-Object { $n = $_.Groups[1].Value; $n + '=' + $(if ($n -match 'HOME$') { $_.Groups[2].Value } else { '(설정됨)' }) })
Log ("  S-1 Jenkins 전역 변수: " + $(if ($gp.Count) { $gp -join ', ' } else { '없음' }))
$jd = Join-Path $jh 'jobs\juprovider-ai\builds'
$bd = @(Get-ChildItem $jd -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' } | Sort-Object { [int]$_.Name } -Descending | Select-Object -First 3)
foreach ($b in $bd) {
    $bx = Join-Path $b.FullName 'build.xml'
    $t2 = $(if (Test-Path $bx) { Get-Content $bx -Raw } else { '' })
    $res = $(if ($t2 -match '<result>(\w+)</result>') { $matches[1] } else { '(진행 중?)' })
    $sha = $(if ($t2 -match '<SHA1>([0-9a-f]{7})') { $matches[1] } else { '?' })
    Log ("  S-2 #" + $b.Name + " " + $res + " rev " + $sha + " " + $b.CreationTime.ToString('MM-dd HH:mm'))
    $lf = Join-Path $b.FullName 'log'
    if (Test-Path $lf) {
        $lines = @(Get-Content $lf -Encoding UTF8 | ForEach-Object { $_ -replace '\x1b\[[0-9;]*m', '' -replace 'ha:////\S+', '' })
        $key = @($lines | Select-String -Pattern 'Stage "|\[Pipeline\] stage|^\[Pipeline\] \{ \((.+)\)|Tests run: \d+, Failures|ERROR|FAILURE|Finished:|BUILD|Backup|백업|health|status|JU_TOMCAT_HOME|Checking out Revision|WAR' | ForEach-Object { $_.Line.Trim() } | Where-Object { $_ -and $_.Length -lt 220 } | Select-Object -Last 45)
        $key | ForEach-Object { Log ('      ' + $_) }
    }
    break
}
Log ("  S-3 8081 listen " + @(Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue).Count)
try { $r = Invoke-WebRequest 'http://localhost:8081/juprovider/api/health' -UseBasicParsing -TimeoutSec 10; Log ("  S-4 health " + [int]$r.StatusCode + " " + $r.Content) } catch { Log ("  S-4 health 실패 " + $_.Exception.Message) }
Log 'C5C-DEPLOY-STATUS-DONE'

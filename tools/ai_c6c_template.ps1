# 11/23 사용자 결정: 빈 template.accdb(테이블 없음)를 ADOX 로 app\config 에 만든다 (git 제외 경로, 서버 DB 무관) → Client 다시 실행
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$app = Join-Path $jp 'desktop\app'
$tpl = Join-Path $app 'config\template.accdb'
$log = Join-Path $ws ("ai_c6c_template_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("template " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if (Test-Path $tpl) { Log '  이미 있음 (그대로 둠)' }
else {
    try {
        $cat = New-Object -ComObject ADOX.Catalog
        $cn = $cat.Create("Provider=Microsoft.ACE.OLEDB.16.0;Data Source=$tpl;")
        try { $cn.Close() } catch {}
        [Runtime.InteropServices.Marshal]::ReleaseComObject($cat) | Out-Null
        Log ("  생성 " + (Get-Item $tpl).Length + " B")
    } catch { Log ('  생성 실패: ' + $_.Exception.Message); Log 'TEMPLATE-FAIL'; exit 1 }
}
$ig = (& git -C $jp check-ignore 'desktop/app/config/template.accdb'); Log ("  git 제외: " + $(if ($ig) { '제외됨' } else { '!! 제외 안 됨' }))
Log ("  git status: " + ((& git -C $jp status --porcelain) -join ' | '))
$c = @(Get-Process -Name 'juprovider.client' -ErrorAction SilentlyContinue)
if ($c.Count) { Log ("  Client 실행 중 PID " + (($c | ForEach-Object { $_.Id }) -join ',')) }
else { $p = Start-Process -FilePath (Join-Path $app 'juprovider.client.exe') -WorkingDirectory $app -PassThru; Log ("  Client 시작 PID " + $p.Id) }
Log ("  Terminal: " + ((@(Get-Process -Name 'juprovider.terminal' -ErrorAction SilentlyContinue) | ForEach-Object { $_.Id }) -join ','))
Log 'TEMPLATE-DONE'

# [읽기 전용] Desktop Client 동기화 확인: ju_client 상태(키 해시 제외) + client.json 존재 + Client 로컬 DB/로그 갱신 시각
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'; $app = Join-Path $ws 'juprovider\desktop\app'
$log = Join-Path $ws ("ai_ju1_synccheck_{0}.log" -f $env:COMPUTERNAME)
$vars = @{}
foreach ($l in Get-Content 'C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52\bin\setenv.bat') { if ($l -match '^\s*set\s+"?(JU_DB_[A-Z]+)=(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] } }
$env:MYSQL_PWD = $vars['JU_DB_PASSWORD']
$base = "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h localhost -u $($vars['JU_DB_USER']) --default-character-set=utf8mb4 -N -B juprovider"
$out = @("확인 시각: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$cols = (cmd /c "$base -e `"SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='juprovider' AND TABLE_NAME='ju_client' AND COLUMN_NAME NOT LIKE '%HASH%' AND COLUMN_NAME NOT LIKE '%KEY%'`" 2>&1")
$out += "ju_client 컬럼(키 제외): $cols"
$out += (cmd /c "$base -e `"SELECT $cols FROM ju_client`" 2>&1")
$env:MYSQL_PWD = $null
$cj = Join-Path $app 'config\client.json'
if (Test-Path $cj) { try { $j = Get-Content $cj -Raw | ConvertFrom-Json; $out += ("client.json: 있음 / ServerUrl=" + $j.ServerUrl + " / ClientId=" + $j.ClientId + " / ClientKey 길이=" + ([string]$j.ClientKey).Length + " / 수정 " + (Get-Item $cj).LastWriteTime) } catch { $out += 'client.json: 읽기 실패' } } else { $out += 'client.json: 없음' }
foreach ($d in 'data','logs') { $p = Join-Path $app $d; if (Test-Path $p) { $out += "--- $d (최근 5개) ---"; $out += (Get-ChildItem $p -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $_.FullName.Substring($app.Length) + '  ' + $_.Length }) } }
$out += 'SYNCCHECK-DONE'
Set-Content -Path $log -Value $out -Encoding UTF8

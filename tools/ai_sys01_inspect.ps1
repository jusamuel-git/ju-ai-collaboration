# SYS-01 사전조사: juproject DB 읽기 전용 조회. 변경 없음. 비밀 값은 로그에 쓰지 않는다.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$out = Join-Path $ws ("ai_sys01_inspect_{0}.log" -f $env:COMPUTERNAME)
$sec = Get-ChildItem "$env:APPDATA\Microsoft\UserSecrets\*\secrets.json" | Where-Object { (Get-Content $_ -Raw) -match 'ConnectionStrings' } | Select-Object -First 1
$cs = ((Get-Content $sec.FullName -Raw | ConvertFrom-Json).'ConnectionStrings:Default')
if (-not $cs) { $cs = (Get-Content $sec.FullName -Raw | ConvertFrom-Json).ConnectionStrings.Default }
$kv = @{}; foreach ($p in $cs -split ';') { if ($p -match '^\s*([^=]+?)\s*=\s*(.*)$') { $kv[$matches[1].ToLower()] = $matches[2] } }
$h = $kv['server']; if (-not $h) { $h = $kv['host'] }; $port = $kv['port']; if (-not $port) { $port = '3306' }
$db = $kv['database']; $u = $kv['user']; if (-not $u) { $u = $kv['uid'] }; if (-not $u) { $u = $kv['user id'] }
$env:MYSQL_PWD = $kv['password']; if (-not $env:MYSQL_PWD) { $env:MYSQL_PWD = $kv['pwd'] }
$hdr = "SYS-01 inspect " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " host=$h port=$port db=$db user=" + $(if ($u) {'SET'} else {'MISSING'})
[IO.File]::WriteAllText($out, $hdr + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
cmd /c "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h $h -P $port -u $u --default-character-set=utf8mb4 -B $db < `"$ws\ai_changes\sys01\sys01_inspect.sql`" >> `"$out`" 2>&1"
$env:MYSQL_PWD = $null
Add-Content $out ("exit $LASTEXITCODE`r`nINSPECT-DONE")

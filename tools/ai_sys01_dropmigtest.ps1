$sec = Get-ChildItem "$env:APPDATA\Microsoft\UserSecrets\*\secrets.json" | Where-Object { (Get-Content $_ -Raw) -match 'ConnectionStrings' } | Select-Object -First 1
$cs = (Get-Content $sec.FullName -Raw | ConvertFrom-Json).'ConnectionStrings:Default'
$kv = @{}; foreach ($p in $cs -split ';') { if ($p -match '^\s*([^=]+?)\s*=\s*(.*)$') { $kv[$matches[1].ToLower()] = $matches[2] } }
$u = $kv['user']; if (-not $u) { $u = $kv['user id'] }; if (-not $u) { $u = $kv['uid'] }
$env:MYSQL_PWD = $kv['password']; if (-not $env:MYSQL_PWD) { $env:MYSQL_PWD = $kv['pwd'] }
$o = cmd /c "`"C:\Program Files\MariaDB 10.6\bin\mysql.exe`" -h $($kv['server']) -u $u -e `"DROP DATABASE IF EXISTS juproject_migtest; SHOW DATABASES LIKE 'juproject%';`" 2>&1"
$env:MYSQL_PWD = $null
[IO.File]::WriteAllText('C:\MyData\MyDev\workspace\ai_sys01_dropmigtest.log', (($o -join "`r`n") + "`r`nexit $LASTEXITCODE`r`nDONE"), (New-Object System.Text.UTF8Encoding($false)))

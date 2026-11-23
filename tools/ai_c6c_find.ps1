# template.accdb 찾기 (읽기만): Client Local DB 초기화 실패 원인 확인
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c6c_find_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("find " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Log '===== *.accdb (C:\MyData, D:\) ====='
foreach ($root in 'C:\MyData', 'D:\') {
    Get-ChildItem -Path $root -Recurse -File -Include '*.accdb' -ErrorAction SilentlyContinue | ForEach-Object { Log ("  {0}  {1:N0} B  {2:yyyy-MM-dd HH:mm}  {3}" -f $_.FullName, $_.Length, $_.LastWriteTime, (Get-FileHash $_.FullName -Algorithm SHA256).Hash.Substring(0, 16)) }
}
Log '===== zip 안의 template.accdb ====='
Add-Type -AssemblyName System.IO.Compression.FileSystem
Get-ChildItem -Path 'C:\MyData\MyDev' -Recurse -File -Filter '*.zip' -ErrorAction SilentlyContinue | ForEach-Object {
    $zn = $_.FullName; try { $z = [IO.Compression.ZipFile]::OpenRead($zn); $z.Entries | Where-Object { $_.FullName -match '\.accdb$' } | ForEach-Object { Log ("  " + $zn + " :: " + $_.FullName + " " + $_.Length) }; $z.Dispose() } catch {}
}
Log '===== ACE OLEDB 공급자 ====='
try { (New-Object System.Data.OleDb.OleDbEnumerator).GetElements() | Where-Object { $_.SOURCES_NAME -match 'ACE' } | ForEach-Object { Log ("  " + $_.SOURCES_NAME) } } catch { Log ("  열거 실패: " + $_.Exception.Message) }
Log 'FIND-DONE'

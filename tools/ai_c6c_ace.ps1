# ACE OLEDB 공급자 확인 (읽기만)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws = 'C:\MyData\MyDev\workspace'
$log = Join-Path $ws ("ai_c6c_ace_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
Log ("ace " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " 64bit=" + [Environment]::Is64BitProcess)
foreach ($v in '12.0', '16.0') {
    $k = "Registry::HKEY_CLASSES_ROOT\Microsoft.ACE.OLEDB.$v\CLSID"
    if (Test-Path $k) { $clsid = (Get-ItemProperty $k).'(default)'; Log "  Microsoft.ACE.OLEDB.$v CLSID $clsid"
        foreach ($p in "Registry::HKEY_CLASSES_ROOT\CLSID\$clsid\InprocServer32", "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$clsid\InprocServer32") { if (Test-Path $p) { Log ("    " + $p.Split('\')[2] + " " + (Get-ItemProperty $p).'(default)') } } }
    else { Log "  Microsoft.ACE.OLEDB.$v 없음" }
}
try { $c = New-Object -ComObject ADOX.Catalog; Log '  ADOX.Catalog COM 사용 가능'; [Runtime.InteropServices.Marshal]::ReleaseComObject($c) | Out-Null } catch { Log ('  ADOX.Catalog 없음: ' + $_.Exception.Message) }
Log 'ACE-DONE'

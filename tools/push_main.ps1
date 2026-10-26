# 사용자 실행용: 두 저장소 main push (ENV-0). Jenkins JU_TOMCAT_HOME 추가 후에 실행.
$ws='C:\MyData\MyDev\workspace'
foreach ($r in 'juprovider','juproject') { $p=Join-Path $ws $r; Write-Host "== $r"; git -C $p log origin/main..main --oneline; git -C $p push origin main }

$ws = 'C:\MyData\MyDev\workspace'; $pf = Join-Path $ws 'ai_ju1_local.pid'
if (Test-Path $pf) { Stop-Process -Id ([int](Get-Content $pf)) -Force -ErrorAction SilentlyContinue; Remove-Item $pf -Force; Write-Host '18081 서버 종료' } else { Write-Host '실행 중인 서버 없음' }

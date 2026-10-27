# Desktop Client 등록 도우미 (사용자가 직접 실행): 어드민 로그인 → Client 등록 → desktop\app\config\client.json 작성
# 키는 화면·로그에 출력하지 않고 client.json에만 쓴다 (Git 밖).
$ErrorActionPreference = 'Stop'
$base = Read-Host '서버 주소 (Enter = http://localhost:18081/juprovider)'; if (-not $base) { $base = 'http://localhost:18081/juprovider' }
$loginId = Read-Host '어드민 아이디'
$sec = Read-Host '비밀번호' -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$clientId = Read-Host 'CLIENT_ID (영문·숫자·_.-)'
$clientName = Read-Host 'Client 표시명'
$login = Invoke-RestMethod -Method Post -Uri "$base/api/auth/login" -ContentType 'application/json' -Body (@{ loginId = $loginId; password = $pw } | ConvertTo-Json)
$pw = $null
if ($login.data.passwordChangeRequired) { Write-Host '먼저 웹에서 비밀번호를 변경하세요.'; exit 1 }
$h = @{ Authorization = 'Bearer ' + $login.data.accessToken }
$r = Invoke-RestMethod -Method Post -Uri "$base/api/admin/clients" -Headers $h -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes((@{ clientId = $clientId; clientName = $clientName } | ConvertTo-Json)))
# Client는 {실행 폴더}\config\client.json 을 읽는다 (ClientSettings.cs)
$exe = Get-ChildItem 'C:\MyData\MyDev\workspace\juprovider\desktop\juprovider.client\bin' -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
$appDir = Read-Host ('Client 실행 폴더 (Enter = ' + $(if ($exe) { $exe.DirectoryName } else { '없음' }) + ')'); if (-not $appDir -and $exe) { $appDir = $exe.DirectoryName }
if (-not $appDir) { Write-Host 'Client 실행 폴더를 지정하세요.'; exit 1 }
$cfgDir = Join-Path $appDir 'config'; New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$cfg = @{ ServerUrl = "$base/"; ClientId = $r.data.clientId; ClientKey = $r.data.clientKey } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $cfgDir 'client.json'), $cfg, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("등록 완료: " + $r.data.clientId + " → " + (Join-Path $cfgDir 'client.json') + " (키는 이 파일에만 저장됨)")

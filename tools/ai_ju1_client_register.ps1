# Desktop Client 등록/재발급 도우미 (사용자가 직접 실행)
#  1) Client 실행 폴더를 먼저 확정 (juprovider.client.exe 확인) → API 호출 전에 확인해 키 유실 방지
#  2) 어드민 로그인 → Client 목록 조회
#     - 없음: 신규 등록
#     - 사용 중(YENO0001): 선택 시 /api/admin/clients/{id}/key 재발급 (이전 키 무효)
#     - 사용 중지: 재등록(POST /api/admin/clients) 선택 가능
#  3) 키는 {실행 폴더}\config\client.json 에만 저장. 콘솔·로그에 출력하지 않음 (desktop/app 은 .gitignore 대상)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$defApp = 'C:\MyData\MyDev\workspace\juprovider\desktop\app'
$appDir = Read-Host "Client 실행 폴더 (Enter = $defApp)"; if (-not $appDir) { $appDir = $defApp }
if (-not (Test-Path (Join-Path $appDir 'juprovider.client.exe'))) { Write-Host "중단: $appDir 에 juprovider.client.exe 없음"; exit 1 }
$base = Read-Host '서버 주소 (Enter = http://localhost:18081/juprovider)'; if (-not $base) { $base = 'http://localhost:18081/juprovider' }
$base = $base.TrimEnd('/')
$loginId = Read-Host '어드민 아이디'
$sec = Read-Host '비밀번호' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
function Api([string]$m, [string]$path, $body, $hdr) {
    $p = @{ Method = $m; Uri = "$base$path"; ContentType = 'application/json; charset=utf-8' }
    if ($hdr) { $p.Headers = $hdr }
    if ($null -ne $body) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)) }
    try { return @{ ok = $true; json = (Invoke-RestMethod @p) } }
    catch { $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}; return @{ ok = $false; code = $code } }
}
$r = Api 'POST' '/api/auth/login' @{ loginId = $loginId; password = $pw } $null; $pw = $null
if (-not $r.ok) { Write-Host ("중단: 로그인 실패 (HTTP " + $r.code + ")"); exit 1 }
if ($r.json.data.passwordChangeRequired) { Write-Host '중단: 먼저 웹에서 비밀번호를 변경하세요.'; exit 1 }
$h = @{ Authorization = 'Bearer ' + $r.json.data.accessToken }
$clientId = Read-Host 'CLIENT_ID (예: PCA_DESKTOP01)'
$list = Api 'GET' '/api/admin/clients' $null $h
if (-not $list.ok) { Write-Host ("중단: Client 목록 조회 실패 (HTTP " + $list.code + ")"); exit 1 }
$cur = @($list.json.data) | Where-Object { $_.clientId -eq $clientId } | Select-Object -First 1
if (-not $cur) {
    $name = Read-Host 'Client 표시명'
    $res = Api 'POST' '/api/admin/clients' @{ clientId = $clientId; clientName = $name } $h; $act = '신규 등록'
} elseif ($cur.useYn -eq 'YENO0001') {
    $a = Read-Host "$clientId 는 이미 사용 중입니다. 키를 재발급할까요? 이전 키는 즉시 무효가 됩니다 (Y/N)"
    if ($a -notmatch '^[Yy]') { Write-Host '취소'; exit 0 }
    $res = Api 'POST' "/api/admin/clients/$clientId/key" $null $h; $act = '키 재발급'
} else {
    $a = Read-Host "$clientId 는 사용 중지 상태입니다. 재등록(재활성화)할까요? (Y/N)"
    if ($a -notmatch '^[Yy]') { Write-Host '취소'; exit 0 }
    $name = Read-Host ('Client 표시명 (Enter = ' + $cur.clientName + ')'); if (-not $name) { $name = $cur.clientName }
    $res = Api 'POST' '/api/admin/clients' @{ clientId = $clientId; clientName = $name } $h; $act = '재등록'
}
if (-not $res.ok -or -not $res.json.data.clientKey) { Write-Host ("중단: $act 실패 (HTTP " + $res.code + ")"); exit 1 }
$cfgDir = Join-Path $appDir 'config'; New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$cfgPath = Join-Path $cfgDir 'client.json'
$cfg = [ordered]@{ ServerUrl = "$base/"; ClientId = $clientId; ClientKey = $res.json.data.clientKey } | ConvertTo-Json
[IO.File]::WriteAllText($cfgPath, $cfg, (New-Object System.Text.UTF8Encoding($false)))
$res = $null; $cfg = $null
Write-Host ("$act 완료: $clientId → $cfgPath (키는 이 파일에만 저장)")

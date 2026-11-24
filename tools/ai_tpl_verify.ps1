# 표준 템플릿 확인 보완 (읽기만): ai_tpl 의 해시 함수 이름(H)이 PowerShell 기본 별칭(h=Get-History)과 겹쳐 해시·내용 점검이 비어 있었음 → 다시 확인
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ws  = 'C:\MyData\MyDev\workspace'
$jp  = Join-Path $ws 'juprovider'
$app = Join-Path $jp 'desktop\app'
$res = Join-Path $jp 'desktop\resources\template.accdb'
$userDb = Join-Path $app 'data\juprovider.accdb'
$log = Join-Path $ws ("ai_tpl_verify_{0}.log" -f $env:COMPUTERNAME)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $enc)
function Log([string]$t) { Write-Host $t; [IO.File]::AppendAllText($log, $t + "`r`n", $enc) }
function FileHash16([string]$p) { if (Test-Path $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 16) } else { return '(없음)' } }
function Show-Db([string]$db) {
    try {
        $cn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$db;")
        $cn.Open()
        foreach ($t in 'LOCAL_DEVICE', 'LOCAL_SCHEMA_INFO', 'LOCAL_SYNC_STATE', 'LOCAL_USER') {
            try {
                $cmd = $cn.CreateCommand(); $cmd.CommandText = "SELECT COUNT(*) FROM [$t]"; $n = $cmd.ExecuteScalar()
                $cmd = $cn.CreateCommand(); $cmd.CommandText = "SELECT * FROM [$t] WHERE 1=0"; $r = $cmd.ExecuteReader(); $cols = @(for ($i = 0; $i -lt $r.FieldCount; $i++) { $r.GetName($i) }); $r.Close()
                Log ("    $t 행 $n | " + ($cols -join ','))
            } catch { Log ("    $t 없음/실패: " + $_.Exception.Message) }
        }
        try { $cmd = $cn.CreateCommand(); $cmd.CommandText = "SELECT INFO_KEY, INFO_VALUE FROM LOCAL_SCHEMA_INFO"; $r = $cmd.ExecuteReader(); while ($r.Read()) { Log ("    LOCAL_SCHEMA_INFO: " + $r.GetValue(0) + '=' + $r.GetValue(1)) }; $r.Close() } catch { Log ('    LOCAL_SCHEMA_INFO 읽기 실패: ' + $_.Exception.Message) }
        $cn.Close()
    } catch { Log ('    !! 열기·조회 실패: ' + $_.Exception.Message) }
    [System.Data.OleDb.OleDbConnection]::ReleaseObjectPool()
}
Log ("verify " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Log ("  git " + @(cmd /c "git -C `"$jp`" rev-parse --abbrev-ref HEAD 2>nul")[0] + " @ " + @(cmd /c "git -C `"$jp`" log -1 --format=%h 2>nul")[0] + ", origin " + @(cmd /c "git -C `"$jp`" rev-parse --short origin/feature/local-db-template 2>nul")[0])
Log ("  .gitattributes: " + ((Get-Content (Join-Path $jp '.gitattributes')) -join ' / '))
Log ("  git check-attr: " + (& git -C $jp check-attr binary -- desktop/resources/template.accdb))
$hr = FileHash16 $res; $hs = FileHash16 (Join-Path $app 'config\template.accdb'); $hg = FileHash16 (Join-Path $ws 'ai_changes\tpl\gen\template.accdb')
$tmp = Join-Path $env:TEMP 'ju_tpl_head.accdb'; cmd /c "git -C `"$jp`" show HEAD:desktop/resources/template.accdb > `"$tmp`"" ; $hh = FileHash16 $tmp; Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Log "  해시: 저장소 파일 $hr / commit(HEAD) 내용 $hh / app\config $hs / 생성 원본 $hg"
Log ("  크기: " + (Get-Item $res).Length + " B")
Log '  [표준 템플릿 desktop/resources/template.accdb]'; Show-Db $res
Log '  [기존 설치 사용자 DB app\data\juprovider.accdb]'; Show-Db $userDb
Log ("  사용자 DB 수정 시각 " + (Get-Item $userDb).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + ", 생성 시각 " + (Get-Item $userDb).CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))
Log 'VERIFY-DONE'

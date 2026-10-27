// JU-1c Desktop online/offline smoke (DesktopAuthService + LOCAL_USER)
// args: serverUrl clientId
// env : JU_SMOKE_CLIENT_KEY, JU_SMOKE_PW_USR, JU_SMOKE_PW_USR2, JU_SMOKE_PW_NEW  (값은 출력하지 않는다)
using System.Data.OleDb;
using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Text;
using JuProvider.Lib.Data.Auth;
using JuProvider.Lib.Data.Local;

string server = args[0];
string clientId = args[1];
string key = Env("JU_SMOKE_CLIENT_KEY");
string pwUsr = Env("JU_SMOKE_PW_USR");
string pwUsr2 = Env("JU_SMOKE_PW_USR2");
string pwNew = Env("JU_SMOKE_PW_NEW");
const string down = "http://localhost:18099/juprovider/";
int fail = 0, pass = 0;

void Check(string name, bool ok, string note = "")
{
    if (ok) pass++; else fail++;
    Console.WriteLine($"  [{(ok ? "PASS" : "FAIL")}] {name} {note}");
}

// 503을 돌려주는 가짜 서버 (5xx → OFFLINE 확인)
TcpListener err = new(IPAddress.Loopback, 0);
err.Start();
int errPort = ((IPEndPoint)err.LocalEndpoint).Port;
_ = Task.Run(async () =>
{
    while (true)
    {
        try
        {
            using TcpClient c = await err.AcceptTcpClientAsync();
            using NetworkStream s = c.GetStream();
            byte[] buf = new byte[8192];
            _ = await s.ReadAsync(buf);
            byte[] resp = Encoding.ASCII.GetBytes("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            await s.WriteAsync(resp);
        }
        catch { return; }
    }
});
string errUrl = $"http://127.0.0.1:{errPort}/juprovider/";

// Local DB 새로 시작
LocalDatabase db = new();
if (File.Exists(db.DatabasePath)) File.Delete(db.DatabasePath);
Console.WriteLine("template LOCAL_USER 컬럼: " + await Cols(db, true));
await db.InitializeAsync();
Console.WriteLine("초기화 후 LOCAL_USER 컬럼: " + await Cols(db, false));
LocalDeviceRepository devices = new(db);
LocalUserRepository users = new(db);
DesktopAuthService Svc(string url, string? id, string? k) => new(devices, users, url, id, k);

Console.WriteLine("== 1. PBKDF2 검증자");
{
    string t1 = OfflineCredential.Create("Sample-Pass-1");
    string t2 = OfflineCredential.Create("Sample-Pass-1");
    Check("형식 pbkdf2-sha256$210000$salt$hash", t1.StartsWith("pbkdf2-sha256$210000$") && t1.Split('$').Length == 4);
    Check("같은 비밀번호도 salt가 달라 결과가 다름", t1 != t2);
    Check("검증 성공 / 다른 비밀번호 실패", OfflineCredential.Verify("Sample-Pass-1", t1) && !OfflineCredential.Verify("Sample-Pass-2", t1));
    string[] p = t1.Split('$'); p[3] = Convert.ToBase64String(new byte[32]);
    Check("변조된 검증자 실패 / 반복 횟수 낮춤 거부", !OfflineCredential.Verify("Sample-Pass-1", string.Join('$', p)) && !OfflineCredential.Verify("Sample-Pass-1", t1.Replace("$210000$", "$1000$")));
}

Console.WriteLine("== 2. 연결 상태 분류");
{
    var r = await Svc(server, clientId, key).SyncAsync();
    Check("유효 키 → ONLINE", r.State == ConnectionState.Online, $"devices={r.DeviceCount}");
    Check("장치 Local DB 반영", (await devices.GetAllAsync()).Count == r.DeviceCount && r.DeviceCount > 0);
    Check("잘못된 키 → CLIENT_REJECTED", (await Svc(server, clientId, "wrong-key-value-000000000000000000000000000").SyncAsync()).State == ConnectionState.ClientRejected);
    Check("Client 자격 없음 → CLIENT_REJECTED", (await Svc(server, null, null).SyncAsync()).State == ConnectionState.ClientRejected);
    Check("서버 없음(연결 실패) → OFFLINE", (await Svc(down, clientId, key).SyncAsync()).State == ConnectionState.Offline);
    Check("서버 503 → OFFLINE", (await Svc(errUrl, clientId, key).SyncAsync()).State == ConnectionState.Offline);
}

Console.WriteLine("== 3. 온라인 로그인 / offline credential 저장");
{
    var r = await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr);
    Check("온라인 로그인 성공", r.Code == LoginResultCode.OnlineSuccess && r.Session?.Mode == ConnectionState.Online && !string.IsNullOrEmpty(r.Session?.AccessToken), r.Code.ToString());
    Check("세션 ToString에 토큰 없음", r.Session != null && !r.Session.ToString().Contains(r.Session.AccessToken ?? "#none#"));
    var u = await users.GetAsync("smoke_usr");
    Check("LOCAL_USER 저장 (Y, 실패 0, 잠금 N, DEVICE_ID=Client)", u != null && u.EnabledYn == "Y" && u.OfflineFailCount == 0 && u.OfflineLockYn == "N" && u.DeviceId == clientId);
    Check("검증자만 저장 (평문 비밀번호 없음)", u?.OfflineToken != null && u.OfflineToken.StartsWith("pbkdf2-sha256$") && !u.OfflineToken.Contains(pwUsr));
    Check("만료 = 온라인 인증 + 7일", u?.ExpireDt != null && Math.Abs((u.ExpireDt.Value - DateTime.Now.AddDays(7)).TotalMinutes) < 5);
}

Console.WriteLine("== 4. 오프라인 로그인");
{
    var r = await Svc(down, clientId, key).LoginAsync("smoke_usr", pwUsr);
    Check("서버 없음 + 이전 사용자 → OFFLINE 성공", r.Code == LoginResultCode.OfflineSuccess && r.Session?.Mode == ConnectionState.Offline && r.Session.AccessToken == null, r.Code.ToString());
    Check("서버 503 + 이전 사용자 → OFFLINE 성공", (await Svc(errUrl, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OfflineSuccess);
    Check("최초 사용자(smoke_mgr) offline 불가", (await Svc(down, clientId, key).LoginAsync("smoke_mgr", "Any-Pass-123")).Code == LoginResultCode.OfflineNotAvailable);
    Check("다른 Client ID에서는 offline 불가", (await Svc(down, "OTHER_PC", key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OfflineNotAvailable);
}

Console.WriteLine("== 5. offline 실패 5회 잠금 (LOCAL_USER)");
{
    var s = Svc(down, clientId, key);
    bool four = true;
    for (int i = 1; i <= 4; i++) four &= (await s.LoginAsync("smoke_usr", "Wrong-Pass-" + i)).Code == LoginResultCode.InvalidCredentials;
    Check("1~4회 실패 → 비밀번호 오류", four && (await users.GetAsync("smoke_usr"))?.OfflineFailCount == 4);
    Check("5회째 → 잠금", (await s.LoginAsync("smoke_usr", "Wrong-Pass-5")).Code == LoginResultCode.OfflineLocked && (await users.GetAsync("smoke_usr"))?.OfflineLockYn == "Y");
    Check("잠금 후 올바른 비밀번호도 offline 불가", (await s.LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OfflineLocked);
    Check("온라인 로그인 성공 → 잠금 해제", (await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OnlineSuccess
        && (await users.GetAsync("smoke_usr")) is { OfflineFailCount: 0, OfflineLockYn: "N" });
    Check("해제 후 offline 성공", (await s.LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OfflineSuccess);
}

Console.WriteLine("== 6. offline 만료");
{
    await using (OleDbConnection c = db.CreateConnection())
    {
        await c.OpenAsync();
        await using OleDbCommand cmd = new("UPDATE LOCAL_USER SET EXPIRE_DT = ? WHERE USER_ID = 'smoke_usr'", c);
        cmd.Parameters.Add(new OleDbParameter { OleDbType = OleDbType.Date, Value = DateTime.Now.AddMinutes(-1) });
        await cmd.ExecuteNonQueryAsync();
    }
    Check("만료 → offline 불가", (await Svc(down, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OfflineExpired);
    Check("온라인 로그인으로 만료 갱신", (await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OnlineSuccess
        && (await Svc(down, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OfflineSuccess);
}

Console.WriteLine("== 7. 서버 401 → offline fallback 금지");
{
    var r = await Svc(server, clientId, key).LoginAsync("smoke_usr", "Wrong-Pass-X");
    Check("온라인 비밀번호 오류 → 401 처리 (offline 성공으로 넘어가지 않음)", r.Code == LoginResultCode.InvalidCredentials && r.Session == null, r.Code.ToString());
    Check("서버 거부 후 offline 허용 해제 (ENABLED_YN=N)", (await users.GetAsync("smoke_usr"))?.EnabledYn == "N");
    Check("해제 상태에서 서버 없음 → offline 불가", (await Svc(down, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OfflineDisabled);
    Check("온라인 재로그인 → 다시 허용", (await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.OnlineSuccess && (await users.GetAsync("smoke_usr"))?.EnabledYn == "Y");
}

Console.WriteLine("== 8. CLIENT_REJECTED → 로그인 차단, offline fallback 금지");
{
    var before = await users.GetAsync("smoke_usr");
    var r = await Svc(server, clientId, "wrong-key-value-000000000000000000000000000").LoginAsync("smoke_usr", pwUsr);
    Check("잘못된 Client 키 + 올바른 비밀번호 → CLIENT_REJECTED", r.Code == LoginResultCode.ClientRejected && r.Session == null, r.Code.ToString());
    Check("Client 자격 없음 → CLIENT_REJECTED", (await Svc(server, null, null).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.ClientRejected);
    var after = await users.GetAsync("smoke_usr");
    Check("LOCAL_USER 변화 없음", before?.OfflineToken == after?.OfflineToken && after?.EnabledYn == "Y" && after?.OfflineFailCount == 0);
}

Console.WriteLine("== 9. 비밀번호 변경 필요 사용자");
{
    var r = await Svc(server, clientId, key).LoginAsync("smoke_new", pwNew);
    Check("passwordChangeRequired → Desktop 로그인 거부", r.Code == LoginResultCode.PasswordChangeRequired && r.Session == null, r.Code.ToString());
    Check("offline credential 저장 안 함", (await users.GetAsync("smoke_new"))?.EnabledYn != "Y");
    Check("서버 없음 → offline 불가", (await Svc(down, clientId, key).LoginAsync("smoke_new", pwNew)).Code != LoginResultCode.OfflineSuccess);
}

Console.WriteLine("== 10. 서버 비밀번호 변경 후 검증자 교체");
{
    var r = await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr);
    using HttpClient http = new() { BaseAddress = new Uri(server) };
    http.DefaultRequestHeaders.Authorization = new("Bearer", r.Session?.AccessToken);
    var pr = await http.PostAsJsonAsync("api/auth/password", new { currentPassword = pwUsr, newPassword = pwUsr2 });
    Check("서버 비밀번호 변경", pr.StatusCode == HttpStatusCode.OK, ((int)pr.StatusCode).ToString());
    Check("이전 비밀번호 온라인 → 거부", (await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.InvalidCredentials);
    Check("새 비밀번호 온라인 → 성공", (await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr2)).Code == LoginResultCode.OnlineSuccess);
    Check("offline: 이전 비밀번호 실패 / 새 비밀번호 성공",
        (await Svc(down, clientId, key).LoginAsync("smoke_usr", pwUsr)).Code == LoginResultCode.InvalidCredentials
        && (await Svc(down, clientId, key).LoginAsync("smoke_usr", pwUsr2)).Code == LoginResultCode.OfflineSuccess);
}

Console.WriteLine("== 11. 기존 LOCAL_USER(컬럼 없음) → 컬럼 추가, 행 보존");
{
    await using (OleDbConnection c = db.CreateConnection())
    {
        await c.OpenAsync();
        foreach (string sql in new[] {
            "DROP TABLE LOCAL_USER",
            "CREATE TABLE LOCAL_USER (USER_ID VARCHAR(100) NOT NULL, SERVER_USER_ID VARCHAR(100), DEVICE_ID VARCHAR(100), OFFLINE_TOKEN LONGTEXT, LAST_AUTH_DT DATETIME, EXPIRE_DT DATETIME, ENABLED_YN VARCHAR(8), CONSTRAINT PK_LOCAL_USER PRIMARY KEY (USER_ID))",
            "INSERT INTO LOCAL_USER (USER_ID, ENABLED_YN) VALUES ('legacy_user', 'N')" })
        {
            await using OleDbCommand cmd = new(sql, c);
            await cmd.ExecuteNonQueryAsync();
        }
    }
    await db.InitializeAsync();
    var legacy = await users.GetAsync("legacy_user");
    Check("ALTER로 OFFLINE_FAIL_CNT/OFFLINE_LOCK_YN 추가, 기존 행 유지", legacy != null && legacy.EnabledYn == "N" && legacy.OfflineFailCount == 0);
    Check("추가 후 저장 동작", (await Svc(server, clientId, key).LoginAsync("smoke_usr", pwUsr2)).Code == LoginResultCode.OnlineSuccess && (await users.GetAsync("smoke_usr"))?.OfflineLockYn == "N");
}

err.Stop();
Console.WriteLine($"DESKTOP JU-1c SMOKE PASS {pass} FAIL {fail}");
return fail == 0 ? 0 : 1;

static async Task<string> Cols(LocalDatabase d, bool template)
{
    string path = template ? Path.Combine(AppContext.BaseDirectory, "config", "template.accdb") : d.DatabasePath;
    await using OleDbConnection c = new($"Provider=Microsoft.ACE.OLEDB.12.0;Data Source={path};Persist Security Info=False;");
    await c.OpenAsync();
    var t = c.GetOleDbSchemaTable(OleDbSchemaGuid.Columns, new object?[] { null, null, "LOCAL_USER", null });
    return t == null || t.Rows.Count == 0 ? "(없음)" : string.Join(",", t.Rows.Cast<System.Data.DataRow>().OrderBy(r => Convert.ToInt32(r["ORDINAL_POSITION"])).Select(r => r["COLUMN_NAME"]));
}

static string Env(string name) => Environment.GetEnvironmentVariable(name) ?? throw new InvalidOperationException(name + " missing");

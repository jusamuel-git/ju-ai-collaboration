// C5d 실장비 회귀 도구 (제품 저장소 밖).
// 실제 C5c 서버 응답(ai_c4srv -C5d 가 저장한 protocols·data-tags·data-map JSON) + 내장 설정 없음(서버 값만) → CollectionPlan
// → DeviceSession(서버 초기화 루틴·명령 간격·Frame·역할·동작·응답 판정·멱등 + data-map 매핑) + LinkSupervisor + 직렬 포트(기본 COM3).
// 루틴은 세션이 자동 실행(도구는 손대지 않음). 장비에는 중지·장치확인·센서정보·모드·시작만 보낸다.
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using JuProvider.Lib.Protocol.Mapping;
using JuProvider.Lib.Protocol.Scheduling;
using JuProvider.Lib.Protocol.Session;
using JuProvider.Lib.Protocol.Sync;
using JuProvider.Lib.Protocol.Transport;

string port = args.Length > 0 ? args[0] : "COM3";
int baud = args.Length > 1 ? int.Parse(args[1]) : 115200;
int cableWaitSec = args.Length > 2 ? int.Parse(args[2]) : 60;
string serverDir = args.Length > 3 ? args[3] : @"C:\MyData\MyDev\workspace\ai_changes\c5d\server";
const string Dev = "SDEV_GTEC01";
var sw = Stopwatch.StartNew();
void Log(string s) => Console.WriteLine($"[{sw.ElapsedMilliseconds,6} ms] {s}");
int fail = 0;
void Check(bool ok, string what) { Log((ok ? "OK   " : "FAIL ") + what); if (!ok) fail++; }

var web = new JsonSerializerOptions(JsonSerializerDefaults.Web);
var group = JsonSerializer.Deserialize<SyncResult<ProtocolGroupSync>>(File.ReadAllText(Path.Combine(serverDir, "protocols_GTEC.json")), web)!.Items[0];
var tags = JsonSerializer.Deserialize<SyncResult<DataTagSync>>(File.ReadAllText(Path.Combine(serverDir, "data_tags.json")), web)!.Items;
var dataMap = JsonSerializer.Deserialize<SyncResult<DataChannelMapSync>>(File.ReadAllText(Path.Combine(serverDir, "data_map.json")), web)!.Items;
CollectionPlan plan = CollectionPlanBuilder.Build(Dev, group, tags, CollectionProfile.Empty("GTEC"), dataMap);
Log($"PLAN {plan.PtlGrpCd}: 프로토콜 {plan.Protocols.Count}, 간격 {plan.Scheduler.InterCommandGapMs} ms, 루틴 {string.Join("→", plan.Session.InitRoutine!)}, 시작문자 '{Encoding.ASCII.GetString(plan.Frame.Start ?? [])}', 매핑 {plan.MapEntries.Count}");
foreach (string w in plan.Warnings) Log("     계획 경고: " + w);
Log("     출처: " + string.Join(", ", plan.Sources.Where(k => !k.Key.Contains('.') || k.Key.StartsWith("GTEC03")).Select(k => $"{k.Key}={k.Value}")));
Check(new[] { "frame", "cmdGapMs", "initDelayMs", "initRoutine", "map" }.All(k => plan.Sources.GetValueOrDefault(k) == "server"), "계획 출처: 서버 값만 (내장 설정 없음)");
Check(plan.Session.InitRoutine is { Count: 4 } r0 && r0[0] == "GTEC0301" && plan.Scheduler.InterCommandGapMs == 200 && plan.Frame.Start is [(byte)'{'], "서버 초기화 루틴(STOP 먼저)·간격 200·시작 문자");

var transport = new SerialTransport(new SerialSettings(port, baud));
var policy = new ReconnectPolicy([TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(3)], TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(5));
var supervisor = new LinkSupervisor(transport, policy);
var linkEvents = new ConcurrentQueue<LinkEventKind>();
supervisor.Event += (_, e) => { linkEvents.Enqueue(e.Kind); if (e.Kind != LinkEventKind.Reconnecting) Log($"LINK {e.Kind} attempt={e.Attempt}{(e.Error is null ? "" : " " + e.Error.GetType().Name)}"); };

DeviceSession session = plan.CreateSession(transport);
var values = new ConcurrentQueue<LogicalValue>();
var inits = new ConcurrentQueue<InitRoutineResult>();
int warnCount = 0, unhandled = 0;
session.Values += (_, e) => { foreach (var v in e.Values) values.Enqueue(v); };
session.InitCompleted += (_, r) => { inits.Enqueue(r); Log($"INIT {(r.AllOk ? "OK" : "NG")} " + string.Join(", ", r.Steps.Select(s => $"{s.Key}:{s.Value.Status}"))); };
session.Warning += (_, w) => { Interlocked.Increment(ref warnCount); Log("WARN " + w); };
session.UnhandledFrame += (_, f) => { Interlocked.Increment(ref unhandled); Log("UNHANDLED " + Encoding.ASCII.GetString(f.Body)); };
session.StateChanged += (_, s) => Log($"SESSION {s}");

async Task<bool> WaitFor(Func<bool> c, int ms) { var t = Stopwatch.StartNew(); while (t.ElapsedMilliseconds < ms) { if (c()) return true; await Task.Delay(50); } return c(); }

async Task Collect(string label, int ms)
{
    while (values.TryDequeue(out _)) { }
    var start = await session.ExecuteAsync("GTEC0300");
    Check(start.Ok, $"[{label}] START ({start.Status})");
    await Task.Delay(ms);
    var got = values.ToArray();
    var refs = got.Select(v => v.Data?.Key ?? "UNMAPPED").Distinct().OrderBy(x => x, StringComparer.Ordinal).ToArray();
    Log($"[{label}] 값 {got.Length}개(≈{got.Length / 3} 프레임 / {ms} ms), 대상 {string.Join(",", refs)}, 품질 {string.Join(",", got.GroupBy(v => v.Quality).Select(g => $"{g.Key}={g.Count()}"))}");
    if (got.Length > 0) Log($"     예: CH{got[0].Channel.ChannelKey} → {got[0].Data?.Key} = {got[0].Value}");
    Check(got.Length / 3 >= ms / 200, $"[{label}] 데이터 수신");
    Check(refs.SequenceEqual(new[] { "DG_GTEC01/GTEC-DATA-01/1", "DG_GTEC01/GTEC-DATA-02/2", "DG_GTEC01/GTEC-DATA-03/3" }), $"[{label}] 매핑 DG_GTEC01/GTEC-DATA-01..03");
    Check(got.All(v => v.Quality == DataQuality.Good), $"[{label}] 품질 GOOD");
}

bool measuring = false;
try
{
    Log($"START {port} {baud}");
    await supervisor.StartAsync();
    await session.StartAsync();
    Check(await WaitFor(() => inits.Count >= 1, 30000), "연결 → 초기화 루틴 자동 실행");
    Check(inits.LastOrDefault()?.AllOk == true, "초기화 루틴 전부 성공 (STOP→확인→센서정보→모드)");
    Check(session.State == DeviceSessionState.Ready, "세션 Ready");

    measuring = true;
    await Collect("1차", 5000);
    var stop = await session.ExecuteAsync("GTEC0301");
    Check(stop.Ok, "STOP");
    await Task.Delay(700); int n1 = values.Count; await Task.Delay(1500);
    Check(values.Count == n1, "중지 후 수신 없음");

    // 측정 중 상태로 케이블 분리 (재연결 시 STOP 먼저 루틴 확인)
    await session.ExecuteAsync("GTEC0300");
    await Task.Delay(1000);
    Check(values.Count > n1, "측정 재시작 (측정 중 상태로 분리 준비)");
    while (linkEvents.TryDequeue(out _)) { }
    int initsBefore = inits.Count;
    Console.Beep();
    Log("==================================================");
    Log($">>> 측정 중입니다. 지금 {port} 장비 USB 케이블을 뽑아 주세요 ({cableWaitSec}초 대기) <<<");
    Log("==================================================");
    bool faulted = await WaitFor(() => session.State == DeviceSessionState.Suspended, cableWaitSec * 1000);
    if (!faulted) Log("SKIP 케이블 분리 감지 안 됨");
    else
    {
        Check(true, "케이블 분리 → 세션 Suspended");
        Console.Beep();
        Log(">>> 이제 케이블을 다시 꽂아 주세요 (60초 대기) <<<");
        bool back = await WaitFor(() => inits.Count > initsBefore, 60000);
        Check(back, "재연결 → 초기화 루틴 자동 재실행");
        Check(inits.LastOrDefault()?.AllOk == true, "재연결 루틴 전부 성공 (STOP 먼저)");
        Check(session.State == DeviceSessionState.Ready, "재연결 후 세션 Ready");
        if (back)
        {
            await Collect("재연결 후", 5000);
            Check((await session.ExecuteAsync("GTEC0301")).Ok, "재연결 후 STOP");
            await Task.Delay(700); int m1 = values.Count; await Task.Delay(1500);
            Check(values.Count == m1, "재연결 후 중지 후 수신 없음");
        }
    }
    measuring = false;
}
catch (Exception ex)
{
    Log($"EXCEPTION {ex.GetType().Name}: {ex.Message}");
    fail++;
}
finally
{
    if (measuring && transport.State == TransportState.Open)
    {
        try { await transport.WriteAsync(Encoding.ASCII.GetBytes("S{10,0}")); await Task.Delay(300); } catch { }
    }
    await session.StopAsync();
    await supervisor.DisposeAsync();
}
Log($"경고 {warnCount}건, 처리 안 된 프레임 {unhandled}건, 초기화 루틴 {inits.Count}회");
Log(fail == 0 ? "PROBE-PASS" : $"PROBE-FAIL ({fail})");
return fail == 0 ? 0 : 1;

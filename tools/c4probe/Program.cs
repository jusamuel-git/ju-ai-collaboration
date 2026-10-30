// C4 실장비 회귀 확인용 임시 도구 (제품 저장소 밖).
// 서버 내려받기 응답(seed 기준 JSON) + 내장 GTEC 수집 설정 → CollectionPlan → DeviceSession(초기화 루틴·명령 간격·시작 문자) + LinkSupervisor + COM6.
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

string port = args.Length > 0 ? args[0] : "COM6";
int baud = args.Length > 1 ? int.Parse(args[1]) : 115200;
int cableWaitSec = args.Length > 2 ? int.Parse(args[2]) : 60;
const string Dev = "SDEV_GTEC01";
var sw = Stopwatch.StartNew();
void Log(string s) => Console.WriteLine($"[{sw.ElapsedMilliseconds,6} ms] {s}");
int fail = 0;
void Check(bool ok, string what) { Log((ok ? "OK   " : "FAIL ") + what); if (!ok) fail++; }

var web = new JsonSerializerOptions(JsonSerializerDefaults.Web);
var group = JsonSerializer.Deserialize<SyncResult<ProtocolGroupSync>>(ProtocolsJson, web)!.Items[0];
var tags = JsonSerializer.Deserialize<SyncResult<DataTagSync>>(TagsJson, web)!.Items;
CollectionPlan plan = CollectionPlanBuilder.Build(Dev, group, tags);
Log($"PLAN {plan.PtlGrpCd}: 프로토콜 {plan.Protocols.Count}, 간격 {plan.Scheduler.InterCommandGapMs} ms, 루틴 {string.Join("→", plan.Session.InitRoutine!)}, 시작문자 '{Encoding.ASCII.GetString(plan.Frame.Start ?? [])}', 매핑 {plan.MapEntries.Count}");
foreach (string w in plan.Warnings) Log("     계획 경고: " + w);

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
    Log($">>> 측정 중입니다. 지금 COM6 장비 USB 케이블을 뽑아 주세요 ({cableWaitSec}초 대기) <<<");
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

partial class Program
{
    const string ProtocolsJson = """
    { "revision": "r1", "removed": [], "items": [ {
        "ptlGrpCd": "GTEC", "ptlGrpNm": "그린테크", "pollingIntval": 1000, "timeoutMs": 3000, "retryCnt": 3, "sortOrd": 0,
        "protocols": [
          { "ptlCd": "GTEC0000", "ptlType": "PROT0000", "ptlLen": null, "ptlVal": "S{TEST}[CR][LF]", "ptlNm": "장치확인(가상)", "ptlDesc": null,
            "packets": [
              { "packetSeq": 1, "packetType": "TX_PACKET", "direction": "TX", "packetExpr": "S{TEST}[CR][LF]", "responsePtlCd": null, "parseRule": "", "dataCount": 0, "dataType": null, "dataPosition": null },
              { "packetSeq": 2, "packetType": "RX_PACKET", "direction": "RX", "packetExpr": "{OK}[CR][LF]", "responsePtlCd": null, "parseRule": "패킷길이|STX DLE|ETX|ETX DLE", "dataCount": 0, "dataType": null, "dataPosition": null } ] },
          { "ptlCd": "GTEC0001", "ptlType": "PROT0000", "ptlVal": "S{10,3}", "ptlNm": "장치확인", "packets": [
              { "packetSeq": 1, "packetType": "TX_PACKET", "direction": "TX", "packetExpr": "S{10,3}", "parseRule": "", "dataCount": 0 } ] },
          { "ptlCd": "GTEC0002", "ptlType": "PROT0000", "ptlVal": "S{20}", "ptlNm": "센서정보", "packets": [] },
          { "ptlCd": "GTEC0100", "ptlType": "PROT0000", "ptlVal": "S{11,1}", "ptlNm": "모드", "packets": [] },
          { "ptlCd": "GTEC0300", "ptlType": "PROT0000", "ptlVal": "S{10,1}", "ptlNm": "시작", "packets": [] },
          { "ptlCd": "GTEC0301", "ptlType": "PROT0000", "ptlVal": "S{10,0}", "ptlNm": "중지", "packets": [] },
          { "ptlCd": "GTEC0400", "ptlType": "PROT0000", "ptlVal": "", "ptlNm": "저속 데이터", "packets": [] },
          { "ptlCd": "GTEC0401", "ptlType": "PROT0000", "ptlVal": "", "ptlNm": "고속 데이터", "packets": [] }
        ] } ] }
    """;

    const string TagsJson = """
    { "revision": "t1", "removed": [], "items": [
      { "devCd": "SDEV_GTEC01", "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-01", "datIdx": 1, "datType": "DATA0001", "datUnit": "", "tagId": "CH1", "datNm": "GTEC Analog CH1", "datMin": null, "datMax": null, "sortOrd": 1 },
      { "devCd": "SDEV_GTEC01", "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-02", "datIdx": 2, "datType": "DATA0001", "datUnit": "", "tagId": "CH2", "sortOrd": 2 },
      { "devCd": "SDEV_GTEC01", "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-03", "datIdx": 3, "datType": "DATA0001", "datUnit": "", "tagId": "CH3", "sortOrd": 3 },
      { "devCd": "SDEV_GTEC01", "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-04", "datIdx": 4, "datType": "DATA0001", "datUnit": "", "tagId": "CH4", "datMin": 0.0000000000, "datMax": 1.0000000000, "sortOrd": 4 },
      { "devCd": "VDEV_GTEC01", "datGrCd": "DG_GTECV01", "datCd": "VGTEC-DATA-01", "datIdx": 1, "datType": "DATA0001", "datUnit": "%", "tagId": "CH1", "sortOrd": 1 }
    ] }
    """;
}

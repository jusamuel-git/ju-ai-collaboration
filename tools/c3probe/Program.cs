// C3 실장비 확인용 임시 도구 (제품 저장소 밖). DeviceSession + LinkSupervisor + SerialTransport 경로.
// 장비에는 장치확인·센서정보·모드·측정 시작/중지만 보낸다.
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using JuProvider.Lib.Protocol.Mapping;
using JuProvider.Lib.Protocol.Model;
using JuProvider.Lib.Protocol.Rules;
using JuProvider.Lib.Protocol.Scheduling;
using JuProvider.Lib.Protocol.Session;
using JuProvider.Lib.Protocol.Transport;

string port = args.Length > 0 ? args[0] : "COM6";
int baud = args.Length > 1 ? int.Parse(args[1]) : 115200;
int cableWaitSec = args.Length > 2 ? int.Parse(args[2]) : 45;
const string Dev = "SDEV_GTEC01";
var sw = Stopwatch.StartNew();
void Log(string s) => Console.WriteLine($"[{sw.ElapsedMilliseconds,6} ms] {s}");
int fail = 0;
void Check(bool ok, string what) { Log((ok ? "OK   " : "FAIL ") + what); if (!ok) fail++; }
string B(CommandResult r) => r.Response is null ? "-" : Encoding.ASCII.GetString(r.Response.Body);

var defs = new List<ProtocolDefinition>
{
    new() { PtlCd = "GTEC0001", Pattern = ExchangePattern.TxRx, Roles = ProtocolRole.Info, Tx = "S{10,3}",
            Expect = ResponseMatcher.Regex(@"^\{[A-Za-z]"), TimeoutMs = 1500, RetryCount = 1 },
    new() { PtlCd = "GTEC0002", Pattern = ExchangePattern.TxRx, Roles = ProtocolRole.Info, Tx = "S{20}",
            Expect = ResponseMatcher.Regex(@"^\{\d{3},\d{3},\d{3},\d{3}\}$"), TimeoutMs = 1500, RetryCount = 1 },
    new() { PtlCd = "GTEC0100", Pattern = ExchangePattern.TxOnly, Roles = ProtocolRole.Control, Tx = "S{11,1}", Idempotent = true },
    new() { PtlCd = "GTEC0300", Pattern = ExchangePattern.TxOnly, Roles = ProtocolRole.Control, Action = CommandAction.Start, Tx = "S{10,1}" },
    new() { PtlCd = "GTEC0301", Pattern = ExchangePattern.TxOnly, Roles = ProtocolRole.Control, Action = CommandAction.Stop, Tx = "S{10,0}" },
    new() { PtlCd = "GTEC0400", Pattern = ExchangePattern.RxStream, Roles = ProtocolRole.Data,
            Parse = new ParseRule { Kind = ParseKind.Text, Trim = "{}", Separator = TextSeparator.Space, Count = 3 } },
};
var mapper = new DataMapper(LegacyTagIdMapping.ToEntries(
[
    new(Dev, "GTEC", "AIN", 1, "CH1"),
    new(Dev, "GTEC", "AIN", 2, "CH2"),
    new(Dev, "GTEC", "AIN", 3, "CH3"),
]));

var transport = new SerialTransport(new SerialSettings(port, baud));
var policy = new ReconnectPolicy([TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(3)], TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(5));
var supervisor = new LinkSupervisor(transport, policy);
var linkEvents = new ConcurrentQueue<LinkEventKind>();
supervisor.Event += (_, e) => { linkEvents.Enqueue(e.Kind); Log($"LINK {e.Kind} attempt={e.Attempt}{(e.Error is null ? "" : " " + e.Error.GetType().Name + ": " + e.Error.Message)}"); };

int gapMs = args.Length > 4 ? int.Parse(args[4]) : 0;
var session = new DeviceSession(Dev, transport, new FrameRule { Kind = FrameKind.Delim, End = [0x0D, 0x0A] }, defs, mapper,
    new SchedulerOptions(InterCommandGapMs: gapMs));
var values = new ConcurrentQueue<LogicalValue>();
var warnings = new ConcurrentQueue<string>();
int unhandled = 0;
session.Values += (_, e) => { foreach (var v in e.Values) values.Enqueue(v); };
session.Warning += (_, w) => { warnings.Enqueue(w); Log("WARN " + w); };
session.UnhandledFrame += (_, f) => { Interlocked.Increment(ref unhandled); Log("UNHANDLED " + Encoding.ASCII.GetString(f.Body)); };
session.StateChanged += (_, s) => Log($"SESSION {s}");
// 원시 수신 기록 (프레임 규칙 {..}[CR][LF] 이 깨졌는지 확인용)
long rawBytes = 0; var rawHead = new List<byte>(); object rawLock = new();
transport.Received += (_, b) => { lock (rawLock) { rawBytes += b.Length; if (rawHead.Count < 160) rawHead.AddRange(b.Take(160 - rawHead.Count)); } };
void RawReset() { lock (rawLock) { rawBytes = 0; rawHead.Clear(); } }
string RawInfo() { lock (rawLock) return $"원시 {rawBytes} byte, 앞부분 '{JuProvider.Lib.Protocol.Expression.ProtocolExpression.ToDisplay(rawHead.ToArray())}'"; }

async Task<bool> WaitFor(Func<bool> c, int ms) { var t = Stopwatch.StartNew(); while (t.ElapsedMilliseconds < ms) { if (c()) return true; await Task.Delay(50); } return c(); }

async Task<int> Measure(string label, int ms)
{
    while (values.TryDequeue(out _)) { }
    RawReset();
    var start = await session.ExecuteAsync("GTEC0300");
    Check(start.Ok, $"[{label}] START S{{10,1}} ({start.Status})");
    await Task.Delay(ms);
    var got = values.ToArray();
    int frames = got.Length / 3;
    Log($"[{label}] {RawInfo()}");
    var refs = got.Select(v => v.Data?.Key ?? "UNMAPPED").Distinct().OrderBy(x => x, StringComparer.Ordinal).ToArray();
    var q = got.GroupBy(v => v.Quality).Select(g => $"{g.Key}={g.Count()}");
    Log($"[{label}] 값 {got.Length}개(≈{frames} 프레임 / {ms} ms), 대상 {string.Join(",", refs)}, 품질 {string.Join(",", q)}");
    foreach (var v in got.Take(3)) Log($"     예: {v.Device.DevCd} CH{v.Channel.ChannelKey} → {v.Data?.Key} = {v.Value} ({v.Quality})");
    Check(frames >= ms / 100 / 2, $"[{label}] 데이터 수신 (≥ {ms / 200} 프레임)");
    Check(refs.SequenceEqual(new[] { "GTEC/AIN/1", "GTEC/AIN/2", "GTEC/AIN/3" }), $"[{label}] 매핑 대상 GTEC/AIN/1..3");
    Check(got.All(v => v.Quality == DataQuality.Good && v.Device.DevCd == Dev), $"[{label}] 품질 GOOD, DeviceRef {Dev}");
    Check(got.Where(v => v.Channel.ChannelKey == "1").Select(v => v.SampleIndex).All(i => i == 0), $"[{label}] 저속 3채널 SampleIndex 0");

    var stop = await session.ExecuteAsync("GTEC0301");
    Check(stop.Ok, $"[{label}] STOP S{{10,0}} ({stop.Status})");
    await Task.Delay(700);
    int n1 = values.Count; await Task.Delay(1500); int n2 = values.Count;
    Check(n2 == n1, $"[{label}] 중지 후 수신 없음 ({n2 - n1}개)");
    return frames;
}

// 연결·재연결 루틴 (사용자 지침 11:09): 측정 중인 장비는 S{10,0} 외 명령을 무시하므로 STOP 먼저 → 정상 루틴
async Task Routine(string label)
{
    var stop0 = await session.ExecuteAsync("GTEC0301");
    Check(stop0.Ok, $"[{label}] 루틴 1. STOP 먼저 ({stop0.Status})");
    await Task.Delay(500);
    var c = await session.ExecuteAsync("GTEC0001");
    Log($"     [{label}] 장치확인 응답: {B(c)}");
    Check(c.Ok, $"[{label}] 루틴 2. 장치확인 S{{10,3}} ({c.Status})");
    var i = await session.ExecuteAsync("GTEC0002");
    Log($"     [{label}] 센서정보 응답: {B(i)}");
    Check(i.Ok, $"[{label}] 루틴 3. 센서정보 S{{20}} ({i.Status})");
    Check((await session.ExecuteAsync("GTEC0100")).Ok, $"[{label}] 루틴 4. 모드 S{{11,1}}");
}

bool measuring = false;
try
{
    Log($"START supervisor {port} {baud}");
    await supervisor.StartAsync();
    await session.StartAsync();
    Check(await WaitFor(() => session.State == DeviceSessionState.Ready, 60000), $"세션 Ready (명령 간격 {gapMs} ms)");

    if (args.Length > 3 && args[3] == "gapseq")
    {
        // 송신 간격 확인: 확인 → 모드(TX_ONLY) → 시작(TX_ONLY) 연속 송신
        for (int round = 1; round <= 2; round++)
        {
            Log($"     [GAP {gapMs}ms #{round}] 장치확인: {B(await session.ExecuteAsync("GTEC0001"))}");
            await session.ExecuteAsync("GTEC0100");
            while (values.TryDequeue(out _)) { }
            await session.ExecuteAsync("GTEC0300");
            await Task.Delay(2500);
            int n = values.Count / 3;
            await session.ExecuteAsync("GTEC0301");
            await Task.Delay(800);
            while (values.TryDequeue(out _)) { }
            Log($"[GAP {gapMs}ms #{round}] 모드→시작 연속 송신 → 2.5초 프레임 {n}");
        }
        throw new OperationCanceledException("initseq 종료");
    }
    if (args.Length > 3 && args[3] == "initseq")
    {
        // 재연결(장비 재시작) 뒤 데이터가 안 오는 원인 확인: 어떤 명령 후에 START가 데이터를 내는지
        async Task<int> TryStart(string label)
        {
            while (values.TryDequeue(out _)) { }
            await session.ExecuteAsync("GTEC0300");
            await Task.Delay(2500);
            int n = values.Count / 3;
            await session.ExecuteAsync("GTEC0301");
            await Task.Delay(800);
            while (values.TryDequeue(out _)) { }
            Log($"[INIT] {label} → START 2.5초 프레임 {n}");
            return n;
        }
        Log($"     장치확인: {B(await session.ExecuteAsync("GTEC0001"))}");
        await TryStart("장치확인만");
        Check((await session.ExecuteAsync("GTEC0100")).Ok, "모드 S{11,1}");
        await TryStart("+ 모드");
        Log($"     센서정보: {B(await session.ExecuteAsync("GTEC0002"))}");
        int withInfo = await TryStart("+ 센서정보 S{20}");
        Check(withInfo > 0, "센서정보 후 데이터 수신");
        throw new OperationCanceledException("initseq 종료");
    }

    await Routine("최초");
    measuring = true;
    await Measure("1차", 5000);

    // 스트림 중 요청 (응답 매칭 충돌 M1 실장비)
    while (values.TryDequeue(out _)) { }
    await session.ExecuteAsync("GTEC0300");
    await Task.Delay(1000);
    var during = await session.ExecuteAsync("GTEC0002");
    int before = values.Count;
    await Task.Delay(1000);
    Log($"     측정 중 센서정보: {during.Status} {B(during)}, 이후 값 +{values.Count - before}");
    Check(during.Ok && values.Count > before, "측정 중 센서정보 요청 + 데이터 계속 (M1)");
    await session.ExecuteAsync("GTEC0301");
    await Task.Delay(500);
    measuring = false;

    // 케이블 분리·재연결
    while (linkEvents.TryDequeue(out _)) { }
    Console.Beep();
    Log("==================================================");
    Log($">>> 지금 COM6 장비 USB 케이블을 뽑아 주세요 ({cableWaitSec}초 대기) <<<");
    Log("==================================================");
    bool faulted = await WaitFor(() => linkEvents.Contains(LinkEventKind.Faulted) || session.State == DeviceSessionState.Suspended, cableWaitSec * 1000);
    if (!faulted)
    {
        Log("SKIP 케이블 분리 감지 안 됨 (분리하지 않았거나 감지 실패)");
    }
    else
    {
        Check(true, "케이블 분리 → Link Faulted 감지");
        Check(await WaitFor(() => session.State == DeviceSessionState.Suspended, 3000), "세션 Suspended");
        var down = await session.ExecuteAsync("GTEC0001");
        Check(down.Status == CommandStatus.LinkDown, $"분리 중 명령 → LinkDown ({down.Status})");
        Console.Beep();
        Log(">>> 이제 케이블을 다시 꽂아 주세요 (60초 대기) <<<");
        bool back = await WaitFor(() => linkEvents.Contains(LinkEventKind.Recovered) && session.State == DeviceSessionState.Ready, 60000);
        Check(back, "자동 재연결 Recovered + 세션 Ready");
        if (back)
        {
            await Task.Delay(1000);
            await Routine("재연결");
            measuring = true;
            await Measure("재연결 후", 5000);
            measuring = false;
        }
    }
}
catch (OperationCanceledException ex) when (ex.Message == "initseq 종료")
{
    Log("initseq 끝");
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
Log($"경고 {warnings.Count}건, 처리 안 된 프레임 {unhandled}건");
Log(fail == 0 ? "PROBE-PASS" : $"PROBE-FAIL ({fail})");
return fail == 0 ? 0 : 1;

// C2 실장비 확인용 임시 도구 (제품 저장소 밖). 읽기·측정 시작/중지 명령만 보낸다.
using System.Diagnostics;
using JuProvider.Lib.Protocol.Expression;
using JuProvider.Lib.Protocol.Framing;
using JuProvider.Lib.Protocol.Parsing;
using JuProvider.Lib.Protocol.Rules;
using JuProvider.Lib.Protocol.Transport;

string port = args.Length > 0 ? args[0] : "COM6";
int baud = args.Length > 1 ? int.Parse(args[1]) : 115200;
var sw = Stopwatch.StartNew();
void Log(string s) => Console.WriteLine($"[{sw.ElapsedMilliseconds,6} ms] {s}");

var framer = FramerFactory.Create(new FrameRule { Kind = FrameKind.Delim, End = [0x0D, 0x0A] });
var frames = new List<(long t, Frame f)>();
var raw = new List<byte>();
int chunks = 0; long bytes = 0;
var gate = new object();

ITransport tr = new SerialTransport(new SerialSettings(port, baud));
tr.StateChanged += (_, e) => Log($"STATE {e.State}{(e.Error is null ? "" : " " + e.Error.GetType().Name + ": " + e.Error.Message)}");
tr.Received += (_, b) =>
{
    lock (gate)
    {
        chunks++; bytes += b.Length; raw.AddRange(b);
        foreach (var f in framer.Push(b)) frames.Add((sw.ElapsedMilliseconds, f));
    }
};

List<Frame> Take() { lock (gate) { var l = frames.Select(x => x.f).ToList(); frames.Clear(); raw.Clear(); return l; } }
string RawNow() { lock (gate) { return ProtocolExpression.ToDisplay(raw.ToArray()); } }

async Task<List<Frame>> Send(string expr, int waitMs)
{
    Take();
    await tr.WriteAsync(ProtocolExpression.ToBytes(expr));
    await Task.Delay(waitMs);
    string rawText = RawNow();
    var got = Take();
    if (got.Count == 0) Log($"     (프레임 없음) 받은 바이트: '{rawText}', framer 대기 {framer.Pending}");
    Log($"TX {expr,-18} -> {got.Count} frame(s)" + (got.Count > 0 ? ": " + string.Join(" | ", got.Take(3).Select(f => ProtocolExpression.ToDisplay(f.Raw))) : ""));
    return got;
}

async Task<List<Frame>> SendTry(string expr, int waitMs)
{
    var got = await Send(expr, waitMs);
    if (got.Count == 0 && !expr.EndsWith("[CR][LF]")) got = await Send(expr + "[CR][LF]", waitMs);
    return got;
}

int fail = 0;
void Check(bool ok, string what) { Log((ok ? "OK   " : "FAIL ") + what); if (!ok) fail++; }

bool started = false;
try
{
    Log($"OPEN {port} {baud}");
    await tr.OpenAsync();
    Check(tr.State == TransportState.Open, "포트 열기");
    await Task.Delay(300); Take();

    var r1 = await Send("S{TEST}[CR][LF]", 1500);
    if (r1.Count == 0) r1 = await Send("S{TEST}", 1500);
    Log($"     S{{TEST}} 응답 {r1.Count}건 (정보용, seed 기대값 {{OK}})");
    var r2 = await SendTry("S{10,3}", 1500);
    Check(r2.Count > 0, "장치확인 S{10,3} 응답");

    var r3 = await SendTry("S{20}", 1500);
    var info = ParserFactory.Create(new ParseRule { Kind = ParseKind.Info, Trim = "{}", Separator = TextSeparator.Comma, Fields = ["1", "2", "3", "4"], Absent = "000" });
    if (r3.Count > 0)
    {
        var pr = info.Parse(r3[^1]);
        Log($"     센서정보 파싱 ok={pr.Ok} {pr.Error} " + string.Join(", ", pr.Values.Select(v => $"CH{v.ChannelKey}={v.Text}{(v.Absent ? "(없음)" : "")}")));
        Check(pr.Ok, "센서정보 S{20} INFO 파싱");
    }
    else Check(false, "센서정보 S{20} 응답");

    await SendTry("S{11,1}", 800);
    started = true;
    Take();
    await tr.WriteAsync(ProtocolExpression.ToBytes("S{10,1}"));
    Log("TX S{10,1} (측정 시작), 5초 수집");
    await Task.Delay(5000);
    var data = Take();
    if (data.Count == 0)
    {
        await tr.WriteAsync(ProtocolExpression.ToBytes("S{10,1}[CR][LF]"));
        Log("TX S{10,1}[CR][LF] 재시도, 5초 수집");
        await Task.Delay(5000);
        data = Take();
    }
    var text = ParserFactory.Create(new ParseRule { Kind = ParseKind.Text, Trim = "{}", Separator = TextSeparator.Space });
    int ok = 0, bad = 0; var counts = new Dictionary<int, int>();
    foreach (var f in data)
    {
        var pr = text.Parse(f);
        if (pr.Ok) { ok++; counts[pr.Values.Count] = counts.GetValueOrDefault(pr.Values.Count) + 1; } else bad++;
    }
    Log($"     스트림 {data.Count} frame / 5 s, 파싱 ok={ok} fail={bad}, 값 개수 분포: " + string.Join(", ", counts.Select(kv => $"{kv.Key}개×{kv.Value}")));
    foreach (var f in data.Take(5)) Log("     예: " + ProtocolExpression.ToDisplay(f.Raw));
    Check(data.Count > 0 && ok > 0, "측정 데이터 수신·파싱");

    await tr.WriteAsync(ProtocolExpression.ToBytes("S{10,0}"));
    await Task.Delay(700); Take();
    await Task.Delay(1500);
    var after = Take();
    if (after.Count > 0)
    {
        await tr.WriteAsync(ProtocolExpression.ToBytes("S{10,0}[CR][LF]"));
        await Task.Delay(700); Take(); await Task.Delay(1500); after = Take();
    }
    started = after.Count > 0;
    Check(after.Count == 0, $"측정 중지 후 수신 없음 (중지 후 1.5초 {after.Count}건)");

    Log("CLOSE → 다시 OPEN");
    await tr.CloseAsync();
    Check(tr.State == TransportState.Closed, "닫기");
    await Task.Delay(500);
    await tr.OpenAsync();
    await Task.Delay(300); Take();
    var r4 = await SendTry("S{10,3}", 1500);
    Check(r4.Count > 0, "재연결 후 장치확인 응답");
    Log($"합계: chunk {chunks}, byte {bytes}, 거부 프레임 {framer.Rejections.Count}" + (framer.Rejections.Count > 0 ? " 첫 사유=" + framer.Rejections[0].Reason : ""));
}
catch (Exception ex)
{
    Log($"EXCEPTION {ex.GetType().Name}: {ex.Message}");
    fail++;
}
finally
{
    if (started && tr.State == TransportState.Open)
    {
        try { await tr.WriteAsync(ProtocolExpression.ToBytes("S{10,0}[CR][LF]")); await Task.Delay(300); } catch { }
    }
    await tr.DisposeAsync();
}
Log(fail == 0 ? "PROBE-PASS" : $"PROBE-FAIL ({fail})");
return fail == 0 ? 0 : 1;

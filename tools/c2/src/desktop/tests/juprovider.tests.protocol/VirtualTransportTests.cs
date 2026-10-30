using System.Text;
using JuProvider.Lib.Protocol.Framing;
using JuProvider.Lib.Protocol.Parsing;
using JuProvider.Lib.Protocol.Rules;
using JuProvider.Lib.Protocol.Simulation;
using JuProvider.Lib.Protocol.Transport;

namespace JuProvider.Tests.Protocol;

public class VirtualTransportTests
{
    private static VirtualTransport Gtec(FaultOptions? faults = null, ProfileSimulator? sim = null) =>
        new(sim ?? new ProfileSimulator(BuiltInProfiles.Get("GTEC_SCIENCE_CUBE")), faults);

    private static Task Send(ITransport t, string expr) => t.WriteAsync(JuProvider.Lib.Protocol.Expression.ProtocolExpression.ToBytes(expr));

    [Fact] // V1 GTEC 시나리오: 확인 → 센서정보 → 간격 → 시작(연속) → 중지
    public async Task Gtec_Scenario_Through_Framer_And_Parser()
    {
        var sim = new ProfileSimulator(BuiltInProfiles.Get("GTEC_SCIENCE_CUBE"));
        await using VirtualTransport t = Gtec(sim: sim);
        var frames = new FrameCollector(t);
        await t.OpenAsync();

        await Send(t, "S{TEST}[CR][LF]");
        Assert.True(await Wait.UntilAsync(() => frames.Frames.Contains("{OK}")));

        await Send(t, "S{20}");
        Assert.True(await Wait.UntilAsync(() => frames.Frames.Contains("{008,000,000,000}")));

        await Send(t, "S{12,0.020}");
        Assert.Equal("20", sim.GetVar("intervalMs"));

        int before = frames.Frames.Count;
        await Send(t, "S{10,1}");
        Assert.True(await Wait.UntilAsync(() => frames.Frames.Count >= before + 5), "연속 데이터 5프레임 이상");

        IFrameParser parser = ParserFactory.Create(RuleReader.ReadParseRule("FRAME=CRLF;STX={;ETX=};MODE=DELIMITED;SEP=SPACE;COUNT=3;MAP=CHANNELS")!);
        List<string> data = frames.Snapshot().Skip(before).Take(5).ToList();
        foreach (string f in data)
        {
            byte[] b = Encoding.ASCII.GetBytes(f);
            ParseResult r = parser.Parse(new Frame(b, b));
            Assert.True(r.Ok, f + " → " + r.Error);
            Assert.Equal(3, r.Values.Count);
        }

        await Send(t, "S{10,0}[CR][LF]");
        await Task.Delay(100);
        int stopped = frames.Frames.Count;
        await Task.Delay(150);
        Assert.Equal(stopped, frames.Frames.Count); // 중지 후 추가 데이터 없음
        Assert.Equal(0, sim.UnmatchedRequests);
    }

    [Fact]
    public async Task Unknown_Request_Is_Counted_Without_Reply()
    {
        var sim = new ProfileSimulator(BuiltInProfiles.Get("GTEC_SCIENCE_CUBE"));
        await using VirtualTransport t = Gtec(sim: sim);
        var frames = new FrameCollector(t);
        await t.OpenAsync();
        await Send(t, "S{99}");
        await Task.Delay(100);
        Assert.Empty(frames.Frames);
        Assert.Equal(1, sim.UnmatchedRequests);
    }

    [Fact] // V2 장애: 1바이트 조각 + 지연 → 그래도 프레임 복원
    public async Task Fault_Fragment_And_Delay()
    {
        await using VirtualTransport t = Gtec(new FaultOptions(FragmentSize: 1, DelayMs: 30));
        var frames = new FrameCollector(t);
        await t.OpenAsync();
        await Send(t, "S{20}");
        await Task.Delay(10);
        Assert.Empty(frames.Frames); // 지연 중
        Assert.True(await Wait.UntilAsync(() => frames.Frames.Contains("{008,000,000,000}")));
        Assert.True(frames.Chunks >= "{008,000,000,000}\r\n".Length);
    }

    [Fact] // V3 장애: 응답 누락(drop=1) → 응답 없음
    public async Task Fault_Drop_All()
    {
        await using VirtualTransport t = Gtec(new FaultOptions(DropRate: 1));
        var frames = new FrameCollector(t);
        await t.OpenAsync();
        await Send(t, "S{20}");
        await Task.Delay(150);
        Assert.Empty(frames.Frames);
    }

    [Fact] // V4 장애: 쓰레기 바이트 → 해당 프레임은 해석 실패, 다음 정상 프레임은 계속
    public async Task Fault_Garbage_Then_Recover()
    {
        var parser = ParserFactory.Create(RuleReader.ReadParseRule("""{"v":1,"kind":"INFO","trim":"{}","fields":["CH1","CH2","CH3","CH4"]}""")!);
        await using VirtualTransport bad = Gtec(new FaultOptions(GarbageRate: 1));
        var frames = new FrameCollector(bad);
        await bad.OpenAsync();
        await Send(bad, "S{20}");
        Assert.True(await Wait.UntilAsync(() => frames.Frames.Count == 1));
        byte[] body = Encoding.Latin1.GetBytes(frames.Snapshot()[0]);
        Assert.False(parser.Parse(new Frame(body, body)).Ok);

        await using VirtualTransport good = Gtec(new FaultOptions(GarbageRate: 0));
        var frames2 = new FrameCollector(good);
        await good.OpenAsync();
        await Send(good, "S{20}");
        Assert.True(await Wait.UntilAsync(() => frames2.Frames.Count == 1));
        byte[] ok = Encoding.ASCII.GetBytes(frames2.Snapshot()[0]);
        Assert.True(parser.Parse(new Frame(ok, ok)).Ok);
    }

    [Fact] // V5 같은 seed → 같은 장애 결과 (재현성)
    public async Task Fault_Is_Deterministic_By_Seed()
    {
        async Task<int> Run()
        {
            await using VirtualTransport t = Gtec(new FaultOptions(DropRate: 0.5, Seed: 42));
            var frames = new FrameCollector(t);
            await t.OpenAsync();
            for (int i = 0; i < 20; i++) await Send(t, "S{TEST}");
            await Task.Delay(150);
            return frames.Frames.Count;
        }
        int a = await Run();
        int b = await Run();
        Assert.Equal(a, b);
        Assert.InRange(a, 1, 19);
    }

    [Fact] // V6 강제 끊김 → Faulted, 쓰기 거부
    public async Task ForceDisconnect_Faults()
    {
        await using VirtualTransport t = Gtec();
        await t.OpenAsync();
        t.ForceDisconnect();
        Assert.True(await Wait.UntilAsync(() => t.State == TransportState.Faulted));
        await Assert.ThrowsAsync<InvalidOperationException>(() => t.WriteAsync(new byte[] { 1 }));
    }

    [Fact] // V7 연결 후 자동 끊김 + 감독자 재연결 → 장치 상태 초기화(running=false)
    public async Task DisconnectAfter_Supervisor_Recovers_And_Device_Resets()
    {
        var sim = new ProfileSimulator(BuiltInProfiles.Get("GTEC_SCIENCE_CUBE"));
        var t = Gtec(new FaultOptions(DisconnectAfterMs: 150), sim);
        var policy = new ReconnectPolicy([TimeSpan.FromMilliseconds(10)], TimeSpan.FromMilliseconds(20), TimeSpan.FromMilliseconds(40));
        await using var sup = new LinkSupervisor(t, policy);
        var events = new List<LinkEvent>();
        sup.Event += (_, e) => { lock (events) events.Add(e); };

        await sup.StartAsync();
        await Send(t, "S{10,1}");
        Assert.Equal("true", sim.GetVar("running"));

        Assert.True(await Wait.UntilAsync(() => { lock (events) return events.Any(e => e.Kind == LinkEventKind.Recovered); }));
        Assert.Equal(TransportState.Open, t.State);
        Assert.Equal("false", sim.GetVar("running")); // 재연결 = 장치 재시작
    }

    [Fact] // V8 처음 N번 Open 실패 → 감독자가 계속 시도해 연결 (지연은 가짜로 즉시)
    public async Task FailOpen_Then_Connects_With_Policy_Delays()
    {
        var delays = new List<TimeSpan>();
        var t = Gtec(new FaultOptions(FailOpenCount: 5));
        await using var sup = new LinkSupervisor(t, ReconnectPolicy.Default, (d, _) => { lock (delays) delays.Add(d); return Task.CompletedTask; });
        var events = new List<LinkEvent>();
        sup.Event += (_, e) => { lock (events) events.Add(e); };

        await sup.StartAsync(); // 1번째 실패 (예외 없음)
        Assert.True(await Wait.UntilAsync(() => t.State == TransportState.Open));

        lock (delays) Assert.Equal(new[] { 1, 2, 3, 5, 10 }.Select(s => TimeSpan.FromSeconds(s)), delays);
        lock (events)
        {
            Assert.Equal(LinkEventKind.Faulted, events[0].Kind);
            Assert.Equal(LinkEventKind.Connected, events[^1].Kind); // 한 번도 연결된 적 없음 → Connected
            Assert.Equal(5, events.Count(e => e.Kind == LinkEventKind.Reconnecting));
        }
    }

    [Fact] // V9 Stop 후에는 재연결하지 않음
    public async Task Stop_Prevents_Reconnect()
    {
        var t = Gtec();
        var sup = new LinkSupervisor(t, ReconnectPolicy.Default, (_, ct) => Task.Delay(10, ct));
        await sup.StartAsync();
        await sup.StopAsync();
        Assert.Equal(TransportState.Closed, t.State);
        t.ForceDisconnect();
        await Task.Delay(100);
        Assert.Equal(TransportState.Closed, t.State);
        await sup.DisposeAsync();
    }

    [Fact]
    public async Task Echo_And_Stream_Profiles()
    {
        await using var echo = new VirtualTransport(new ProfileSimulator(BuiltInProfiles.Get("GENERIC_ECHO")));
        var ef = new FrameCollector(echo);
        await echo.OpenAsync();
        await Send(echo, "HELLO[01]");
        Assert.True(await Wait.UntilAsync(() => ef.Frames.Count == 1));
        Assert.Equal("HELLO\u0001", ef.Snapshot()[0]);

        await using var stream = new VirtualTransport(new ProfileSimulator(BuiltInProfiles.Get("GENERIC_STREAM")));
        var sf = new FrameCollector(stream);
        await stream.OpenAsync();
        Assert.True(await Wait.UntilAsync(() => sf.Frames.Count >= 3));
        Assert.Equal(new[] { "{1}", "{2}", "{3}" }, sf.Snapshot().Take(3));
    }
}

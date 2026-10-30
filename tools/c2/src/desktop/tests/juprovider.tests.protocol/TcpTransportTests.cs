using System.Net;
using System.Net.Sockets;
using System.Text;
using JuProvider.Lib.Protocol.Transport;

namespace JuProvider.Tests.Protocol;

/// <summary>로컬 루프백 TCP 서버로 백그라운드 수신·조각·종료·재연결 확인</summary>
public class TcpTransportTests
{
    private static TcpListener Listen()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        return l;
    }

    private static int PortOf(TcpListener l) => ((IPEndPoint)l.LocalEndpoint).Port;

    [Fact] // T1 조각난 연속 수신 → Framer가 프레임 복원, 쓰기 전달
    public async Task Receives_Fragmented_Stream_And_Writes()
    {
        using TcpListener listener = Listen();
        await using var t = new TcpClientTransport("127.0.0.1", PortOf(listener));
        var frames = new FrameCollector(t);

        Task<TcpClient> accept = listener.AcceptTcpClientAsync();
        await t.OpenAsync();
        using TcpClient server = await accept;
        NetworkStream s = server.GetStream();

        byte[] data = Encoding.ASCII.GetBytes("{1 2 3}\r\n{4 5 6}\r\n{7 8 9}\r\n");
        foreach (byte b in data)
        {
            await s.WriteAsync(new[] { b });
            await s.FlushAsync();
        }

        Assert.True(await Wait.UntilAsync(() => frames.Frames.Count == 3), "프레임 3개 수신");
        Assert.Equal(new[] { "{1 2 3}", "{4 5 6}", "{7 8 9}" }, frames.Snapshot());
        Assert.Equal(TransportState.Open, t.State);

        await t.WriteAsync(Encoding.ASCII.GetBytes("S{10,1}\r\n"));
        var buf = new byte[64];
        int n = await s.ReadAsync(buf).AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        Assert.Equal("S{10,1}\r\n", Encoding.ASCII.GetString(buf, 0, n));
    }

    [Fact] // T2 상대 종료 → Faulted
    public async Task Peer_Close_Faults()
    {
        using TcpListener listener = Listen();
        await using var t = new TcpClientTransport("127.0.0.1", PortOf(listener));
        var states = new List<TransportState>();
        t.StateChanged += (_, e) => { lock (states) states.Add(e.State); };

        Task<TcpClient> accept = listener.AcceptTcpClientAsync();
        await t.OpenAsync();
        (await accept).Dispose();

        Assert.True(await Wait.UntilAsync(() => t.State == TransportState.Faulted));
        lock (states) Assert.Equal(new[] { TransportState.Opening, TransportState.Open, TransportState.Faulted }, states);
        await Assert.ThrowsAsync<InvalidOperationException>(() => t.WriteAsync(new byte[] { 1 }));
    }

    [Fact] // T3 열 수 없는 포트 → 예외 + Faulted
    public async Task Open_Refused_Faults()
    {
        int port;
        using (TcpListener l = Listen()) { port = PortOf(l); l.Stop(); }
        await using var t = new TcpClientTransport("127.0.0.1", port, connectTimeoutMs: 2000);
        await Assert.ThrowsAnyAsync<Exception>(() => t.OpenAsync());
        Assert.Equal(TransportState.Faulted, t.State);
    }

    [Fact] // T4 끊김 후 LinkSupervisor가 다시 연결 (Recovered)
    public async Task Supervisor_Reconnects_After_Peer_Close()
    {
        using TcpListener listener = Listen();
        var t = new TcpClientTransport("127.0.0.1", PortOf(listener));
        var policy = new ReconnectPolicy([TimeSpan.FromMilliseconds(20)], TimeSpan.FromMilliseconds(40), TimeSpan.FromMilliseconds(80));
        await using var sup = new LinkSupervisor(t, policy);
        var events = new List<LinkEventKind>();
        sup.Event += (_, e) => { lock (events) events.Add(e.Kind); };

        Task<TcpClient> accept1 = listener.AcceptTcpClientAsync();
        await sup.StartAsync();
        TcpClient first = await accept1;
        Task<TcpClient> accept2 = listener.AcceptTcpClientAsync();
        first.Dispose();

        using TcpClient second = await accept2.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.True(await Wait.UntilAsync(() => { lock (events) return events.Contains(LinkEventKind.Recovered); }));
        Assert.Equal(TransportState.Open, t.State);
        lock (events)
        {
            Assert.Equal(LinkEventKind.Connected, events[0]);
            Assert.Contains(LinkEventKind.Faulted, events);
            Assert.Contains(LinkEventKind.Reconnecting, events);
        }
    }

    [Fact]
    public void Ctor_Validates()
    {
        Assert.Throws<ArgumentException>(() => new TcpClientTransport(" ", 1));
        Assert.Throws<ArgumentOutOfRangeException>(() => new TcpClientTransport("h", 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new TcpClientTransport("h", 70000));
    }
}

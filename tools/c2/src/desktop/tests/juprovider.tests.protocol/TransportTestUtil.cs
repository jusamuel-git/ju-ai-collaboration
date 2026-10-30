using System.Collections.Concurrent;
using System.Text;
using JuProvider.Lib.Protocol.Framing;
using JuProvider.Lib.Protocol.Rules;
using JuProvider.Lib.Protocol.Transport;

namespace JuProvider.Tests.Protocol;

/// <summary>Transport 수신을 CRLF Framer로 모아 문자열 프레임 목록으로 만든다</summary>
internal sealed class FrameCollector
{
    private readonly IFramer _framer = FramerFactory.Create(new FrameRule { Kind = FrameKind.Delim, End = [0x0D, 0x0A] });
    private readonly object _lock = new();
    public ConcurrentQueue<string> Frames { get; } = new();
    public int Chunks;
    public int Rejected;

    public FrameCollector(ITransport t) => t.Received += (_, data) =>
    {
        Interlocked.Increment(ref Chunks);
        lock (_lock)
        {
            foreach (Frame f in _framer.Push(data)) Frames.Enqueue(Encoding.ASCII.GetString(f.Body));
            Rejected += _framer.Rejections.Count;
        }
    };

    public List<string> Snapshot() => Frames.ToList();
}

internal static class Wait
{
    public static async Task<bool> UntilAsync(Func<bool> condition, int timeoutMs = 3000)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            if (condition()) return true;
            await Task.Delay(10);
        }
        return condition();
    }
}

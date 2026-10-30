using JuProvider.Lib.Protocol.Rules;

namespace JuProvider.Lib.Protocol.Framing;

/// <summary>버퍼·거부 목록·최대 길이·체크섬 공통 처리</summary>
public abstract class FramerBase : IFramer
{
    protected readonly FrameRule Rule;
    protected readonly List<byte> Buffer = new();
    private readonly List<FrameRejection> _rejections = new();

    protected FramerBase(FrameRule rule) => Rule = rule;

    public IReadOnlyList<FrameRejection> Rejections => _rejections;
    public int Pending => Buffer.Count;

    public void Reset() => Buffer.Clear();

    public IReadOnlyList<Frame> Push(ReadOnlySpan<byte> chunk)
    {
        _rejections.Clear();
        foreach (byte b in chunk) Buffer.Add(b);

        var frames = new List<Frame>();
        while (TryTake(out Frame? frame))
        {
            if (frame is null) continue;
            if (ApplyChecksum(frame, out Frame? ok)) frames.Add(ok!);
        }

        if (Buffer.Count > Rule.MaxLength)
        {
            Reject("최대 길이 초과", Buffer.ToArray());
            Buffer.Clear();
        }

        return frames;
    }

    /// <summary>버퍼에서 프레임 1개를 꺼낸다. 더 꺼낼 게 없으면 false. 꺼냈지만 버린 경우 true + frame=null.</summary>
    protected abstract bool TryTake(out Frame? frame);

    protected void Reject(string reason, byte[] data) => _rejections.Add(new FrameRejection(reason, data));

    protected byte[] TakeFront(int count)
    {
        byte[] taken = Buffer.GetRange(0, count).ToArray();
        Buffer.RemoveRange(0, count);
        return taken;
    }

    private bool ApplyChecksum(Frame frame, out Frame? result)
    {
        ChecksumRule c = Rule.Checksum;
        result = frame;
        if (c.Type == ChecksumType.None) return true;

        byte[] body = frame.Body;
        int size = c.Size;
        if (body.Length < c.From + size)
        {
            Reject("체크섬 길이 부족", frame.Raw);
            result = null;
            return false;
        }

        ReadOnlySpan<byte> covered = body.AsSpan(c.From, body.Length - size - c.From);
        ReadOnlySpan<byte> actual = body.AsSpan(body.Length - size, size);
        if (!Checksum.Verify(c.Type, covered, actual))
        {
            Reject("체크섬 불일치", frame.Raw);
            result = null;
            return false;
        }

        result = frame with { Body = body[..^size] };
        return true;
    }
}

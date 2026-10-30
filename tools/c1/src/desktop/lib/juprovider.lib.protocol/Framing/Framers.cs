using JuProvider.Lib.Protocol.Rules;

namespace JuProvider.Lib.Protocol.Framing;

/// <summary>끝 구분자. Body = 구분자 앞부분. 빈 프레임은 건너뜀.</summary>
public sealed class DelimiterFramer(FrameRule rule) : FramerBase(rule)
{
    protected override bool TryTake(out Frame? frame)
    {
        frame = null;
        byte[] end = Rule.End;
        int at = IndexOf(Buffer, end);
        if (at < 0) return false;

        byte[] raw = TakeFront(at + end.Length);
        byte[] body = raw[..at];
        if (body.Length > 0) frame = new Frame(raw, body);
        return true;
    }

    private static int IndexOf(List<byte> buffer, byte[] pattern)
    {
        for (int i = 0; i <= buffer.Count - pattern.Length; i++)
        {
            int j = 0;
            while (j < pattern.Length && buffer[i + j] == pattern[j]) j++;
            if (j == pattern.Length) return i;
        }
        return -1;
    }
}

/// <summary>
/// 시작·끝 바이트. STX 앞의 바이트는 버림(거부 기록). Escape가 있으면 다음 1바이트를 그대로 내용으로 본다.
/// Body = STX/ETX 제외, escape 해제된 내용.
/// </summary>
public sealed class StxEtxFramer(FrameRule rule) : FramerBase(rule)
{
    protected override bool TryTake(out Frame? frame)
    {
        frame = null;
        if (Buffer.Count == 0) return false;

        int start = Buffer.IndexOf(Rule.Stx);
        if (start < 0)
        {
            Reject("STX 없음", TakeFront(Buffer.Count));
            return false;
        }
        if (start > 0)
        {
            Reject("STX 앞 데이터", TakeFront(start));
        }

        var body = new List<byte>();
        for (int i = 1; i < Buffer.Count; i++)
        {
            byte b = Buffer[i];
            if (Rule.Escape is byte esc && b == esc)
            {
                if (i + 1 >= Buffer.Count) return false; // escape 다음 바이트 대기
                body.Add(Buffer[++i]);
                continue;
            }
            if (b == Rule.Etx)
            {
                byte[] raw = TakeFront(i + 1);
                frame = new Frame(raw, body.ToArray());
                return true;
            }
            if (b == Rule.Stx && Rule.Escape is null)
            {
                // ETX 없이 새 STX → 앞 프레임은 깨진 것으로 보고 버림
                Reject("ETX 없이 새 STX", TakeFront(i));
                return true;
            }
            body.Add(b);
        }
        return false;
    }
}

/// <summary>고정 길이. Body = 프레임 전체.</summary>
public sealed class FixedLengthFramer(FrameRule rule) : FramerBase(rule)
{
    protected override bool TryTake(out Frame? frame)
    {
        frame = null;
        if (Buffer.Count < Rule.Length) return false;
        byte[] raw = TakeFront(Rule.Length);
        frame = new Frame(raw, raw);
        return true;
    }
}

/// <summary>
/// 길이 필드. 전체 길이 = 헤더 포함이면 값+adjust, 아니면 (offset+size)+값+adjust.
/// Body = 프레임 전체. 길이가 잘못되면(헤더보다 짧거나 MaxLength 초과) 1바이트 버리고 다시 찾는다.
/// </summary>
public sealed class LengthFieldFramer(FrameRule rule) : FramerBase(rule)
{
    protected override bool TryTake(out Frame? frame)
    {
        frame = null;
        int header = Rule.LengthOffset + Rule.LengthSize;
        if (Buffer.Count < header) return false;

        long value = 0;
        for (int k = 0; k < Rule.LengthSize; k++)
        {
            int idx = Rule.LengthBigEndian ? Rule.LengthOffset + k : Rule.LengthOffset + Rule.LengthSize - 1 - k;
            value = (value << 8) | Buffer[idx];
        }

        long total = (Rule.LengthIncludesHeader ? value : header + value) + Rule.LengthAdjust;
        if (total < header || total > Rule.MaxLength)
        {
            Reject("길이 필드 값 오류", TakeFront(1));
            return true;
        }
        if (Buffer.Count < total) return false;

        byte[] raw = TakeFront((int)total);
        frame = new Frame(raw, raw);
        return true;
    }
}

public static class FramerFactory
{
    public static IFramer Create(FrameRule rule) => rule.Kind switch
    {
        FrameKind.Delim => new DelimiterFramer(rule),
        FrameKind.StxEtx => new StxEtxFramer(rule),
        FrameKind.Fixed => new FixedLengthFramer(rule),
        FrameKind.LenField => new LengthFieldFramer(rule),
        _ => throw new ArgumentOutOfRangeException(nameof(rule))
    };
}

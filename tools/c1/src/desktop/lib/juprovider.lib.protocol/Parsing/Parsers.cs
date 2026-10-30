using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using JuProvider.Lib.Protocol.Framing;
using JuProvider.Lib.Protocol.Rules;

namespace JuProvider.Lib.Protocol.Parsing;

/// <summary>
/// 파서 출력 1개.
/// ChannelKey: TEXT=위치("1","2",…), SAMPLES=선택 채널 키, INFO/BINARY=필드 key. 문자열 그대로 비교한다("1" ≠ "01").
/// Value: 숫자 값(INFO는 null), Text: 원래 토큰, Absent: INFO에서 '없음' 값과 같을 때 true.
/// </summary>
public sealed record RawValue(string ChannelKey, int SampleIndex, double? Value, string? Text, bool Absent = false);

/// <summary>SAMPLES 모드의 선택 채널 등 실행 시점 값</summary>
public sealed record ParseContext(string SelectedChannelKey = "1");

public sealed record ParseResult(bool Ok, IReadOnlyList<RawValue> Values, string? Error)
{
    public static ParseResult Fail(string error) => new(false, [], error);
    public static ParseResult Success(IReadOnlyList<RawValue> values) => new(true, values, null);
}

public interface IFrameParser
{
    ParseResult Parse(Frame frame, ParseContext? context = null);
}

public static class ParserFactory
{
    public static IFrameParser Create(ParseRule rule) => rule.Kind switch
    {
        ParseKind.Text => new TextFrameParser(rule),
        ParseKind.Info => new InfoFrameParser(rule),
        ParseKind.Binary => new BinaryFrameParser(rule),
        _ => throw new ArgumentOutOfRangeException(nameof(rule))
    };
}

internal static class TextTokens
{
    /// <summary>ASCII 본문 → (trim 확인 후) 토큰. 실패 시 null + 사유</summary>
    public static string[]? Split(Frame frame, ParseRule rule, out string? error)
    {
        error = null;
        foreach (byte b in frame.Body)
        {
            if (b > 0x7F)
            {
                error = "ASCII가 아닌 바이트";
                return null;
            }
        }

        string s = Encoding.ASCII.GetString(frame.Body).Trim();
        if (rule.Trim is { Length: 2 } trim)
        {
            if (s.Length < 2 || s[0] != trim[0] || s[^1] != trim[1])
            {
                error = $"앞뒤 문자 불일치 (기대 {trim[0]}…{trim[1]})";
                return null;
            }
            s = s[1..^1];
        }

        string[] tokens = rule.Separator switch
        {
            TextSeparator.Comma => s.Split(',', StringSplitOptions.TrimEntries),
            TextSeparator.Tab => s.Split('\t', StringSplitOptions.TrimEntries),
            _ => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        };

        if (tokens.Length == 1 && tokens[0].Length == 0) tokens = [];
        if (rule.Count > 0 && tokens.Length != rule.Count)
        {
            error = $"항목 수 불일치 (기대 {rule.Count}, 실제 {tokens.Length})";
            return null;
        }
        return tokens;
    }
}

/// <summary>TEXT: 숫자 토큰 → CHANNELS("1".."n") 또는 SAMPLES(선택 채널, 샘플 0..n-1)</summary>
public sealed class TextFrameParser(ParseRule rule) : IFrameParser
{
    public ParseResult Parse(Frame frame, ParseContext? context = null)
    {
        string[]? tokens = TextTokens.Split(frame, rule, out string? error);
        if (tokens is null) return ParseResult.Fail(error!);
        if (tokens.Length == 0) return ParseResult.Fail("항목 없음");

        var values = new List<RawValue>(tokens.Length);
        string selected = (context ?? new ParseContext()).SelectedChannelKey;

        for (int i = 0; i < tokens.Length; i++)
        {
            if (!double.TryParse(tokens[i], NumberStyles.Float, CultureInfo.InvariantCulture, out double v))
            {
                return ParseResult.Fail($"숫자가 아님: '{tokens[i]}' (항목 {i + 1})");
            }
            values.Add(rule.Map == ValueMap.Channels
                ? new RawValue((i + 1).ToString(CultureInfo.InvariantCulture), 0, v, tokens[i])
                : new RawValue(selected, i, v, tokens[i]));
        }
        return ParseResult.Success(values);
    }
}

/// <summary>INFO: 토큰 i → Fields[i], 숫자 변환 없음. Absent 값이면 Absent=true</summary>
public sealed class InfoFrameParser(ParseRule rule) : IFrameParser
{
    public ParseResult Parse(Frame frame, ParseContext? context = null)
    {
        string[]? tokens = TextTokens.Split(frame, rule with { Count = rule.Fields.Count }, out string? error);
        if (tokens is null) return ParseResult.Fail(error!);

        var values = new List<RawValue>(tokens.Length);
        for (int i = 0; i < tokens.Length; i++)
        {
            if (tokens[i].Length == 0) return ParseResult.Fail($"빈 항목 (항목 {i + 1})");
            bool absent = rule.Absent is not null && string.Equals(tokens[i], rule.Absent, StringComparison.Ordinal);
            values.Add(new RawValue(rule.Fields[i], 0, null, tokens[i], absent));
        }
        return ParseResult.Success(values);
    }
}

/// <summary>BINARY: Body 기준 offset의 값 × scale + valueOffset</summary>
public sealed class BinaryFrameParser(ParseRule rule) : IFrameParser
{
    public ParseResult Parse(Frame frame, ParseContext? context = null)
    {
        ReadOnlySpan<byte> body = frame.Body;
        var values = new List<RawValue>(rule.BinaryFields.Count);

        foreach (BinaryField f in rule.BinaryFields)
        {
            int size = Size(f.Type);
            if (f.Offset + size > body.Length)
            {
                return ParseResult.Fail($"{f.Key}: 프레임 길이 부족 (필요 {f.Offset + size}, 실제 {body.Length})");
            }
            double raw = Read(body.Slice(f.Offset, size), f.Type, f.BigEndian);
            values.Add(new RawValue(f.Key, 0, raw * f.Scale + f.ValueOffset, null));
        }
        return ParseResult.Success(values);
    }

    private static int Size(BinaryType t) => t switch
    {
        BinaryType.U8 or BinaryType.I8 => 1,
        BinaryType.U16 or BinaryType.I16 => 2,
        BinaryType.U32 or BinaryType.I32 or BinaryType.F32 => 4,
        BinaryType.F64 => 8,
        _ => throw new ArgumentOutOfRangeException(nameof(t))
    };

    private static double Read(ReadOnlySpan<byte> s, BinaryType t, bool be) => t switch
    {
        BinaryType.U8 => s[0],
        BinaryType.I8 => (sbyte)s[0],
        BinaryType.U16 => be ? BinaryPrimitives.ReadUInt16BigEndian(s) : BinaryPrimitives.ReadUInt16LittleEndian(s),
        BinaryType.I16 => be ? BinaryPrimitives.ReadInt16BigEndian(s) : BinaryPrimitives.ReadInt16LittleEndian(s),
        BinaryType.U32 => be ? BinaryPrimitives.ReadUInt32BigEndian(s) : BinaryPrimitives.ReadUInt32LittleEndian(s),
        BinaryType.I32 => be ? BinaryPrimitives.ReadInt32BigEndian(s) : BinaryPrimitives.ReadInt32LittleEndian(s),
        BinaryType.F32 => be ? BinaryPrimitives.ReadSingleBigEndian(s) : BinaryPrimitives.ReadSingleLittleEndian(s),
        BinaryType.F64 => be ? BinaryPrimitives.ReadDoubleBigEndian(s) : BinaryPrimitives.ReadDoubleLittleEndian(s),
        _ => throw new ArgumentOutOfRangeException(nameof(t))
    };
}

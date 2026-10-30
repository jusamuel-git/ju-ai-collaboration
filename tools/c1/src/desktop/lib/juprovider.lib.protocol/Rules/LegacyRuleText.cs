namespace JuProvider.Lib.Protocol.Rules;

/// <summary>
/// 과거 GTEC 규칙 텍스트(읽기 호환):
///   FRAME=CRLF;STX={;ETX=};MODE=DELIMITED|INFO|NONE;SEP=SPACE|COMMA;COUNT=3;MAP=CHANNELS|SAMPLES|NONE
/// 과거 의미: 프레임은 CRLF로 끊고, STX/ETX 문자는 프레임 내용의 앞뒤 확인용이었다.
/// 변환: Frame = DELIM [CR][LF], Parse = TEXT(trim = STX+ETX) 또는 INFO(CH1..CHn).
/// 과거 INFO(센서정보)는 4항목 고정이었다 → COUNT가 없으면 4.
/// </summary>
public static class LegacyRuleText
{
    public static (FrameRule? Frame, ParseRule? Parse) ToRules(string text)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string item in text.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            int p = item.IndexOf('=');
            if (p <= 0) throw new RuleFormatException($"규칙 항목은 KEY=VALUE 형식이어야 합니다: {item}");
            values[item[..p].Trim()] = item[(p + 1)..].Trim();
        }
        if (values.Count == 0) throw new RuleFormatException("규칙이 비어 있습니다.");

        string V(string key, string fallback) => values.TryGetValue(key, out string? v) && v.Length > 0 ? v : fallback;

        string frame = V("FRAME", "CRLF").ToUpperInvariant();
        FrameRule frameRule = frame switch
        {
            "CRLF" => new FrameRule { Kind = FrameKind.Delim, End = [0x0D, 0x0A] },
            "LF" => new FrameRule { Kind = FrameKind.Delim, End = [0x0A] },
            "CR" => new FrameRule { Kind = FrameKind.Delim, End = [0x0D] },
            _ => throw new RuleFormatException($"과거 규칙 FRAME 값을 알 수 없습니다: {frame}")
        };

        string stx = V("STX", "{");
        string etx = V("ETX", "}");
        if (stx.Length != 1 || etx.Length != 1) throw new RuleFormatException("과거 규칙 STX/ETX는 1글자입니다.");
        string trim = stx + etx;

        string mode = V("MODE", "DELIMITED").ToUpperInvariant();
        string map = V("MAP", "CHANNELS").ToUpperInvariant();
        int count = RuleReader.ParseIntInvariant(V("COUNT", "0"), "COUNT");
        if (count < 0) throw new RuleFormatException("COUNT는 0 이상이어야 합니다.");

        if (mode == "NONE" || map == "NONE")
        {
            return (frameRule, null);
        }

        if (mode == "INFO")
        {
            int n = count > 0 ? count : 4;
            return (frameRule, new ParseRule
            {
                Kind = ParseKind.Info,
                Trim = trim,
                Separator = RuleReader.Sep(V("SEP", "COMMA")),
                Fields = Enumerable.Range(1, n).Select(i => "CH" + i).ToArray(),
                Count = n,
                Absent = "000"
            });
        }

        if (mode != "DELIMITED") throw new RuleFormatException($"과거 규칙 MODE 값을 알 수 없습니다: {mode}");

        return (frameRule, new ParseRule
        {
            Kind = ParseKind.Text,
            Trim = trim,
            Separator = RuleReader.Sep(V("SEP", "SPACE")),
            Count = count,
            Map = map switch
            {
                "CHANNELS" => ValueMap.Channels,
                "SAMPLES" => ValueMap.Samples,
                _ => throw new RuleFormatException($"과거 규칙 MAP 값을 알 수 없습니다: {map}")
            }
        });
    }
}

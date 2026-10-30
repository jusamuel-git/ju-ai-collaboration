using System.Globalization;
using System.Text.Json;
using JuProvider.Lib.Protocol.Expression;

namespace JuProvider.Lib.Protocol.Rules;

public sealed class RuleFormatException(string message) : FormatException(message);

/// <summary>
/// Frame Rule / Parse Rule 읽기 (C0 §4.1).
/// - JSON v1: {"v":1,"kind":"DELIM", ...}
/// - 과거 GTEC 텍스트: FRAME=CRLF;STX={;ETX=};MODE=DELIMITED;SEP=SPACE;COUNT=3;MAP=CHANNELS (읽기 호환)
/// 빈 값이면 null (규칙 없음).
/// </summary>
public static class RuleReader
{
    public static FrameRule? ReadFrameRule(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        string t = text.Trim();
        return t.StartsWith('{') ? FrameFromJson(t) : LegacyRuleText.ToRules(t).Frame;
    }

    public static ParseRule? ReadParseRule(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        string t = text.Trim();
        return t.StartsWith('{') ? ParseFromJson(t) : LegacyRuleText.ToRules(t).Parse;
    }

    // ----- JSON -----

    private static JsonElement Root(string json)
    {
        JsonElement root;
        try
        {
            using JsonDocument doc = JsonDocument.Parse(json);
            root = doc.RootElement.Clone();
        }
        catch (JsonException ex)
        {
            throw new RuleFormatException("규칙 JSON 형식 오류: " + ex.Message);
        }

        if (root.ValueKind != JsonValueKind.Object) throw new RuleFormatException("규칙은 JSON 객체여야 합니다.");
        int v = root.TryGetProperty("v", out JsonElement ve) && ve.TryGetInt32(out int n) ? n : 0;
        if (v != 1) throw new RuleFormatException($"지원하지 않는 규칙 버전입니다: v={v}");
        return root;
    }

    private static string Kind(JsonElement r) =>
        Str(r, "kind") ?? throw new RuleFormatException("kind가 필요합니다.");

    private static FrameRule FrameFromJson(string json)
    {
        JsonElement r = Root(json);
        string kind = Kind(r).ToUpperInvariant();
        int maxLen = Int(r, "maxLen") ?? 4096;
        if (maxLen <= 0) throw new RuleFormatException("maxLen은 1 이상이어야 합니다.");
        ChecksumRule checksum = ReadChecksum(r);

        FrameRule rule = kind switch
        {
            "DELIM" => new FrameRule
            {
                Kind = FrameKind.Delim,
                End = Bytes(Str(r, "end") ?? "[CR][LF]", "end", minLength: 1)
            },
            "STXETX" => new FrameRule
            {
                Kind = FrameKind.StxEtx,
                Stx = OneByte(Str(r, "stx") ?? "[STX]", "stx"),
                Etx = OneByte(Str(r, "etx") ?? "[ETX]", "etx"),
                Escape = Str(r, "escape") is { } esc ? OneByte(esc, "escape") : null
            },
            "FIXED" => new FrameRule
            {
                Kind = FrameKind.Fixed,
                Length = Int(r, "len") is int len && len > 0 ? len : throw new RuleFormatException("FIXED는 len(1 이상)이 필요합니다.")
            },
            "LENFIELD" => ReadLenField(r),
            _ => throw new RuleFormatException($"알 수 없는 frame kind: {kind}")
        };

        return rule with { MaxLength = maxLen, Checksum = checksum };
    }

    private static FrameRule ReadLenField(JsonElement r)
    {
        int offset = Int(r, "offset") ?? throw new RuleFormatException("LENFIELD는 offset이 필요합니다.");
        int size = Int(r, "size") ?? 1;
        if (offset < 0) throw new RuleFormatException("offset은 0 이상이어야 합니다.");
        if (size is not (1 or 2 or 4)) throw new RuleFormatException("size는 1, 2, 4 중 하나여야 합니다.");
        string endian = (Str(r, "endian") ?? "BE").ToUpperInvariant();
        if (endian is not ("BE" or "LE")) throw new RuleFormatException("endian은 BE 또는 LE입니다.");

        return new FrameRule
        {
            Kind = FrameKind.LenField,
            LengthOffset = offset,
            LengthSize = size,
            LengthBigEndian = endian == "BE",
            LengthAdjust = Int(r, "adjust") ?? 0,
            LengthIncludesHeader = Bool(r, "includesHeader") ?? false
        };
    }

    private static ChecksumRule ReadChecksum(JsonElement r)
    {
        if (!r.TryGetProperty("checksum", out JsonElement c) || c.ValueKind == JsonValueKind.Null)
        {
            return new ChecksumRule(ChecksumType.None);
        }

        string type = (Str(c, "type") ?? "NONE").ToUpperInvariant();
        ChecksumType t = type switch
        {
            "NONE" => ChecksumType.None,
            "SUM8" => ChecksumType.Sum8,
            "XOR8" => ChecksumType.Xor8,
            "CRC16_MODBUS" => ChecksumType.Crc16Modbus,
            _ => throw new RuleFormatException($"알 수 없는 checksum type: {type}")
        };
        int from = Int(c, "from") ?? 0;
        if (from < 0) throw new RuleFormatException("checksum.from은 0 이상이어야 합니다.");
        int to = Int(c, "to") ?? 0;
        if (to > 0 && to < from) throw new RuleFormatException("checksum.to는 from 이상이어야 합니다 (양수일 때).");
        return new ChecksumRule(t, from, to);
    }

    private static ParseRule ParseFromJson(string json)
    {
        JsonElement r = Root(json);
        string kind = Kind(r).ToUpperInvariant();
        string? trim = Str(r, "trim");
        if (trim is not null && trim.Length != 2) throw new RuleFormatException("trim은 앞·뒤 2글자입니다 (예: \"{}\").");

        switch (kind)
        {
            case "TEXT":
            {
                int count = Int(r, "count") ?? 0;
                if (count < 0) throw new RuleFormatException("count는 0 이상이어야 합니다.");
                return new ParseRule
                {
                    Kind = ParseKind.Text,
                    Trim = trim,
                    Separator = Sep(Str(r, "sep")),
                    Count = count,
                    Map = (Str(r, "map") ?? "CHANNELS").ToUpperInvariant() switch
                    {
                        "CHANNELS" => ValueMap.Channels,
                        "SAMPLES" => ValueMap.Samples,
                        string m => throw new RuleFormatException($"알 수 없는 map: {m}")
                    }
                };
            }
            case "INFO":
            {
                IReadOnlyList<string> fields = StrArray(r, "fields");
                if (fields.Count == 0) throw new RuleFormatException("INFO는 fields가 필요합니다.");
                return new ParseRule
                {
                    Kind = ParseKind.Info,
                    Trim = trim,
                    Separator = Sep(Str(r, "sep") ?? "COMMA"),
                    Fields = fields,
                    Count = fields.Count,
                    Absent = Str(r, "absent")
                };
            }
            case "BINARY":
                return new ParseRule { Kind = ParseKind.Binary, BinaryFields = ReadBinaryFields(r) };
            default:
                throw new RuleFormatException($"알 수 없는 parse kind: {kind}");
        }
    }

    private static IReadOnlyList<BinaryField> ReadBinaryFields(JsonElement r)
    {
        if (!r.TryGetProperty("fields", out JsonElement arr) || arr.ValueKind != JsonValueKind.Array || arr.GetArrayLength() == 0)
        {
            throw new RuleFormatException("BINARY는 fields 배열이 필요합니다.");
        }

        var list = new List<BinaryField>();
        var keys = new HashSet<string>(StringComparer.Ordinal);
        foreach (JsonElement f in arr.EnumerateArray())
        {
            string key = Str(f, "key") ?? throw new RuleFormatException("BINARY 필드에 key가 필요합니다.");
            if (!keys.Add(key)) throw new RuleFormatException($"BINARY 필드 key 중복: {key}");
            int offset = Int(f, "offset") ?? throw new RuleFormatException($"{key}: offset이 필요합니다.");
            if (offset < 0) throw new RuleFormatException($"{key}: offset은 0 이상이어야 합니다.");
            string typeText = (Str(f, "type") ?? throw new RuleFormatException($"{key}: type이 필요합니다.")).ToUpperInvariant();
            if (!Enum.TryParse(typeText, ignoreCase: true, out BinaryType type) || !Enum.IsDefined(type))
            {
                throw new RuleFormatException($"{key}: 알 수 없는 type {typeText}");
            }
            string endian = (Str(f, "endian") ?? "LE").ToUpperInvariant();
            if (endian is not ("BE" or "LE")) throw new RuleFormatException($"{key}: endian은 BE 또는 LE입니다.");

            list.Add(new BinaryField(key, offset, type, endian == "BE",
                Dbl(f, "scale") ?? 1, Dbl(f, "valueOffset") ?? 0));
        }
        return list;
    }

    // ----- 공통 -----

    internal static TextSeparator Sep(string? text) => (text ?? "SPACE").ToUpperInvariant() switch
    {
        "SPACE" => TextSeparator.Space,
        "COMMA" => TextSeparator.Comma,
        "TAB" => TextSeparator.Tab,
        string s => throw new RuleFormatException($"알 수 없는 sep: {s}")
    };

    private static byte[] Bytes(string expr, string name, int minLength)
    {
        byte[] b;
        try { b = ProtocolExpression.ToBytes(expr); }
        catch (FormatException ex) { throw new RuleFormatException($"{name}: {ex.Message}"); }
        if (b.Length < minLength) throw new RuleFormatException($"{name}: {minLength}바이트 이상이어야 합니다.");
        return b;
    }

    internal static byte OneByte(string expr, string name)
    {
        byte[] b = Bytes(expr, name, 1);
        if (b.Length != 1) throw new RuleFormatException($"{name}: 1바이트여야 합니다.");
        return b[0];
    }

    private static string? Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int? Int(JsonElement e, string name)
    {
        if (!e.TryGetProperty(name, out JsonElement v) || v.ValueKind == JsonValueKind.Null) return null;
        if (v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out int n)) return n;
        throw new RuleFormatException($"{name}: 정수여야 합니다.");
    }

    private static double? Dbl(JsonElement e, string name)
    {
        if (!e.TryGetProperty(name, out JsonElement v) || v.ValueKind == JsonValueKind.Null) return null;
        if (v.ValueKind == JsonValueKind.Number) return v.GetDouble();
        throw new RuleFormatException($"{name}: 숫자여야 합니다.");
    }

    private static bool? Bool(JsonElement e, string name)
    {
        if (!e.TryGetProperty(name, out JsonElement v) || v.ValueKind == JsonValueKind.Null) return null;
        return v.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new RuleFormatException($"{name}: true/false여야 합니다.")
        };
    }

    private static IReadOnlyList<string> StrArray(JsonElement e, string name)
    {
        if (!e.TryGetProperty(name, out JsonElement v) || v.ValueKind != JsonValueKind.Array) return [];
        var list = new List<string>();
        foreach (JsonElement x in v.EnumerateArray())
        {
            if (x.ValueKind != JsonValueKind.String || string.IsNullOrEmpty(x.GetString()))
            {
                throw new RuleFormatException($"{name}: 빈 값이 아닌 문자열 배열이어야 합니다.");
            }
            list.Add(x.GetString()!);
        }
        if (list.Distinct(StringComparer.Ordinal).Count() != list.Count) throw new RuleFormatException($"{name}: 중복 항목");
        return list;
    }

    internal static int ParseIntInvariant(string s, string name) =>
        int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out int n)
            ? n
            : throw new RuleFormatException($"{name}: 정수여야 합니다 ({s}).");
}

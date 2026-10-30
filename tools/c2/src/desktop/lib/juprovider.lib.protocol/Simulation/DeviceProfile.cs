using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace JuProvider.Lib.Protocol.Simulation;

public sealed class ProfileFormatException(string message) : FormatException(message);

public sealed record ProfileResponse(string? Match, Regex? MatchRegex, string? Reply, IReadOnlyDictionary<string, string> Set);

public sealed record ProfileStream(string When, string EveryMs, string Frame);

public sealed record GeneratorSpec(string Type, double Value, double Min, double Max, double Step, double Amp, double PeriodMs, double Offset, IReadOnlyList<double> Values);

/// <summary>
/// 장치 프로파일 (C0 §5, JSON v1). 코드가 아니라 데이터로 장치 동작을 적는다.
/// {"profileId","v":1,"seed","vars":{..},"responses":[{"match"|"matchRegex","reply","set":{..}}],
///  "streams":[{"when","everyMs","frame"}],"generators":{"name":{"type":"constant|ramp|sine|random|sequence",..}}}
/// match: 요청 표현식(끝의 [CR][LF]는 무시하고 비교). reply/frame: 표현식 템플릿, ${이름}·${이름*수}·${이름/수}.
/// when: "이름", "이름==값", "이름!=값"을 && 로 연결.
/// </summary>
public sealed record DeviceProfile(
    string ProfileId,
    int Seed,
    IReadOnlyDictionary<string, string> Vars,
    IReadOnlyList<ProfileResponse> Responses,
    IReadOnlyList<ProfileStream> Streams,
    IReadOnlyDictionary<string, GeneratorSpec> Generators)
{
    public static DeviceProfile Parse(string json)
    {
        JsonElement r;
        try
        {
            using JsonDocument doc = JsonDocument.Parse(json);
            r = doc.RootElement.Clone();
        }
        catch (JsonException ex)
        {
            throw new ProfileFormatException("프로파일 JSON 형식 오류: " + ex.Message);
        }

        if (r.ValueKind != JsonValueKind.Object) throw new ProfileFormatException("프로파일은 JSON 객체입니다.");
        if (!r.TryGetProperty("v", out JsonElement v) || v.ValueKind != JsonValueKind.Number || v.GetInt32() != 1)
        {
            throw new ProfileFormatException("프로파일 버전 v=1 이 필요합니다.");
        }

        string id = Str(r, "profileId") ?? throw new ProfileFormatException("profileId가 필요합니다.");
        int seed = r.TryGetProperty("seed", out JsonElement s) && s.ValueKind == JsonValueKind.Number ? s.GetInt32() : 1;

        var vars = new Dictionary<string, string>(StringComparer.Ordinal);
        if (r.TryGetProperty("vars", out JsonElement ve) && ve.ValueKind == JsonValueKind.Object)
        {
            foreach (JsonProperty p in ve.EnumerateObject()) vars[p.Name] = Scalar(p.Value, "vars." + p.Name);
        }

        var responses = new List<ProfileResponse>();
        if (r.TryGetProperty("responses", out JsonElement re) && re.ValueKind == JsonValueKind.Array)
        {
            foreach (JsonElement x in re.EnumerateArray())
            {
                string? match = Str(x, "match");
                string? regexText = Str(x, "matchRegex");
                if ((match is null) == (regexText is null)) throw new ProfileFormatException("response는 match 또는 matchRegex 중 하나가 필요합니다.");
                Regex? regex = null;
                if (regexText is not null)
                {
                    try { regex = new Regex(regexText, RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(200)); }
                    catch (ArgumentException ex) { throw new ProfileFormatException("matchRegex 오류: " + ex.Message); }
                }
                var set = new Dictionary<string, string>(StringComparer.Ordinal);
                if (x.TryGetProperty("set", out JsonElement se) && se.ValueKind == JsonValueKind.Object)
                {
                    foreach (JsonProperty p in se.EnumerateObject()) set[p.Name] = Scalar(p.Value, "set." + p.Name);
                }
                string? reply = Str(x, "reply");
                if (reply is null && set.Count == 0) throw new ProfileFormatException("response는 reply 또는 set이 필요합니다.");
                responses.Add(new ProfileResponse(match, regex, reply, set));
            }
        }

        var streams = new List<ProfileStream>();
        if (r.TryGetProperty("streams", out JsonElement st) && st.ValueKind == JsonValueKind.Array)
        {
            foreach (JsonElement x in st.EnumerateArray())
            {
                streams.Add(new ProfileStream(
                    Str(x, "when") ?? "",
                    x.TryGetProperty("everyMs", out JsonElement e) ? Scalar(e, "everyMs") : throw new ProfileFormatException("stream everyMs가 필요합니다."),
                    Str(x, "frame") ?? throw new ProfileFormatException("stream frame이 필요합니다.")));
            }
        }

        var generators = new Dictionary<string, GeneratorSpec>(StringComparer.Ordinal);
        if (r.TryGetProperty("generators", out JsonElement ge) && ge.ValueKind == JsonValueKind.Object)
        {
            foreach (JsonProperty p in ge.EnumerateObject())
            {
                string type = (Str(p.Value, "type") ?? throw new ProfileFormatException($"generator {p.Name}: type이 필요합니다.")).ToLowerInvariant();
                if (type is not ("constant" or "ramp" or "sine" or "random" or "sequence"))
                {
                    throw new ProfileFormatException($"generator {p.Name}: 알 수 없는 type {type}");
                }
                var values = new List<double>();
                if (p.Value.TryGetProperty("values", out JsonElement va) && va.ValueKind == JsonValueKind.Array)
                {
                    foreach (JsonElement n in va.EnumerateArray()) values.Add(n.GetDouble());
                }
                if (type == "sequence" && values.Count == 0) throw new ProfileFormatException($"generator {p.Name}: values가 필요합니다.");
                generators[p.Name] = new GeneratorSpec(type,
                    Num(p.Value, "value", 0), Num(p.Value, "min", 0), Num(p.Value, "max", 1), Num(p.Value, "step", 1),
                    Num(p.Value, "amp", 1), Num(p.Value, "periodMs", 1000), Num(p.Value, "offset", 0), values);
            }
        }

        return new DeviceProfile(id, seed, vars, responses, streams, generators);
    }

    private static string? Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static double Num(JsonElement e, string name, double fallback) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : fallback;

    private static string Scalar(JsonElement e, string name) => e.ValueKind switch
    {
        JsonValueKind.String => e.GetString()!,
        JsonValueKind.Number => e.GetDouble().ToString(CultureInfo.InvariantCulture),
        JsonValueKind.True => "true",
        JsonValueKind.False => "false",
        _ => throw new ProfileFormatException($"{name}: 문자열·숫자·true/false만 허용됩니다.")
    };
}

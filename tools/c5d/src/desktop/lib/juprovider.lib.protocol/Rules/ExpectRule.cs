using System.Text.Json;
using JuProvider.Lib.Protocol.Scheduling;

namespace JuProvider.Lib.Protocol.Rules;

/// <summary>
/// 응답 판정 규칙 (C5d, 서버 ju_protocol.EXPECT_RULE): {"startsWith":".."} 또는 {"regex":".."} — 키 1개, 빈 값 불가.
/// 서버(Java ProtocolRules.validateExpectRule)와 같은 형식. regex 는 .NET 으로 다시 컴파일한다 (Java·.NET 문법 차이는 공통 벡터로 확인).
/// </summary>
public static class ExpectRule
{
    /// <summary>해석 성공이면 true. 실패면 false + error (예외 없음)</summary>
    public static bool TryRead(string? text, out ResponseMatcher? matcher, out string? error)
    {
        matcher = null;
        error = null;
        if (string.IsNullOrWhiteSpace(text))
        {
            error = "비어 있음";
            return false;
        }
        try
        {
            using JsonDocument doc = JsonDocument.Parse(text);
            JsonElement r = doc.RootElement;
            if (r.ValueKind != JsonValueKind.Object)
            {
                error = "JSON 객체가 아님";
                return false;
            }
            List<JsonProperty> props = r.EnumerateObject().ToList();
            if (props.Count != 1 || props[0].Value.ValueKind != JsonValueKind.String || string.IsNullOrEmpty(props[0].Value.GetString()))
            {
                error = "키 1개(startsWith 또는 regex)와 빈 값이 아닌 문자열이어야 함";
                return false;
            }
            string v = props[0].Value.GetString()!;
            switch (props[0].Name)
            {
                case "startsWith":
                    matcher = ResponseMatcher.StartsWith(v);
                    return true;
                case "regex":
                    matcher = ResponseMatcher.Regex(v);
                    return true;
                default:
                    error = "알 수 없는 키 " + props[0].Name;
                    return false;
            }
        }
        catch (Exception ex) when (ex is JsonException or ArgumentException)
        {
            error = ex.Message;
            return false;
        }
    }
}

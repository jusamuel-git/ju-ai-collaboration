using System.Text.Json;
using JuProvider.Lib.Protocol.Expression;
using JuProvider.Lib.Protocol.Rules;

namespace JuProvider.Tests.Protocol;

/// <summary>C5c 서버(Java ProtocolRules)와 같은 공통 판정 벡터 (TestData/rule_vectors.json)</summary>
public class RuleVectorTests
{
    private static JsonElement Vectors()
    {
        string path = Path.Combine(AppContext.BaseDirectory, "TestData", "rule_vectors.json");
        using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(path));
        return doc.RootElement.Clone();
    }

    private static int Verify(JsonElement list, string key, Action<string> check)
    {
        int n = 0;
        foreach (JsonElement v in list.EnumerateArray())
        {
            string value = v.GetProperty(key).GetString()!;
            bool ok = v.GetProperty("ok").GetBoolean();
            Exception? error = null;
            try { check(value); }
            catch (FormatException ex) { error = ex; }
            Assert.True(ok == (error is null), $"{key} '{value}': 기대 {(ok ? "통과" : "오류")}, 실제 {(error is null ? "통과" : error.Message)}");
            n++;
        }
        return n;
    }

    [Fact]
    public void Shared_Vectors_Match_Server()
    {
        JsonElement root = Vectors();
        int n = Verify(root.GetProperty("frame"), "rule", s => RuleReader.ReadFrameRule(s))
              + Verify(root.GetProperty("parse"), "rule", s => RuleReader.ReadParseRule(s))
              + Verify(root.GetProperty("expression"), "expr", s => ProtocolExpression.ToBytes(s));
        Assert.True(n >= 40, $"벡터 수 {n}");
    }
}

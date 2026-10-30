using JuProvider.Lib.Protocol.Rules;

namespace JuProvider.Tests.Protocol;

public class RuleTests
{
    [Fact] // F5 과거 GTEC 텍스트 → 같은 의미의 규칙
    public void Legacy_Gtec_LowSpeed()
    {
        const string legacy = "FRAME=CRLF;STX={;ETX=};MODE=DELIMITED;SEP=SPACE;COUNT=3;MAP=CHANNELS";
        FrameRule frame = RuleReader.ReadFrameRule(legacy)!;
        ParseRule parse = RuleReader.ReadParseRule(legacy)!;

        Assert.Equal(FrameKind.Delim, frame.Kind);
        Assert.Equal(new byte[] { 0x0D, 0x0A }, frame.End);
        Assert.Equal(ParseKind.Text, parse.Kind);
        Assert.Equal("{}", parse.Trim);
        Assert.Equal(3, parse.Count);
        Assert.Equal(ValueMap.Channels, parse.Map);

        ParseRule json = RuleReader.ReadParseRule("""{"v":1,"kind":"TEXT","trim":"{}","sep":"SPACE","count":3,"map":"CHANNELS"}""")!;
        Assert.Equal(json with { Fields = parse.Fields, BinaryFields = parse.BinaryFields }, parse);
    }

    [Fact]
    public void Legacy_Info_Defaults_To_4_Fields()
    {
        ParseRule p = RuleReader.ReadParseRule("MODE=INFO;SEP=COMMA")!;
        Assert.Equal(ParseKind.Info, p.Kind);
        Assert.Equal(new[] { "CH1", "CH2", "CH3", "CH4" }, p.Fields);
        Assert.Equal("000", p.Absent);
    }

    [Fact]
    public void Legacy_None_Has_No_Parse()
    {
        Assert.Null(RuleReader.ReadParseRule("MODE=NONE"));
        Assert.NotNull(RuleReader.ReadFrameRule("MODE=NONE"));
    }

    [Fact]
    public void Empty_Is_Null()
    {
        Assert.Null(RuleReader.ReadFrameRule(""));
        Assert.Null(RuleReader.ReadParseRule("  "));
    }

    [Theory]
    [InlineData("""{"kind":"DELIM"}""")]                              // 버전 없음
    [InlineData("""{"v":2,"kind":"DELIM"}""")]                        // 버전 다름
    [InlineData("""{"v":1}""")]                                       // kind 없음
    [InlineData("""{"v":1,"kind":"NOPE"}""")]
    [InlineData("""{"v":1,"kind":"FIXED"}""")]                        // len 없음
    [InlineData("""{"v":1,"kind":"STXETX","stx":"[STX][ETX]"}""")]    // 1바이트 아님
    [InlineData("""{"v":1,"kind":"LENFIELD","offset":0,"size":3}""")]
    [InlineData("""{"v":1,"kind":"DELIM","checksum":{"type":"MD5"}}""")]
    [InlineData("""{"v":1,"kind":"DELIM","end":"[XX]"}""")]
    [InlineData("""not json""")]
    public void Invalid_FrameRule(string text)
    {
        Assert.ThrowsAny<FormatException>(() => RuleReader.ReadFrameRule(text));
    }

    [Theory]
    [InlineData("""{"v":1,"kind":"TEXT","map":"ROWS"}""")]
    [InlineData("""{"v":1,"kind":"TEXT","trim":"{"}""")]
    [InlineData("""{"v":1,"kind":"INFO"}""")]                          // fields 없음
    [InlineData("""{"v":1,"kind":"INFO","fields":["A","A"]}""")]       // 중복
    [InlineData("""{"v":1,"kind":"BINARY","fields":[]}""")]
    [InlineData("""{"v":1,"kind":"BINARY","fields":[{"key":"A","offset":0,"type":"I24"}]}""")]
    [InlineData("""{"v":1,"kind":"BINARY","fields":[{"key":"A","offset":0,"type":"U8"},{"key":"A","offset":1,"type":"U8"}]}""")]
    [InlineData("FRAME=CRLF;MODE=STREAM")]
    [InlineData("FRAME=CRLF;COUNT=x")]
    [InlineData("패킷길이|STX DLE|ETX|ETX DLE")]                      // 현재 seed의 설명문 형식 → 규칙 아님
    public void Invalid_ParseRule(string text)
    {
        Assert.ThrowsAny<FormatException>(() => RuleReader.ReadParseRule(text));
    }
}

using JuProvider.Lib.Protocol.Framing;
using JuProvider.Lib.Protocol.Parsing;
using JuProvider.Lib.Protocol.Rules;
using static JuProvider.Tests.Protocol.TestUtil;

namespace JuProvider.Tests.Protocol;

public class ParserTests
{
    private static IFrameParser P(string rule) => ParserFactory.Create(RuleReader.ReadParseRule(rule)!);

    [Fact] // P1 저속: 3채널
    public void Text_Channels()
    {
        ParseResult r = P("FRAME=CRLF;STX={;ETX=};MODE=DELIMITED;SEP=SPACE;COUNT=3;MAP=CHANNELS")
            .Parse(BodyFrame("{1.23 -4.5  7e-1}"));
        Assert.True(r.Ok, r.Error);
        Assert.Equal(new[] { "1", "2", "3" }, r.Values.Select(v => v.ChannelKey));
        Assert.Equal(new double?[] { 1.23, -4.5, 0.7 }, r.Values.Select(v => v.Value));
        Assert.All(r.Values, v => Assert.Equal(0, v.SampleIndex));
    }

    [Fact] // P1 고속: 선택 채널 6샘플
    public void Text_Samples()
    {
        ParseResult r = P("""{"v":1,"kind":"TEXT","trim":"{}","count":6,"map":"SAMPLES"}""")
            .Parse(BodyFrame("{1 2 3 4 5 6}"), new ParseContext("2"));
        Assert.True(r.Ok, r.Error);
        Assert.All(r.Values, v => Assert.Equal("2", v.ChannelKey));
        Assert.Equal(Enumerable.Range(0, 6), r.Values.Select(v => v.SampleIndex));
    }

    [Theory] // P1 거부
    [InlineData("{1 2}")]        // 개수 불일치
    [InlineData("1 2 3")]        // 앞뒤 문자 없음
    [InlineData("{1 x 3}")]      // 숫자 아님
    [InlineData("{1,5 2 3}")]    // 지역 형식 쉼표 소수점 거부
    public void Text_Rejects(string body)
    {
        ParseResult r = P("""{"v":1,"kind":"TEXT","trim":"{}","count":3}""").Parse(BodyFrame(body));
        Assert.False(r.Ok);
        Assert.NotNull(r.Error);
        Assert.Empty(r.Values);
    }

    [Fact] // P2 센서정보
    public void Info_SensorList()
    {
        ParseResult r = P("""{"v":1,"kind":"INFO","trim":"{}","fields":["CH1","CH2","CH3","CH4"],"absent":"000"}""")
            .Parse(BodyFrame("{008,000,000,000}"));
        Assert.True(r.Ok, r.Error);
        Assert.Equal(new[] { "CH1", "CH2", "CH3", "CH4" }, r.Values.Select(v => v.ChannelKey));
        Assert.Equal("008", r.Values[0].Text);
        Assert.False(r.Values[0].Absent);
        Assert.True(r.Values.Skip(1).All(v => v.Absent));
        Assert.All(r.Values, v => Assert.Null(v.Value));
    }

    [Theory]
    [InlineData("{008,000,000}")]
    [InlineData("{008,,000,000}")]
    public void Info_Rejects(string body)
    {
        Assert.False(P("""{"v":1,"kind":"INFO","trim":"{}","fields":["CH1","CH2","CH3","CH4"]}""").Parse(BodyFrame(body)).Ok);
    }

    [Fact] // P3
    public void Binary_Fields()
    {
        // I16 LE = -2 (FE FF), F32 BE = 1.5 (3F C0 00 00), U8 = 200
        byte[] body = { 0xAA, 0xFE, 0xFF, 0x3F, 0xC0, 0x00, 0x00, 0xC8 };
        ParseResult r = P("""
            {"v":1,"kind":"BINARY","fields":[
              {"key":"T","offset":1,"type":"I16","endian":"LE","scale":0.5,"valueOffset":10},
              {"key":"P","offset":3,"type":"F32","endian":"BE"},
              {"key":"S","offset":7,"type":"U8"}]}
            """).Parse(new Frame(body, body));
        Assert.True(r.Ok, r.Error);
        Assert.Equal(new double?[] { 9.0, 1.5, 200 }, r.Values.Select(v => v.Value));
        Assert.Equal(new[] { "T", "P", "S" }, r.Values.Select(v => v.ChannelKey));
    }

    [Fact]
    public void Binary_ShortFrame_Rejected()
    {
        byte[] body = { 0x01 };
        Assert.False(P("""{"v":1,"kind":"BINARY","fields":[{"key":"A","offset":0,"type":"U16"}]}""").Parse(new Frame(body, body)).Ok);
    }

    [Fact] // Framer + Parser 연결: 조각 입력 GTEC 저속 스트림
    public void Pipeline_Gtec_Stream()
    {
        const string legacy = "FRAME=CRLF;STX={;ETX=};MODE=DELIMITED;SEP=SPACE;COUNT=3;MAP=CHANNELS";
        IFramer framer = FramerFactory.Create(RuleReader.ReadFrameRule(legacy)!);
        IFrameParser parser = ParserFactory.Create(RuleReader.ReadParseRule(legacy)!);

        List<Frame> frames = PushInChunks(framer, B("{1 2 3}[CR][LF]{4 5 6}[CR][LF]{bad}[CR][LF]{7 8 9}[CR][LF]"), 5);
        List<ParseResult> results = frames.Select(f => parser.Parse(f)).ToList();

        Assert.Equal(4, results.Count);
        Assert.Equal(3, results.Count(r => r.Ok));
        Assert.Equal(9.0, results[3].Values[2].Value);
    }
}

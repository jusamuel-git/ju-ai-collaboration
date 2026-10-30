using JuProvider.Lib.Protocol.Framing;
using JuProvider.Lib.Protocol.Rules;
using static JuProvider.Tests.Protocol.TestUtil;

namespace JuProvider.Tests.Protocol;

public class FramerTests
{
    private static IFramer Delim() => FramerFactory.Create(RuleReader.ReadFrameRule("""{"v":1,"kind":"DELIM","end":"[CR][LF]"}""")!);

    [Theory] // F1 조각 크기와 무관하게 같은 결과
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(7)]
    [InlineData(1000)]
    public void Delim_Fragmented_And_Multiple(int chunk)
    {
        byte[] data = B("{1.0 2.0 3.0}[CR][LF]{4 5 6}[CR][LF][CR][LF]{7 8");
        IFramer f = Delim();
        List<Frame> frames = PushInChunks(f, data, chunk);

        Assert.Equal(2, frames.Count); // 빈 프레임은 건너뜀, 마지막 미완성은 버퍼에 남음
        Assert.Equal(B("{1.0 2.0 3.0}"), frames[0].Body);
        Assert.Equal(B("{4 5 6}[CR][LF]"), frames[1].Raw);
        Assert.Equal(B("{7 8").Length, f.Pending);

        frames = f.Push(B("}[CR][LF]")).ToList();
        Assert.Single(frames);
        Assert.Equal(B("{7 8}"), frames[0].Body);
    }

    [Fact] // F1 최대 길이 초과 → 버퍼 비움
    public void Delim_MaxLength_Clears()
    {
        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule("""{"v":1,"kind":"DELIM","end":"[LF]","maxLen":8}""")!);
        Assert.Empty(f.Push(B("0123456789")));
        Assert.Single(f.Rejections);
        Assert.Equal(0, f.Pending);
        Assert.Single(f.Push(B("ok[LF]")));
    }

    [Fact] // F2 STX 앞 쓰레기, escape 된 ETX
    public void StxEtx_Garbage_And_Escape()
    {
        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule("""{"v":1,"kind":"STXETX","stx":"[STX]","etx":"[ETX]","escape":"[DLE]"}""")!);
        byte[] data = B("xx[STX]A[DLE][ETX]B[DLE][DLE][ETX][STX]C[ETX]");
        List<Frame> frames = PushInChunks(f, data, 1);

        Assert.Equal(2, frames.Count);
        Assert.Equal(new byte[] { 0x41, 0x03, 0x42, 0x10 }, frames[0].Body);
        Assert.Equal(B("C"), frames[1].Body);
    }

    [Fact]
    public void StxEtx_Garbage_Is_Reported()
    {
        IFramer f = FramerFactory.Create(new FrameRule { Kind = FrameKind.StxEtx });
        Assert.Single(f.Push(B("zz[STX]A[ETX]")));
        Assert.Contains(f.Rejections, r => r.Reason == "STX 앞 데이터");
    }

    [Fact] // F3
    public void Fixed_Length()
    {
        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule("""{"v":1,"kind":"FIXED","len":3}""")!);
        List<Frame> frames = PushInChunks(f, B("ABCDEFG"), 2);
        Assert.Equal(2, frames.Count);
        Assert.Equal(B("DEF"), frames[1].Body);
        Assert.Equal(1, f.Pending);
    }

    [Theory] // F3 BE/LE, 헤더 포함 여부, adjust
    [InlineData("""{"v":1,"kind":"LENFIELD","offset":1,"size":2,"endian":"BE"}""", "[AA][00][02]XY[AA][00][01]Z")]
    [InlineData("""{"v":1,"kind":"LENFIELD","offset":1,"size":2,"endian":"LE"}""", "[AA][02][00]XY[AA][01][00]Z")]
    [InlineData("""{"v":1,"kind":"LENFIELD","offset":0,"size":1,"includesHeader":true,"adjust":0}""", "[03]XY[02]Z")]
    [InlineData("""{"v":1,"kind":"LENFIELD","offset":0,"size":1,"adjust":1}""", "[01]XY[00]Z")]
    public void LengthField(string rule, string data)
    {
        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule(rule)!);
        List<Frame> frames = PushInChunks(f, B(data), 1);
        Assert.Equal(2, frames.Count);
        Assert.EndsWith("XY", System.Text.Encoding.ASCII.GetString(frames[0].Body));
        Assert.EndsWith("Z", System.Text.Encoding.ASCII.GetString(frames[1].Body));
    }

    [Fact] // F3 잘못된 길이 → 1바이트씩 버리고 재동기화
    public void LengthField_Invalid_Resyncs()
    {
        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule("""{"v":1,"kind":"LENFIELD","offset":0,"size":1,"includesHeader":true,"maxLen":4}""")!);
        List<Frame> frames = f.Push(B("[00][09][02]A")).ToList();
        Assert.Single(frames);
        Assert.Equal(B("[02]A"), frames[0].Body);
        Assert.Equal(2, f.Rejections.Count);
    }

    [Theory] // F4
    [InlineData("SUM8")]
    [InlineData("XOR8")]
    [InlineData("CRC16_MODBUS")]
    public void Checksum_Valid_Stripped_Invalid_Rejected(string type)
    {
        ChecksumType t = type switch { "SUM8" => ChecksumType.Sum8, "XOR8" => ChecksumType.Xor8, _ => ChecksumType.Crc16Modbus };
        byte[] payload = B("12AB");
        byte[] good = payload.Concat(Checksum.Compute(t, payload)).Concat(B("[CR][LF]")).ToArray();
        byte[] bad = payload.Concat(Checksum.Compute(t, B("ZZZY"))).Concat(B("[CR][LF]")).ToArray();

        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule($$$"""{"v":1,"kind":"DELIM","end":"[CR][LF]","checksum":{"type":"{{{type}}}"}}""")!);
        List<Frame> frames = f.Push(good).ToList();
        Assert.Single(frames);
        Assert.Equal(payload, frames[0].Body);

        Assert.Empty(f.Push(bad));
        Assert.Contains(f.Rejections, r => r.Reason == "체크섬 불일치");
    }

    [Theory] // F4 계산 범위 from/to: 헤더 1바이트·끝 1바이트 제외
    [InlineData("""{"from":1,"to":-1}""")]
    [InlineData("""{"from":1,"to":4}""")]
    public void Checksum_Range_From_To(string range)
    {
        // 데이터부 AA 01 02 03 0D, 계산 범위 01 02 03 → SUM8 = 06
        byte[] frame = { 0xAA, 0x01, 0x02, 0x03, 0x0D, 0x06 };
        string rule = "{\"v\":1,\"kind\":\"FIXED\",\"len\":6,\"checksum\":{\"type\":\"SUM8\"," + range[1..] + "}";
        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule(rule)!);

        List<Frame> frames = f.Push(frame).ToList();
        Assert.Single(frames);
        Assert.Equal(new byte[] { 0xAA, 0x01, 0x02, 0x03, 0x0D }, frames[0].Body);

        // 전체 범위였다면 맞았을 값 → 범위 규칙에서는 불일치
        byte whole = Checksum.Compute(ChecksumType.Sum8, new byte[] { 0xAA, 0x01, 0x02, 0x03, 0x0D })[0];
        Assert.Empty(f.Push(new byte[] { 0xAA, 0x01, 0x02, 0x03, 0x0D, whole }));
        Assert.Contains(f.Rejections, r => r.Reason == "체크섬 불일치");
    }

    [Fact] // F4 범위가 데이터부를 벗어나면 프레임 버림
    public void Checksum_Range_Invalid_Rejected()
    {
        IFramer f = FramerFactory.Create(RuleReader.ReadFrameRule("""{"v":1,"kind":"FIXED","len":3,"checksum":{"type":"XOR8","from":3}}""")!);
        Assert.Empty(f.Push(new byte[] { 0x01, 0x02, 0x03 }));
        Assert.Contains(f.Rejections, r => r.Reason == "체크섬 범위 오류");
    }

    [Fact]
    public void ChecksumRule_TryRange()
    {
        var c = new ChecksumRule(ChecksumType.Sum8, 1, -1);
        Assert.True(c.TryRange(5, out int s, out int e));
        Assert.Equal((1, 4), (s, e));
        Assert.True(new ChecksumRule(ChecksumType.Sum8).TryRange(5, out s, out e));
        Assert.Equal((0, 5), (s, e));
        Assert.False(new ChecksumRule(ChecksumType.Sum8, 0, 6).TryRange(5, out _, out _));
    }

    [Fact]
    public void Crc16Modbus_KnownVector()
    {
        // 01 03 00 00 00 01 → CRC 84 0A (Little Endian)
        Assert.Equal(new byte[] { 0x84, 0x0A }, Checksum.Compute(ChecksumType.Crc16Modbus, new byte[] { 0x01, 0x03, 0x00, 0x00, 0x00, 0x01 }));
    }
}

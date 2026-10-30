using JuProvider.Lib.Protocol.Simulation;
using JuProvider.Lib.Protocol.Transport;

namespace JuProvider.Tests.Protocol;

public class ProfileAndConfigTests
{
    [Fact]
    public void BuiltIn_Profiles_Parse()
    {
        foreach (string id in new[] { "GTEC_SCIENCE_CUBE", "GENERIC_ECHO", "GENERIC_STREAM" })
        {
            Assert.Equal(id, BuiltInProfiles.Get(id).ProfileId);
        }
        Assert.Throws<ProfileFormatException>(() => BuiltInProfiles.Get("NOPE"));
    }

    [Theory]
    [InlineData("""{"profileId":"X"}""")]                                                     // v 없음
    [InlineData("""{"v":1}""")]                                                               // id 없음
    [InlineData("""{"v":1,"profileId":"X","responses":[{"reply":"A"}]}""")]                   // match 없음
    [InlineData("""{"v":1,"profileId":"X","responses":[{"match":"A","matchRegex":"A","reply":"B"}]}""")]
    [InlineData("""{"v":1,"profileId":"X","responses":[{"match":"A"}]}""")]                   // reply/set 없음
    [InlineData("""{"v":1,"profileId":"X","responses":[{"matchRegex":"(","reply":"B"}]}""")]  // 잘못된 정규식
    [InlineData("""{"v":1,"profileId":"X","streams":[{"frame":"A"}]}""")]                     // everyMs 없음
    [InlineData("""{"v":1,"profileId":"X","generators":{"g":{"type":"noise"}}}""")]
    [InlineData("""{"v":1,"profileId":"X","generators":{"g":{"type":"sequence"}}}""")]
    [InlineData("""{"v":1,"profileId":"X","vars":{"a":[1]}}""")]
    [InlineData("""not json""")]
    public void Invalid_Profiles(string json)
    {
        Assert.ThrowsAny<FormatException>(() => DeviceProfile.Parse(json));
    }

    [Fact]
    public void ReconnectPolicy_Default_Delays()
    {
        ReconnectPolicy p = ReconnectPolicy.Default;
        int[] expected = { 1, 2, 3, 5, 10, 20, 40, 60, 60, 60 };
        for (int i = 0; i < expected.Length; i++) Assert.Equal(TimeSpan.FromSeconds(expected[i]), p.DelayFor(i + 1));
        Assert.Equal(TimeSpan.FromSeconds(60), p.DelayFor(1000));
        Assert.Throws<ArgumentOutOfRangeException>(() => p.DelayFor(0));
    }

    [Fact]
    public async Task Factory_Builds_Transports()
    {
        await using ITransport serial = TransportFactory.FromLocalConfig("""{"transport":"serial","portName":"COM6","baudRate":115200,"parity":"even","stopBits":"Two"}""");
        var s = Assert.IsType<SerialTransport>(serial);
        Assert.Equal(new SerialSettings("COM6", 115200, 8, System.IO.Ports.Parity.Even, System.IO.Ports.StopBits.Two), s.Settings);

        await using ITransport legacyKeys = TransportFactory.FromLocalConfig("""{"transport":"SERIAL","serialPort":"COM3","timeoutMs":500}""");
        Assert.Equal(500, ((SerialTransport)legacyKeys).Settings.WriteTimeoutMs);

        await using ITransport tcp = TransportFactory.FromLocalConfig("""{"transport":"TCP","ip":"10.0.0.1","port":"5000"}""");
        Assert.Equal("TCP 10.0.0.1:5000", tcp.Name);

        await using ITransport v = TransportFactory.FromLocalConfig("""{"transport":"VIRTUAL","profile":"GENERIC_ECHO","faults":{"dropRate":0.1,"seed":7}}""");
        Assert.Equal("VIRTUAL GENERIC_ECHO", v.Name);
    }

    [Theory]
    [InlineData("""{"portName":"COM1"}""")]                          // transport 없음
    [InlineData("""{"transport":"USB"}""")]
    [InlineData("""{"transport":"SERIAL"}""")]                       // 포트 없음
    [InlineData("""{"transport":"SERIAL","portName":"COM1","parity":"Maybe"}""")]
    [InlineData("""{"transport":"SERIAL","portName":"COM1","baudRate":"fast"}""")]
    [InlineData("""{"transport":"TCP","host":"h"}""")]               // port 없음
    [InlineData("""{"transport":"TCP","host":"h","port":70000}""")]
    [InlineData("""{"transport":"VIRTUAL","profile":"NOPE"}""")]
    [InlineData("""[1]""")]
    public void Factory_Rejects_Invalid(string json)
    {
        Assert.Throws<TransportConfigException>(() => TransportFactory.FromLocalConfig(json));
    }

    [Fact] // S1 없는 COM 포트 → 예외 + Faulted (장비 없이 확인 가능한 범위)
    public async Task Serial_Missing_Port_Faults()
    {
        await using var t = new SerialTransport(new SerialSettings("COM250"));
        await Assert.ThrowsAnyAsync<Exception>(() => t.OpenAsync());
        Assert.Equal(TransportState.Faulted, t.State);
        Assert.Equal("SERIAL COM250", t.Name);
    }
}

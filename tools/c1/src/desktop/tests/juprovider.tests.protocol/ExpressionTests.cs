using JuProvider.Lib.Protocol.Expression;
using static JuProvider.Tests.Protocol.TestUtil;

namespace JuProvider.Tests.Protocol;

public class ExpressionTests
{
    [Fact] // E1
    public void SeedExpressions_RoundTrip()
    {
        List<string> list = SeedExpressions().ToList();
        Assert.True(list.Count >= 10, "seed 표현식 목록이 비었습니다.");
        foreach (string e in list)
        {
            byte[] bytes = ProtocolExpression.ToBytes(e);
            string display = ProtocolExpression.ToDisplay(bytes);
            Assert.Equal(bytes, ProtocolExpression.ToBytes(display));
        }
    }

    [Fact]
    public void Known_Bytes()
    {
        Assert.Equal(new byte[] { 0x53, 0x7B, 0x31, 0x30, 0x2C, 0x31, 0x7D, 0x0D, 0x0A }, B("S{10,1}[CR][LF]"));
        Assert.Equal(new byte[] { 0x02, 0x41, 0x00, 0x03 }, B("[STX]A[00][ETX]"));
        Assert.Equal(new byte[] { 0x10, 0xFF }, B("[dle][ff]"));
        Assert.Empty(ProtocolExpression.ToBytes(null));
        Assert.Equal("53 7B 0D", ProtocolExpression.Hex(new byte[] { 0x53, 0x7B, 0x0D }));
    }

    [Fact]
    public void Display_Escapes_Bracket_And_NonPrintable_For_RoundTrip()
    {
        byte[] data = { (byte)'[', (byte)'A', (byte)']', 0x01, 0x0D, 0x7F };
        string display = ProtocolExpression.ToDisplay(data);
        Assert.Equal("[5B]A][01][CR][7F]", display);
        Assert.Equal(data, ProtocolExpression.ToBytes(display));
    }

    [Theory] // E2
    [InlineData("S{10,1}[CR")]
    [InlineData("[XYZ]")]
    [InlineData("[0G]")]
    [InlineData("[123]")]
    [InlineData("가")]
    public void Invalid_Expression_Throws(string expr)
    {
        Assert.Throws<FormatException>(() => ProtocolExpression.ToBytes(expr));
    }

    [Fact]
    public void AllBytes_RoundTrip()
    {
        byte[] all = Enumerable.Range(0, 256).Select(i => (byte)i).ToArray();
        Assert.Equal(all, ProtocolExpression.ToBytes(ProtocolExpression.ToDisplay(all)));
    }
}

using JuProvider.Lib.Protocol.Expression;
using JuProvider.Lib.Protocol.Framing;

namespace JuProvider.Tests.Protocol;

internal static class TestUtil
{
    public static byte[] B(string expression) => ProtocolExpression.ToBytes(expression);

    public static Frame BodyFrame(string expression)
    {
        byte[] b = B(expression);
        return new Frame(b, b);
    }

    /// <summary>입력을 지정 크기 조각으로 나눠 넣고 프레임을 모두 모은다</summary>
    public static List<Frame> PushInChunks(IFramer framer, byte[] data, int chunkSize)
    {
        var frames = new List<Frame>();
        for (int i = 0; i < data.Length; i += chunkSize)
        {
            frames.AddRange(framer.Push(data.AsSpan(i, Math.Min(chunkSize, data.Length - i))));
        }
        return frames;
    }

    public static IEnumerable<string> SeedExpressions() =>
        File.ReadAllLines(Path.Combine(AppContext.BaseDirectory, "TestData", "seed_expressions.txt"))
            .Where(l => l.Length > 0 && !l.StartsWith('#'));
}

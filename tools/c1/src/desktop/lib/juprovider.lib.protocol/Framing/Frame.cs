namespace JuProvider.Lib.Protocol.Framing;

/// <summary>완성된 프레임. Raw = 받은 바이트 그대로, Body = 규칙에 따른 내용 (FrameRule 설명 참고)</summary>
public sealed record Frame(byte[] Raw, byte[] Body);

/// <summary>버린 바이트와 사유 (Traffic 로그용)</summary>
public sealed record FrameRejection(string Reason, byte[] Data);

/// <summary>바이트 조각 → 완성 프레임. 조각을 여러 번 나눠 넣어도 결과가 같아야 한다.</summary>
public interface IFramer
{
    /// <summary>새 바이트를 넣고 완성된 프레임을 꺼낸다. 미완성 부분은 내부 버퍼에 남는다.</summary>
    IReadOnlyList<Frame> Push(ReadOnlySpan<byte> chunk);

    /// <summary>버린 데이터 (Push 호출마다 새로 채워짐)</summary>
    IReadOnlyList<FrameRejection> Rejections { get; }

    /// <summary>미완성 버퍼 비우기 (재연결 등)</summary>
    void Reset();

    /// <summary>현재 버퍼에 남은 바이트 수</summary>
    int Pending { get; }
}

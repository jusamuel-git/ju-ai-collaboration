namespace JuProvider.Lib.Protocol.Rules;

/// <summary>프레임 구분 방식 (C0 §4)</summary>
public enum FrameKind
{
    /// <summary>끝 구분자 (예: [CR][LF])</summary>
    Delim,
    /// <summary>시작·끝 바이트 + 선택 escape (예: [STX]…[ETX], DLE)</summary>
    StxEtx,
    /// <summary>고정 길이</summary>
    Fixed,
    /// <summary>헤더 안 길이 필드로 가변 길이</summary>
    LenField
}

public enum ChecksumType
{
    None,
    Sum8,
    Xor8,
    Crc16Modbus
}

/// <summary>
/// 체크섬: 프레임 본문(Body)의 마지막 Size 바이트가 체크섬 값이다.
/// 데이터부 D = Body[0 .. Body.Length - Size).
/// 계산 범위 = D[From .. End), End = To &gt; 0 이면 To, To &lt;= 0 이면 D.Length + To (기본 0 = 끝까지).
/// 범위가 잘못되면(From &gt; End, End &gt; D.Length) 프레임을 버린다.
/// 검증 후 체크섬 바이트는 Body에서 제거한다. CRC16_MODBUS 값은 Little Endian.
/// 예: 헤더 1바이트 제외 → from=1, 마지막 1바이트(예: 종료 문자) 제외 → to=-1
/// </summary>
public sealed record ChecksumRule(ChecksumType Type, int From = 0, int To = 0)
{
    public int Size => Type switch
    {
        ChecksumType.None => 0,
        ChecksumType.Crc16Modbus => 2,
        _ => 1
    };

    /// <summary>데이터부 길이에 대한 계산 범위 [start, end). 잘못되면 false</summary>
    public bool TryRange(int dataLength, out int start, out int end)
    {
        start = From;
        end = To > 0 ? To : dataLength + To;
        return start >= 0 && end <= dataLength && start <= end;
    }
}

/// <summary>
/// 바이트 흐름 → 프레임 규칙. 바이트 값은 ProtocolExpression 문법으로 적고 여기서는 변환된 바이트를 가진다.
/// Body 정의:
///  - Delim  : 끝 구분자를 뺀 앞부분
///  - StxEtx : STX·ETX를 빼고 escape를 푼 내용
///  - Fixed / LenField : 프레임 전체 (바이너리 Parse Rule의 offset 기준)
/// </summary>
public sealed record FrameRule
{
    public FrameKind Kind { get; init; } = FrameKind.Delim;

    public byte[] End { get; init; } = [0x0D, 0x0A];

    public byte Stx { get; init; } = 0x02;
    public byte Etx { get; init; } = 0x03;
    public byte? Escape { get; init; }

    /// <summary>Fixed 길이</summary>
    public int Length { get; init; }

    /// <summary>LenField: 길이 필드 위치·크기(1,2,4)·바이트 순서</summary>
    public int LengthOffset { get; init; }
    public int LengthSize { get; init; } = 1;
    public bool LengthBigEndian { get; init; } = true;
    /// <summary>LenField: 길이 값에 더할 보정값</summary>
    public int LengthAdjust { get; init; }
    /// <summary>LenField: 길이 값이 헤더(0..LengthOffset+LengthSize)까지 포함하는지</summary>
    public bool LengthIncludesHeader { get; init; }

    /// <summary>이 길이를 넘으면 버퍼를 비우고 거부한다 (쓰레기 데이터 보호)</summary>
    public int MaxLength { get; init; } = 4096;

    public ChecksumRule Checksum { get; init; } = new(ChecksumType.None);
}

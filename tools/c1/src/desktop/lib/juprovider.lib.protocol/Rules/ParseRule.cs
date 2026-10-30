namespace JuProvider.Lib.Protocol.Rules;

public enum ParseKind
{
    /// <summary>ASCII 텍스트 숫자 목록 (GTEC 저속·고속)</summary>
    Text,
    /// <summary>ASCII 텍스트 항목 목록 (센서정보 등, 숫자 변환 없음)</summary>
    Info,
    /// <summary>바이너리 필드</summary>
    Binary
}

public enum TextSeparator
{
    /// <summary>공백·탭 연속 허용</summary>
    Space,
    Comma,
    Tab
}

public enum ValueMap
{
    /// <summary>토큰 i → 채널 "i+1", 샘플 0</summary>
    Channels,
    /// <summary>토큰 i → 선택 채널, 샘플 i</summary>
    Samples
}

public enum BinaryType
{
    U8, I8, U16, I16, U32, I32, F32, F64
}

/// <summary>BINARY 필드: Body 기준 Offset 위치의 값 → (raw × Scale + ValueOffset)</summary>
public sealed record BinaryField(
    string Key,
    int Offset,
    BinaryType Type,
    bool BigEndian = false,
    double Scale = 1,
    double ValueOffset = 0);

/// <summary>
/// 프레임 → 원시값 규칙 (C0 §4).
/// Trim: 앞뒤 감싸는 문자 2개(예: "{}"). 지정하면 프레임이 반드시 그 문자로 시작·끝나야 한다.
/// Count: 0이면 토큰 수 검사 안 함.
/// </summary>
public sealed record ParseRule
{
    public ParseKind Kind { get; init; } = ParseKind.Text;

    public string? Trim { get; init; }
    public TextSeparator Separator { get; init; } = TextSeparator.Space;
    public int Count { get; init; }
    public ValueMap Map { get; init; } = ValueMap.Channels;

    /// <summary>INFO: 항목 순서대로 붙일 채널 키 (예: CH1..CH4)</summary>
    public IReadOnlyList<string> Fields { get; init; } = [];
    /// <summary>INFO: 이 값이면 미연결/없음으로 표시 (예: "000")</summary>
    public string? Absent { get; init; }

    public IReadOnlyList<BinaryField> BinaryFields { get; init; } = [];
}

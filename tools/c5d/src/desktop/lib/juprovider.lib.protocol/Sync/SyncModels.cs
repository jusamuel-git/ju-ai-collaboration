namespace JuProvider.Lib.Protocol.Sync;

/// <summary>
/// 서버 내려받기 응답 (C4, SYNC-01 형식). Revision: 내용 해시(같으면 변경 없음). Removed: 삭제 추적 전까지 항상 빈 목록.
/// JSON 은 camelCase (System.Text.Json Web 기본값으로 읽는다).
/// </summary>
public sealed record SyncResult<T>(string Revision, IReadOnlyList<T> Items, IReadOnlyList<string> Removed);

/// <summary>
/// GET /api/core/sync/protocols — ju_protocol_group + detail.
/// C5c 수집 설정(FrameRule JSON v1 원문, CmdGapMs, InitRoutine, InitDelayMs)은 C5c 이전 서버 응답에 없으므로 null 허용.
/// </summary>
public sealed record ProtocolGroupSync(
    string PtlGrpCd,
    string? PtlGrpNm,
    int PollingIntval,
    int TimeoutMs,
    int RetryCnt,
    int SortOrd,
    IReadOnlyList<ProtocolSync> Protocols,
    string? FrameRule = null,
    int? CmdGapMs = null,
    IReadOnlyList<string>? InitRoutine = null,
    int? InitDelayMs = null);

/// <summary>
/// ju_protocol + detail.
/// C5c: Roles(INFO/CONTROL/DATA, 미설정이면 빈 목록), Action(NONE/START/PAUSE/STOP), Expect(응답 판정 JSON 원문), Idempotent(명시값).
/// </summary>
public sealed record ProtocolSync(
    string PtlCd,
    string? PtlType,
    int? PtlLen,
    string? PtlVal,
    string? PtlNm,
    string? PtlDesc,
    IReadOnlyList<ProtocolPacketSync> Packets,
    IReadOnlyList<string>? Roles = null,
    string? Action = null,
    string? Expect = null,
    bool? Idempotent = null);

/// <summary>ju_protocol_packet</summary>
public sealed record ProtocolPacketSync(
    int PacketSeq,
    string? PacketType,
    string? Direction,
    string? PacketExpr,
    string? ResponsePtlCd,
    string? ParseRule,
    int DataCount,
    string? DataType,
    string? DataPosition);

/// <summary>GET /api/core/sync/data-tags?devCd= — ju_data_group(DEV_CD) + ju_data_tag + detail</summary>
public sealed record DataTagSync(
    string DevCd,
    string DatGrCd,
    string DatCd,
    int DatIdx,
    string? DatType,
    string? DatUnit,
    string? TagId,
    string? DatNm,
    decimal? DatMin,
    decimal? DatMax,
    int SortOrd);

/// <summary>
/// GET /api/core/sync/data-map?devCd= (C5c) — ju_data_channel_map. 값 환산: value × Scale + Offset.
/// PtlCd 가 null 이면 모든 프로토콜에 적용. 매핑이 없는 장치는 TAG_ID=CH&lt;n&gt; 임시 변환을 쓴다.
/// </summary>
public sealed record DataChannelMapSync(
    string DevCd,
    string ChannelKey,
    string? PtlCd,
    string DatGrCd,
    string DatCd,
    int DatIdx,
    double Scale = 1,
    double Offset = 0,
    int SortOrd = 0);

using JuProvider.Lib.Protocol.Mapping;
using JuProvider.Lib.Protocol.Model;
using JuProvider.Lib.Protocol.Rules;
using JuProvider.Lib.Protocol.Scheduling;
using JuProvider.Lib.Protocol.Session;
using JuProvider.Lib.Protocol.Transport;

namespace JuProvider.Lib.Protocol.Sync;

/// <summary>설정 출처 (C5d)</summary>
public static class PlanSource
{
    /// <summary>서버 내려받기 값 (ju_protocol_group·ju_protocol·ju_protocol_packet·ju_data_channel_map)</summary>
    public const string Server = "server";

    /// <summary>Desktop 내장 수집 설정 (BuiltInCollectionProfiles)</summary>
    public const string BuiltIn = "builtin";

    /// <summary>호출자가 넘긴 수집 설정</summary>
    public const string Profile = "profile";

    /// <summary>기본값 (설정 없음)</summary>
    public const string Default = "default";

    /// <summary>데이터 태그 TAG_ID=CH&lt;n&gt; 임시 변환</summary>
    public const string LegacyTagId = "legacy-tagid";
}

/// <summary>DeviceSession 생성에 필요한 것 전부 (서버 정의 + 수집 설정 결합 결과)</summary>
public sealed record CollectionPlan(
    string DevCd,
    string PtlGrpCd,
    FrameRule Frame,
    IReadOnlyList<ProtocolDefinition> Protocols,
    SchedulerOptions Scheduler,
    DeviceSessionOptions Session,
    IReadOnlyList<ChannelMapEntry> MapEntries,
    IReadOnlyList<string> Warnings)
{
    /// <summary>
    /// 항목별 설정 출처 (C5d). 키: frame, cmdGapMs, initDelayMs, initRoutine, map, {PTL_CD}.pattern|roles|action|expect|idempotent|tx|parse.
    /// 값: <see cref="PlanSource"/>.
    /// </summary>
    public IReadOnlyDictionary<string, string> Sources { get; init; } = new Dictionary<string, string>(StringComparer.Ordinal);

    public IDataMapper CreateMapper() => new DataMapper(MapEntries);

    public DeviceSession CreateSession(ITransport transport) =>
        new(DevCd, transport, Frame, Protocols, CreateMapper(), Scheduler, Session);
}

/// <summary>
/// 서버 내려받기(ProtocolGroupSync·DataTagSync·DataChannelMapSync) + 수집 설정 → CollectionPlan.
/// C5d 우선순위: <b>서버 설정 → 내장(또는 지정) 수집 설정 → 기본값</b>. 항목별 출처는 <see cref="CollectionPlan.Sources"/>,
/// 서버 값 누락·오류로 다음 단계로 넘어간 경우는 <see cref="CollectionPlan.Warnings"/> 에 남긴다. 서버 값 오류는 예외가 아니라 경고 + 대체값.
/// <list type="bullet">
/// <item>그룹: frameRule(JSON 이 맞으면) / cmdGapMs·initDelayMs(서버 그룹 수집 설정이 있을 때) / initRoutine(서버 목록이 있을 때)</item>
/// <item>서버 그룹 수집 설정 있음 = frameRule 또는 initRoutine 이 있거나 cmdGapMs &gt; 0 (DB 기본값 0·500 만 있으면 미설정)</item>
/// <item>프로토콜: 서버 roles 가 있으면 "서버 설정됨" → PTL_TYPE·roles 서버 값. 없으면(미설정·과거 데이터) 내장 보정 → PTL_TYPE</item>
/// <item>action·expect·idempotent: 서버 값 → 내장 보정 → 기본(None·없음·null)</item>
/// <item>송신: TX 패킷 PACKET_EXPR → PTL_VAL → 내장 tx. 해석: RX 패킷 PARSE_RULE(JSON) → 내장 parse</item>
/// <item>타임아웃: 내장 → 그룹 TIMEOUT_MS, 재시도: 그룹 RETRY_CNT (Idempotent 명령만 적용됨)</item>
/// <item>매핑: data-map 행이 있으면 그것 → 없으면 데이터 태그 TAG_ID=CH&lt;n&gt; 임시 변환</item>
/// </list>
/// </summary>
public static class CollectionPlanBuilder
{
    public static CollectionPlan Build(
        string devCd,
        ProtocolGroupSync group,
        IEnumerable<DataTagSync> tags,
        CollectionProfile? profile = null,
        IEnumerable<DataChannelMapSync>? dataMap = null)
    {
        ArgumentException.ThrowIfNullOrEmpty(devCd);
        ArgumentNullException.ThrowIfNull(group);
        ArgumentNullException.ThrowIfNull(tags);

        string fallback;
        if (profile is not null) fallback = PlanSource.Profile;
        else if (BuiltInCollectionProfiles.Get(group.PtlGrpCd) is { } builtIn)
        {
            profile = builtIn;
            fallback = PlanSource.BuiltIn;
        }
        else
        {
            profile = CollectionProfile.Empty(group.PtlGrpCd);
            fallback = PlanSource.Default;
        }
        if (profile.PtlGrpCd != group.PtlGrpCd)
            throw new ArgumentException($"수집 설정 그룹({profile.PtlGrpCd})과 서버 그룹({group.PtlGrpCd})이 다름", nameof(profile));

        var warnings = new List<string>();
        var sources = new Dictionary<string, string>(StringComparer.Ordinal);

        // ----- 그룹 수집 설정 -----
        bool serverGroup = !string.IsNullOrWhiteSpace(group.FrameRule) || (group.InitRoutine?.Count ?? 0) > 0 || (group.CmdGapMs ?? 0) > 0;
        if (!serverGroup && fallback != PlanSource.Default)
            warnings.Add($"그룹 {group.PtlGrpCd}: 서버 수집 설정 없음 → {fallback} 설정 사용");

        FrameRule frame = profile.Frame;
        sources["frame"] = fallback;
        if (!string.IsNullOrWhiteSpace(group.FrameRule))
        {
            try
            {
                frame = RuleReader.ReadFrameRule(group.FrameRule) ?? profile.Frame;
                sources["frame"] = PlanSource.Server;
            }
            catch (RuleFormatException ex)
            {
                warnings.Add($"그룹 {group.PtlGrpCd}: 서버 FRAME_RULE 오류 → {fallback} 사용 ({ex.Message})");
            }
        }

        int gap = profile.InterCommandGapMs;
        sources["cmdGapMs"] = fallback;
        if (serverGroup && group.CmdGapMs is int g)
        {
            if (g >= 0) { gap = g; sources["cmdGapMs"] = PlanSource.Server; }
            else warnings.Add($"그룹 {group.PtlGrpCd}: 서버 CMD_GAP_MS {g} 음수 → {fallback} 사용");
        }

        int delay = profile.InitDelayMs;
        sources["initDelayMs"] = fallback;
        if (serverGroup && group.InitDelayMs is int d)
        {
            if (d >= 0) { delay = d; sources["initDelayMs"] = PlanSource.Server; }
            else warnings.Add($"그룹 {group.PtlGrpCd}: 서버 INIT_DELAY_MS {d} 음수 → {fallback} 사용");
        }

        // ----- 프로토콜 -----
        var protocols = new List<ProtocolDefinition>();
        var known = new HashSet<string>(StringComparer.Ordinal);

        foreach (ProtocolSync p in group.Protocols ?? [])
        {
            known.Add(p.PtlCd);
            profile.Protocols.TryGetValue(p.PtlCd, out ProtocolOverlay? o);
            string ofb = o is null ? PlanSource.Default : fallback;

            ProtocolRole serverRoles = ReadRoles(p, warnings);
            bool serverProtocol = serverRoles != ProtocolRole.None;
            if (!serverProtocol && o is not null)
                warnings.Add($"{p.PtlCd}: 서버 역할 미설정 → {fallback} 설정 사용");

            // 교환 방식
            ExchangePattern pattern;
            string patternSource;
            if (serverProtocol && TryPattern(p.PtlType, out ExchangePattern sp))
            {
                pattern = sp;
                patternSource = PlanSource.Server;
            }
            else if (o?.Pattern is { } op)
            {
                if (serverProtocol) warnings.Add($"{p.PtlCd}: 서버 PTL_TYPE '{p.PtlType}' 해석 불가 → {fallback} 사용");
                pattern = op;
                patternSource = fallback;
            }
            else if (TryPattern(p.PtlType, out ExchangePattern tp))
            {
                pattern = tp;
                patternSource = PlanSource.Server;
            }
            else
            {
                warnings.Add($"{p.PtlCd}: PTL_TYPE '{p.PtlType}' 해석 불가 → 제외");
                continue;
            }

            // 송신
            string? serverTx = FirstNonEmpty(
                (p.Packets ?? []).Where(k => string.Equals(k.Direction, "TX", StringComparison.OrdinalIgnoreCase))
                    .OrderBy(k => k.PacketSeq).Select(k => k.PacketExpr).FirstOrDefault(x => !string.IsNullOrEmpty(x)),
                p.PtlVal);
            string? tx = null;
            if (pattern != ExchangePattern.RxStream)
            {
                tx = serverTx ?? o?.Tx;
                if (tx is null)
                {
                    warnings.Add($"{p.PtlCd}: 송신 표현식 없음 → 제외");
                    continue;
                }
                sources[p.PtlCd + ".tx"] = serverTx is not null ? PlanSource.Server : fallback;
            }

            // 해석 규칙
            ParseRule? parse = null;
            string? parseSource = null;
            string? ruleText = (p.Packets ?? []).Where(k => string.Equals(k.Direction, "RX", StringComparison.OrdinalIgnoreCase))
                .OrderBy(k => k.PacketSeq).Select(k => k.ParseRule).FirstOrDefault(x => !string.IsNullOrWhiteSpace(x));
            if (ruleText is not null)
            {
                if (ruleText.TrimStart().StartsWith('{'))
                {
                    try { parse = RuleReader.ReadParseRule(ruleText); parseSource = PlanSource.Server; }
                    catch (RuleFormatException ex) { warnings.Add($"{p.PtlCd}: PARSE_RULE 오류 → 무시 ({ex.Message})"); }
                }
                else warnings.Add($"{p.PtlCd}: PARSE_RULE 이 JSON 규칙이 아님 → 무시");
            }
            if (parse is null && o?.Parse is { } opr)
            {
                parse = opr;
                parseSource = fallback;
            }
            if (parseSource is not null) sources[p.PtlCd + ".parse"] = parseSource;

            if (pattern == ExchangePattern.RxStream && parse is null)
                warnings.Add($"{p.PtlCd}: RX_STREAM 인데 해석 규칙 없음 → 수신만");

            if (!serverProtocol && o is null && p.PtlType == "PROT0000")
                warnings.Add($"{p.PtlCd}: 서버 역할·수집 설정 없음, PTL_TYPE POLLING 그대로 사용");

            // 역할
            ProtocolRole roles;
            if (serverProtocol) { roles = serverRoles; sources[p.PtlCd + ".roles"] = PlanSource.Server; }
            else if (o?.Roles is { } orl) { roles = orl; sources[p.PtlCd + ".roles"] = fallback; }
            else
            {
                roles = pattern == ExchangePattern.RxStream ? ProtocolRole.Data : ProtocolRole.Info;
                sources[p.PtlCd + ".roles"] = PlanSource.Default;
            }

            // 실험 동작
            CommandAction action = CommandAction.None;
            sources[p.PtlCd + ".action"] = PlanSource.Default;
            if (TryAction(p, warnings, out CommandAction sa)) { action = sa; sources[p.PtlCd + ".action"] = PlanSource.Server; }
            else if (o?.Action is { } oa) { action = oa; sources[p.PtlCd + ".action"] = ofb; }

            // 응답 판정
            ResponseMatcher? expect = null;
            if (TryExpect(p, warnings, out ResponseMatcher? se)) { expect = se; sources[p.PtlCd + ".expect"] = PlanSource.Server; }
            else if (o?.Expect is { } oe) { expect = oe; sources[p.PtlCd + ".expect"] = ofb; }

            // 멱등 (명령별 명시값, 없으면 Scheduler 기본 규칙)
            bool? idempotent = null;
            if (p.Idempotent is bool si) { idempotent = si; sources[p.PtlCd + ".idempotent"] = PlanSource.Server; }
            else if (o?.Idempotent is bool oi) { idempotent = oi; sources[p.PtlCd + ".idempotent"] = ofb; }

            sources[p.PtlCd + ".pattern"] = patternSource;

            protocols.Add(new ProtocolDefinition
            {
                PtlCd = p.PtlCd,
                Pattern = pattern,
                Roles = roles,
                Action = action,
                Tx = tx,
                Expect = expect,
                Parse = parse,
                TimeoutMs = o?.TimeoutMs ?? group.TimeoutMs,
                RetryCount = Math.Max(0, group.RetryCnt),
                Idempotent = idempotent
            });
        }

        foreach (string extra in profile.Protocols.Keys.Where(k => !known.Contains(k)).OrderBy(k => k, StringComparer.Ordinal))
            warnings.Add($"{extra}: 수집 설정에만 있음(서버 정의 없음) → 무시");

        // ----- 초기화 루틴 -----
        IReadOnlyList<string> steps = profile.InitRoutine;
        sources["initRoutine"] = fallback;
        if ((group.InitRoutine?.Count ?? 0) > 0)
        {
            steps = group.InitRoutine!;
            sources["initRoutine"] = PlanSource.Server;
        }
        var defined = protocols.ToDictionary(x => x.PtlCd, StringComparer.Ordinal);
        var routine = new List<string>();
        foreach (string step in steps)
        {
            if (defined.TryGetValue(step, out ProtocolDefinition? def) && def.Pattern != ExchangePattern.RxStream) routine.Add(step);
            else warnings.Add($"초기화 루틴 {step}: 사용할 수 있는 프로토콜 없음 → 제외");
        }

        // ----- 채널 매핑 -----
        IReadOnlyList<ChannelMapEntry> map = BuildMap(devCd, tags, dataMap, warnings, out string mapSource);
        sources["map"] = mapSource;

        var scheduler = new SchedulerOptions(
            DefaultTimeoutMs: group.TimeoutMs > 0 ? group.TimeoutMs : 1000,
            InterCommandGapMs: gap);
        var session = new DeviceSessionOptions(routine, delay);

        return new CollectionPlan(devCd, group.PtlGrpCd, frame, protocols, scheduler, session, map, warnings)
        {
            Sources = sources
        };
    }

    // ----- 서버 값 해석 (오류는 경고 + 대체값) -----

    private static ProtocolRole ReadRoles(ProtocolSync p, List<string> warnings)
    {
        ProtocolRole acc = ProtocolRole.None;
        foreach (string r in p.Roles ?? [])
        {
            switch ((r ?? "").Trim().ToUpperInvariant())
            {
                case "INFO": acc |= ProtocolRole.Info; break;
                case "CONTROL": acc |= ProtocolRole.Control; break;
                case "DATA": acc |= ProtocolRole.Data; break;
                default: warnings.Add($"{p.PtlCd}: 서버 역할 '{r}' 알 수 없음 → 무시"); break;
            }
        }
        return acc;
    }

    private static bool TryPattern(string? ptlType, out ExchangePattern pattern)
    {
        try
        {
            pattern = ProtocolModel.FromPtlType(ptlType);
            return true;
        }
        catch (ArgumentException)
        {
            pattern = default;
            return false;
        }
    }

    private static bool TryAction(ProtocolSync p, List<string> warnings, out CommandAction action)
    {
        action = CommandAction.None;
        if (string.IsNullOrWhiteSpace(p.Action)) return false;
        switch (p.Action.Trim().ToUpperInvariant())
        {
            case "NONE": action = CommandAction.None; return true;
            case "START": action = CommandAction.Start; return true;
            case "PAUSE": action = CommandAction.Pause; return true;
            case "STOP": action = CommandAction.Stop; return true;
            default:
                warnings.Add($"{p.PtlCd}: 서버 동작 '{p.Action}' 알 수 없음 → 무시");
                return false;
        }
    }

    /// <summary>서버 EXPECT_RULE (<see cref="ExpectRule"/>). 오류면 경고 후 false</summary>
    private static bool TryExpect(ProtocolSync p, List<string> warnings, out ResponseMatcher? matcher)
    {
        matcher = null;
        if (string.IsNullOrWhiteSpace(p.Expect)) return false;
        if (ExpectRule.TryRead(p.Expect, out matcher, out string? error)) return true;
        warnings.Add($"{p.PtlCd}: 서버 EXPECT_RULE 오류 → 무시 ({error})");
        return false;
    }

    private static IReadOnlyList<ChannelMapEntry> BuildMap(
        string devCd,
        IEnumerable<DataTagSync> tags,
        IEnumerable<DataChannelMapSync>? dataMap,
        List<string> warnings,
        out string source)
    {
        List<DataTagSync> devTags = tags.Where(t => t.DevCd == devCd).ToList();
        List<DataChannelMapSync> rows = (dataMap ?? []).Where(m => m.DevCd == devCd).ToList();

        if (rows.Count > 0)
        {
            source = PlanSource.Server;
            var byKey = devTags.GroupBy(t => (t.DatGrCd, t.DatCd, t.DatIdx)).ToDictionary(x => x.Key, x => x.First());
            var entries = new List<ChannelMapEntry>();
            foreach (DataChannelMapSync m in rows.OrderBy(m => m.SortOrd).ThenBy(m => m.ChannelKey, StringComparer.Ordinal))
            {
                if (string.IsNullOrEmpty(m.ChannelKey) || string.IsNullOrEmpty(m.DatGrCd) || string.IsNullOrEmpty(m.DatCd))
                {
                    warnings.Add($"data-map 행 불완전 → 제외 ({m.ChannelKey}→{m.DatGrCd}/{m.DatCd}/{m.DatIdx})");
                    continue;
                }
                byKey.TryGetValue((m.DatGrCd, m.DatCd, m.DatIdx), out DataTagSync? tag);
                if (tag is null) warnings.Add($"data-map {m.ChannelKey}→{m.DatGrCd}/{m.DatCd}/{m.DatIdx}: 장치 데이터 태그에 없음 → 단위·범위 없이 사용");
                bool identity = m.Scale == 1 && m.Offset == 0;
                entries.Add(new ChannelMapEntry(
                    devCd,
                    m.ChannelKey,
                    new LogicalDataRef(m.DatGrCd, m.DatCd, m.DatIdx),
                    string.IsNullOrEmpty(m.PtlCd) ? null : m.PtlCd,
                    identity ? null : new ValueTransform(m.Scale, m.Offset),
                    NullIfEmpty(tag?.DatUnit),
                    (double?)tag?.DatMin,
                    (double?)tag?.DatMax));
            }
            return entries;
        }

        source = PlanSource.LegacyTagId;
        if (devTags.Count > 0) warnings.Add($"장치 {devCd}: 서버 채널 매핑(data-map) 없음 → TAG_ID=CH<n> 임시 변환");
        var tagWarnings = new List<string>();
        IReadOnlyList<ChannelMapEntry> legacy = LegacyTagIdMapping.ToEntries(
            devTags.Select(t => new LegacyDataTag(t.DevCd, t.DatGrCd, t.DatCd, t.DatIdx, t.TagId, NullIfEmpty(t.DatUnit),
                (double?)t.DatMin, (double?)t.DatMax)),
            tagWarnings);
        warnings.AddRange(tagWarnings);
        return legacy;
    }

    private static string? FirstNonEmpty(params string?[] values) => values.FirstOrDefault(v => !string.IsNullOrEmpty(v));

    private static string? NullIfEmpty(string? s) => string.IsNullOrEmpty(s) ? null : s;
}

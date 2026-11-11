using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using JuProvider.Lib.Protocol.Framing;
using JuProvider.Lib.Protocol.Mapping;
using JuProvider.Lib.Protocol.Model;
using JuProvider.Lib.Protocol.Parsing;
using JuProvider.Lib.Protocol.Rules;
using JuProvider.Lib.Protocol.Scheduling;
using JuProvider.Lib.Protocol.Session;
using JuProvider.Lib.Protocol.Sync;
using JuProvider.Lib.Protocol.Transport;

namespace JuProvider.Tests.Protocol;

/// <summary>
/// C5d: 서버 설정 우선 (서버 → 내장 → 기본), 출처·누락 경고, data-map 매핑, 서버 값 오류 시 안전한 대체.
/// 서버 JSON 은 C5c 서버 + migration 08 적용 DB 의 GET /api/core/sync/protocols/GTEC · data-map 응답 형태.
/// </summary>
public class ServerPlanTests
{
    private const string Dev = "SDEV_GTEC01";

    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    internal const string ServerProtocolsJson = """
    { "revision": "r2", "removed": [], "items": [ {
        "ptlGrpCd": "GTEC", "ptlGrpNm": "그린테크", "pollingIntval": 1000, "timeoutMs": 3000, "retryCnt": 3, "sortOrd": 0,
        "frameRule": "{\"v\":1,\"kind\":\"DELIM\",\"start\":\"{\",\"end\":\"[CR][LF]\",\"maxLen\":512}",
        "cmdGapMs": 200, "initRoutine": ["GTEC0301","GTEC0001","GTEC0002","GTEC0100"], "initDelayMs": 500,
        "protocols": [
          { "ptlCd": "GTEC0000", "ptlType": "PROT0003", "ptlVal": "S{TEST}[CR][LF]", "ptlNm": "장치확인(가상)",
            "roles": ["INFO"], "action": null, "expect": "{\"startsWith\":\"{OK\"}", "idempotent": null,
            "packets": [
              { "packetSeq": 1, "direction": "TX", "packetExpr": "S{TEST}[CR][LF]", "parseRule": "", "dataCount": 0 },
              { "packetSeq": 2, "direction": "RX", "packetExpr": "{OK}[CR][LF]", "parseRule": "패킷길이|STX DLE|ETX|ETX DLE", "dataCount": 0 } ] },
          { "ptlCd": "GTEC0001", "ptlType": "PROT0003", "ptlVal": "S{10,3}", "roles": ["INFO"], "action": null,
            "expect": "{\"regex\":\"^[{][A-Za-z]\"}", "idempotent": null,
            "packets": [ { "packetSeq": 1, "direction": "TX", "packetExpr": "S{10,3}", "parseRule": "", "dataCount": 0 } ] },
          { "ptlCd": "GTEC0002", "ptlType": "PROT0003", "ptlVal": "S{20}", "roles": ["INFO"],
            "expect": "{\"regex\":\"^[{][0-9]{3},[0-9]{3},[0-9]{3},[0-9]{3}[}]$\"}",
            "packets": [ { "packetSeq": 1, "packetType": "RX_PACKET", "direction": "RX",
              "parseRule": "{\"v\":1,\"kind\":\"INFO\",\"trim\":\"{}\",\"fields\":[\"CH1\",\"CH2\",\"CH3\",\"CH4\"],\"absent\":\"000\"}", "dataCount": 0 } ] },
          { "ptlCd": "GTEC0100", "ptlType": "PROT0001", "ptlVal": "S{11,1}", "roles": ["CONTROL"], "idempotent": true, "packets": [] },
          { "ptlCd": "GTEC0101", "ptlType": "PROT0000", "ptlVal": "S{11,2}", "roles": [], "action": null, "expect": null, "idempotent": null, "packets": [] },
          { "ptlCd": "GTEC0300", "ptlType": "PROT0001", "ptlVal": "S{10,1}", "roles": ["CONTROL"], "action": "START", "packets": [] },
          { "ptlCd": "GTEC0301", "ptlType": "PROT0001", "ptlVal": "S{10,0}", "roles": ["CONTROL"], "action": "STOP", "idempotent": true, "packets": [] },
          { "ptlCd": "GTEC0400", "ptlType": "PROT0002", "ptlVal": "", "roles": ["DATA"],
            "packets": [ { "packetSeq": 1, "packetType": "RX_PACKET", "direction": "RX",
              "parseRule": "{\"v\":1,\"kind\":\"TEXT\",\"trim\":\"{}\",\"sep\":\"SPACE\",\"count\":3}", "dataCount": 3 } ] },
          { "ptlCd": "GTEC0401", "ptlType": "PROT0000", "ptlVal": "", "roles": [], "packets": [] }
        ] } ] }
    """;

    internal const string DataMapJson = """
    { "revision": "m1", "removed": [], "items": [
      { "devCd": "SDEV_GTEC01", "channelKey": "1", "ptlCd": null, "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-01", "datIdx": 1, "scale": 1.0, "offset": 0.0, "sortOrd": 1 },
      { "devCd": "SDEV_GTEC01", "channelKey": "2", "ptlCd": null, "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-02", "datIdx": 2, "scale": 1.0, "offset": 0.0, "sortOrd": 2 },
      { "devCd": "SDEV_GTEC01", "channelKey": "3", "ptlCd": null, "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-03", "datIdx": 3, "scale": 1.0, "offset": 0.0, "sortOrd": 3 },
      { "devCd": "SDEV_GTEC01", "channelKey": "4", "ptlCd": null, "datGrCd": "DG_GTEC01", "datCd": "GTEC-DATA-04", "datIdx": 4, "scale": 1.0, "offset": 0.0, "sortOrd": 4 }
    ] }
    """;

    internal static ProtocolGroupSync ServerGroup() => JsonSerializer.Deserialize<SyncResult<ProtocolGroupSync>>(ServerProtocolsJson, Web)!.Items[0];

    internal static IReadOnlyList<DataChannelMapSync> DataMap() => JsonSerializer.Deserialize<SyncResult<DataChannelMapSync>>(DataMapJson, Web)!.Items;

    /// <summary>내장 설정 없이 서버 값만으로 만든 계획</summary>
    private static CollectionPlan ServerOnly(ProtocolGroupSync? g = null, IEnumerable<DataChannelMapSync>? map = null) =>
        CollectionPlanBuilder.Build(Dev, g ?? ServerGroup(), CollectionTests.Tags(), CollectionProfile.Empty("GTEC"), map ?? DataMap());

    private static Frame F(string body) => new(Encoding.ASCII.GetBytes(body), Encoding.ASCII.GetBytes(body));

    private static ProtocolGroupSync WithProtocol(ProtocolGroupSync g, string ptlCd, Func<ProtocolSync, ProtocolSync> change) =>
        g with { Protocols = g.Protocols.Select(p => p.PtlCd == ptlCd ? change(p) : p).ToList() };

    // ---------- 우선순위 · 출처 ----------

    [Fact]
    public void Server_Json_With_C5c_Fields_Deserializes()
    {
        ProtocolGroupSync g = ServerGroup();
        Assert.Equal(200, g.CmdGapMs);
        Assert.Equal(new[] { "GTEC0301", "GTEC0001", "GTEC0002", "GTEC0100" }, g.InitRoutine);
        Assert.Equal(new[] { "CONTROL" }, g.Protocols.Single(p => p.PtlCd == "GTEC0301").Roles);
        Assert.True(g.Protocols.Single(p => p.PtlCd == "GTEC0301").Idempotent);
        Assert.Empty(g.Protocols.Single(p => p.PtlCd == "GTEC0101").Roles!);
        Assert.Equal(4, DataMap().Count);
        // C5c 이전 서버 응답(필드 없음)도 그대로 읽힘
        Assert.Null(CollectionTests.Group().CmdGapMs);
        Assert.Null(CollectionTests.Group().Protocols[0].Roles);
    }

    [Fact] // 내장 설정 없이 서버 값만으로 C4(내장 설정) 계획과 같은 수집 동작
    public void Server_Only_Plan_Matches_BuiltIn_Plan()
    {
        CollectionPlan s = ServerOnly();
        CollectionPlan b = CollectionPlanBuilder.Build(Dev, CollectionTests.Group(), CollectionTests.Tags());
        var sp = s.Protocols.ToDictionary(p => p.PtlCd);
        var bp = b.Protocols.ToDictionary(p => p.PtlCd);

        foreach (string cd in new[] { "GTEC0000", "GTEC0001", "GTEC0002", "GTEC0100", "GTEC0300", "GTEC0301", "GTEC0400" })
        {
            Assert.Equal(bp[cd].Pattern, sp[cd].Pattern);
            Assert.Equal(bp[cd].Roles, sp[cd].Roles);
            Assert.Equal(bp[cd].Action, sp[cd].Action);
            Assert.Equal(bp[cd].Tx, sp[cd].Tx);
            Assert.Equal(bp[cd].Parse?.Kind, sp[cd].Parse?.Kind);
            Assert.Equal(bp[cd].Expect is null, sp[cd].Expect is null);
            Assert.Equal("server", s.Sources[cd + ".pattern"]);
            Assert.Equal("server", s.Sources[cd + ".roles"]);
        }
        Assert.Equal(b.Scheduler.InterCommandGapMs, s.Scheduler.InterCommandGapMs);
        Assert.Equal(b.Session.InitRoutine, s.Session.InitRoutine);
        Assert.Equal(b.Session.InitDelayMs, s.Session.InitDelayMs);
        Assert.Equal(b.Frame.Start, s.Frame.Start);
        Assert.Equal(b.Frame.End, s.Frame.End);
        Assert.Equal(b.Frame.MaxLength, s.Frame.MaxLength);
        Assert.Equal(b.MapEntries.Select(e => (e.ChannelKey, e.Target)), s.MapEntries.Select(e => (e.ChannelKey, e.Target)));

        // 응답 판정은 서버 표기([{]·[0-9])로도 실장비 응답과 같게 맞는다
        Assert.True(sp["GTEC0001"].Expect!.IsMatch(F("{Science Cube Lite II Memory}")));
        Assert.False(sp["GTEC0001"].Expect!.IsMatch(F("{008,000,000,000}")));
        Assert.True(sp["GTEC0002"].Expect!.IsMatch(F("{008,000,000,000}")));
        Assert.True(sp["GTEC0000"].Expect!.IsMatch(F("{OK}")));

        // 멱등은 서버 명시값 (STOP 자동 규칙 없음): 0301 은 서버만 명시
        Assert.True(sp["GTEC0100"].Idempotent);
        Assert.True(sp["GTEC0301"].Idempotent);
        Assert.Null(sp["GTEC0300"].Idempotent);
        Assert.Null(bp["GTEC0301"].Idempotent);

        foreach (string k in new[] { "frame", "cmdGapMs", "initDelayMs", "initRoutine", "map" })
            Assert.Equal("server", s.Sources[k]);
        Assert.DoesNotContain(s.Warnings, w => w.Contains("서버 수집 설정 없음"));
    }

    [Fact] // 서버와 내장 값이 다르면 서버 값
    public void Server_Value_Wins_Over_BuiltIn()
    {
        ProtocolGroupSync g = ServerGroup() with { CmdGapMs = 250, InitRoutine = ["GTEC0301", "GTEC0001"], InitDelayMs = 100 };
        g = WithProtocol(g, "GTEC0300", p => p with { Idempotent = false, Action = "PAUSE" });
        CollectionPlan plan = CollectionPlanBuilder.Build(Dev, g, CollectionTests.Tags(), null, DataMap());
        var by = plan.Protocols.ToDictionary(p => p.PtlCd);

        Assert.Equal(250, plan.Scheduler.InterCommandGapMs);
        Assert.Equal(new[] { "GTEC0301", "GTEC0001" }, plan.Session.InitRoutine);
        Assert.Equal(100, plan.Session.InitDelayMs);
        Assert.Equal(CommandAction.Pause, by["GTEC0300"].Action);
        Assert.False(by["GTEC0300"].Idempotent);
        Assert.Equal("server", plan.Sources["GTEC0300.idempotent"]);
    }

    [Fact] // C5c 이전 서버(필드 없음): 내장 설정, 출처·경고 기록
    public void Old_Server_Response_Uses_BuiltIn_With_Sources_And_Warnings()
    {
        CollectionPlan plan = CollectionPlanBuilder.Build(Dev, CollectionTests.Group(), CollectionTests.Tags());

        Assert.Equal(200, plan.Scheduler.InterCommandGapMs);
        Assert.Equal("builtin", plan.Sources["cmdGapMs"]);
        Assert.Equal("builtin", plan.Sources["frame"]);
        Assert.Equal("builtin", plan.Sources["initRoutine"]);
        Assert.Equal("builtin", plan.Sources["GTEC0301.roles"]);
        Assert.Equal("builtin", plan.Sources["GTEC0301.action"]);
        Assert.Equal("legacy-tagid", plan.Sources["map"]);
        Assert.Contains(plan.Warnings, w => w.Contains("서버 수집 설정 없음"));
        Assert.Contains(plan.Warnings, w => w.Contains("GTEC0301") && w.Contains("서버 역할 미설정"));
        Assert.Contains(plan.Warnings, w => w.Contains("data-map") && w.Contains("CH<n>"));
    }

    [Fact] // 서버도 내장도 없으면 기본값
    public void No_Server_No_BuiltIn_Uses_Defaults()
    {
        ProtocolGroupSync g = CollectionTests.Group() with { PtlGrpCd = "OTHER" };
        CollectionPlan plan = CollectionPlanBuilder.Build(Dev, g, CollectionTests.Tags());
        Assert.Equal("default", plan.Sources["frame"]);
        Assert.Equal("default", plan.Sources["cmdGapMs"]);
        Assert.Equal(0, plan.Scheduler.InterCommandGapMs);
        Assert.Equal("default", plan.Sources["GTEC0001.roles"]);
    }

    [Fact] // 역할 없는(미설정) 프로토콜은 서버 PTL_TYPE 이 아니라 내장 보정 → 없으면 PTL_TYPE
    public void Unconfigured_Protocol_Uses_BuiltIn_Then_PtlType()
    {
        ProtocolGroupSync g = WithProtocol(ServerGroup(), "GTEC0301", p => p with { Roles = [], PtlType = "PROT0000" });
        CollectionPlan plan = CollectionPlanBuilder.Build(Dev, g, CollectionTests.Tags(), null, DataMap());
        var by = plan.Protocols.ToDictionary(p => p.PtlCd);
        Assert.Equal(ExchangePattern.TxOnly, by["GTEC0301"].Pattern);
        Assert.Equal("builtin", plan.Sources["GTEC0301.pattern"]);
        Assert.Equal(ExchangePattern.Poll, by["GTEC0101"].Pattern);
        Assert.Equal("server", plan.Sources["GTEC0101.pattern"]);
        Assert.Contains(plan.Warnings, w => w.Contains("GTEC0101") && w.Contains("POLLING"));
    }

    // ---------- 서버 값 누락·오류 → 안전한 대체 (예외 없음) ----------

    [Fact]
    public void Invalid_Server_Values_Fall_Back_Safely()
    {
        ProtocolGroupSync g = ServerGroup() with { FrameRule = "{\"v\":1,\"kind\":\"SLIP\"}", CmdGapMs = -5, InitRoutine = ["GTEC0301", "NOPE", "GTEC0400"] };
        g = WithProtocol(g, "GTEC0001", p => p with { Expect = "{\"regex\":\"[\"}" });
        g = WithProtocol(g, "GTEC0002", p => p with { Expect = "not json" });
        g = WithProtocol(g, "GTEC0300", p => p with { Action = "LAUNCH", Roles = ["CONTROL", "BOSS"] });
        g = WithProtocol(g, "GTEC0100", p => p with { Roles = ["BOSS"] });

        CollectionPlan plan = CollectionPlanBuilder.Build(Dev, g, CollectionTests.Tags(), null, DataMap());
        var by = plan.Protocols.ToDictionary(p => p.PtlCd);

        Assert.Equal(new byte[] { (byte)'{' }, plan.Frame.Start);          // 내장 Frame
        Assert.Equal("builtin", plan.Sources["frame"]);
        Assert.Equal(200, plan.Scheduler.InterCommandGapMs);                 // 음수 → 내장 200
        Assert.Equal(new[] { "GTEC0301" }, plan.Session.InitRoutine);         // 없는 코드·RX_STREAM 제외
        Assert.Equal("builtin", plan.Sources["GTEC0001.expect"]);           // regex 오류 → 내장 expect
        Assert.True(by["GTEC0001"].Expect!.IsMatch(F("{Science}")));
        Assert.Equal("builtin", plan.Sources["GTEC0002.expect"]);
        Assert.Equal(CommandAction.Start, by["GTEC0300"].Action);           // 알 수 없는 동작 → 내장 START
        Assert.Equal(ProtocolRole.Control, by["GTEC0300"].Roles);           // 알 수 없는 역할만 무시
        Assert.Equal("builtin", plan.Sources["GTEC0100.roles"]);            // 유효 역할 0개 → 미설정 취급
        foreach (string key in new[] { "FRAME_RULE", "CMD_GAP_MS", "NOPE", "GTEC0400", "EXPECT_RULE", "LAUNCH", "BOSS" })
            Assert.Contains(plan.Warnings, w => w.Contains(key));
    }

    [Fact] // 서버 PARSE_RULE 오류면 내장 parse, 내장도 없으면 수신만 경고
    public void Invalid_Server_Parse_Rule_Falls_Back()
    {
        ProtocolGroupSync g = WithProtocol(ServerGroup(), "GTEC0400", p => p with
        {
            Packets = [p.Packets[0] with { ParseRule = "{\"v\":1,\"kind\":\"CSV\"}" }]
        });
        CollectionPlan plan = CollectionPlanBuilder.Build(Dev, g, CollectionTests.Tags(), null, DataMap());
        Assert.Equal(ParseKind.Text, plan.Protocols.Single(p => p.PtlCd == "GTEC0400").Parse!.Kind);
        Assert.Equal("builtin", plan.Sources["GTEC0400.parse"]);

        CollectionPlan bare = ServerOnly(g);
        Assert.Null(bare.Protocols.Single(p => p.PtlCd == "GTEC0400").Parse);
        Assert.Contains(bare.Warnings, w => w.Contains("GTEC0400") && w.Contains("수신만"));
    }

    // ---------- data-map ----------

    [Fact]
    public void Data_Map_Applies_Transform_PtlCd_And_Tag_Range()
    {
        var rows = new List<DataChannelMapSync>(DataMap())
        {
            new("SDEV_GTEC01", "1", "GTEC0400", "DG_GTEC01", "GTEC-DATA-04", 4, 10, -1, 5),
            new("SDEV_GTEC01", "9", null, "DG_X", "NOPE", 1),
            new("VDEV_GTEC01", "1", null, "DG_GTECV01", "VGTEC-DATA-01", 1)
        };
        CollectionPlan plan = ServerOnly(map: rows);

        Assert.Equal(6, plan.MapEntries.Count); // 다른 장치 제외
        ChannelMapEntry scaled = plan.MapEntries.Single(e => e.PtlCd == "GTEC0400");
        Assert.Equal(new ValueTransform(10, -1), scaled.Transform);
        Assert.Equal(1.0, scaled.Max);           // 태그 범위
        Assert.Null(plan.MapEntries.First(e => e.ChannelKey == "1" && e.PtlCd is null).Transform);
        Assert.Contains(plan.Warnings, w => w.Contains("NOPE") && w.Contains("태그에 없음"));

        IDataMapper mapper = plan.CreateMapper();
        var values = mapper.Map(Dev, "GTEC0400", [new RawValue("1", 0, 2.0, "2.0", false)], DateTimeOffset.Now);
        Assert.Contains(values, v => v.Data == new LogicalDataRef("DG_GTEC01", "GTEC-DATA-04", 4) && v.Value == 19.0);
        Assert.Contains(values, v => v.Data == new LogicalDataRef("DG_GTEC01", "GTEC-DATA-01", 1) && v.Value == 2.0);
    }

    [Fact] // data-map 이 비면 CH<n> 임시 호환 그대로
    public void Empty_Data_Map_Keeps_Legacy_TagId()
    {
        CollectionPlan plan = ServerOnly(map: []);
        Assert.Equal("legacy-tagid", plan.Sources["map"]);
        Assert.Equal(4, plan.MapEntries.Count);
        Assert.Equal(new LogicalDataRef("DG_GTEC01", "GTEC-DATA-01", 1), plan.MapEntries.Single(e => e.ChannelKey == "1").Target);
    }

    // ---------- 응답 판정 (Java·.NET 공통 벡터) ----------

    [Fact]
    public void Expect_Rule_Reader()
    {
        Assert.True(ExpectRule.TryRead("{\"startsWith\":\"{OK\"}", out ResponseMatcher? m, out _));
        Assert.True(m!.IsMatch(F("{OK}")));
        foreach (string bad in new[] { "", "x", "[]", "{}", "{\"startsWith\":\"\"}", "{\"contains\":\"a\"}", "{\"startsWith\":\"a\",\"regex\":\"b\"}", "{\"regex\":\"[\"}" })
            Assert.False(ExpectRule.TryRead(bad, out _, out _), bad);
    }

    // ---------- 가상 장치 자동 회귀 (서버 값만) ----------

    private static async Task<(DeviceSession S, VirtualTransport T, ConcurrentQueue<LogicalValue> V, ConcurrentQueue<InitRoutineResult> I)> StartAsync(
        CollectionPlan plan, GtecLikeDevice device)
    {
        var t = new VirtualTransport(device);
        await t.OpenAsync();
        DeviceSession s = plan.CreateSession(t);
        var values = new ConcurrentQueue<LogicalValue>();
        var inits = new ConcurrentQueue<InitRoutineResult>();
        s.Values += (_, e) => { foreach (LogicalValue v in e.Values) values.Enqueue(v); };
        s.InitCompleted += (_, r) => inits.Enqueue(r);
        await s.StartAsync();
        return (s, t, values, inits);
    }

    [Fact] // 측정 중 장비 → 초기화(STOP 먼저) → START → 수집·매핑 → STOP → 분리 → 재연결(루틴 재실행) → 수집 → STOP
    public async Task Virtual_Gtec_Full_Cycle_With_Server_Values_Only()
    {
        CollectionPlan plan = ServerOnly() with { Session = new DeviceSessionOptions(ServerOnly().Session.InitRoutine, 50) };
        var device = new GtecLikeDevice { Running = true };
        var (s, t, values, inits) = await StartAsync(plan, device);
        await using var _s = s;
        await using var _t = t;

        Assert.True(await Wait.UntilAsync(() => inits.Count == 1, 5000));
        Assert.True(inits.Single().AllOk, string.Join(",", inits.Single().Steps.Select(x => $"{x.Key}:{x.Value.Status}")));
        Assert.Equal(new[] { "S{10,0}", "S{10,3}", "S{20}", "S{11,1}" }, device.Accepted.ToArray());
        Assert.Equal(DeviceSessionState.Ready, s.State);

        Assert.True((await s.ExecuteAsync("GTEC0300")).Ok);
        Assert.True(await Wait.UntilAsync(() => values.Count >= 9, 3000), $"values {values.Count}");
        Assert.All(values, v => Assert.Equal(DataQuality.Good, v.Quality));
        Assert.Equal(
            new[] { "DG_GTEC01/GTEC-DATA-01/1", "DG_GTEC01/GTEC-DATA-02/2", "DG_GTEC01/GTEC-DATA-03/3" },
            values.Select(v => v.Data!.Key).Distinct().OrderBy(x => x, StringComparer.Ordinal));

        Assert.True((await s.ExecuteAsync("GTEC0301")).Ok);
        await Task.Delay(300);
        int n = values.Count;
        await Task.Delay(300);
        Assert.Equal(n, values.Count);
        Assert.False(device.Running);

        // 측정 중 분리 → 재연결
        Assert.True((await s.ExecuteAsync("GTEC0300")).Ok);
        Assert.True(await Wait.UntilAsync(() => values.Count > n, 3000));
        t.ForceDisconnect();
        Assert.True(await Wait.UntilAsync(() => s.State == DeviceSessionState.Suspended, 2000));
        Assert.True(device.Running);
        await t.OpenAsync();
        Assert.True(await Wait.UntilAsync(() => inits.Count == 2, 5000));
        Assert.True(inits.Last().AllOk);
        Assert.False(device.Running);

        while (values.TryDequeue(out _)) { }
        Assert.True((await s.ExecuteAsync("GTEC0300")).Ok);
        Assert.True(await Wait.UntilAsync(() => values.Count >= 6, 3000), "재연결 후 데이터");
        Assert.True((await s.ExecuteAsync("GTEC0301")).Ok);
    }
}

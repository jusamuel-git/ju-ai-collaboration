// C4 실서버 검증 6: 실제 응답 JSON → Desktop(JuProviderApiClient) 역직렬화 → CollectionPlan. 제품 저장소 밖 임시 도구.
// Client 자격은 환경 변수로만 받는다(출력하지 않음).
using JuProvider.Lib.Data.Api;
using JuProvider.Lib.Protocol.Model;
using JuProvider.Lib.Protocol.Sync;

string baseUrl = args[0];
string devCd = args.Length > 1 ? args[1] : "SDEV_GTEC01";
int fail = 0;
void Check(bool ok, string what) { Console.WriteLine((ok ? "[PASS] " : "[FAIL] ") + what); if (!ok) fail++; }

try
{
    using var api = new JuProviderApiClient(baseUrl,
        Environment.GetEnvironmentVariable("C4_CLIENT_ID"), Environment.GetEnvironmentVariable("C4_CLIENT_KEY"));

    var all = await api.GetProtocolGroupsAsync();
    Check(all is not null && all.Items.Count > 0 && all.Revision.Length == 64 && all.Removed.Count == 0,
        $"전체 그룹 역직렬화 (그룹 {all?.Items.Count}, 프로토콜 {all?.Items.Sum(x => x.Protocols.Count)}, 패킷 {all?.Items.Sum(x => x.Protocols.Sum(p => p.Packets.Count))})");

    var one = await api.GetProtocolGroupsAsync("GTEC");
    ProtocolGroupSync g = one!.Items.Single();
    Check(g.PtlGrpCd == "GTEC" && g.TimeoutMs > 0, $"GTEC 그룹 (timeout {g.TimeoutMs}, retry {g.RetryCnt}, 프로토콜 {g.Protocols.Count})");
    Check(await api.GetProtocolGroupsAsync("C4T_NONE") is null, "없는 그룹 → null (404 처리)");

    var tags = await api.GetDataTagsAsync(devCd);
    Check(tags.Items.Count > 0 && tags.Items.All(t => t.DevCd == devCd), $"{devCd} 데이터 태그 역직렬화 ({tags.Items.Count}개: {string.Join(",", tags.Items.Select(t => t.TagId))})");

    CollectionPlan plan = CollectionPlanBuilder.Build(devCd, g, tags.Items);
    var byCd = plan.Protocols.ToDictionary(p => p.PtlCd);
    Console.WriteLine($"       계획: 프로토콜 {plan.Protocols.Count}, 간격 {plan.Scheduler.InterCommandGapMs} ms, 루틴 {string.Join("→", plan.Session.InitRoutine ?? [])}, 매핑 {plan.MapEntries.Count}");
    foreach (string w in plan.Warnings) Console.WriteLine("       계획 경고: " + w);
    Check(byCd.TryGetValue("GTEC0001", out var check) && check.Tx == "S{10,3}" && check.Pattern == ExchangePattern.TxRx, "GTEC0001 장치확인 S{10,3} TX_RX");
    Check(byCd.TryGetValue("GTEC0400", out var data) && data.Pattern == ExchangePattern.RxStream && data.Parse is not null, "GTEC0400 RX_STREAM + 해석 규칙");
    Check(plan.Session.InitRoutine is { Count: 4 } r && r[0] == "GTEC0301", "초기화 루틴 4단계 (STOP 먼저)");
    Check(plan.Scheduler.InterCommandGapMs == 200 && plan.Scheduler.DefaultTimeoutMs == g.TimeoutMs, "명령 간격 200 ms, 기본 타임아웃 = 그룹 TIMEOUT_MS");
    Check(plan.Frame.Start is [(byte)'{'], "Frame 시작 문자 '{'");
    int chTags = tags.Items.Count(t => t.TagId is { } id && System.Text.RegularExpressions.Regex.IsMatch(id, "^CH[0-9]{1,4}$"));
    var ch1 = plan.MapEntries.FirstOrDefault(e => e.ChannelKey == "1");
    Check(plan.MapEntries.Count == chTags && ch1 is not null, $"매핑 {plan.MapEntries.Count} = CH 태그 {chTags}, CH1 → {ch1?.Target.Key}");
}
catch (Exception ex)
{
    Console.WriteLine($"[FAIL] 예외 {ex.GetType().Name}: {ex.Message}");
    fail++;
}
Console.WriteLine(fail == 0 ? "PLAN-PASS" : $"PLAN-FAIL ({fail})");
return fail == 0 ? 0 : 1;

// JU-1B Desktop smoke: JuProviderApiClient가 Client 자격 헤더로 /api/core/sync/devices를 호출하는지 확인
// args: baseUrl clientId   (키는 환경변수 JU_SMOKE_CLIENT_KEY, 출력하지 않음)
using JuProvider.Lib.Data.Api;

string baseUrl = args[0];
string clientId = args[1];
string? key = Environment.GetEnvironmentVariable("JU_SMOKE_CLIENT_KEY");
int fail = 0;

using (var ok = new JuProviderApiClient(baseUrl, clientId, key))
{
    try { var list = await ok.GetDevicesAsync(); Console.WriteLine($"with credential: OK devices={list.Count}"); }
    catch (Exception ex) { Console.WriteLine($"with credential: FAIL {ex.GetType().Name} {ex.Message}"); fail++; }
}
using (var none = new JuProviderApiClient(baseUrl))
{
    try { await none.GetDevicesAsync(); Console.WriteLine("without credential: FAIL (allowed)"); fail++; }
    catch (HttpRequestException ex) { Console.WriteLine($"without credential: rejected {(int?)ex.StatusCode}"); if (ex.StatusCode != System.Net.HttpStatusCode.Unauthorized) fail++; }
}
Console.WriteLine(fail == 0 ? "DESKTOP SMOKE PASS" : "DESKTOP SMOKE FAIL");
return fail == 0 ? 0 : 1;

// JU-0B smoke: DB(ju_device) 장치 목록으로 DeviceRuntimeManager를 동기화하고
// 가상장치(DEVI0000)가 연결·데이터 생성되는지, 다른 유형은 미구현 처리되는지 확인한다.
using JuProvider.Lib.Device.Models;
using JuProvider.Terminal.Runtime;

string path = args[0];
var devices = new List<DeviceSyncModel>();
foreach (var line in File.ReadAllLines(path))
{
    var c = line.Split('\t');
    if (c.Length < 8) continue;
    devices.Add(new DeviceSyncModel { DevCd = c[0], DevType = c[1], DevForm = c[2], DevComm = c[3], PtlGrpCd = c[4], DevCh = int.Parse(c[5]), DevDatCnt = int.Parse(c[6]), UseYn = c[7] });
}
var mgr = new DeviceRuntimeManager();
var received = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
mgr.DataReceived += (dev, _) => { lock (received) { received[dev] = received.GetValueOrDefault(dev) + 1; } };
mgr.SyncDevices(devices);
Console.WriteLine($"synced={mgr.Count}");
int virtualOk = 0, fail = 0;
foreach (var d in devices)
{
    string r;
    try
    {
        bool ok = await mgr.ConnectAsync(d.DevCd);
        r = ok ? "CONNECTED" : "CONNECT=false";
    }
    catch (NotSupportedException) { r = "NOT_IMPLEMENTED"; }
    catch (Exception ex) { r = "ERROR " + ex.GetType().Name + ": " + ex.Message; }
    Console.WriteLine($"{d.DevCd}\t{d.DevType}\t{r}");
    bool isVirtual = d.DevType == "DEVI0000";
    if (isVirtual && r == "CONNECTED") virtualOk++;
    else if (isVirtual || r != "NOT_IMPLEMENTED") fail++;
}
await Task.Delay(3000);
foreach (var d in devices.Where(x => x.DevType == "DEVI0000"))
{
    int n; lock (received) { n = received.GetValueOrDefault(d.DevCd); }
    Console.WriteLine($"{d.DevCd}\tdata events in 3s={n}");
    if (n == 0) fail++;
    await mgr.DisconnectAsync(d.DevCd);
}
string result = (virtualOk > 0 && fail == 0) ? "PASS" : "FAIL";
Console.WriteLine($"SMOKE {result} (virtual connected={virtualOk}, fail={fail})");
return result == "PASS" ? 0 : 1;

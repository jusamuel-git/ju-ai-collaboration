using System.IO.Ports;
using System.Text.Json;
using JuProvider.Lib.Protocol.Simulation;

namespace JuProvider.Lib.Protocol.Transport;

public sealed class TransportConfigException(string message) : FormatException(message);

/// <summary>
/// PC별 로컬 연결값(C0·SYSINFO-01: ClientId+DevCd 로컬 override) → ITransport.
///  {"transport":"SERIAL","portName":"COM6","baudRate":115200, ...}
///  {"transport":"TCP","host":"192.168.0.10","port":5000,"connectTimeoutMs":3000}
///  {"transport":"VIRTUAL","profile":"GTEC_SCIENCE_CUBE","faults":{"dropRate":0,...}}
/// 키 이름은 과거 장치 설정과 같다(serialPort, ip도 허용). 비밀 값은 다루지 않는다.
/// </summary>
public static class TransportFactory
{
    public static ITransport FromLocalConfig(string json)
    {
        JsonElement r;
        try
        {
            using JsonDocument doc = JsonDocument.Parse(json);
            r = doc.RootElement.Clone();
        }
        catch (JsonException ex)
        {
            throw new TransportConfigException("연결 설정 JSON 형식 오류: " + ex.Message);
        }
        if (r.ValueKind != JsonValueKind.Object) throw new TransportConfigException("연결 설정은 JSON 객체입니다.");

        string kind = (Str(r, "transport") ?? throw new TransportConfigException("transport가 필요합니다.")).ToUpperInvariant();
        return kind switch
        {
            "SERIAL" => new SerialTransport(ReadSerial(r)),
            "TCP" => new TcpClientTransport(
                Str(r, "host") ?? Str(r, "ip") ?? throw new TransportConfigException("TCP host가 필요합니다."),
                Int(r, "port") is int p and > 0 and <= 65535 ? p : throw new TransportConfigException("TCP port(1~65535)가 필요합니다."),
                Int(r, "connectTimeoutMs") ?? 3000),
            "VIRTUAL" => new VirtualTransport(
                new ProfileSimulator(ReadProfile(Str(r, "profile") ?? "GTEC_SCIENCE_CUBE")),
                ReadFaults(r)),
            _ => throw new TransportConfigException($"알 수 없는 transport: {kind}")
        };
    }

    public static SerialSettings ReadSerial(JsonElement r)
    {
        string port = Str(r, "portName") ?? Str(r, "serialPort") ?? throw new TransportConfigException("Serial portName이 필요합니다.");
        return new SerialSettings(
            port,
            Int(r, "baudRate") ?? 9600,
            Int(r, "dataBits") ?? 8,
            Enum<Parity>(r, "parity", Parity.None),
            Enum<StopBits>(r, "stopBits", StopBits.One),
            Enum<Handshake>(r, "handshake", Handshake.None),
            Bool(r, "dtrEnable") ?? true,
            Bool(r, "rtsEnable") ?? true,
            Int(r, "writeTimeoutMs") ?? Int(r, "timeoutMs") ?? 3000);
    }

    private static DeviceProfile ReadProfile(string id)
    {
        try { return BuiltInProfiles.Get(id); }
        catch (ProfileFormatException ex) { throw new TransportConfigException(ex.Message); }
    }

    private static FaultOptions ReadFaults(JsonElement r)
    {
        if (!r.TryGetProperty("faults", out JsonElement f) || f.ValueKind != JsonValueKind.Object) return FaultOptions.None;
        return new FaultOptions(
            Dbl(f, "dropRate") ?? 0, Dbl(f, "garbageRate") ?? 0, Int(f, "delayMs") ?? 0, Int(f, "fragmentSize") ?? 0,
            Int(f, "disconnectAfterMs") ?? 0, Int(f, "failOpenCount") ?? 0, Int(f, "seed") ?? 1);
    }

    private static string? Str(JsonElement e, string n) =>
        e.TryGetProperty(n, out JsonElement v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int? Int(JsonElement e, string n)
    {
        if (!e.TryGetProperty(n, out JsonElement v) || v.ValueKind == JsonValueKind.Null) return null;
        if (v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out int i)) return i;
        if (v.ValueKind == JsonValueKind.String && int.TryParse(v.GetString(), out i)) return i;
        throw new TransportConfigException($"{n}: 정수여야 합니다.");
    }

    private static double? Dbl(JsonElement e, string n)
    {
        if (!e.TryGetProperty(n, out JsonElement v) || v.ValueKind == JsonValueKind.Null) return null;
        if (v.ValueKind == JsonValueKind.Number) return v.GetDouble();
        throw new TransportConfigException($"{n}: 숫자여야 합니다.");
    }

    private static bool? Bool(JsonElement e, string n)
    {
        if (!e.TryGetProperty(n, out JsonElement v) || v.ValueKind == JsonValueKind.Null) return null;
        return v.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new TransportConfigException($"{n}: true/false여야 합니다.")
        };
    }

    private static T Enum<T>(JsonElement e, string n, T fallback) where T : struct, System.Enum
    {
        string? s = Str(e, n);
        if (s is null) return fallback;
        return System.Enum.TryParse(s, ignoreCase: true, out T value) && System.Enum.IsDefined(value)
            ? value
            : throw new TransportConfigException($"{n}: 알 수 없는 값 {s}");
    }
}

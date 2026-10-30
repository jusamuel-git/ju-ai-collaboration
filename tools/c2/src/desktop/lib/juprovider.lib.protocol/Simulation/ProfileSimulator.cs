using System.Diagnostics;
using System.Globalization;
using System.Text.RegularExpressions;
using JuProvider.Lib.Protocol.Expression;

namespace JuProvider.Lib.Protocol.Simulation;

/// <summary>범용 시뮬레이터 엔진: DeviceProfile에 따라 요청에 응답하고, 조건이 맞는 동안 연속 송신한다.</summary>
public sealed partial class ProfileSimulator(DeviceProfile profile) : ISimulatedDevice
{
    private readonly object _lock = new();
    private readonly Dictionary<string, string> _vars = new(StringComparer.Ordinal);
    private readonly Dictionary<string, double> _ramp = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _sequence = new(StringComparer.Ordinal);
    private Random _random = new(profile.Seed);
    private readonly Stopwatch _clock = new();
    private ISimulatorSink? _sink;
    private Task? _streamTask;

    public DeviceProfile Profile { get; } = profile;
    public string ProfileId => Profile.ProfileId;

    /// <summary>처리하지 못한 요청 수 (매칭 없음·템플릿 오류)</summary>
    public int UnmatchedRequests { get; private set; }

    /// <summary>현재 변수 값 (시험용)</summary>
    public string? GetVar(string name)
    {
        lock (_lock) return _vars.TryGetValue(name, out string? v) ? v : null;
    }

    public void Open(ISimulatorSink sink, CancellationToken lifetime)
    {
        lock (_lock)
        {
            // 연결마다 장치 상태 초기화 (전원 재투입과 같음)
            _vars.Clear();
            foreach (var p in Profile.Vars) _vars[p.Key] = p.Value;
            _ramp.Clear();
            _sequence.Clear();
            _random = new Random(Profile.Seed);
            _sink = sink;
            _clock.Restart();
        }
        if (Profile.Streams.Count > 0)
        {
            _streamTask = Task.Run(() => StreamLoopAsync(lifetime));
        }
    }

    public void Close()
    {
        lock (_lock) _sink = null;
    }

    public void OnRequest(byte[] request)
    {
        byte[]? reply = null;
        ISimulatorSink? sink;
        lock (_lock)
        {
            sink = _sink;
            string display = Normalize(request);
            bool handled = false;

            foreach (ProfileResponse r in Profile.Responses)
            {
                Dictionary<string, string>? groups = Match(r, display);
                if (groups is null) continue;

                try
                {
                    foreach (var s in r.Set) _vars[s.Key] = Render(s.Value, groups);
                    if (r.Reply is not null) reply = ProtocolExpression.ToBytes(Render(r.Reply, groups));
                    handled = true;
                }
                catch (Exception ex) when (ex is FormatException or InvalidOperationException)
                {
                    handled = false;
                }
                break;
            }
            if (!handled) UnmatchedRequests++;
        }
        if (reply is not null) sink?.Send(reply);
    }

    // ----- 내부 -----

    private static string Normalize(byte[] bytes)
    {
        int end = bytes.Length;
        while (end > 0 && (bytes[end - 1] == 0x0D || bytes[end - 1] == 0x0A)) end--;
        return ProtocolExpression.ToDisplay(bytes.AsSpan(0, end));
    }

    private static Dictionary<string, string>? Match(ProfileResponse r, string display)
    {
        if (r.Match is not null)
        {
            return Normalize(ProtocolExpression.ToBytes(r.Match)) == display ? new Dictionary<string, string>() : null;
        }
        System.Text.RegularExpressions.Match m = r.MatchRegex!.Match(display);
        if (!m.Success) return null;
        var groups = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (Group g in m.Groups)
        {
            if (!int.TryParse(g.Name, out _)) groups[g.Name] = g.Value;
        }
        return groups;
    }

    [GeneratedRegex(@"\$\{(?<name>[A-Za-z_][A-Za-z0-9_]*)(?:(?<op>[*/])(?<num>[0-9]+(?:\.[0-9]+)?))?\}")]
    private static partial Regex TokenRegex();

    /// <summary>${이름}, ${이름*수}, ${이름/수}. 우선순위: 정규식 그룹 → 생성기 → 변수. 없으면 InvalidOperationException</summary>
    private string Render(string template, IReadOnlyDictionary<string, string> groups) =>
        TokenRegex().Replace(template, m =>
        {
            string name = m.Groups["name"].Value;
            string value = groups.TryGetValue(name, out string? g) ? g
                : Profile.Generators.TryGetValue(name, out GeneratorSpec? gen) ? Format(Next(name, gen))
                : _vars.TryGetValue(name, out string? v) ? v
                : throw new InvalidOperationException($"템플릿 값 없음: {name}");

            if (!m.Groups["op"].Success) return value;
            if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double x))
            {
                throw new InvalidOperationException($"숫자가 아님: {name}={value}");
            }
            double k = double.Parse(m.Groups["num"].Value, CultureInfo.InvariantCulture);
            return Format(m.Groups["op"].Value == "*" ? x * k : x / k);
        });

    private static string Format(double v) => Math.Round(v, 4).ToString("0.####", CultureInfo.InvariantCulture);

    private double Next(string name, GeneratorSpec g)
    {
        switch (g.Type)
        {
            case "constant":
                return g.Value;
            case "ramp":
            {
                double cur = _ramp.TryGetValue(name, out double c) ? c : g.Value;
                double next = cur + g.Step;
                _ramp[name] = next > g.Max ? g.Value : next;
                return cur;
            }
            case "sine":
                return g.Offset + g.Amp * Math.Sin(2 * Math.PI * _clock.Elapsed.TotalMilliseconds / Math.Max(1, g.PeriodMs));
            case "random":
                return g.Min + _random.NextDouble() * (g.Max - g.Min);
            case "sequence":
            {
                int i = _sequence.TryGetValue(name, out int idx) ? idx : 0;
                _sequence[name] = i + 1;
                return g.Values[i % g.Values.Count];
            }
            default:
                throw new InvalidOperationException("알 수 없는 생성기: " + g.Type);
        }
    }

    private bool When(string condition)
    {
        if (string.IsNullOrWhiteSpace(condition)) return true;
        foreach (string part in condition.Split("&&", StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            bool ok;
            int ne = part.IndexOf("!=", StringComparison.Ordinal);
            int eq = part.IndexOf("==", StringComparison.Ordinal);
            if (ne > 0)
            {
                ok = !string.Equals(Var(part[..ne].Trim()), part[(ne + 2)..].Trim(), StringComparison.Ordinal);
            }
            else if (eq > 0)
            {
                ok = string.Equals(Var(part[..eq].Trim()), part[(eq + 2)..].Trim(), StringComparison.Ordinal);
            }
            else
            {
                string v = Var(part);
                ok = v.Length > 0 && v != "false" && v != "0";
            }
            if (!ok) return false;
        }
        return true;
    }

    private string Var(string name) => _vars.TryGetValue(name, out string? v) ? v : "";

    private async Task StreamLoopAsync(CancellationToken lifetime)
    {
        var last = new double[Profile.Streams.Count];
        Array.Fill(last, double.NegativeInfinity);
        try
        {
            while (!lifetime.IsCancellationRequested)
            {
                for (int i = 0; i < Profile.Streams.Count; i++)
                {
                    byte[]? frame = null;
                    ISimulatorSink? sink;
                    lock (_lock)
                    {
                        sink = _sink;
                        ProfileStream s = Profile.Streams[i];
                        if (sink is null || !When(s.When))
                        {
                            last[i] = double.NegativeInfinity;
                            continue;
                        }
                        double now = _clock.Elapsed.TotalMilliseconds;
                        double every = double.TryParse(Render(s.EveryMs, new Dictionary<string, string>()), NumberStyles.Float,
                            CultureInfo.InvariantCulture, out double e) ? Math.Max(1, e) : 1000;
                        if (now - last[i] < every) continue;
                        last[i] = now;
                        frame = ProtocolExpression.ToBytes(Render(s.Frame, new Dictionary<string, string>()));
                    }
                    sink?.Send(frame!);
                }
                await Task.Delay(5, lifetime).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception ex) when (ex is FormatException or InvalidOperationException)
        {
            // 프로파일 템플릿 오류 → 연속 송신 중단 (요청 응답은 계속)
        }
    }
}

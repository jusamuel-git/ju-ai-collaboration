using System.Threading.Channels;
using JuProvider.Lib.Protocol.Simulation;

namespace JuProvider.Lib.Protocol.Transport;

/// <summary>
/// 장애 주입 (C0 §5). 장치 → 수신 방향에 적용한다. Seed가 같으면 같은 결과.
/// DropRate: 응답/송신 조각을 버릴 확률, GarbageRate: 조각 앞에 쓰레기 바이트를 붙일 확률,
/// DelayMs: 전달 지연, FragmentSize: 조각을 이 크기로 나눠 전달(0=그대로),
/// DisconnectAfterMs: 연결 후 이 시간이 지나면 끊김(0=안 함), FailOpenCount: 처음 N번 Open 실패.
/// </summary>
public sealed record FaultOptions(
    double DropRate = 0,
    double GarbageRate = 0,
    int DelayMs = 0,
    int FragmentSize = 0,
    int DisconnectAfterMs = 0,
    int FailOpenCount = 0,
    int Seed = 1)
{
    public static FaultOptions None { get; } = new();
}

/// <summary>
/// 가상 Transport = 범용 시뮬레이터 장치(ISimulatedDevice) + 장애 주입.
/// 실제 Transport와 같은 Received/StateChanged 경로를 거치므로 Framer·Parser·재연결을 장비 없이 시험한다.
/// 쓰기 1회 = 장치가 받는 요청 1건.
/// </summary>
public sealed class VirtualTransport : TransportBase, ISimulatorSink
{
    private static readonly byte[] Garbage = [0x00, 0xFF, 0x23];

    private readonly ISimulatedDevice _device;
    private readonly FaultOptions _faults;
    private readonly Random _random;
    private readonly object _randomLock = new();
    private Channel<byte[]>? _inbound;
    private byte[]? _pending;
    private int _pendingOffset;
    private int _openAttempts;
    private CancellationTokenSource? _lifetime;

    public VirtualTransport(ISimulatedDevice device, FaultOptions? faults = null, string? name = null)
    {
        _device = device;
        _faults = faults ?? FaultOptions.None;
        _random = new Random(_faults.Seed);
        Name = name ?? $"VIRTUAL {device.ProfileId}";
    }

    public override string Name { get; }
    public override LinkCaps Caps => new(FullDuplex: true);

    /// <summary>시험용: 지금 연결을 끊는다(상대 종료와 같음)</summary>
    public void ForceDisconnect() => _inbound?.Writer.TryComplete(new IOException($"{Name}: 가상 연결 끊김"));

    protected override Task OpenCoreAsync(CancellationToken cancellationToken)
    {
        int attempt = Interlocked.Increment(ref _openAttempts);
        if (attempt <= _faults.FailOpenCount)
        {
            throw new IOException($"{Name}: 가상 Open 실패 주입 ({attempt}/{_faults.FailOpenCount})");
        }

        _inbound = Channel.CreateUnbounded<byte[]>(new UnboundedChannelOptions { SingleReader = true });
        _pending = null;
        _lifetime = new CancellationTokenSource();
        _device.Open(this, _lifetime.Token);

        if (_faults.DisconnectAfterMs > 0)
        {
            CancellationToken token = _lifetime.Token;
            _ = Task.Delay(_faults.DisconnectAfterMs, token).ContinueWith(t =>
            {
                if (!t.IsCanceled) ForceDisconnect();
            }, TaskScheduler.Default);
        }
        return Task.CompletedTask;
    }

    protected override async Task<int> ReadCoreAsync(Memory<byte> buffer, CancellationToken cancellationToken)
    {
        if (_pending is null)
        {
            Channel<byte[]> inbound = _inbound ?? throw new IOException($"{Name}: 연결 없음");
            _pending = await inbound.Reader.ReadAsync(cancellationToken).ConfigureAwait(false);
            _pendingOffset = 0;
        }

        int n = Math.Min(buffer.Length, _pending.Length - _pendingOffset);
        _pending.AsMemory(_pendingOffset, n).CopyTo(buffer);
        _pendingOffset += n;
        if (_pendingOffset >= _pending.Length) _pending = null;
        return n;
    }

    protected override Task WriteCoreAsync(ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        if (_inbound is null || _inbound.Reader.Completion.IsCompleted)
        {
            throw new IOException($"{Name}: 연결 끊김");
        }
        _device.OnRequest(data.ToArray());
        return Task.CompletedTask;
    }

    protected override Task CloseCoreAsync()
    {
        _lifetime?.Cancel();
        _lifetime?.Dispose();
        _lifetime = null;
        _device.Close();
        _inbound?.Writer.TryComplete();
        return Task.CompletedTask;
    }

    /// <summary>시뮬레이터 장치가 보내는 바이트 (장애 주입 후 수신 큐로)</summary>
    void ISimulatorSink.Send(byte[] data)
    {
        Channel<byte[]>? inbound = _inbound;
        if (inbound is null || data.Length == 0) return;

        bool drop, garbage;
        lock (_randomLock)
        {
            drop = _faults.DropRate > 0 && _random.NextDouble() < _faults.DropRate;
            garbage = _faults.GarbageRate > 0 && _random.NextDouble() < _faults.GarbageRate;
        }
        if (drop) return;

        byte[] payload = garbage ? [.. Garbage, .. data] : data;

        if (_faults.DelayMs > 0)
        {
            CancellationToken token = _lifetime?.Token ?? CancellationToken.None;
            _ = Task.Delay(_faults.DelayMs, token).ContinueWith(t =>
            {
                if (!t.IsCanceled) Enqueue(inbound, payload);
            }, TaskScheduler.Default);
        }
        else
        {
            Enqueue(inbound, payload);
        }
    }

    private void Enqueue(Channel<byte[]> inbound, byte[] payload)
    {
        int size = _faults.FragmentSize;
        if (size <= 0 || size >= payload.Length)
        {
            inbound.Writer.TryWrite(payload);
            return;
        }
        for (int i = 0; i < payload.Length; i += size)
        {
            inbound.Writer.TryWrite(payload[i..Math.Min(i + size, payload.Length)]);
        }
    }
}

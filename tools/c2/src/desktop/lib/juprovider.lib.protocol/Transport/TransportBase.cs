namespace JuProvider.Lib.Protocol.Transport;

/// <summary>상태 전이·백그라운드 수신 루프·오류 처리 공통</summary>
public abstract class TransportBase : ITransport
{
    private readonly object _sync = new();
    private CancellationTokenSource? _readCts;
    private Task? _readTask;
    private TransportState _state = TransportState.Closed;

    public abstract string Name { get; }
    public virtual LinkCaps Caps => new();

    public TransportState State
    {
        get { lock (_sync) return _state; }
    }

    public event EventHandler<byte[]>? Received;
    public event EventHandler<TransportStateChangedEventArgs>? StateChanged;

    public async Task OpenAsync(CancellationToken cancellationToken = default)
    {
        lock (_sync)
        {
            if (_state is TransportState.Open or TransportState.Opening) return;
        }

        SetState(TransportState.Opening, null);
        try
        {
            await OpenCoreAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            await SafeCloseCoreAsync().ConfigureAwait(false);
            SetState(TransportState.Faulted, ex);
            throw;
        }

        var cts = new CancellationTokenSource();
        lock (_sync) _readCts = cts;
        SetState(TransportState.Open, null);
        _readTask = Task.Run(() => ReadLoopAsync(cts.Token));
    }

    public async Task CloseAsync()
    {
        CancellationTokenSource? cts;
        Task? readTask;
        lock (_sync)
        {
            cts = _readCts;
            _readCts = null;
            readTask = _readTask;
            _readTask = null;
        }

        cts?.Cancel();
        await SafeCloseCoreAsync().ConfigureAwait(false);
        if (readTask is not null)
        {
            try { await readTask.ConfigureAwait(false); } catch { /* 닫는 중 읽기 오류는 무시 */ }
        }
        cts?.Dispose();

        if (State != TransportState.Closed) SetState(TransportState.Closed, null);
    }

    public async Task WriteAsync(ReadOnlyMemory<byte> data, CancellationToken cancellationToken = default)
    {
        if (State != TransportState.Open)
        {
            throw new InvalidOperationException($"{Name}: 연결되어 있지 않습니다 ({State}).");
        }

        try
        {
            await WriteCoreAsync(data, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            await FaultAsync(ex).ConfigureAwait(false);
            throw;
        }
    }

    public ValueTask DisposeAsync() => new(CloseAsync());

    protected abstract Task OpenCoreAsync(CancellationToken cancellationToken);

    /// <summary>읽은 바이트 수. 0 이하 = 상대가 연결을 닫음(EOF)</summary>
    protected abstract Task<int> ReadCoreAsync(Memory<byte> buffer, CancellationToken cancellationToken);

    protected abstract Task WriteCoreAsync(ReadOnlyMemory<byte> data, CancellationToken cancellationToken);

    protected abstract Task CloseCoreAsync();

    private async Task ReadLoopAsync(CancellationToken ct)
    {
        byte[] buffer = new byte[4096];
        try
        {
            while (!ct.IsCancellationRequested)
            {
                int n = await ReadCoreAsync(buffer, ct).ConfigureAwait(false);
                if (n <= 0) throw new IOException($"{Name}: 상대가 연결을 닫았습니다.");
                Received?.Invoke(this, buffer.AsSpan(0, n).ToArray());
            }
        }
        catch (Exception ex) when (!ct.IsCancellationRequested)
        {
            await FaultAsync(ex).ConfigureAwait(false);
        }
        catch
        {
            // CloseAsync가 취소한 경우
        }
    }

    private async Task FaultAsync(Exception ex)
    {
        CancellationTokenSource? cts;
        lock (_sync)
        {
            if (_state != TransportState.Open) return;
            cts = _readCts;
            _readCts = null;
        }
        cts?.Cancel();
        await SafeCloseCoreAsync().ConfigureAwait(false);
        SetState(TransportState.Faulted, ex);
    }

    private async Task SafeCloseCoreAsync()
    {
        try { await CloseCoreAsync().ConfigureAwait(false); } catch { /* 이미 닫힘 */ }
    }

    private void SetState(TransportState state, Exception? error)
    {
        lock (_sync) _state = state;
        StateChanged?.Invoke(this, new TransportStateChangedEventArgs(state, error));
    }
}

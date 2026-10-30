namespace JuProvider.Lib.Protocol.Transport;

/// <summary>
/// 재연결 대기 시간 (C0 §2.4): 빠른 재시도(기본 1·2·3초) 후 점증(기본 5초부터 2배, 최대 60초). 포기하지 않는다.
/// </summary>
public sealed record ReconnectPolicy(IReadOnlyList<TimeSpan> Quick, TimeSpan BackoffStart, TimeSpan BackoffMax)
{
    public static ReconnectPolicy Default { get; } =
        new([TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(3)], TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(60));

    /// <summary>attempt: 1부터</summary>
    public TimeSpan DelayFor(int attempt)
    {
        if (attempt < 1) throw new ArgumentOutOfRangeException(nameof(attempt));
        if (attempt <= Quick.Count) return Quick[attempt - 1];
        int n = Math.Min(attempt - Quick.Count - 1, 20);
        double ms = BackoffStart.TotalMilliseconds * Math.Pow(2, n);
        return TimeSpan.FromMilliseconds(Math.Min(ms, BackoffMax.TotalMilliseconds));
    }
}

public enum LinkEventKind
{
    Connected,
    Faulted,
    Reconnecting,
    Recovered,
    Stopped
}

public sealed record LinkEvent(LinkEventKind Kind, int Attempt, TimeSpan Delay, Exception? Error);

/// <summary>
/// Link 소유자 (C0 §1.2: 재연결 권한은 Link 소유자에만). "연결 원함"인 동안 끊기면 정책대로 다시 연다.
/// delay 함수는 시험에서 바꿔 넣을 수 있다.
/// </summary>
public sealed class LinkSupervisor : IAsyncDisposable
{
    private readonly ITransport _transport;
    private readonly ReconnectPolicy _policy;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;
    private readonly object _sync = new();
    private CancellationTokenSource? _cts;
    private Task? _reconnectTask;
    private bool _wasConnected;
    private volatile bool _opening; // 감독자가 직접 Open 중 → 그 실패는 호출한 쪽이 처리

    public LinkSupervisor(ITransport transport, ReconnectPolicy? policy = null, Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        _transport = transport;
        _policy = policy ?? ReconnectPolicy.Default;
        _delay = delay ?? ((d, ct) => Task.Delay(d, ct));
        _transport.StateChanged += OnStateChanged;
    }

    public ITransport Transport => _transport;
    public bool Desired { get; private set; }
    public event EventHandler<LinkEvent>? Event;

    /// <summary>연결 시작. 첫 연결이 실패해도 예외 없이 재연결을 이어간다(결과는 Event로).</summary>
    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        lock (_sync)
        {
            if (Desired) return;
            Desired = true;
            _cts = new CancellationTokenSource();
        }

        _opening = true;
        try
        {
            await _transport.OpenAsync(cancellationToken).ConfigureAwait(false);
            _wasConnected = true;
            Raise(LinkEventKind.Connected, 0, TimeSpan.Zero, null);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            Raise(LinkEventKind.Faulted, 0, TimeSpan.Zero, ex);
            StartReconnect();
        }
        finally
        {
            _opening = false;
        }
    }

    public async Task StopAsync()
    {
        CancellationTokenSource? cts;
        Task? task;
        lock (_sync)
        {
            Desired = false;
            cts = _cts;
            _cts = null;
            task = _reconnectTask;
            _reconnectTask = null;
        }
        cts?.Cancel();
        if (task is not null)
        {
            try { await task.ConfigureAwait(false); } catch { /* 취소 */ }
        }
        await _transport.CloseAsync().ConfigureAwait(false);
        cts?.Dispose();
        Raise(LinkEventKind.Stopped, 0, TimeSpan.Zero, null);
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        _transport.StateChanged -= OnStateChanged;
    }

    private void OnStateChanged(object? sender, TransportStateChangedEventArgs e)
    {
        if (e.State != TransportState.Faulted) return;
        if (!Desired || _opening) return; // 감독자의 Open 실패는 Open을 부른 쪽(루프·Start)이 처리

        Raise(LinkEventKind.Faulted, 0, TimeSpan.Zero, e.Error);
        StartReconnect();
    }

    private void StartReconnect()
    {
        lock (_sync)
        {
            if (!Desired || _cts is null) return;
            CancellationToken token = _cts.Token;
            Task? previous = _reconnectTask;
            // 이전 루프가 막 끝나는 중이면 그 뒤에 이어서 시작 (끊김을 놓치지 않음)
            _reconnectTask = previous is { IsCompleted: false }
                ? previous.ContinueWith(_ => ReconnectLoopAsync(token), CancellationToken.None,
                    TaskContinuationOptions.None, TaskScheduler.Default).Unwrap()
                : Task.Run(() => ReconnectLoopAsync(token));
        }
    }

    private async Task ReconnectLoopAsync(CancellationToken ct)
    {
        for (int attempt = 1; !ct.IsCancellationRequested; attempt++)
        {
            TimeSpan delay = _policy.DelayFor(attempt);
            Raise(LinkEventKind.Reconnecting, attempt, delay, null);
            await _delay(delay, ct).ConfigureAwait(false);
            if (ct.IsCancellationRequested) return;

            if (_transport.State == TransportState.Open) return; // 이미 다른 경로로 열림
            _opening = true;
            try
            {
                await _transport.OpenAsync(ct).ConfigureAwait(false);
                _opening = false;
                Raise(_wasConnected ? LinkEventKind.Recovered : LinkEventKind.Connected, attempt, delay, null);
                _wasConnected = true;
                return;
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                Raise(LinkEventKind.Faulted, attempt, delay, ex);
            }
            finally
            {
                _opening = false;
            }
        }
    }

    private void Raise(LinkEventKind kind, int attempt, TimeSpan delay, Exception? error) =>
        Event?.Invoke(this, new LinkEvent(kind, attempt, delay, error));
}

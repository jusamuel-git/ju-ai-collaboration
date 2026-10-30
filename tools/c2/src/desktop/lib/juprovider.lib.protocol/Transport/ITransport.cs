namespace JuProvider.Lib.Protocol.Transport;

public enum TransportState
{
    Closed,
    Opening,
    Open,
    Faulted
}

/// <summary>Link 능력 (C0 §2.2). 기본은 반이중·동시 1건</summary>
public sealed record LinkCaps(bool FullDuplex = false, int MaxInFlight = 1);

public sealed class TransportStateChangedEventArgs(TransportState state, Exception? error) : EventArgs
{
    public TransportState State { get; } = state;
    public Exception? Error { get; } = error;
}

/// <summary>
/// 바이트 전송 (C0 §0, §3). 프레임·프로토콜을 모른다.
/// 수신은 Open 이후 백그라운드에서 계속되며 Received 이벤트로 조각(chunk)을 넘긴다.
/// 읽기·쓰기 오류나 상대 종료(EOF)는 State = Faulted 로 알린다. 재연결은 LinkSupervisor 책임.
/// </summary>
public interface ITransport : IAsyncDisposable
{
    string Name { get; }
    TransportState State { get; }
    LinkCaps Caps { get; }

    /// <summary>수신 조각. 배열은 호출마다 새로 만든 것이므로 보관해도 된다. 백그라운드 스레드에서 호출된다.</summary>
    event EventHandler<byte[]>? Received;

    event EventHandler<TransportStateChangedEventArgs>? StateChanged;

    Task OpenAsync(CancellationToken cancellationToken = default);
    Task CloseAsync();
    Task WriteAsync(ReadOnlyMemory<byte> data, CancellationToken cancellationToken = default);
}

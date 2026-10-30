using System.Net.Sockets;

namespace JuProvider.Lib.Protocol.Transport;

/// <summary>TCP 클라이언트. 과거 구현(1회 Read)과 달리 백그라운드에서 계속 수신한다.</summary>
public sealed class TcpClientTransport(string host, int port, int connectTimeoutMs = 3000) : TransportBase
{
    private TcpClient? _client;
    private NetworkStream? _stream;

    public string Host { get; } = string.IsNullOrWhiteSpace(host) ? throw new ArgumentException("host가 필요합니다.", nameof(host)) : host;
    public int Port { get; } = port is > 0 and <= 65535 ? port : throw new ArgumentOutOfRangeException(nameof(port), "port는 1~65535");

    public override string Name => $"TCP {Host}:{Port}";
    public override LinkCaps Caps => new(FullDuplex: true);

    protected override async Task OpenCoreAsync(CancellationToken cancellationToken)
    {
        var client = new TcpClient { NoDelay = true };
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(connectTimeoutMs);
        try
        {
            await client.ConnectAsync(Host, Port, timeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            client.Dispose();
            throw new TimeoutException($"{Name}: {connectTimeoutMs}ms 안에 연결하지 못했습니다.");
        }
        catch
        {
            client.Dispose();
            throw;
        }
        _client = client;
        _stream = client.GetStream();
    }

    protected override async Task<int> ReadCoreAsync(Memory<byte> buffer, CancellationToken cancellationToken)
    {
        NetworkStream stream = _stream ?? throw new IOException($"{Name}: 연결 없음");
        return await stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
    }

    protected override async Task WriteCoreAsync(ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        NetworkStream stream = _stream ?? throw new IOException($"{Name}: 연결 없음");
        await stream.WriteAsync(data, cancellationToken).ConfigureAwait(false);
        await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    protected override Task CloseCoreAsync()
    {
        _stream?.Dispose();
        _client?.Dispose();
        _stream = null;
        _client = null;
        return Task.CompletedTask;
    }
}

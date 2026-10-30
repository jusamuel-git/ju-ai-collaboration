using System.IO.Ports;

namespace JuProvider.Lib.Protocol.Transport;

/// <summary>
/// Serial 설정. 키 이름은 과거 장치 설정과 같다 (CP-Q5): portName(또는 serialPort), baudRate, dataBits,
/// parity(None/Odd/Even/Mark/Space), stopBits(One/OnePointFive/Two), handshake(None/XOnXOff/RequestToSend/RequestToSendXOnXOff),
/// dtrEnable, rtsEnable, writeTimeoutMs.
/// </summary>
public sealed record SerialSettings(
    string PortName,
    int BaudRate = 9600,
    int DataBits = 8,
    Parity Parity = Parity.None,
    StopBits StopBits = StopBits.One,
    Handshake Handshake = Handshake.None,
    bool DtrEnable = true,
    bool RtsEnable = true,
    int WriteTimeoutMs = 3000);

/// <summary>
/// Serial. 과거 구현(응답 끝을 100ms 무수신으로 판단)과 달리 바이트를 그대로 계속 넘기고,
/// 프레임 경계는 Framer(Frame Rule)가 판단한다.
/// </summary>
public sealed class SerialTransport(SerialSettings settings) : TransportBase
{
    private SerialPort? _port;

    public SerialSettings Settings { get; } = settings;
    public override string Name => $"SERIAL {Settings.PortName}";

    protected override Task OpenCoreAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var port = new SerialPort(Settings.PortName, Settings.BaudRate, Settings.Parity, Settings.DataBits, Settings.StopBits)
        {
            Handshake = Settings.Handshake,
            DtrEnable = Settings.DtrEnable,
            RtsEnable = Settings.RtsEnable,
            WriteTimeout = Settings.WriteTimeoutMs,
            ReadTimeout = SerialPort.InfiniteTimeout
        };
        try
        {
            port.Open();
            port.DiscardInBuffer();
        }
        catch
        {
            port.Dispose();
            throw;
        }
        _port = port;
        return Task.CompletedTask;
    }

    protected override async Task<int> ReadCoreAsync(Memory<byte> buffer, CancellationToken cancellationToken)
    {
        SerialPort port = _port ?? throw new IOException($"{Name}: 연결 없음");
        // 포트를 닫으면 대기 중인 읽기가 예외로 끝난다 (CloseCoreAsync).
        return await port.BaseStream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
    }

    protected override async Task WriteCoreAsync(ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        SerialPort port = _port ?? throw new IOException($"{Name}: 연결 없음");
        await port.BaseStream.WriteAsync(data, cancellationToken).ConfigureAwait(false);
        await port.BaseStream.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    protected override Task CloseCoreAsync()
    {
        SerialPort? port = _port;
        _port = null;
        if (port is not null)
        {
            try { if (port.IsOpen) port.Close(); } finally { port.Dispose(); }
        }
        return Task.CompletedTask;
    }
}

namespace JuProvider.Lib.Protocol.Simulation;

/// <summary>시뮬레이터 장치가 바이트를 내보내는 곳 (VirtualTransport)</summary>
public interface ISimulatorSink
{
    void Send(byte[] data);
}

/// <summary>가상 장치. 요청을 받고 응답·연속 데이터를 sink로 보낸다.</summary>
public interface ISimulatedDevice
{
    string ProfileId { get; }

    /// <summary>연결 시작. lifetime이 취소되면 연속 송신을 멈춘다.</summary>
    void Open(ISimulatorSink sink, CancellationToken lifetime);

    /// <summary>쓰기 1회 = 요청 1건</summary>
    void OnRequest(byte[] request);

    void Close();
}

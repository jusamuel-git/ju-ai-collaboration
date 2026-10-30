namespace JuProvider.Lib.Protocol.Simulation;

/// <summary>
/// 기본 프로파일 (C0-Q6: 1차는 코드에 포함된 리소스, DB 저장은 후속).
/// GTEC_SCIENCE_CUBE 명령은 seed의 GTEC 프로토콜(PTL_VAL)과 같다:
///  S{TEST}·S{10,3} 확인, S{20} 센서정보, S{11,n} 모드, S{12,초} 간격, S{10,1} 시작, S{10,0} 중지.
/// </summary>
public static class BuiltInProfiles
{
    public const string GtecScienceCubeJson = """
    {
      "profileId": "GTEC_SCIENCE_CUBE", "v": 1, "seed": 1,
      "vars": { "running": false, "mode": "ANALOG", "intervalMs": 100, "sensor1": "008" },
      "responses": [
        { "match": "S{TEST}", "reply": "{OK}[CR][LF]" },
        { "match": "S{10,3}", "reply": "{OK}[CR][LF]" },
        { "match": "S{20}",   "reply": "{${sensor1},000,000,000}[CR][LF]" },
        { "match": "S{10,1}", "set": { "running": true } },
        { "match": "S{10,0}", "set": { "running": false } },
        { "match": "S{11,1}", "set": { "mode": "ANALOG" } },
        { "match": "S{11,0}", "set": { "mode": "PHOTOGATE1" } },
        { "match": "S{11,2}", "set": { "mode": "PHOTOGATE2" } },
        { "matchRegex": "^S\\{12,(?<sec>[0-9]+(\\.[0-9]+)?)\\}$", "set": { "intervalMs": "${sec*1000}" } }
      ],
      "streams": [
        { "when": "running==true && mode==ANALOG", "everyMs": "${intervalMs}", "frame": "{${ch1} ${ch2} ${ch3}}[CR][LF]" }
      ],
      "generators": {
        "ch1": { "type": "sine", "amp": 1, "periodMs": 2000, "offset": 2 },
        "ch2": { "type": "ramp", "value": 0, "step": 0.1, "max": 5 },
        "ch3": { "type": "random", "min": 0, "max": 5 }
      }
    }
    """;

    /// <summary>받은 요청을 그대로 + [CR][LF] 로 돌려준다</summary>
    public const string EchoJson = """
    { "profileId": "GENERIC_ECHO", "v": 1,
      "responses": [ { "matchRegex": "^(?<all>.*)$", "reply": "${all}[CR][LF]" } ] }
    """;

    /// <summary>연결되면 바로 일정 간격으로 순번을 보낸다</summary>
    public const string StreamJson = """
    { "profileId": "GENERIC_STREAM", "v": 1,
      "vars": { "running": true, "everyMs": 20 },
      "responses": [ { "match": "STOP", "set": { "running": false } }, { "match": "START", "set": { "running": true } } ],
      "streams": [ { "when": "running", "everyMs": "${everyMs}", "frame": "{${seq}}[CR][LF]" } ],
      "generators": { "seq": { "type": "ramp", "value": 1, "step": 1, "max": 1000000 } } }
    """;

    public static DeviceProfile Get(string profileId) => profileId.ToUpperInvariant() switch
    {
        "GTEC_SCIENCE_CUBE" => DeviceProfile.Parse(GtecScienceCubeJson),
        "GENERIC_ECHO" => DeviceProfile.Parse(EchoJson),
        "GENERIC_STREAM" => DeviceProfile.Parse(StreamJson),
        _ => throw new ProfileFormatException($"알 수 없는 프로파일: {profileId}")
    };
}

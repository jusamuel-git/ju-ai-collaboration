# 수집 경로 설계 — Protocol → Device → Data (ChatGPT 구조 검토 요청)

- 일시: 2026-10-30. **설계만**: 소스 수정·DB 변경·제품 브랜치 병합·Jenkins 없음
- 근거: 과거 ZIP(`juprovider-backup.zip`, 참조 전용) + 현재 `feature/integration-1` @ `14d1ab9`
- 방향(사용자 10/30): 현재 소스가 기준, 과거는 참조. Protocol → Device → Data 우선. Experiment Data는 별도 안정화 단계. Viewer·Designer는 선택형 제품군

---

## 1. 과거 Protocol 코드의 입력·출력 계약

### 1.1 `ProtocolExpression` (lib.protocol) — 패킷 표현 ↔ 바이트
| 함수 | 입력 | 출력 | 규칙 |
|---|---|---|---|
| `ToBytes(string?)` | 표현식 예: `S{10,1}[CR][LF]`, `[STX]ABC[00][ETX]` | `byte[]` | `[...]`만 제어 의미. 이름(`NUL STX ETX TAB LF CR`) 또는 16진 2자리(`[0D]`). 그 외 문자는 ASCII 그대로(`{}` 포함). ASCII 밖 문자·닫는 `]` 없음·모르는 이름 → `FormatException` |
| `ToDisplay(bytes)` | `byte[]` | 표현식 문자열 | 이름 있는 제어문자는 이름, 출력 가능 ASCII는 그대로, 나머지 `[hh]` → **ToBytes와 왕복 가능** |
| `Hex(bytes)` | `byte[]` | `"53 7B 31 30"` | 로그용 |
- 현재 seed의 `PACKET_EXPR`·`PTL_VAL`(`S{10,1}`, `S{TEST}[CR][LF]`)이 **이 문법 그대로** → 재사용 가치 가장 높음.
- 문제: 과거 소스에 같은 기능이 3벌(이 클래스, `protocolmanager/ProtocolExpression.cs`, `ScLoggerProtocol.BuildRequest`의 문자열 치환, backend Java `ProtocolExpressionParser`). 규칙이 조금씩 달라 **한 구현 + 같은 테스트 벡터**로 통일 필요.

### 1.2 `GtecProtocolParser` — GTEC(Science Cube) 텍스트 프레임
| 함수 | 입력 | 출력 |
|---|---|---|
| `ParseRuleText(text, fallbackCount)` | `FRAME=CRLF;STX={;ETX=};MODE=DELIMITED;SEP=SPACE;COUNT=3;MAP=CHANNELS` | `ParseRule(Frame, Stx, Etx, Mode, Separator, Count, Map)` |
| `ToRuleText(rule)` | ParseRule | 위 텍스트 (왕복) |
| `ExtractFrames(StringBuilder buf, string? incoming)` | 누적 버퍼 + 새 문자열 | CRLF로 끝난 프레임 목록(나머지는 버퍼에 남김) |
| `TryParse(frame, rule, selectedChannel, out values)` | `{1.23 4.56 7.89}` | `ParsedValue(ChannelIndex, SampleIndex, Value)` 목록. `MAP=CHANNELS` → 토큰 i = 채널 i+1. `MAP=SAMPLES` → 선택 채널 1개의 연속 샘플 |
| `TryParseSensorInfo(frame, out sensors)` | `{008,000,000,000}` | `SensorInfo(ChannelIndex, SensorCode, Connected)` 4개 |
- 장점: 규칙이 **텍스트 계약**이라 DB `PARSE_RULE`에 그대로 저장 가능, 순수 함수라 단위 테스트 쉬움.
- 한계: 프레임 구분이 CRLF 고정(`FRAME` 값 무시), 문자열 기반(바이너리 프레임 불가), 채널 수 1~3·센서 4개가 코드에 고정(GTEC 전용), 저속/고속 규칙이 상수.

### 1.3 `ProtocolEngine` — JSON 설정 기반 범용 파서
| 함수 | 입력 | 출력 |
|---|---|---|
| `FromJson(id, name, configJson, defaultPollingMs)` | `{"pollingMs":1000,"request":"READ","tags":[{"name","index","source","dataType","scale","offset","unit"}]}` | `RuntimeProtocol(ProtocolId, Name, PollingMs(≥100), Request, Tags)` |
| `Parse(deviceId, protocol, payload, timestamp)` | **JSON 응답** 바이트 | `JuDataValue(DeviceId, ProtocolId, Name, Index, Value, Timestamp, Unit)` (값 = 원값×scale+offset, int/bool/string 지원) |
- 장점: 태그별 **Scale/Offset/Unit 매핑** 개념.
- 한계: 응답이 JSON인 장치만 해석 가능 → GTEC 텍스트 장비와 맞지 않음. 실제 사용 경로 불명.

### 1.4 종합
- 과거에는 **파서가 3종(JSON 태그, GTEC 텍스트, ScLogger `{DATA,…}`)으로 따로** 있고 공통 계약이 없음.
- 과거 `lib.protocol/Models.cs`의 `ProtocolCommandType(Polling, Read, Write, Control, Event)`, `FrameType(None, Delimiter, StxEtx, FixedLength, HeaderLength)` 열거형은 **설계 의도만 있고 사용처 없음** → 제안 모델(§4)에 반영.
- 현재 seed `PARSE_RULE`은 형식이 섞여 있음(빈 값, `패킷길이|STX DLE|ETX|ETX DLE` 같은 설명문) → **규칙 문법 확정이 선행 조건**.

---

## 2. 과거 `DeviceConnectionManager` 분석

| 항목 | 내용 |
|---|---|
| 소유 | DeviceManager 프로세스가 연결을 소유, ProtocolManager는 Named Pipe로 시험 요청 |
| 연결 생성 | `Create(type, json)`: 장치유형 코드 우선(`DEVI0000/0003`=가상, `DEVI0002`=Serial, `DEVI0001`=TCP), 없으면 설정 키(`portName`/`host`)로 추정, 설정이 비면 가상, 그 외 Echo |
| 설정 키 | TCP: `host`(또는 `ip`), `port`, `timeoutMs` / Serial: `portName`(또는 `serialPort`), `baudRate`, `dataBits`, `parity`, `stopBits`, `handshake`, `dtrEnable`, `rtsEnable`, `timeoutMs` / 가상: `profile=SCLOGGER`, `sampleIntervalMs`, `highChannel` / Gateway: `maxClients`(화면만) |
| 송수신 3방식 | `ExchangeAsync`(요청→응답), `SendOnlyAsync`(응답 없는 TX), `DataReceived` 이벤트(장비가 스스로 보내는 연속 데이터) |
| 재연결 | 실패 시 연결 폐기 후 **3회**(1·2·3초 간격) 재연결·재시도, 결과를 `ConnectionStateChanged`(IsRecovery, Attempt, Error)로 알림. 3회 실패 후에는 멈춤 |
| 통신 기록 | `Traffic`(장치, 송/수신, 바이트, 시각) → `DeviceTrafficSessionStore` |
| 동시성 | 연결 목록 `SemaphoreSlim` 1개, Serial은 장치별 I/O 게이트(Exchange 중에는 이벤트 수신 중단) |

문제점 (재사용 시 고칠 것)
1. **TCP 응답을 1회 `ReadAsync`로만 읽음** → 응답이 나뉘어 오면 잘림. TCP는 `DataReceived`를 발생시키지 않아 **연속 송신 장치(TCP) 미지원**.
2. **Serial 응답 끝을 "100ms 무수신"으로 판단** → 프레임 규칙과 무관, 느린 장치·빠른 연속 데이터에서 오판.
3. 프레임 조립이 연결 계층 밖(화면·파서 쪽)에 흩어짐.
4. 3회 실패 후 자동 복구 없음(장시간 실험에 부적합).
5. **Gateway는 설정·DB 링크(`ju_device_link`: parent, child, module_no, channel_no)만 있고 실행 로직 없음**.
6. 장치 연결값을 공통 장치정의(`DEV_CONFIG`)에 저장 → SYSINFO-01 결정(PC별 로컬 override)과 충돌.

---

## 3. 공통 장치 인터페이스 제안 (Terminal 쪽, C#)

계층을 **바이트 전송 / 프레임 조립 / 장치 세션 / 장치 구성**으로 나눈다.

```text
ITransport            바이트만 다룬다 (Serial, TCP client, Virtual, GatewaySubChannel)
  OpenAsync / CloseAsync / WriteAsync(bytes)
  event Received(bytes chunk)          ← TCP도 백그라운드 수신으로 통일
  State: Closed|Opening|Open|Faulted

IFramer               바이트 조각 → 완성 프레임 (Delimiter(CRLF 등) | StxEtx | FixedLength | HeaderLength)
  Push(chunk) → IReadOnlyList<Frame>   (나머지는 내부 버퍼)

IDeviceSession        장치 1대의 통신 단위 (Transport + Framer + 프로토콜 집합)
  ExecuteAsync(ptlCd)  : TX 전용 / 요청-응답(응답 프로토콜·timeout·retry) 
  event Frame(ptlCd?, frame)          : 연속 수신(RX 스트림)
  Reconnect 정책: 빠른 재시도 3회(1·2·3s) → 이후 점증 대기(5s→최대 60s), "연결 원함" 상태인 동안 계속
  event StateChanged / Traffic

DeviceNode            구성 (서버 정의 + 로컬 연결값)
  DevCd, Kind = PHYSICAL | VIRTUAL | GATEWAY | CHILD
  ParentDevCd, Address(moduleNo, channelNo)   ← CHILD만
  PtlGrpCd, ChannelCount(DEV_CH)
  Connection (로컬 override, ClientId+DevCd)  ← 서버 공통정의에 PC별 값 저장 안 함
```

| 장치 종류 | 구성 |
|---|---|
| 물리 Serial | `SerialTransport` + Framer + Session |
| 물리 TCP | `TcpClientTransport` (백그라운드 수신) + Framer + Session |
| 가상 | `VirtualTransport` = **장치 시뮬레이터**(요청 바이트를 받아 GTEC처럼 응답·연속 송신). 현재 `VirtualDeviceRuntime`(1초마다 `{ch1,ch2,ch3}` 고정 패턴 문자열 생성, 프로토콜·요청 없음)을 대체 → 실제 장비와 **같은 Framer·Parser 경로**를 시험 |
| Gateway | 부모 세션이 Transport 1개 소유, 상위 프레임(주소·모듈번호)으로 감싸고 풀어 하위로 분배 |
| N개 하위 장치 | `GatewaySubChannel : ITransport` — 부모를 통해 쓰고, 부모가 분배한 수신만 받음. 하위 장치는 일반 장치와 같은 Session 사용 |

- 현재 IPC(Client↔Terminal) 메시지 `DEVICE_SYNC/CONNECT/DISCONNECT/STATUS/DATA_RECEIVED`는 유지. 상태 값(`CONNECTING/CONNECTED/ERROR` 등)에 `RECONNECTING`만 추가 제안.

---

## 4. Protocol 모델 제안 — 정보·제어·데이터, 상위·하위

### 4.1 두 축으로 분리
| 축 | 값 | 현재 위치 |
|---|---|---|
| **역할 (Role)** | `INFO`(장치확인·센서정보) / `CONTROL`(모드·간격·시작·중지) / `DATA`(측정값) | **없음** — seed는 이름으로만 구분(GTEC0001~0002 정보, 0100~0301 제어, 0400~0402 데이터) |
| **교환 방식 (Pattern)** | `TX_ONLY` / `TX_RX`(요청-응답) / `RX_STREAM`(장치가 연속 송신) | `PTL_TYPE`(PROT: POLLING/TX/RX/TXRX) — 이미 있음, 단 seed는 전부 `PROT0000` |
- 역할 저장 방법(결정 필요): ① `ju_protocol`에 `PTL_ROLE` 컬럼 추가(스키마 변경) ② 공통코드 PROT를 역할+방식 조합으로 확장 ③ 당분간 그룹 내 코드 범위 규칙(00xx 정보, 01xx~03xx 제어, 04xx 데이터). **제안: ①** (명확, Action 계약에 필드 추가)

### 4.2 연결 관계
- **요청→응답**: TX 패킷의 `RESPONSE_PTL_CD` → 응답(RX) 프로토콜. 응답 프로토콜의 `PARSE_RULE`로 해석. (컬럼 있음)
- **제어 순서(시퀀스)**: 실험 시작 = 모드(0100) → 간격(0200) → 시작(0300), 중지 = 0301. → 과거 Experiment 명령 큐와 연결되는 부분이라 **Experiment 단계에서 정의**(지금은 모델만).
- **상위·하위 (Gateway)**: 상위 그룹(Gateway 프레임: 주소·모듈번호·길이)과 하위 그룹(장치 페이로드)을 분리. 하위 장치는 자기 그룹을 그대로 쓰고, Gateway 세션이 감싸기/풀기만 담당. 장치 링크(부모·자식·모듈·채널)는 과거 `ju_device_link` 구조를 참고하되 **현재 baseline에는 없음 → Gateway 단계에서 스키마 결정**.

### 4.3 `PARSE_RULE` 문법 확정 (선행)
과거 GTEC 규칙 텍스트를 일반화:
```
FRAME=CRLF|LF|STXETX|FIXED:<n>|HEADLEN:<off>,<size>
STX=<문자|[hh]>; ETX=<문자|[hh]>
MODE=DELIMITED|INFO|NONE
SEP=SPACE|COMMA|TAB
COUNT=<n>              (0=검사 안 함)
MAP=CHANNELS|SAMPLES|NONE
```
- 서버 ProtocolService가 저장 시 문법 검사(INVALID_VALUE) — Action 계약 변경 아님(필드 형식 검사 추가). 실제 구현은 승인 후.

---

## 5. 데이터 흐름 — 장치 채널 → 논리 Data → Runtime

```text
[Transport] bytes
   → [Framer] frame
   → [Parser(PARSE_RULE)] ParsedValue(channelIndex, sampleIndex, raw)
   → [Mapper] 장치(DEV_CD)의 데이터 그룹(ju_data_group.DEV_CD) 태그(ju_data_tag: DAT_IDX, TAG_ID='CH1'…)
              + 변환(DAT_TYPE, 단위, ju_data_tag_detail: 범위·수식)
      LogicalValue(DEV_CD, DAT_GR_CD, DAT_CD, DAT_IDX, value, unit, collectedDt, sampleIndex)
   → [Terminal RuntimeBus] 최신값 + IPC DATA_VALUES(구조화) → Client 화면
   → (실험 중) Client 로컬 누적 저장 + 서버 전송 대기열   ← Experiment Data 단계(이번 범위 밖)
```
| 단계 | 키 | 현재 테이블 |
|---|---|---|
| 장치 채널 | DEV_CD + 채널번호(1..DEV_CH) | `ju_device.DEV_CH`, `DEV_DAT_CNT` |
| 논리 Data | DAT_GR_CD + DAT_CD + DAT_IDX | `ju_data_group`(장치당 그룹), `ju_data_tag`(+detail: 단위·범위·수식) |
| 매핑 | TAG_ID(`CH1`~) ↔ 채널번호 | seed `DG_GTEC01` 태그 TAG_ID `CH1~CH3` 존재 |
| Runtime 최신값 | CLIENT_ID + DEV_CD + DAT_GR_CD + DAT_CD + DAT_IDX | `ju_runtime_data` (PK 일치) |
| 실험 데이터 | EXP_ID + RUN_ID + … + COLLECTED_DT | `ju_experiment_data` (별도 단계) |
- 매핑 규칙(제안): 1차는 **TAG_ID = `CH<n>`** 로 채널 연결, SAMPLES 모드는 같은 태그에 sampleIndex 순서로 누적. 수식(FORMULA)은 후속.
- 현재 IPC `DeviceDataMessage.Data`(문자열) → **구조화 메시지 `DATA_VALUES`(LogicalValue 목록) 추가**, 기존 메시지는 호환 유지.

---

## 6. 최소 변경 범위와 단계

원칙: 서버 계약·DB 변경 없는 Terminal 내부부터. 각 단계 = 작은 commit + 테스트 + 보고, 다음 단계는 승인 후.

| 단계 | 범위 | 변경 파일(예상) | 서버/DB |
|---|---|---|---|
| **C1 표현식·프레임·파서 코어** | `ProtocolExpression`(과거 로직 참조 재작성, 단일 구현), `IFramer` 4종 중 Delimiter·StxEtx, `ParseRule` 문법·`TextFrameParser`(CHANNELS/SAMPLES/INFO) | `desktop/lib/juprovider.lib.protocol/*` (현재 빈 Class1 대체) + **신규 테스트 프로젝트** `desktop/tests/juprovider.lib.protocol.tests` | 없음 |
| **C2 전송 계층** | `ITransport`, `SerialTransport`, `TcpClientTransport`(백그라운드 수신), `VirtualTransport`(GTEC 시뮬레이터), 재연결 정책 | `desktop/lib/juprovider.lib.device/*` + 테스트 | 없음 |
| **C3 장치 세션 + Terminal 연결** | `DeviceSession`(TX/TX_RX/RX_STREAM), `DeviceRuntimeManager`가 Kind별 세션 생성. 가상 장치를 시뮬레이터 경로로 교체. IPC `DATA_VALUES`·`RECONNECTING` 추가(기존 유지) | `juprovider.terminal/Runtime/*`, `lib.ipc/Messages/*` | 없음 |
| C4 프로토콜·데이터 정의 내려받기 | Client가 장치의 프로토콜 그룹·패킷·데이터 태그를 받아 Terminal에 전달 | `GET /api/core/sync/protocols`, `/sync/data-tags` (Client 체인 GET) | **API 추가 → 승인 필요** (SYNC-01과 함께 설계) |
| C5 역할·PARSE_RULE 검사 | `PTL_ROLE`, 파싱 규칙 문법 검사, 화면 필드 | migration 07+, ProtocolContracts | **스키마·계약 변경 → 승인 필요** |
| C6 Gateway·하위 장치 | 장치 링크 테이블, `GatewaySubChannel` | migration, Device Action | **승인 필요** |
| (별도) Experiment Data | 로컬 누적·Outbox·업로드 | — | 별도 안정화 단계 |
- C1~C3은 **현재 Client·Server·DB를 바꾸지 않음**. 연결값은 당분간 로컬 설정 파일(`config\devices.local.json`, ClientId+DevCd 키)로 — SYSINFO-01 S2(로컬 override)와 같은 방향.
- 의존성: `System.IO.Ports` NuGet 1개 필요(Serial). **의존성 추가 → 승인 필요**. 테스트 프로젝트(xUnit 등)도 의존성 추가.

## 7. 테스트 계획
| 구분 | 내용 |
|---|---|
| 단위 (C1) | 표현식 왕복 벡터(seed의 모든 `PTL_VAL`·`PACKET_EXPR`), 잘못된 표현식 오류, Framer: 조각 나뉜 입력·여러 프레임 한 번에·쓰레기 바이트, ParseRule 왕복, GTEC 저속(3채널)·고속(6샘플)·센서정보 프레임 |
| 단위 (C2) | 재연결 정책(시간 주입), TCP 조각 수신(로컬 루프백 서버), 가상 시뮬레이터 응답·연속 송신 |
| 통합 (C3) | 가상 GTEC: 연결 → 장치확인(TX_RX) → 모드·간격·시작(TX) → 데이터 스트림 → 중지 → 해제, 연결 끊김 주입 후 RECONNECTING → 복구, IPC 메시지 순서 |
| 실제 장비 | Science Cube Lite II(COM6/115200): 장치확인·센서정보·저속 3채널·고속 1채널, 케이블 분리·재연결 — **사용자 PC에서 수동 체크리스트** |
| 회귀 | 빌드 5종, Desktop 온라인/오프라인 로그인, 장치 동기화·IPC, Protocol CRUD(서버 변경 없음 확인) |

## 8. 결정 요청
| # | 질문 | 제안 |
|---|---|---|
| CP-Q1 | 프로토콜 역할(INFO/CONTROL/DATA) 저장 방식 | `PTL_ROLE` 컬럼 (C5, 승인 후) |
| CP-Q2 | `PARSE_RULE` 문법 (§4.3) 확정 | GTEC 규칙 일반화안 채택 |
| CP-Q3 | 가상 장치를 GTEC 시뮬레이터로 교체 | 예 — 실제 장비와 같은 경로 시험 |
| CP-Q4 | C1~C3 착수 시 의존성 추가(`System.IO.Ports`, 테스트 프레임워크) | 승인 요청 |
| CP-Q5 | 연결값 로컬 파일(`devices.local.json`) 형식 | 과거 설정 키 이름 유지(`portName`, `baudRate`, `host`, `port`, `timeoutMs` …) |
| CP-Q6 | Gateway 장치 링크 스키마 시점 | C6 (Experiment 이전 또는 이후) 결정 |

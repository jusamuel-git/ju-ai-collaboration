# C0 공통 계약 설계 — 수집 경로 (ChatGPT 검토 요청)

- 일시: 2026-10-30. **설계만**: 제품 소스·DB·제품 commit/push·Jenkins 없음
- 선행 문서: [2026-10-30_collect-path_design.md](2026-10-30_collect-path_design.md) (조건부 승인, 구현 보류)
- 이번 보완 대상: 사용자 검토 1~7항
- 진행: **C0(이 문서) 검토** → C1~C3 Desktop 내부 구현(승인 후) → C4~C6 API·DB·Gateway

## 0. 용어와 계층

```text
Link        물리 연결 1개 (COM 포트 1개, TCP 연결 1개, 시뮬레이터 1개)
Transport   Link의 바이트 입출력                     ITransport
Framer      바이트 흐름 → 프레임 (Frame Rule)         IFramer
Scheduler   Link 1개의 송신 순서·응답 매칭·타임아웃     ICommandScheduler
Session     장치 1대의 논리 통신 (프로토콜 실행·수신 분배) IDeviceSession
Parser      프레임 → 원시값 (Parse Rule)              IFrameParser
Mapper      원시값 → 논리 Data                        IDataMapper
```
- **Link : Scheduler = 1 : 1**, **Link : Session = 1 : N** (Gateway일 때 N, 일반 장치는 1).

---

## 1. Gateway — Transport 1개 공유, 하위 Session N개

### 1.1 구조
```text
GatewayNode (DEV_CD=NET_GTEC01, Kind=GATEWAY)
 ├─ Link: TcpClientTransport(host:port)     ← 연결·재연결은 여기서만
 ├─ Gateway Framer (상위 Frame Rule)
 ├─ Scheduler (Link 단위, 하위 모든 명령이 여기로)
 ├─ Demux: 상위 프레임의 주소 → 하위 Session
 └─ Children
     ├─ ChildSession(SDEV_GTEC01, Address{module=1})  — 자기 Framer·Parser·프로토콜 그룹
     └─ ChildSession(…,           Address{module=2})
```
| 모드 | 의미 | 송신 | 수신 |
|---|---|---|---|
| `TRANSPARENT` | Serial↔TCP 변환기처럼 하위 1대를 그대로 통과 (seed의 `NET_GTEC01`→`SDEV_GTEC01` 경우) | 하위 바이트 그대로 | 그대로 하위로. 하위 1대만 허용 |
| `ADDRESSED` | 상위 프레임에 주소(모듈·채널)를 붙여 N대 공유 | 하위 페이로드를 상위 프레임으로 감쌈(envelope) | 상위 프레임을 풀어 주소로 하위에 분배 |

- 하위 Session은 일반 장치와 **같은 코드**. 차이는 Transport가 `GatewaySubChannel(parent, address)`라는 것뿐 (Write = 부모 Scheduler에 envelope 요청, Received = 부모 Demux가 넘겨준 페이로드).
- 주소: `moduleNo`(1..128, 과거 `ju_device_link.module_no` 범위), 선택 `channelNo`. 같은 부모 아래 주소 중복 금지.
- 알 수 없는 주소의 프레임: 버리고 Traffic 로그에 `UNROUTED`로 기록.

### 1.2 상태 전파
| 이벤트 | Gateway | 하위 Session |
|---|---|---|
| Link 연결 성공 | `CONNECTED` | `READY` (하위별 초기화 명령은 각자 실행) |
| Link 끊김 | `RECONNECTING` | `SUSPENDED` (대기 명령 `LINK_DOWN`으로 실패, 재연결 시도 안 함) |
| Link 복구 | `CONNECTED` | `READY` → 하위별 재초기화(설정된 경우) |
| 하위 응답 타임아웃 | 영향 없음 | 하위만 `DEGRADED` (연속 K회면 Gateway에 보고, Link 재연결은 Gateway가 판단) |
| 하위 연결 해제 요청 | 하위가 0대가 되면 Link 닫기 (설정: 유지 가능) | `DISCONNECTED` |
- **재연결 권한은 Link 소유자(Gateway)에만** 있다. 하위가 Link를 닫거나 다시 열지 않는다.

---

## 2. Command Scheduler

### 2.1 명령 형식
```text
CommandRequest {
  DevCd, PtlCd, Role(s), Pattern,          // §3
  Payload: byte[]                           // 표현식 → 바이트 (ProtocolExpression)
  Expect: ResponseMatcher?                  // TX_RX만
  TimeoutMs, RetryCount, Idempotent: bool,
  Priority: STOP > CONTROL > INFO > POLL,
  CancellationToken, CorrelationKey?        // 주소·거래번호
}
결과: Completed(frame?) | Timeout | Cancelled | LinkDown | Rejected(reason)
```

### 2.2 직렬·병렬 실행 조건
| 조건 | 동시 진행(in-flight) |
|---|---|
| 기본 (Serial, 반이중, 주소 없음) | **Link당 1개**. 응답 또는 타임아웃 후 다음 명령 |
| `TX_ONLY` | 송신 완료 = 완료. 다음 명령 전 `InterCommandGapMs`(기본 0, 프로파일 설정) |
| 병렬 허용 | Link가 `fullDuplex=true` **이고** 응답에 상관키(주소·거래번호)가 있을 때만, `maxInFlight`(기본 1) 까지 |
| Gateway `ADDRESSED` | 기본 직렬. 서로 다른 주소 + 장비가 동시 처리를 지원할 때만 병렬(설정으로 명시) |
| `RX_STREAM` | Scheduler를 거치지 않음 (수신 분배만) |

### 2.3 응답 매칭 (수신 프레임마다 순서대로 검사)
1. **상관키**가 있으면 키가 같은 대기 명령에 연결
2. 대기 명령의 `Expect`(응답 프로토콜의 Frame/Parse Rule로 해석 가능 + 선택 조건: 시작 바이트·토큰 수 등)에 맞으면 연결
3. 맞는 대기 명령이 없으면 → **스트림 수신**으로 넘김 (과거처럼 Exchange 중 수신을 버리지 않음)
4. `Expect`가 없는 레거시 TX_RX → "요청 후 첫 프레임" (호환용, 경고 로그)

### 2.4 타임아웃·재시도
- 타임아웃 = 명령값 → 없으면 프로토콜 그룹 `TIMEOUT_MS`(현재 컬럼). 재시도 = 그룹 `RETRY_CNT`.
- **재시도는 `Idempotent=true`인 명령만** (INFO, DATA 폴링, 모드·간격 설정). `START` 같은 상태 전이 명령은 자동 재시도 안 함 → 오류 보고 (중복 시작 방지).
- 같은 Link에서 연속 타임아웃 K회(기본 3) → Link 의심 → Link 소유자가 재연결 (빠른 3회 1·2·3초 → 이후 5초부터 최대 60초까지 늘리며 "연결 원함" 상태 동안 계속).
- 타임아웃 후 늦게 온 응답: 매칭 실패 → 스트림 처리 대상인지 검사, 아니면 `LATE` 로그 후 버림.

### 2.5 취소
| 시점 | 처리 |
|---|---|
| 대기 중 | 큐에서 제거 → `Cancelled` |
| 진행 중 (TX_RX) | 호출자에게 즉시 `Cancelled`, Link는 응답 또는 타임아웃까지 점유 유지(장비 상태 꼬임 방지) |
| Link 끊김 | 대기·진행 전부 `LinkDown` |
| `STOP` 명령 도착 | 최우선 큐. 같은 장치의 대기 중 `START`·`PAUSE` 취소 (과거 실험 명령 규칙과 동일) |
| 폴링 | 이전 폴링이 끝나지 않았으면 이번 회차 건너뜀 (쌓이지 않음) |

---

## 3. Protocol Role과 Exchange Pattern

| 축 | 값 | 개수 | 비고 |
|---|---|---|---|
| **Exchange Pattern** | `TX_ONLY` / `TX_RX` / `RX_STREAM` / `POLL`(주기적 TX_RX) | 프로토콜당 **1개** | 기존 `PTL_TYPE`(공통코드 PROT) 의미를 이것으로 확정: PROT0000 POLLING→`POLL`, 0001 TX→`TX_ONLY`, 0002 RX→`RX_STREAM`, 0003 TXRX→`TX_RX` |
| **Role** | `INFO` / `CONTROL` / `DATA` | 프로토콜당 **1개 이상** | 복수 예: 시작 명령의 응답에 첫 데이터가 실림(CONTROL+DATA), 센서정보 응답을 채널 구성 데이터로 씀(INFO+DATA) |

- Role 사용처: Scheduler 우선순위·재시도 기본값(CONTROL은 기본 Idempotent=false), Mapper 대상(DATA 포함 프로토콜만 논리 Data로), 화면 분류.
- 저장 제안(C5): 공통코드 그룹 `PROL`(INFO/CONTROL/DATA) + `ju_protocol.PTL_ROLES` (쉼표로 구분된 코드 목록, 최소 1개, 코드 검사). 비트값 대신 코드 목록 — 읽기 쉽고 MACT 비트와 혼동 없음.
- **데이터 정정 필요**: 현재 seed GTEC 프로토콜 17개가 모두 `PROT0000`(POLLING). 실제는 장치확인·센서정보=TX_RX, 모드·간격·시작·중지=TX_ONLY 또는 TX_RX, 데이터=RX_STREAM → C5 migration에서 정정 (승인 후).

---

## 4. Frame Rule과 Parse Rule 분리

| 규칙 | 책임 | 단위 | 저장 위치 (제안, C5) |
|---|---|---|---|
| **Frame Rule** | 바이트 흐름에서 프레임 경계 찾기·검증 | `byte[]` | 프로토콜 그룹 기본값 (`ju_protocol_group.FRAME_RULE`) + 패킷별 재정의(선택) |
| **Parse Rule** | 프레임 → 원시값 | 프레임 1개 | RX 패킷 `ju_protocol_packet.PARSE_RULE` (컬럼 있음) |

### 4.1 형식: JSON + 버전 (`{"v":1,"kind":…}`)
Frame Rule
```json
{"v":1,"kind":"DELIM","end":"[CR][LF]","maxLen":4096}
{"v":1,"kind":"STXETX","stx":"[02]","etx":"[03]","escape":"[10]","maxLen":4096}
{"v":1,"kind":"FIXED","len":12}
{"v":1,"kind":"LENFIELD","offset":2,"size":2,"endian":"BE","adjust":0,"includesHeader":false}
공통 선택: "checksum":{"type":"NONE|SUM8|XOR8|CRC16_MODBUS","from":1,"to":-2}, "idleResetMs":200
```
Parse Rule
```json
{"v":1,"kind":"TEXT","trim":"{}","sep":"SPACE|COMMA|TAB","count":3,"map":"CHANNELS|SAMPLES","number":"INVARIANT"}
{"v":1,"kind":"INFO","trim":"{}","sep":"COMMA","fields":["CH1","CH2","CH3","CH4"],"absent":"000"}
{"v":1,"kind":"BINARY","fields":[{"key":"CH1","offset":3,"type":"I16","endian":"LE","scale":0.01,"valueOffset":0}]}
```
- 바이트 표현(`[CR]`, `[02]`)은 `ProtocolExpression` 문법을 그대로 사용 → 한 문법.
- 과거 GTEC 텍스트 규칙(`FRAME=CRLF;…;MAP=CHANNELS`)은 **읽기 호환**: 파서가 JSON으로 변환. 새로 저장할 때는 JSON.
- 바이너리 타입: `U8 I8 U16 I16 U32 I32 F32 F64`, endian, `scale`·`valueOffset`(값 보정; `offset`은 바이트 위치). 가변 길이는 `LENFIELD`로.
- 검증: 서버 저장 시 형식 검사(INVALID_VALUE) — C5. Desktop은 읽을 때 같은 검사, 실패 시 해당 프로토콜 비활성 + 오류 보고.

---

## 5. VirtualTransport — 범용 시뮬레이터 + 장치별 프로파일

```text
VirtualTransport ── SimulatorEngine ── DeviceProfile (데이터, 코드 아님)
```
프로파일(JSON, Desktop 배포 리소스 `profiles\*.json`, 1차는 DB 아님)
```json
{
  "profileId":"GTEC_SCIENCE_CUBE", "v":1,
  "frame":{"kind":"DELIM","end":"[CR][LF]"},
  "vars":{"mode":"ANALOG","intervalMs":100,"running":false,"highChannel":1},
  "responses":[
    {"match":"S{20}",        "reply":"{${sensor1},000,000,000}[CR][LF]"},
    {"match":"S{10,1}",      "set":{"running":true}},
    {"match":"S{10,0}",      "set":{"running":false}},
    {"matchRegex":"S\\{12,(?<ms>[0-9.]+)\\}", "set":{"intervalMs":"${ms*1000}"}}
  ],
  "streams":[
    {"when":"running && mode=='ANALOG'","everyMs":"${intervalMs}",
     "frame":"{${ch1} ${ch2} ${ch3}}[CR][LF]"}
  ],
  "generators":{"ch1":{"type":"sine","amp":1,"periodMs":5000},"ch2":{"type":"ramp"},"ch3":{"type":"random","min":0,"max":5}},
  "faults":{"dropRate":0,"delayMs":0,"garbageRate":0,"disconnectAfterMs":0}
}
```
- 엔진 기능: 요청 매칭(표현식·정규식) → 응답/변수 변경, 조건부 연속 송신, 값 생성기(constant, sine, ramp, random, sequence, replay 파일), **장애 주입**(지연·누락·쓰레기 바이트·끊김·조각 나눔).
- 기본 프로파일: `GTEC_SCIENCE_CUBE`(과거 `ScLoggerVirtualConnection` 동작 참고), `GENERIC_ECHO`, `GENERIC_STREAM`.
- 같은 Framer·Parser·Scheduler 경로를 거침 → 실제 장비와 같은 코드 경로 시험.
- 장치와 프로파일 연결: 가상 장치의 로컬 연결값 `{"transport":"VIRTUAL","profile":"GTEC_SCIENCE_CUBE"}`.

---

## 6. Data Mapping — 식별자 분리

| 식별자 | 구성 | 출처 |
|---|---|---|
| **DeviceRef** | `DEV_CD` | ju_device |
| **ChannelRef** | `DEV_CD` + `ChannelKey`(문자열) | Parser 출력: TEXT=위치(`"1"`,`"2"`), INFO/BINARY=필드 key(`"CH1"`, `"TEMP"`) |
| **Sample** | `SampleIndex` | SAMPLES 모드 |
| **LogicalDataRef** | `DAT_GR_CD` + `DAT_CD` + `DAT_IDX` | ju_data_tag |

매핑 규칙 (제안, C5 신규 테이블 `ju_data_channel_map`)
```text
DEV_CD, CHANNEL_KEY, (PTL_CD 선택: 특정 응답에서만)
  → DAT_GR_CD, DAT_CD, DAT_IDX, TRANSFORM{scale, offset, formulaRef?}, USE_YN
```
- 한 채널 → 여러 논리 Data 가능(원값·환산값), 여러 채널 → 한 논리 Data는 수식 단계(후속).
- 출력 `LogicalValue{DeviceRef, ChannelRef, SampleIndex, LogicalDataRef, Value, Unit, Quality(GOOD|RANGE|PARSE_ERR|STALE), DeviceTime?, ReceivedAt}`.
- 현재 `TAG_ID='CH1'` 관례는 **C1~C3 동안만 임시 매핑(legacy fallback)** 으로 사용하고, 매핑 테이블이 생기면 자동 변환. 코드에 `CH<n>` 고정 안 함 — Mapper는 매핑 목록만 받는다.
- 단위·범위 검사: `ju_data_tag(_detail)`의 DAT_UNIT, DAT_MIN/MAX → Quality.

---

## 7. 기존 계약·정책과의 영향

| 대상 | C1~C3 (Desktop 내부) | C4 (내려받기 API) | C5 (스키마·계약) | C6 (Gateway) |
|---|---|---|---|---|
| **Action Contract v1** | 영향 없음 | 영향 없음 | Protocol 계약에 `ptlRoles`, `frameRule`, 패턴 의미 확정 추가 → **v2로 함께 설계**(이미 보류한 clearable 포함). v1 호출은 유지 | Device 계약에 부모·주소 추가(v2) |
| **Protocol CRUD** | 영향 없음 | 읽기만 | 검사 추가(규칙 JSON·역할 코드), seed 데이터 정정 migration | 링크 CRUD 추가 |
| **Client 인증** | 영향 없음 | `GET /api/core/sync/protocols`, `/sync/data-map` — 기존 Client 키 체인, 응답 형식은 SYNC-01 `{revision, items, removed}`와 맞춤 | — | — |
| **SEC-S1** | 영향 없음 | **GET만** → SEC-S1(`/api/core/sync/**` 쓰기 차단)과 일치 | — | — |
| 장치 정의 소유 | Terminal은 서버 정의를 읽기만, 연결값은 로컬 파일 | 같음 | — | 링크도 서버 정의 |
| 업로드(Runtime·실험 데이터) | 없음 | 없음 | 없음 | **별도 Experiment Data 단계**: `/api/client/**` POST + 멱등키(기존 `CLIENT_ID+LOCAL_*_ID` 구조) |
| IPC | 메시지 **추가만**(`DATA_VALUES`, `RECONNECTING`, `COMMAND_RESULT`), 기존 유지 | — | — | 하위 상태 메시지 |
| DB | 없음 | 없음 | migration (번호는 SYSINFO-02의 07 `ju_schema_version`과 조율) | migration |
| 의존성 | `System.IO.Ports`, 테스트 프레임워크 — **승인 필요** | — | — | — |

## 8. C1~C3 착수 시 인터페이스 목록 (구현 아님, 계약만)
| 인터페이스 | 핵심 멤버 |
|---|---|
| `ITransport` | `OpenAsync`, `CloseAsync`, `WriteAsync(byte[])`, `event Received(ReadOnlyMemory<byte>)`, `State`, `LinkCaps{fullDuplex, maxInFlight}` |
| `IFramer` | `Push(ReadOnlySpan<byte>) → IReadOnlyList<Frame>`, `Reset()` (Frame Rule로 생성) |
| `IFrameParser` | `TryParse(Frame, out IReadOnlyList<RawValue>)` (Parse Rule로 생성), `RawValue{ChannelKey, SampleIndex, Value, Text?}` |
| `ICommandScheduler` | `EnqueueAsync(CommandRequest) → CommandResult`, `CancelDevice(devCd, roles?)`, `event Unmatched(Frame)` |
| `IDeviceSession` | `StartAsync/StopAsync`, `ExecuteAsync(ptlCd)`, `event Values(LogicalValue[])`, `State` |
| `IDataMapper` | `Map(DevCd, PtlCd, RawValue[]) → LogicalValue[]` |
| `ISimulatorProfile` | 프로파일 JSON 로더·검증 |

## 9. 결정 요청
| # | 질문 | 제안 |
|---|---|---|
| C0-Q1 | Gateway 모드 `TRANSPARENT`/`ADDRESSED` 두 가지로 시작 | 예 (seed의 NET_GTEC01은 TRANSPARENT) |
| C0-Q2 | 기본 실행은 Link당 직렬, 병렬은 명시 설정만 | 예 |
| C0-Q3 | 상태 전이 명령(START 등)은 자동 재시도 안 함 | 예 |
| C0-Q4 | Role 복수 허용 + `PTL_ROLES` 코드 목록 | 예 (C5) |
| C0-Q5 | Frame/Parse Rule을 JSON(`v`,`kind`)으로, 과거 텍스트는 읽기 호환 | 예 |
| C0-Q6 | 시뮬레이터 프로파일은 1차 Desktop 리소스 파일 | 예, DB 저장은 후속 |
| C0-Q7 | 매핑 테이블 `ju_data_channel_map` 신설, 그 전엔 `TAG_ID=CH<n>` 임시 사용 | 예 (C5) |
| C0-Q8 | Protocol·Device 계약 확장을 Contract v2(clearable 포함)로 묶음 | 예 |

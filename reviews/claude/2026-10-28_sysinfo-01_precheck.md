# SYSINFO-01 사전 조사 — 서버/클라이언트 환경정보와 동기화 구조

- 일시: 2026-10-28 (PC-A 작업일)
- 기준 코드: juprovider `origin/feature/protocol-ref` @ `157635a` (main `fce5048` + PR-1·PR-2)
- 범위: 조사 + 설계안만. **제품 코드 수정 없음, push 없음**

## 0. PR-2 검토 상태 / 작업 브랜치

| 항목 | 상태 |
|---|---|
| PC-A juprovider | HEAD = `feature/protocol-ref` @ `157635a` = origin 동일, main `fce5048` |
| PR-1 `02ab18c` | 사용자 검토 PASS(10/27 16:39) |
| PR-2 `157635a` | PC-A PASS + PC-B 재현 PASS. **ChatGPT 검토 문서 없음** (`reviews/chatgpt/` 최신 10/26) → 검토 대기 |
| PR-3 Protocol Vue | 같은 브랜치에서 이어서 진행 예정. 이번 턴은 지시대로 코드 수정 안 함 → 착수 지시 대기 |

## 1. 현재 구조 조사 결과 (항목 1~8)

**1) 서버 배포·API·DB 스키마 버전**
- WAR: `pom.xml` `1.0.0` 고정(core는 `1.0.0-SNAPSHOT`). Jenkins는 빌드 번호·commit을 WAR에 넣지 않음. 백업 파일명 timestamp만 있음.
- API: `GET /api/health` → `{status, application}`만. 버전·commit 없음. API 전체 버전 없음. Action 단위 `contractVersion`(PR-1)만 있음.
- DB: baseline 헤더 주석 "V2.4"뿐. **스키마 버전 테이블 없음** (Flyway 등 없음). migration 03~06은 수동 적용. 적용 기록은 worklog에만 있음.

**2) Desktop EXE/DLL 버전 · 실행 설정**
- csproj/Directory.Build.props에 `Version/FileVersion` 없음 → 모든 EXE/DLL `1.0.0.0`.
- `Directory.Build.props`는 출력 경로만 정함 (client→`app\`, terminal/updater→`app\service\`, lib→`app\libs\`, control→`app\control\`).
- Updater(`service/juprovider.service.updater`)는 빈 Form1 stub.
- `ju_sys`에 정책값만 있음: `UPDATE_CHECK_MODE=FULL_AND_MODULE`, `DEPLOY_MODE=SELF_CONTAINED`, `DOTNET_VERSION=10.0`, `CLIENT_MODULE_UPDATE`, `ACE_PROVIDER`, `CLIENT_LOG_PATH`, `CLIENT_PROJECT_PATH`, `CLIENT_DEFAULT_PROJECT`, `DEVICE_LOG_PATH`. **Client가 읽는 코드 없음.**
- 실행 설정은 `app\config\client.json`(ServerUrl, ClientId, ClientKey)뿐.

**3) client.json / template.accdb / 로컬 DB / 서버 DB**
| 파일 | 역할 | 생성 | 저장소 |
|---|---|---|---|
| `config\client.json` | 서버 주소 + Client 자격 | PC별 (등록 스크립트) | 없음(비밀 포함, 올리면 안 됨) |
| `config\template.accdb` | 빈 ACCDB 컨테이너. ADOX 없이 `File.Copy`로 로컬 DB를 만들기 위함. 테이블은 코드가 `CREATE TABLE`로 만듦 | 공통 배포물 | **없음** (`desktop/app/` gitignore) → PC-B 실행 실패 원인 |
| `data\juprovider.accdb` | 로컬 DB: LOCAL_USER(오프라인 자격), LOCAL_DEVICE(서버 장치 사본), LOCAL_SYNC_STATE(생성만, 미사용) | PC별 최초 실행 | 없음 |
| 서버 MariaDB | 공통 정의(장치·프로토콜·데이터·실험·메뉴·사용자) + Client별 테이블 | 서버 | baseline/seed/migration |

- template에 예전 구성의 LOCAL_USER가 들어 있었음 (JU-1c에서 재생성으로 처리).

**4) Device/Protocol/Data 동기화 경로**
- Device: `GET /api/core/sync/devices` (Client chain, `X-JU-Client-Id/Key`) → Redis 캐시 → 활성 장치 전체 → `LocalDeviceRepository.UpsertAllAsync` → `LOCAL_DEVICE` → IPC(`DeviceSync`)로 Terminal 메모리(`DeviceRuntimeManager`).
- 호출 시점: 로그인 직후 + MainForm 메뉴 "동기화".
- Protocol/Data/Experiment: **Client 동기화 없음**. 서버에는 레거시 조회 `/api/core/protocol-groups`, `/protocols/{grp}`, `/data-groups`, `/data-tags/{grp}`, `/experiments`만 있음 (Client 미사용).
- 역방향: `PUT /api/core/sync/devices/{devCd}`(Client→서버 장치 INSERT/UPDATE)와 `JuProviderApiClient.SaveDeviceAsync`가 있으나 **호출하는 곳 없음**. 이 경로가 열리면 한 PC가 공통 장치 정의를 바꿀 수 있음 → 원칙 위반 위험.

**5) ClientId별 구분**
- 서버 `ju_device`·`ju_device_detail`에는 CLIENT_ID가 없음 → 장치 설정이 **전역 1벌**.
- 그런데 PC마다 다른 물리 연결값이 공통 정의에 들어 있음. 예: seed 장치 설명 `COM6 / 115200`, `localhost:5000`. 연결값은 `DEV_CONFIG`·`DEV_DESC`에 있고 지금은 대부분 NULL/설명문.
- 실행 상태: `ju_runtime_data` PK = CLIENT_ID+DEV_CD+DAT_GR_CD+DAT_CD+DAT_IDX (Client 구분 O, 쓰기 경로 없음, 조회만), `ju_experiment_run.CLIENT_ID`, `ju_experiment_command.CLIENT_ID` (명령 대상 Client) — 테이블만 있음.
- 로컬 `LOCAL_DEVICE`에는 연결 상태·Client별 override 컬럼 없음 (SYNC_DT/SYNC_STATE뿐). Terminal 장치 상태는 메모리에만 있음.

**6) 데이터 출처 분류 (현재 테이블 기준)**
| 분류 | 원본 | 해당 |
|---|---|---|
| 서버 원본 (공통 업무정의·정책) | 서버 | ju_device(+detail), ju_protocol_group/protocol/packet, ju_data_group/tag, ju_experiment(+data_group), ju_com_*, ju_menu*, ju_language/multi_lang, ju_sys, ju_auth, ju_user |
| 클라이언트 원본 (→서버 보고) | Client | ju_runtime_data, ju_experiment_data, ju_experiment_run(실행 결과), ju_client_audit_hist, ju_client_error_log, ju_client_sync_receipt(수신 확인), (신규) Client 환경정보·장치 연결 상태 |
| 로컬 전용 | Client | client.json(ClientKey), LOCAL_USER 오프라인 자격·잠금, 로그, (신규) PC별 장치 연결값 override, 동기화 커서 |
| 서버 관리 Client 메타 | 서버 | ju_client(+detail): 키 해시, USE_YN, LAST_SEEN_DT |

- 테이블은 있지만 쓰기 API가 없는 것: ju_client_audit_hist, ju_client_error_log, ju_client_sync_receipt, ju_runtime_data, ju_experiment_data. 모두 `(CLIENT_ID, LOCAL_*_ID)` UNIQUE로 멱등 업로드를 전제한 설계.

**7) 전체/증분 동기화**
- 현재는 **전체 동기화만**. 서버는 활성 장치 전부를 반환함. `since`·revision 없음.
- 로컬은 upsert만 함 → **서버에서 비활성·삭제된 장치가 LOCAL_DEVICE에 남음**. 활성만 내려오고 USE_YN 변경이 반영되지 않아 결함 후보.
- 서버 테이블에 UPD_DT·revision 컬럼이 없어 증분 기준도 없음.

**8) 새 PC 설치 파일**
| 공통 배포 (모든 PC 동일) | PC별 생성 |
|---|---|
| `app\*.exe/dll`, `app\service\`, `app\libs\`, `app\control\`, `config\template.accdb`, (권장) `config\client.sample.json` | `config\client.json` (등록 스크립트, Key 1회), `data\juprovider.accdb`, `logs\`, (신규) 로컬 override·커서 |
- 현재 공통 배포물을 만드는 공식 경로가 없음. Jenkins는 WAR만 만들고, Desktop은 로컬 빌드 결과(`desktop\app`)를 그대로 사용함. template은 PC-A 로컬에만 있음.

## 2. 설계 원칙 적용 — 네 가지 버전을 분리

| 버전 | 의미 | 보관 | 비교 주체 |
|---|---|---|---|
| Server Build Version | WAR 버전 + commit | WAR manifest → `/api/health`·sysinfo | 운영자 |
| DB Schema Version | 적용된 migration 번호 | 서버 DB `ju_schema_version`(신규) | 서버 기동 시 확인 |
| Client Build Version | Desktop 묶음 버전 + EXE/DLL FileVersion | Assembly 속성 → Client가 보고 | Updater/서버 정책(`ju_sys`) |
| Action Contract Version | Action별 `contractVersion` (기존 PR-1) | ju_menu_action / Handler | Action 호출 시 |
| Sync Revision | 데이터 변경 순번 (엔터티 유형별) | 서버 단조증가 값, Client는 마지막 수신 값 | 동기화 시 |

- 서로 대체하지 않음. 배포 버전이 같아도 Sync Revision은 계속 증가함. Contract Version은 Action 단위로만 바뀜.

## 3. 지금 확정할 최소 계약 (S1~S7) — 승인 시 별도 구현 계획 작성

| # | 계약 | 내용 | 영향 |
|---|---|---|---|
| S1 | 데이터 출처 3분류 | §1-6 표를 규칙으로 확정. Client는 서버 원본을 **수정 API로 바꾸지 않는다** → `PUT /api/core/sync/devices/{devCd}` 사용 금지(후속 제거 또는 관리자 전용 이동 결정 필요) | 원칙 고정 |
| S2 | 장치 설정 범위 = ClientId+DeviceId | 공통 정의(`ju_device`)는 전역. PC별 연결값(포트, IP, 보레이트 등)은 **로컬 override**로 둔다. 서버 보관이 필요하면 `ju_client_device`(CLIENT_ID, DEV_CD, 연결값 JSON, 사용여부)로 분리. 공통 정의에 PC별 값을 넣지 않음 | 다른 Client 영향 차단 |
| S3 | 버전 4종 분리 + 노출 | `/api/health`(또는 `/api/client/sysinfo`)에 serverVersion·commit·schemaVersion 응답. Desktop은 `Directory.Build.props`에 공통 Version 1곳 | 조회만, 기존 계약 무변경 |
| S4 | Client 환경정보 보고 | `POST /api/client/sysinfo` (Client chain, 기존 X-JU-Client 인증 그대로): clientVersion, 모듈별 FileVersion, OS, .NET, ACE provider 유무, 마지막 동기화 Revision. 서버는 `ju_client` 1:1 최신값만 저장(이력은 후속) | 신규 테이블 1개 또는 컬럼 |
| S5 | Sync 응답 계약 | 전체 동기화 응답에 `revision`과 비활성 포함 목록(또는 `deleted` 키 목록) 추가. Client는 응답에 없는/비활성 장치를 로컬에서 비활성 처리. **증분은 아직 안 함**. 단, 응답 모양은 증분과 호환되게 `{revision, items, removed}` | 기존 GET 응답 형식 변경 → 계약 변경 승인 필요 |
| S6 | 오프라인 유지 | 서버 실패 시 로컬 사본으로 동작(현행 유지). 동기화 실패가 로컬 사본을 지우지 않음. 서버 4xx/CLIENT_REJECTED 정책(JU-1c) 그대로 | 무변경 |
| S7 | 설치 파일 분리 | 공통 배포 / PC별 생성 목록(§1-8) 확정. `template.accdb`는 저장소 `desktop/resources/template.accdb`에 두고 빌드 시 `app\config\`로 복사(또는 코드로 빈 DB 생성 — 택1 결정). `client.sample.json` 제공 | PC-B 문제 해소 |

## 4. 후속 단계로 미룰 항목

- 증분 동기화(`since=revision`), 엔터티별 revision 컬럼·트리거, 충돌 처리
- Protocol/Data/Experiment Client 동기화 (Protocol은 PR-3 이후 S5 형식으로 추가)
- Client→서버 업로드: runtime_data, experiment_data, audit_hist, error_log, sync_receipt (멱등 키는 이미 있음)
- 서버→Client 명령(`ju_experiment_command`) 전달 방식
- Updater 구현 (`UPDATE_CHECK_MODE` 전체 ZIP + 모듈 FileVersion 비교), 배포 묶음 서명·저장 위치
- Client가 `ju_sys` 정책 수신·적용
- 스키마 버전 자동 migration 도구 도입 (Tool 설치 → 별도 승인)
- sysinfo 이력 보관, Web 관리 화면(Client 목록에 버전·마지막 접속·동기화 상태)
- DPAPI ClientKey 보호, Terminal IPC 인증 (JU-1c 보고 항목)

## 5. 결정 요청

| # | 질문 | Claude 제안 |
|---|---|---|
| SI-Q1 | PC별 연결값을 서버에도 둘지 | 1단계는 로컬 override만, 서버 `ju_client_device`는 후속 |
| SI-Q2 | 기존 `PUT /api/core/sync/devices/{devCd}` 처리 | Client chain에서 막고(제거), 장치 편집은 Action(관리자)로만 |
| SI-Q3 | template.accdb | 저장소 `desktop/resources/`에 두고 빌드 후 복사 |
| SI-Q4 | 스키마 버전 기록 | `ju_schema_version` 테이블 + migration 끝에 INSERT (도구 도입 없이) |
| SI-Q5 | S5 응답 형식 변경 시점 | Desktop과 서버 동시 반영. PR-3 이후 별도 단계(SYSINFO-02) |
| SI-Q6 | 진행 순서 | PR-2 검토 → PR-3 Vue → SYSINFO-02(S3·S4·S7) → SYSINFO-03(S2·S5) |

## 6. 발견 사항 (코드 미수정, 보고만)
1. 비활성·삭제 장치가 로컬에 남음 (upsert만, 서버는 활성만 반환).
2. `PUT /api/core/sync/devices/{devCd}`: Client 자격으로 공통 장치 정의를 INSERT/UPDATE할 수 있음 (Client 미호출).
3. `ju_sys` Client 정책값을 읽는 코드 없음.
4. 버전 정보 노출 없음 (health, EXE/DLL 모두).
5. template.accdb가 저장소에 없음.
6. `LOCAL_SYNC_STATE`는 생성만 하고 사용하지 않음. 커서 저장 후보.

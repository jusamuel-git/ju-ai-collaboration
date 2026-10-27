# Protocol Reference Implementation 구현 계획 (2026-10-27, 코드 수정 전)

결정: [decisions/CURRENT.md](../../decisions/CURRENT.md) AC1~AC13. 설계: [action-contract_designer_design](2026-10-27_action-contract_designer_design.md)
범위 밖: Designer · Renderer · Publish · 계약 조회 API · Desktop Protocol 동기화 · Device Action 정리

## 1. 단계와 commit (JU-1과 같은 방식: 단계별 로컬 commit → 마지막 단계까지 Build/Smoke 후 함께 push)
| 단계 | 브랜치 | 내용 | 검증 |
|---|---|---|---|
| **PR-1 Action Contract Core** | `feature/action-contract` (← main `fce5048`) | 계약 모델·검증기·오류 계약·실행 맥락·MNU_CD 경로·기동 정합성 검사 | 빌드 5종 + 단위 테스트(검증기·오류 매핑) + Device 기존 smoke(menuId 경로 회귀 없음) |
| **PR-2 Protocol Backend** | `feature/protocol-ref` (← PR-1) | migration 06, baseline/seed, Protocol DAO/Service/Handler 10개, 다국어 키 규칙 | 빌드 5종 + 06 테스트 DB(1·2회, 신규 설치 동일) + Action API smoke |
| **PR-3 Protocol Vue** | 같은 브랜치 다음 commit | `ProtocolManagement.vue`, `actionApi.executeByCode`, 라우트, `/api/core/protocol*` 제거 | 빌드 5종 + 브라우저 smoke + 비관리자 화면 |
| 통합 | — | 실제 DB 06 적용(백업 후, 사용자 승인) → 18081 통합 확인 → push → Jenkins | 사용자 확인 |

## 2. PR-1 Action Contract Core (juprovider.core `action` + backend)
**계약 모델** (`core/action/contract`)
- `ActionContract { int contractVersion; OutputKind outputKind; List<FieldSpec> input; List<FieldSpec> output; }`
- `FieldSpec { name; FieldType type; boolean required; Integer maxLength; String codeGroup; List<FieldSpec> items /*object·list 원소*/ }`
- `FieldType` 8종, `OutputKind { LIST, RECORD, KEY, NONE }`
- `ActionHandler`에 `default ActionContract contract() { return null; }` 추가 → **계약이 없는 Handler(Device 2개)는 기존 방식 그대로** (검증·출력 변환 없음). Device 화면 회귀 없음

**contractVersion (AC11)**
- 요청 본문: `{ "contractVersion"?: n, "parameters": {…} }` (기존 형태에 선택 필드 추가)
- 서버는 Handler 계약의 `contractVersion`을 응답에 포함 (`"contractVersion": 1`)
- 요청에 version이 있고 서버 계약과 다르면 `400 VALIDATION / CONTRACT_VERSION_MISMATCH` (여러 version 동시 지원은 Designer 단계에서 필요 시 추가)
- 규칙: 비파괴 변경(선택 입력·출력 필드 추가)은 version 유지, 파괴적 변경(이름·형·필수·kind)은 version 증가, 업무 의미 변경만 새 ACT_CD

**검증기** (`ActionInputValidator`)
- 필수 누락 `REQUIRED`, 형 불일치 `TYPE_MISMATCH`, 길이 `MAX_LENGTH`, 코드그룹 외 값 `INVALID_CODE`(ju_com_code 사용 중 값), **미선언 필드 `UNKNOWN_FIELD`(AC12, 중첩 포함)**
- 필드 경로 표기: `packets[2].direction`
- 결과: 검증된 값만 담은 `ActionInput`(형 변환 완료)을 Handler에 전달

**오류 계약 (AC5)**
- `ApiResponse`에 `code`, `errors`, `contractVersion` 추가 (null이면 JSON에서 생략 → 기존 응답 모양 유지)
- 예외: `ActionValidationException`(400) · `ActionNotFoundException`(404: 대상 데이터·정의되지 않은 Action) · `ActionConflictException`(409) · `ActionNotImplementedException`(501). `PermissionDeniedException` 403, 인증 401은 기존 유지
- `GlobalExceptionHandler`에 위 매핑 추가. 기존 `IllegalArgumentException` → 400은 유지 (Device 호환)

**실행 맥락·트랜잭션 (AC6)**
- `ActionRequest`에 `ExecutionContext context`, `langCd`, `requestId`(UUID, 응답 헤더 `X-JU-Request-Id`), `ActionInput input` 추가. 기존 생성자·getter 유지
- `DynamicActionService.executeByCode(mnuCd, actCd, …)`: 메뉴 조회(MNU_CD) → 권한(호출 대상 메뉴, AC2) → 계약 검증 → 실행 → 출력 kind 확인
- 쓰기 kind(ACT_KIND 02/04/08/10)는 `TransactionTemplate`로 Handler 실행을 감싼다

**경로 (AC1)**
- `POST /api/action/{mnuCd}/{actCd}` — `mnuCd`는 `^M\d{8}$`만 허용(그 외 400). 기존 `/api/action/{menuId}/{actCd}`(숫자)와 경로 충돌 없음
- `MenuMapper`에 `selectMenuByCode`, `selectActionByCode` 추가 (소문자 테이블명)

**정합성 (AC7)**
- `ApplicationReadyEvent`에서 활성 `ju_menu_action.HANDLER_ID` 중 Registry에 없는 것 WARN 1줄 목록 (현재 Device 8개 예상)
- 호출 시 Handler 없음 → 501

## 3. PR-2 Protocol Backend
**migration `06_protocol_actions.sql`** (재실행 안전, 스키마 변경 없음)
- `M02010100`에 Action 10개 + `ju_menu_action_detail` + `ju_multi_lang`(LANG0001/0002 Action명)
  | ACT_CD | ACT_KIND | HANDLER_ID |
  |---|---|---|
  | GRP_SEARCH, GRP_GET, SEARCH, GET | MACT0001 (01) | PROTOCOL.GRP_SEARCH … PROTOCOL.GET |
  | GRP_CREATE, CREATE | MACT0003 (02) | PROTOCOL.GRP_CREATE, PROTOCOL.CREATE |
  | GRP_UPDATE, UPDATE | MACT0004 (04) | … |
  | GRP_DELETE, DELETE | MACT0005 (08) | … |
- `INSERT … SELECT … WHERE NOT EXISTS`, `MNU_ID`는 `MNU_CD`로 조회 (대리키 하드코딩 없음)
- baseline/seed 반영 → 신규 설치 = 기존 + 06

**Core `core/protocol`**: `ProtocolDao`+`ProtocolMapper.xml`, `ProtocolService`, `action/Protocol*Action` 10개(각자 계약 선언), `I18nKeys`
- 다국어 키 규칙 (AC9): `PROTOCOL_GROUP.{ptlGrpCd}.NM/.DESC`, `PROTOCOL.{ptlGrpCd}.{ptlCd}.NM/.DESC` — 기존 seed 키와 동일. 등록 시 detail에 키 저장 + `ju_multi_lang` LANG0001 값 upsert, 수정 시 LANG0001 값 갱신 (LANG0002는 이후 다국어 관리 화면)

**계약 요지 (모두 contractVersion 1)**
| Action | input | output |
|---|---|---|
| GRP_SEARCH | keyword?(string 100), useYn?(code YENO) | list: ptlGrpCd, ptlGrpNm, ptlGrpDesc, pollingIntval, timeoutMs, retryCnt, useYn, sortOrd, protocolCount |
| GRP_GET | ptlGrpCd(string 20) | record: 위 + ptlGrpNmKey |
| GRP_CREATE | ptlGrpCd, ptlGrpNm(100), ptlGrpDesc?(500), pollingIntval?, timeoutMs?, retryCnt?, sortOrd? | key: ptlGrpCd |
| GRP_UPDATE | 위 (ptlGrpCd 필수, 변경 불가) + useYn? | key |
| GRP_DELETE | ptlGrpCd | key — 활성 장치가 사용 중이면 409 |
| SEARCH | ptlGrpCd, keyword?, useYn? | list: ptlGrpCd, ptlCd, ptlType, ptlTypeNm, ptlLen, ptlNm, ptlDesc, useYn, packetCount |
| GET | ptlGrpCd, ptlCd | record: 위 + ptlVal + packets[list: packetSeq, packetType, direction, packetExpr, responsePtlCd, parseRule, dataCount, dataType, dataPosition, useYn] |
| CREATE | ptlGrpCd, ptlCd, ptlType(code PROT), ptlLen?, ptlVal?, ptlNm, ptlDesc?, packets?[list] | key: ptlGrpCd, ptlCd |
| UPDATE | 위 (packets 있으면 전체 교체) + useYn? | key |
| DELETE | ptlGrpCd, ptlCd | key — 활성 실험(`ju_experiment_data_group` START/PAUSE/STOP_PTL_CD)이 참조하면 409 |
- 논리 삭제 = `USE_YN=YENO0002`. 중복 키 등록 409. 없는 대상 404

## 4. PR-3 Protocol Vue
- `actionApi.executeByCode(mnuCd, actCd, parameters, { contractVersion })` 추가 (기존 `execute` 유지)
- `views/device/ProtocolManagement.vue`: 좌측 그룹 Grid(GRP_SEARCH) → 우측 프로토콜 Grid(SEARCH) → 상세 Form(GET) + 패킷 목록 편집 → 저장(CREATE/UPDATE)·삭제(DELETE). 그룹 등록·수정 Dialog
  - Designer가 이후 만들 구성(Grid·Form·Button·Dialog)과 같은 단위로 나누고, **모든 데이터는 Action으로만** 호출
  - 버튼은 `/me`의 `M02010100` 비트(01/02/04/08)로 표시 여부 결정
  - 필드 오류(`errors[].field`)를 해당 입력 옆에 표시
- 라우트 `/console/device/protocol`, `meta.menuCode: 'M02010100'` (DB `MNU_URL`과 일치)
- `CoreController`/`CoreQueryService`/`CoreQueryDao.xml`의 `protocol-groups`, `protocols/{grp}` 제거 (AC10. 현재 사용처 없음 확인)

## 5. 검증 계획 (PC-A)
- 단위 테스트: 검증기(필수·형·길이·코드·UNKNOWN_FIELD·중첩 경로·version 불일치), 다국어 키 규칙, 출력 kind 확인
- 테스트 DB(실제 DB 덤프 사본) + 18081 Action smoke:
  - 관리자: GRP/Protocol CRUD 200, 응답 `contractVersion=1`, `list={items,total}`, `key` 모양
  - 비관리자(`01`): 조회 200, 쓰기 403
  - 400 VALIDATION(REQUIRED/TYPE_MISMATCH/UNKNOWN_FIELD/INVALID_CODE/CONTRACT_VERSION_MISMATCH), 404(없는 대상·정의 안 된 ACT_CD), 409(중복·사용 중 그룹), 501(`DEVICE.CREATE`)
  - 다국어 키가 규칙대로 생성, `ju_multi_lang` LANG0001 반영
  - 기존 menuId 경로 Device SEARCH/GET 회귀 없음, 기동 WARN 목록에 Device 8개
- 06: 1·2회 적용 무변경, 신규 설치 = 기존 + 06
- 브라우저 smoke: 관리자 CRUD 흐름, 필드 오류 표시, 비관리자 버튼 숨김

## 6. 구현 전 확인할 것 (사용자/ChatGPT)
| # | 질문 | Claude 기본안 |
|---|---|---|
| Q1 | 그룹 등록 시 기본 프로토콜 `{그룹}0000`("기본 TX/RX", seed 주석 "그룹 생성 시 자동 생성") 자동 생성? | 자동 생성 |
| Q2 | `PTL_CD` 형식을 `그룹코드 + 숫자 4자리`로 강제? (seed는 모두 이 형식) | 강제하지 않음, 길이 20만 검사 |
| Q3 | 그룹 삭제 시 하위 프로토콜 | 함께 논리 삭제 (장치 사용 중이면 409) |
| Q4 | `PTL_VAL`(기존 호환 설정값) 편집 허용 | 허용 (패킷 정의와 병행, 이후 정리) |
| Q5 | 비관리자 `M02010100` 권한 `01` 유지 | 유지 (조회만) |

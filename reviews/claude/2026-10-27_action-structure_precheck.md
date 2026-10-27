# Action 호출 구조 재확인 — Protocol 첫 정식 적용 전 (2026-10-27, 코드 수정 없음)

기준: juprovider main `fce5048`. 전제: `MNU_CD` 4단계(`M` + 2자리×4, 현재 최대 3레벨) 유지.

## 1. 현재 구조 (실제 호출 경로)
```
Vue actionApi.execute(menuId, actionCode, parameters, langCd)
 → POST /api/action/{menuId}/{actionCode}?langCd=   (DynamicActionController, 사용자 JWT + PW_OK)
 → DynamicActionService.execute(menuId, actCd, langCd, params, ExecutionContext)
     1) PermissionService.checkAction: ju_menu_action(MNU_ID, ACT_CD, USE/ENABLED=Y) + ju_menu(USE/ENABLED=Y)
        → ACT_KIND → ju_com_code MACT.COM_VAL(비트) → AUTH_ATTR "메뉴코드+비트" 검사 (없으면 403)
     2) MenuService.getMenu / getAction(menuId, actCd, langCd) → HANDLER_ID
     3) ActionRegistry.execute(HANDLER_ID, ActionRequest(menuCode, actionCode, parameters))
 → ActionHandler(@Component, getHandlerId()) → 업무 Service
 → ActionResult ok/fail → ApiResponse (fail은 IllegalArgumentException → 400)
```
| 요소 | 위치 | 상태 |
|---|---|---|
| `ju_menu_action` | `ACT_ID`, `MNU_ID`, `ACT_CD`(20), `ACT_KIND`(MACT), `HANDLER_ID`(100), USE/ENABLED, SORT · UK(MNU_ID, ACT_CD) | JU-0A에서 정식화 |
| `ju_menu_action_detail` | `ACT_NM/DESC` + `ACT_NM_KEY/DESC_KEY`(다국어) | 있음 |
| MACT 비트 | 조회 01 · 실행 10 · 등록 02 · 수정 04 · 삭제 08 · 내보내기 20 | 있음 (JU-1B 권한 검사에 사용) |
| `ActionRegistry` | 기동 시 `ActionHandler` Bean 수집, ID 공백·중복이면 기동 실패 | 있음 |
| `DynamicActionService` | 권한 → 메뉴/Action 조회 → Registry 실행 | 있음 |
| Handler | `DeviceSearchAction`(`DEVICE.SEARCH`), `DeviceGetAction`(`DEVICE.GET`) | **2개뿐** |
| 화면 | `DeviceManagement.vue`가 `menuId = 15` 하드코딩으로 SEARCH/GET 호출 | 1개 화면 |

**판정**: "메뉴 + Action 코드 → DB가 가리키는 Handler → 업무 Service" 골격은 구현되어 있다. 원래 구상의 `PROTOCOL.GET`·`DEVICE.GET`·`EXPERIMENT.START` 형태는 **`HANDLER_ID` 명명 규칙(도메인.동작)으로 구현**되어 있고, 호출 키는 `MENU_CD`가 아니라 **`MNU_ID`(대리키) + `ACT_CD`**이다.

## 2. Seed 현황
- Action 10개 모두 `MNU_ID 15 = M02010000`(2레벨 그룹 "시스템장치관리")에 붙어 있음: SEARCH/GET/CREATE/UPDATE/DELETE/CONNECT/DISCONNECT/STATUS/START/STOP → `DEVICE.*`
- Protocol 메뉴 `M02010100`(3레벨 leaf "프로토콜관리", URL `/console/device/protocol`)에는 **Action 없음**
- 실험 메뉴(`M02030xxx`)에도 Action 없음 → `EXPERIMENT.START` 등은 아직 미정의
- Protocol 데이터: `ju_protocol_group`(+detail) → `ju_protocol`(PK 그룹+코드, +detail) → `ju_protocol_packet`. `ju_device.PTL_GRP_CD` FK → 그룹. seed: GTEC 17개, GETC 1개(미사용)

## 3. 빠진 부분 / 문제
| # | 내용 | 영향 |
|---|---|---|
| G1 | Handler 미구현 8개 (`DEVICE.CREATE` 외) — 호출 시 "등록되지 않은 Action Handler" → 400 | DB와 코드 불일치를 기동 때 알 수 없음 |
| G2 | DB `HANDLER_ID` ↔ Registry 정합성 검사 없음 | 오타·누락이 실행 시점에만 드러남 |
| G3 | 호출 키가 `MNU_ID`(설치마다 달라질 수 있음). 화면은 `15` 하드코딩 | `MENU_CD` 기반 구상과 다름 |
| G4 | Action이 leaf가 아닌 2레벨 그룹 메뉴에 붙음. Vue 라우트도 `M02010000` 사용, DB URL과 불일치(`/console/device/manage` vs leaf URL) | Protocol부터 기준 정해야 함 |
| G5 | `ActionRequest`에 실행 주체(`ExecutionContext`)·`langCd` 없음 — 컨트롤러의 `langCd`가 Handler로 안 넘어감 (`DeviceGetAction`은 parameters의 langCd를 찾음) | 등록·수정의 작성자 기록, 다국어 조회 불가 |
| G6 | 파라미터가 `Map<String,Object>` — 검증·형변환 규칙 없음 | Handler마다 제각각 |
| G7 | 오류 구분 없음: fail·없는 데이터·검증 오류 모두 400 | 404/409 등 구분 불가 |
| G8 | Action 단위 트랜잭션 규칙 없음 (조회만 있어서 미노출) | 쓰기 Action부터 필요 |
| G9 | 별도 조회 경로 `/api/core/protocol-groups`, `/api/core/protocols/{grp}` (CoreQueryService) — JWT+PW_OK만 검사, 메뉴 비트 검사 없음 | Action 권한을 우회하는 병행 경로 |
| G10 | `MenuMapper.xml`이 대문자 테이블명(`JU_MENU_ACTION`) 사용 — Windows MariaDB(lower_case_table_names=1)에서만 동작 | Linux 배포 시 위험 (보고만) |
| G11 | 화면이 허용 Action 목록을 받는 API 없음 (`/me`는 메뉴별 비트만) | 버튼 표시를 비트로 계산하거나 목록 API 추가 필요 |
| G12 | Desktop용 Protocol 동기화 API 없음 (장치만 `/api/core/sync/devices`) | Protocol 정식화 후 별도 단계 |

## 4. Protocol을 첫 정식 적용 대상으로 만들기 위한 변경 (제안)
**DB (migration 06, 재실행 안전, 스키마 변경 없음)**
- `M02010100`에 Action 추가 (leaf 메뉴 기준) + detail + `ju_multi_lang`(LANG0001/0002)
  | ACT_CD | ACT_KIND | HANDLER_ID | 내용 |
  |---|---|---|---|
  | SEARCH | MACT0001 | PROTOCOL.SEARCH | 그룹·프로토콜 목록 |
  | GET | MACT0001 | PROTOCOL.GET | 프로토콜 1건 + 패킷 |
  | CREATE | MACT0003 | PROTOCOL.CREATE | 등록 (그룹/프로토콜/패킷) |
  | UPDATE | MACT0004 | PROTOCOL.UPDATE | 수정 |
  | DELETE | MACT0005 | PROTOCOL.DELETE | 논리 삭제 (USE_YN, 장치 FK 고려) |
- baseline/seed 갱신 (신규 설치 = 기존+06)
- 권한: AUTH0001 `M02010100FF` (이미), 그 외 `01` → 비관리자는 조회만

**Core**
- `core/protocol/{dao,dto,service,action}` — `ProtocolService`(쓰기 `@Transactional`), Handler 5개
- `ActionRequest`에 `ExecutionContext`, `langCd` 추가 (G5) — 기존 Device Handler 호환 유지
- 기동 시 DB 활성 Action의 `HANDLER_ID`가 Registry에 없으면 WARN 목록 출력 (G2). Device 미구현 8개 때문에 실패로 하지 않음
- 오류 예외 구분: 검증 400 / 없음 404 / 충돌(사용 중 그룹 삭제 등) 409 (G7)

**API (계약 변경 — 결정 필요)**
- 추가: `POST /api/action/by-code/{mnuCd}/{actCd}` (MENU_CD 기반, G3). 기존 `/api/action/{menuId}/{actCd}`는 Device 화면용으로 유지
- `/api/core/protocol*` 조회 경로: Protocol 화면 전환 후 폐기 또는 유지 결정 (G9)

**Vue**
- `ProtocolManagement.vue` + 라우트 `/console/device/protocol`, `meta.menuCode: 'M02010100'`
- 버튼 표시: `/me`의 메뉴 비트로 계산 (G11, API 추가 없이)

**검증**: 빌드 5종 + 테스트 DB(06 1·2회, 신규 설치 동일) + Action smoke (관리자 CRUD 200, 비관리자 조회만 200·쓰기 403, 미정의 Action 400, 없는 데이터 404, 장치가 쓰는 그룹 삭제 409) + 브라우저 smoke

## 5. 결정 필요
| # | 항목 | Claude 권장 |
|---|---|---|
| P1 | 호출 키 | `MNU_CD` 경로 추가, `MNU_ID` 경로는 유지 후 Device 단계에서 정리 |
| P2 | Action 소속 메뉴 | leaf 메뉴(`M02010100`). Device Action의 `M02010000` → leaf 이동은 Device 단계에서 |
| P3 | Protocol Action 단위 | 위 5개 (그룹·프로토콜·패킷을 한 Action에서 `target` 파라미터로 구분) vs 그룹용 Action 별도(`GROUP_SAVE` 등) |
| P4 | `ActionRequest` 확장 (실행 주체·langCd) | 이번에 포함 |
| P5 | HANDLER_ID 정합성 검사 | WARN (실패 아님) |
| P6 | 삭제 | 논리 삭제(USE_YN=YENO0002), 사용 중 그룹은 409 |
| P7 | `/api/core/protocol*` 조회 경로 | Protocol 화면 전환 후 제거 (Desktop은 이후 Client 동기화 API로) |
| P8 | 다국어 | 등록 시 detail의 `*_NM_KEY` 자동 생성 + LANG0001 값만 `ju_multi_lang`에 저장 |

# JuProvider / JuProject 전체 구조·DB 현재 상태 조사 (2026-10-25, Claude, 1단계)

- 목적: ChatGPT가 구조·DB를 설계하기 전에 쓸 사실 자료
- 근거
  - GitHub `main` 코드: juprovider `d963da2`, juproject `98a94f0`
  - 노트북 실제 DB: juprovider 37개 테이블, juproject 4개 테이블
  - juprovider SQL: `database/baseline/01_ju_core_baseline.sql`, `02_ju_core_seed.sql`(V2.2)
- 출발점: `ai_juproject_db_status_2026-10-25.md`. juproject 테이블의 상세 컬럼은 그 문서에 있다.
- 이 단계에서는 아무것도 고치지 않았다. 대상: 소스, DB, Jenkinsfile, 문서
- 이 문서에는 판단을 넣지 않았다. 설계가 필요한 부분은 `[설계 필요]`로 표시했다.

상태 표기
- ✅ 사용 중: 코드에서 실제로 읽고 쓴다.
- 🟡 부분: 코드는 있지만 미완성이거나 조회만 한다.
- ⬜ DB만: 테이블이나 시드만 있고 참조하는 코드가 없다.
- ⚠️ 중복/과거: 중복되었거나 과거 구조일 가능성이 있다.

---

## 0. Git 상태 (노트북 `C:\MyData\MyDev\workspace`)

| 항목 | juprovider | juproject |
|---|---|---|
| branch | main | main |
| HEAD | `d963da2 docs: 작업 기록 갱신` | `98a94f0 docs: 작업 기록 갱신` |
| origin/main과 차이 | 없음 (ahead/behind 0) | 없음 (GitHub 최신과 같음) |
| staged / unstaged | 없음 (추적 파일의 수정 시각이 모두 clone 시각과 같음) | 없음 |
| untracked | 무시 대상만 있음 (`desktop/.vs`, `obj`, `desktop/app`, `juprovider.core/target`) | 무시 대상만 있음 |
| AI_COLLABORATION.md | v1.1 | v1.1 (내용 동일) |

AI_WORKLOG.md에 남아 있는 항목 (origin과 같음)

- **juprovider**
  - 다음 작업: 구조·테이블 정리
  - Jenkins 정리: 8081 하드코딩, options, archive, Node 재다운로드
  - setenv 완료
  - Vue history 404 가능성
  - desktop 빈 `Class1.cs` 5개
  - template.accdb 원본 위치
  - client 서버 주소 하드코딩
  - package.json `latest`
  - desktop/native 유지 방법
- **juproject**
  - 다음 작업: 구조·테이블 정리
  - lint 경고 3건, 번들 1.2MB
  - Frontend 배포 방식 보류
  - 시드 관리자 비밀번호가 평문으로 추적됨
  - README 없음
  - EF/Pomelo 9.x 버전

> 확인 방법 한계: 노트북에서 직접 `git status`를 실행할 수 없었다. 그래서 파일 수정 시각과 GitHub clone을 비교해서 판정했다.

---

## 1. 시스템 구성 개요

| 구분 | juprovider | juproject |
|---|---|---|
| Backend | Spring Boot 3.5.16 / Java 21 / WAR, 외부 Tomcat 10.1.52 (8081, `/juprovider`) | ASP.NET Core .NET 10 (Api / Application / Domain / Infrastructure) |
| 공통 모듈 | `juprovider.core` jar (backend가 Maven 의존성으로 참조, aggregator 없음) | 없음 (계층 프로젝트 4개) |
| DB 접근 | JPA (인증 엔티티 4개) + MyBatis (나머지 전부) | EF Core 9.0.21 + Pomelo 9.0.0 |
| 캐시/이벤트 | Redis (장치, 시스템코드 캐시, 장치 이벤트 발행) | 없음 |
| Frontend | Vue 3 + Vite (WAR `static`에 포함) | React 19 + TS + Vite + antd 6 (배포 방식 보류) |
| Desktop | .NET 10 WinForms (client / terminal / updater + lib), 로컬 Access DB | 없음 |
| 스키마 관리 | SQL baseline / seed / migration 파일 | EF Migrations (`InitialCreate` 1개) |
| CI | Jenkins `juprovider-ai`: core install → WAR → Tomcat 배포 → Health | Jenkins `juproject-ai`: build / publish / npm build / archive (배포 없음) |

---

## 2. [1] System / Organization

### 2-1. juprovider

| 항목 | DB 테이블 | PK / 업무키 | 주요 컬럼 | FK | Entity / Mapper | Service | API | Frontend | 상태 |
|---|---|---|---|---|---|---|---|---|---|
| **Site** | 없음 | — | — | — | — | — | — | 없음 | ⬜ 메뉴 시드에 site 관리 화면 URL만 있다. 공통코드 그룹 `SITE`는 값이 없다. **[설계 필요]** |
| **Dept** | 없음 | — | — | — | — | — | — | 없음 | ⬜ 공통코드 `DEPT`에 `DEPT0000` 1개만 있다. 메뉴 URL만 있다. **[설계 필요]** |
| **User** | `ju_user` + `ju_user_detail` | `USER_ID` / `LOGIN_ID`(uk) | `USER_PW_HASH`, `AUTH_ID`, `USE_YN`. detail: `USER_NM`, `PHONE_NO`, `EMAIL`, `LOGIN_FAIL_CNT`, `LAST_LOGIN_DT`, `PW_CHANGE_DT` | `AUTH_ID`→`ju_auth` | JPA `JuUser`, `JuUserDetail` + Repository | `AuthService` (로그인만) | `POST /api/auth/login` | 없음 (로그인 화면 없음) | 🟡 로그인 조회만 있다. 사용자 CRUD 없음. **시드 사용자 0건** |
| **Auth / Role** | `ju_auth` + `ju_auth_detail` | `AUTH_ID` | `AUTH_TYPE`, `AUTH_ATTR`(JSON 메뉴코드 배열), `USE_YN` | — | JPA `JuAuth`, `JuAuthDetail` | `AuthService` | 로그인 응답에 `authId/authType/authAttr` 포함 | 없음 | 🟡 시드 5건 (AUTH0001~0005). 사용하는 곳은 로그인 응답뿐이다. 접근 제어에 쓰지 않는다. |
| **Menu** | `ju_menu` + `ju_menu_detail` | `MNU_ID` / `MNU_CD`(uk) | `UP_MNU_ID`(self-FK), `MNU_KIND`, `MNU_LV`, `MNU_URL`, `ENABLED_YN`, `SORT_ORD` | self | MyBatis `CoreQueryDao.xml`, core `MenuMapper.xml` | core `MenuService` | `GET /api/core/menus` | 메뉴 화면 없음 (라우트 1개만 있음) | 🟡 시드 29건. 조회와 액션 연결만 쓴다. |
| **Menu Action** | `ju_menu_action` + `ju_menu_action_detail` | `ACT_ID` / (`MNU_ID`, `ACT_CD`) | `ACT_KIND`, `HANDLER_ID`, `ENABLED_YN`, `SORT_ORD`, `ACT_NM_KEY` | → `ju_menu` | core `MenuMapper.xml` | `DynamicActionService` + `ActionRegistry` | `POST /api/action/{menuId}/{actionCode}` | `actionApi.js` (장치 화면) | ⚠️ **노트북 DB에만 있다. baseline/seed에는 없다.** 새로 설치하면 장치 화면 액션이 실패한다. |
| **Menu Permission** | 별도 테이블 없음 (`ju_auth.AUTH_ATTR` JSON) | — | 메뉴코드 배열 | 없음 (JSON이라 FK 불가) | — | — | — | — | ⬜ 권한을 검사하는 코드가 없다. **[설계 필요]** |
| **Code** | `ju_com_group`(+detail), `ju_com_code`(+detail) | `GRP_CD` / (`GRP_CD`, `COM_CD`) 복합 PK | `COM_VAL`, `COM_ATTR`, `SORT_ORD`, `USE_YN`, `*_NM_KEY` | code→group | MyBatis `CoreQueryDao`, core `SystemCode*` | `SystemCodeService` (Redis 캐시) | `GET /api/core/common/groups`, `/common/codes/{grpCd}`, `/core/system-codes/{grpCd}[/{comCd}]` | `DeviceManagement.vue`가 system-codes 사용 | ✅ 조회만 있다 (등록·수정 API 없음). 시드: 그룹 30, 코드 101 |
| **Language** | `ju_language`, `ju_multi_lang` | `LANG_CD` / (`LANG_CD`, `RES_KEY`) | `RES_VAL` | multi_lang→language | MyBatis, core `MultiLanguageService` | 동일 | `GET /api/core/languages`, 각 조회에 `langCd` | `utils/language.js`(과거 구조), 화면은 `LANG0001` 고정 | ✅ 조회 시 `COALESCE(번역, detail 이름, 코드)`. 시드: 언어 2, 리소스 284 |
| **Sys (시스템 설정)** | `ju_sys` + `ju_sys_detail` | `SYS_CD` | `SYS_VAL` | — | 없음 | 없음 | 없음 | 없음 | ⬜ 시드 10건. `DOTNET_VERSION=9.0` (실제는 net10) |

### 2-2. juproject

| 항목 | DB 테이블 | PK / 업무키 | FK | Entity | Repository / Service | API | Frontend | 상태 |
|---|---|---|---|---|---|---|---|---|
| **Site / Dept** | 없음 | — | — | — | — | — | — | 없음 |
| **User** | `tb_user` | `user_id` / `login_id`(uk) | 없음 | `User` | `UserRepository` / `UserService` | `api/users` CRUD (ADMIN 전용), `api/auth/login`, `api/auth/me` | `UserPage`, `LoginPage` | ✅ |
| **Auth / Role** | 없음 (`tb_user.role_code`) | — | — | 상수 `Roles` (`ADMIN`, `USER`) | `JwtTokenService` | JWT claim `role`, 정책 `AdminOnly` | `ProtectedRoute adminOnly`, `RoleCode` 타입 | ✅ 단순 역할 2개 |
| **Menu / 권한** | 없음 | — | — | — | — | — | `MainLayout.tsx`에 4개 하드코딩 (`adminOnly` 플래그) | 🟡 프론트에만 있다 |
| **Code** | `tb_code_group`, `tb_code` | bigint 대리키 / `group_code`, (`code_group_id`, `code`) | code→group (RESTRICT) | `CodeGroup`, `CommonCode` | Repository / Service | `api/code-groups`, `api/code-groups/{groupCode}/codes`, `api/codes` (조회는 로그인 사용자, 변경은 ADMIN) | `CodeGroupPage`, `CodePage` | ✅ CRUD |
| **Language** | 없음 | — | — | — | — | — | 한국어 하드코딩 | 없음 |

---

## 3. [2] Protocol / Device / Data (juprovider만 해당. juproject에는 없음)

### 3-1. DB와 서버

| 항목 | 테이블 | 키 | 주요 컬럼 | 서버 코드 | API | 상태 |
|---|---|---|---|---|---|---|
| Protocol Group | `ju_protocol_group`(+detail) | `PTL_GRP_CD` | `POLLING_INTVAL`, `TIMEOUT_MS`, `RETRY_CNT` | `CoreQueryDao` | `GET /api/core/protocol-groups` | 🟡 조회만. 시드 2 |
| Protocol | `ju_protocol`(+detail) | (`PTL_GRP_CD`, `PTL_CD`) | `PTL_TYPE`, `PTL_LEN`, `PTL_VAL` | `CoreQueryDao` | `GET /api/core/protocols/{ptlGrpCd}` | 🟡 조회만. 시드 18. `PTL_TYPE`이 공통코드(`PROT*`)가 아니라 문자열 `'POLLING'`이다. |
| Protocol Packet (RX/TX) | `ju_protocol_packet` | (`PTL_GRP_CD`, `PTL_CD`, `PACKET_SEQ`) | `PACKET_TYPE`, `DIRECTION`, `PACKET_EXPR`, `RESPONSE_PTL_CD`, `PARSE_RULE`, `DATA_COUNT/TYPE/POSITION` | 없음 | 없음 | ⬜ 시드 5. RX/TX/POLLING 패킷 정의는 이 테이블에만 있다. |
| Device | `ju_device`(+detail) | `DEV_CD` | `DEV_TYPE`, `DEV_FORM`, `DEV_COMM`, `PTL_GRP_CD`(FK), `DEV_CH`, `DEV_DAT_CNT`. detail: `DEV_CONFIG/EXTRA/DATA` longtext | `CoreQueryDao`, core `DeviceMapper`, `DeviceSyncService` (Redis 캐시, 이벤트 `JU:EVENT:DEVICE`), `DeviceSearchAction`, `DeviceGetAction` | `GET /api/core/devices`, `GET/PUT /api/core/sync/devices`, `POST /api/action/15/SEARCH·GET` | ✅ 조회·동기화·upsert. 시드 4 |
| Data Group | `ju_data_group`(+detail) | `DAT_GR_CD` | `DEV_CD`(FK) | `CoreQueryDao` | `GET /api/core/data-groups` | 🟡 조회만. 시드 3 |
| Data Tag | `ju_data_tag`(+detail) | (`DAT_GR_CD`, `DAT_CD`) | `DAT_IDX`, `DAT_TYPE`, `DAT_UNIT`, `TAG_ID`. detail: `TAG_KIND`, `COLOR`, `MIN/MAX`, `FORMULA*` | `CoreQueryDao` | `GET /api/core/data-tags/{datGrCd}` | 🟡 조회만. 시드 9 |
| Runtime Data | `ju_runtime_data` | PK `CLIENT_ID` + DEV/DAT 키 | 최신값 | `CoreQueryDao` | `GET /api/core/runtime` | 🟡 조회만. **쓰는 코드는 없다.** |

### 3-2. 통신 방식별 구현 (desktop)

| 방식 | 공통코드 (`DEVI`) | 시드 장치 | terminal 구현 | 상태 |
|---|---|---|---|---|
| Virtual | `DEVI0000`=가상 | `VDEV_GTEC01`=**DEVI0003** | `DeviceRuntimeManager`가 `DevType=="DEVI0003"`을 `VirtualDeviceRuntime`(ch1~3 값 생성)으로 처리 | 🟡 동작하지만 코드값 의미와 어긋난다 |
| Serial | `DEVI0001`=시리얼 | `SDEV_GTEC01`=DEVI0002 | NotSupported | ⬜ 미구현 |
| Network | `DEVI0002`=네트워크 | `NET_GTEC01`=DEVI0001 | NotSupported | ⬜ 미구현 |
| Network Gateway | `DEVI0003` | (가상 장치가 이 값을 씀) | — | ⚠️ 코드 정의와 시드, terminal 해석이 서로 맞지 않는다. **[설계 필요]** |

Polling: `ju_protocol_group.POLLING_INTVAL`은 컬럼만 있다. desktop 쪽에 polling 루프를 구현한 코드는 확인하지 못했다. virtual은 자체 타이머로 동작한다.

### 3-3. Desktop 구성

- **client (WinForms)** 흐름
  1. `LocalDatabase` 초기화: Access `data/juprovider.accdb`, 템플릿 `config/template.accdb`, 테이블 `LOCAL_USER`, `LOCAL_DEVICE`, `LOCAL_SYNC_STATE`
  2. `JuProviderApiClient`가 `GET api/core/sync/devices`로 장치를 받아 `LOCAL_DEVICE`에 저장한다 (ONLINE). 실패하면 로컬 데이터를 쓴다 (OFFLINE).
  3. Named Pipe IPC로 terminal에 연결하고 `DEVICE_SYNC`를 보낸다.
  4. terminal에서 받은 `DEVICE_STATUS`, `DATA_RECEIVED`는 **Debug 출력만 하고 저장하지 않는다.**
- **terminal**: `DeviceRuntimeManager`, `VirtualDeviceRuntime`
- IPC 메시지: `DEVICE_SYNC`, `DEVICE_CONNECT`, `DEVICE_DISCONNECT`, `DEVICE_STATUS_REQUEST`, `DEVICE_STATUS`, `DATA_RECEIVED`, `ERROR`
- updater: 빈 폼
- lib의 빈 `Class1.cs` 5개: abstractions, common, global, host, protocol
- `LOCAL_USER`: 서버 사용자와 동기화하는 코드를 확인하지 못했다.
- 서버 주소 `http://localhost:8081/juprovider/`가 하드코딩되어 있다.

### 3-4. Vue

- 라우트는 `/console/device/manage` → `DeviceManagement.vue` 1개뿐이다.
- `DeviceManagement.vue`
  - `menuId=15`를 하드코딩했다. 시드에서 15는 URL이 NULL인 그룹 메뉴다.
  - `langCd=LANG0001`로 고정했다.
  - 장치 목록과 상세 조회만 한다.
- 이 라우트 경로는 메뉴 시드의 `MNU_URL` 목록에 없다.

---

## 4. [3] Experiment 흐름 (juprovider)

| 단계 | 관련 테이블 | 구현 상태 | 근거 |
|---|---|---|---|
| 1. 실험 정의 | `ju_experiment`(+detail: `EXP_TIME`, `EXP_INTVAL`, `EXP_CONFIG` json, `RUN_MODE`) | 🟡 조회만 (`GET /api/core/experiments`). 등록/수정 없음. 시드 4 | CoreQueryDao |
| 2. 실험-장치/데이터 연결 | `ju_experiment_data_group` (`START/PAUSE/STOP_PTL_CD`, `VIEW_YN`) | ⬜ 시드 4, 코드 참조 없음 | — |
| 3. Run 생성 | `ju_experiment_run` (`RUN_ID` varchar, `RUN_STAT`, `RUN_SOURCE`, `CLIENT_ID`) | 🟡 조회만 (`GET /api/core/experiment-runs`). 생성 코드 없음 | — |
| 4. Start / Stop 명령 | `ju_experiment_command` (`COMMAND_CD/STAT`) | ⬜ 코드 없음. IPC에도 실험 명령 타입이 없다 | — |
| 5. 수집 | (terminal → client IPC `DATA_RECEIVED`) | 🟡 virtual만 값을 만들고 client는 Debug 출력만 한다 | client/terminal |
| 6. 저장 (DB) | `ju_experiment_data` (`DAT_VAL` longtext, `SNAPSHOT_DT`, `COLLECTED_DT`), `ju_runtime_data` | ⬜ 쓰는 코드 없음 (서버 수신 API 없음) | — |
| 6'. 저장 (파일) | — | ⬜ 파일 저장 코드 없음 | — |
| 7. Viewer | — | ⬜ 화면 없음 (Vue·desktop 모두) | — |
| 보조 | `ju_client_audit_hist`, `ju_client_error_log`, `ju_client_sync_receipt` (FK 없음) | ⬜ 코드 참조 없음 | — |

요약
- 정의 데이터를 조회하는 것까지만 있다.
- Run 생성, Start/Stop, 수집, 저장, Viewer는 구현되어 있지 않다.

---

## 5. [4] DB 전체 목록

### 5-1. juprovider (노트북 DB 37개 = baseline 35 + 노트북에만 있는 2)

| 영역 | 테이블 | 시드 행 | 상태 |
|---|---|---|---|
| 사용자·권한 | ju_user, ju_user_detail | 0 | 🟡 로그인 조회 (JPA) |
| | ju_auth, ju_auth_detail | 5 | 🟡 로그인 응답에만 사용 |
| 메뉴 | ju_menu, ju_menu_detail | 29 | 🟡 조회 + 액션 연결 |
| | ju_menu_action, ju_menu_action_detail | (baseline에 없음) | ⚠️ 코드에서 사용. baseline/seed에 누락 |
| 공통코드 | ju_com_group(+detail), ju_com_code(+detail) | 30 / 101 | ✅ 조회 |
| 다국어 | ju_language, ju_multi_lang | 2 / 284 | ✅ 조회 |
| 시스템 | ju_sys, ju_sys_detail | 10 | ⬜ |
| 프로토콜 | ju_protocol_group(+detail), ju_protocol(+detail) | 2 / 18 | 🟡 조회 |
| | ju_protocol_packet | 5 | ⬜ |
| 장치 | ju_device, ju_device_detail | 4 | ✅ 조회·동기화·upsert |
| 데이터 | ju_data_group(+detail), ju_data_tag(+detail) | 3 / 9 | 🟡 조회 |
| 실험 | ju_experiment(+detail) | 4 | 🟡 조회 |
| | ju_experiment_data_group | 4 | ⬜ |
| | ju_experiment_run | — | 🟡 조회 |
| | ju_experiment_command, ju_experiment_data | — | ⬜ |
| 런타임 | ju_runtime_data | — | 🟡 조회 (쓰는 코드 없음) |
| 클라이언트 로그 | ju_client_audit_hist, ju_client_error_log, ju_client_sync_receipt | — | ⬜ |
| desktop 로컬 (Access) | LOCAL_USER, LOCAL_DEVICE, LOCAL_SYNC_STATE | — | 🟡 LOCAL_DEVICE만 사용 확인 |

> 테이블 수는 baseline 기준이다. detail 테이블도 각각 하나로 셌다.

### 5-2. juproject 3개 테이블과 juprovider 대응

| juproject | juprovider 대응 | 차이 |
|---|---|---|
| `tb_user` | `ju_user` + `ju_user_detail` | 권한 저장 방식이 다르다: `role_code` 문자열 vs `AUTH_ID` FK. juproject는 `email`/`phone`/`last_login_at`이 본 테이블에 있다. 로그인 실패 횟수와 비밀번호 변경일은 juproject에 없다. |
| `tb_code_group` | `ju_com_group` + detail | 키가 다르다: 대리키 + `group_code` vs 자연키 `GRP_CD`. juproject에는 다국어 키가 없다. |
| `tb_code` | `ju_com_code` + detail | juproject는 FK가 bigint, juprovider는 `GRP_CD`다. juproject에는 `COM_VAL`/`COM_ATTR`가 없다. |

---

## 6. [5] 명명·설계 규칙 비교

| 항목 | juprovider | juproject |
|---|---|---|
| 테이블 접두어 | `ju_` (소문자. core 매퍼는 `JU_MENU`처럼 **대문자**로 쓴다) | `tb_` |
| `sys_` 접두어 | 사용 안 함 (`ju_sys`는 설정 테이블 이름) | 사용 안 함 |
| 컬럼 | 대문자 약어 (`GRP_CD`, `SORT_ORD`, `MNU_LV`, `DAT_IDX`) | snake_case 전체 단어 (`group_code`, `sort_order`) |
| PK | 대부분 자연키 varchar 코드. 일부만 숫자 (`USER_ID`, `MNU_ID`, `ACT_ID`, `EXP_DATA_ID`). `RUN_ID`는 varchar | 모두 bigint AUTO_INCREMENT 대리키 |
| 업무 코드 | `XXXX0000` 형식 공통코드 (`YENO0001`, `DEVI0003`, `LANG0001`, `AUTH0001`) | 대문자 영숫자 코드 (`^[A-Z0-9_]+$`), 역할 `ADMIN`/`USER` |
| FK | 코드 컬럼으로 연결 (`PTL_GRP_CD`, `DEV_CD`) | bigint id로 연결 |
| 사용 여부 | `USE_YN varchar(8)` = `YENO0001`/`YENO0002`. 별도로 `ENABLED_YN`도 있음 (menu, action) | `use_yn char(1)` = `Y`/`N` |
| 생성/수정 일시 | 테이블마다 다르다 (`CREATED_DT`/`UPDATED_DT` 계열. 일부 테이블은 다른 날짜 컬럼) | `created_at`, `updated_at` (UTC, 자동) |
| 생성자/수정자 | 없음 | 없음 ("2차 과제" 주석) |
| detail 분리 | 본 테이블 + `_detail` (1:1, 이름/설명/다국어 키/부가정보) | 없음 |
| 다국어 | `*_NM_KEY`/`*_DESC_KEY` + `ju_multi_lang`, 조회 시 COALESCE | 없음 |
| 논리 삭제 | `USE_YN` 값으로 처리. 쿼리에서 직접 조건을 건다 (JPA 로그인은 `YENO0001` 조건) | EF 전역 쿼리 필터 (`use_yn='Y'`) |
| 재활성화 | 확인된 규칙 없음 (장치 upsert는 덮어쓰기) | 같은 업무키가 다시 들어오면 `Restore()`로 복구 |
| collation | `utf8mb4_general_ci` | `utf8mb4_unicode_ci` |
| 테이블명 대소문자 | baseline은 소문자, core 매퍼는 대문자. Windows MariaDB(`lower_case_table_names=1`)에서만 동작한다 | 소문자로 일관됨 |
| API 응답 | `ApiResponse{success,data}`와 `ResponseEntity`(SystemCode)가 섞여 있다 | DTO를 그대로 반환. 목록은 `PagedResult`(user)와 배열(code)이 섞여 있다 |

**[설계 필요]** 표의 모든 항목에서 통일 방향을 정해야 한다. 이 문서에서는 정하지 않았다.

---

## 7. [6] 인증 / 권한 / 메뉴 흐름

### juprovider

1. `POST /api/auth/login` (loginId, password)
2. `AuthService` 처리
   - `findByLoginIdAndUseYn(loginId, "YENO0001")`
   - BCrypt 검증
   - `JuAuth` USE_YN 확인
3. `LoginResponse(userId, loginId, userName, authId, authType, authAttr)`를 반환한다. **토큰이나 세션은 만들지 않는다.**
4. `SecurityConfig`가 `anyRequest().permitAll()`이라 **모든 API가 인증 없이 열려 있다.**
5. `AUTH_ATTR`(메뉴코드 JSON)는 서버와 프론트 어디에서도 검사하지 않는다.
6. 메뉴 `GET /api/core/menus`는 권한으로 거르지 않고 전체를 반환한다.
7. 액션 `POST /api/action/{menuId}/{actionCode}`
   - menu와 action이 있고 활성 상태인지만 확인한다.
   - 그다음 `HANDLER_ID`에 해당하는 핸들러를 실행한다. 권한은 확인하지 않는다.
8. Vue에는 로그인 화면이 없다.
9. desktop `LOCAL_USER`와 서버 인증을 연결한 코드는 확인하지 못했다.
10. 시드 사용자가 없어서 새로 설치하면 로그인할 수 있는 계정이 없다.

### juproject

1. `POST /api/auth/login` (`AllowAnonymous`)
   - PasswordHasher로 검증하고 `last_login_at`을 갱신한다.
   - JWT를 발급한다: HS256, 60분, claim `sub`/`unique_name`/`user_name`/`role`
2. 프론트
   - 토큰을 sessionStorage에 저장한다.
   - `GET /api/auth/me`로 사용자 정보를 복원한다.
3. API 접근 제어
   - Controller 단위 `[Authorize]`
   - 변경 작업은 `[Authorize(Policy="AdminOnly")]` (`RequireRole("ADMIN")`)
   - `api/users`는 전부 ADMIN 전용이다.
4. 프론트 화면 제어
   - `ProtectedRoute`: 로그인하지 않으면 `/login`으로 보낸다.
   - `adminOnly` 화면은 ADMIN만 들어갈 수 있다.
   - `MainLayout`의 메뉴 4개는 `adminOnly` 플래그로 거른다 (하드코딩).
5. 관리자 계정 시드: Development 환경에서 `DbSeeder`가 `admin` 계정을 만든다.
6. Refresh Token은 없다 (코드 주석: 2차).

---

## 8. [7] 기능별 대응표

| 기능 | juprovider | juproject | 비고 |
|---|---|---|---|
| Site | 없음 (메뉴 URL, 빈 코드 그룹만) | 없음 | [설계 필요] |
| Dept | 없음 (코드 `DEPT0000`만) | 없음 | [설계 필요] |
| User | ju_user(+detail). 로그인 조회만 | tb_user. CRUD + 로그인 | |
| Auth | ju_auth(+detail), JSON 메뉴 권한. 강제하지 않음 | role_code 2개, JWT + 정책으로 강제 | 모델이 다르다 |
| Menu | ju_menu(+detail) + menu_action (DB) | 프론트 하드코딩 4개 | |
| Code | ju_com_group/code(+detail). 조회 | tb_code_group/tb_code. CRUD | |
| Language | ju_language, ju_multi_lang | 없음 | |
| Protocol | protocol_group/protocol/packet. 조회 | 없음 | |
| Device | ju_device(+detail). 조회, 동기화, upsert, Vue 화면 1개, desktop 동기화 | 없음 | |
| Data | data_group/tag. 조회 | 없음 | |
| Experiment | experiment(+detail), exp_data_group. 조회 | 없음 | |
| Run | experiment_run(조회), command/data (코드 없음) | 없음 | |

---

## 확인된 사실

1. 두 저장소 모두 노트북 HEAD가 origin/main과 같고, 작업 중인 변경이 없다.
2. juprovider 노트북 DB에는 baseline에 없는 `ju_menu_action`, `ju_menu_action_detail`이 있다. core의 `MenuMapper.xml`과 `DynamicActionService`가 이 두 테이블을 사용한다.
3. juprovider seed V2.2에는 `ju_user` 행이 없다.
4. juprovider `SecurityConfig`는 `anyRequest().permitAll()`이다. 로그인을 해도 토큰이나 세션이 없다.
5. juprovider에는 Site/Dept 테이블이 없다. 메뉴 시드에는 관련 화면 URL이 있다.
6. 시드의 장치 코드(`DEVI`)가 공통코드 정의와 어긋난다. terminal은 `DEVI0003`을 virtual로 처리한다.
7. `ju_protocol.PTL_TYPE`에 공통코드 대신 `'POLLING'` 문자열이 들어 있다.
8. core 매퍼는 대문자 테이블명을, baseline은 소문자 테이블명을 쓴다.
9. Vue 라우트는 1개이고 `menuId=15`를 하드코딩했다. 다른 Vue 파일 여러 개가 존재하지 않는 모듈을 import한다.
10. juproject는 테이블 3개와 EF 마이그레이션 1개로 구성되며, 코드와 DB가 일치한다.
11. 두 프로젝트 모두 생성자/수정자 컬럼이 없다.

## 현재 구현된 기능

- **juprovider**
  - 로그인 검증 API
  - 공통코드·다국어·메뉴·프로토콜·장치·데이터·실험·런타임 조회 API
  - 장치 동기화 API와 upsert (Redis 캐시, 이벤트)
  - 동적 액션 실행 구조. 핸들러는 `DEVICE.SEARCH`, `DEVICE.GET` 2개
  - Vue 장치 관리 화면 1개
  - desktop client의 장치 동기화 (온라인/오프라인, Access 로컬 DB)
  - client와 terminal 사이 Named Pipe IPC
  - virtual 장치의 값 생성
  - Jenkins 빌드, 배포, Health 확인
- **juproject**
  - JWT 로그인과 `/me`
  - 사용자 CRUD (ADMIN)
  - 공통코드 그룹/코드 CRUD (조회는 로그인 사용자, 변경은 ADMIN)
  - 논리 삭제와 재활성화
  - React 화면 5개: 로그인, 홈, 사용자, 코드그룹, 코드
  - Jenkins 빌드와 산출물 보관

## 미구현/부분 구현

- **juprovider 인증·권한**
  - API 보호
  - 토큰/세션
  - 메뉴 권한 적용
  - 로그인 화면
  - 사용자/권한 관리 화면과 API
  - 초기 사용자
- **juprovider 관리 API**: 공통코드·메뉴·다국어·프로토콜·데이터·실험의 등록/수정/삭제 (현재는 조회만 있음)
- **장치 통신**
  - serial/network 런타임
  - polling 처리
  - protocol_packet 기반 송수신과 파싱
- **실험 흐름**
  - Run 생성
  - Start/Stop 명령
  - 수집 데이터 서버 전송
  - `experiment_data`/`runtime_data` 저장
  - 파일 저장
  - Viewer
- **desktop**
  - 수신 데이터 저장 (현재 Debug 출력만 함)
  - LOCAL_USER 사용
  - updater
  - lib의 빈 프로젝트 5개
- **juproject**
  - 메뉴/권한 DB화
  - 다국어
  - Site/Dept
  - Refresh Token
  - 감사 컬럼 (생성자/수정자)

## 두 프로젝트의 구조 차이

- 기술 스택: Java/Spring + MyBatis + Vue + WinForms vs .NET/ASP.NET Core + EF + React
- DB 규칙이 거의 모든 항목에서 다르다 (6장): 접두어, 컬럼 표기, PK 전략, Y/N 표현, detail 분리, 다국어, collation
- 권한 모델: JSON 메뉴 권한(강제 안 함) vs 역할 2개(강제함)
- 메뉴: DB 메뉴 + 메뉴 액션 핸들러 구조 vs 프론트 하드코딩
- 스키마 관리: SQL 파일 vs EF Migrations
- 범위: juprovider는 장치·실험 도메인을 포함하고, juproject는 시스템 관리 기본 기능(사용자/코드)만 있다.

## 중복 또는 정리 후보

- juprovider Vue의 과거 구조 파일: `ConsoleLayout.vue`, `PublicLayout.vue`, `DeviceSetting.vue`, `utils/codeDisplay.js`, `utils/language.js`. 모두 없는 모듈을 import하고, 라우터에 연결되어 있지 않다.
- 공통코드 조회 경로가 두 개다: `/api/core/common/codes/{grpCd}`(CoreQueryDao)와 `/api/core/system-codes/{grpCd}`(SystemCodeService). 응답 형식도 서로 다르다.
- 장치 조회 경로가 세 개다: `/api/core/devices`, `/api/core/sync/devices`, 액션 `DEVICE.SEARCH/GET`
- 사용 여부 성격의 컬럼이 두 개다: `USE_YN`과 `ENABLED_YN` (menu, action)
- 코드 참조가 없는 테이블 9개
  - `ju_sys`(+detail)
  - `ju_protocol_packet`
  - `ju_experiment_data_group`, `ju_experiment_command`, `ju_experiment_data`
  - `ju_client_audit_hist`, `ju_client_error_log`, `ju_client_sync_receipt`
  - 미구현 기능 때문인지 과거 구조인지는 판단하지 않았다.
- desktop의 빈 `Class1.cs` 5개, `Device.java`(빈 클래스)
- 시드 값 오류 후보: `DOTNET_VERSION=9.0`, `PTL_TYPE='POLLING'`, 장치 `DEV_TYPE` 코드

## ChatGPT 설계가 필요한 항목

1. 두 프로젝트에 공통으로 적용할 DB 명명·키·Y/N·감사 컬럼·collation 규칙 (6장 표 전체)
2. Site / Dept / User / Auth 조직·권한 모델. 메뉴 권한을 JSON으로 둘지 매핑 테이블로 둘지 포함
3. 메뉴와 메뉴 액션(동적 핸들러) 모델. 이를 juproject에도 적용할지
4. 다국어 구조: detail + `NM_KEY` + multi_lang 방식을 juproject에도 도입할지
5. juprovider 인증 방식 (토큰/세션, API 보호 범위)과 초기 사용자 시드
6. `ju_menu_action`을 baseline/seed에 반영하는 방법
7. 장치 유형 코드(`DEVI`)와 runtime 매핑 정리, 프로토콜 유형 코드화
8. 실험 실행 흐름 전체: Run 생성 → 명령 → 수집 전송 API → `experiment_data`/`runtime_data` 저장 → 파일 → Viewer. 사용하지 않는 테이블 9개의 역할 확정 포함
9. API 응답 형식 통일 (`ApiResponse` vs `ResponseEntity`, `PagedResult` vs 배열), 중복 조회 경로 정리
10. 테이블명 대소문자 정책 (매퍼와 baseline 통일)
11. juproject "리소스 정의 단일 원천" 개념을 이 구조 설계 범위에 포함할지

## 사용자 결정이 필요한 항목

1. 두 프로젝트의 DB 규칙을 하나로 통일할지, 각자 유지할지. 통일한다면 어느 쪽을 기준으로 할지
2. 테이블명을 바꿀지 (`tb_`/`ju_`/`sys_`), PK를 바꿀지, YENO와 Y/N 중 무엇을 쓸지
3. 정리 후보 테이블과 Vue 과거 파일을 삭제할지 보류할지
4. juproject 기존 데이터 처리: EF Migration으로 변환할지, 새로 만들지
5. juprovider baseline을 수정할지 (`ju_menu_action` 추가, 시드 사용자 추가, 시드 값 오류 정정)
6. juprovider에 API 보호를 도입할 시점 (현재 전체 공개)
7. 권한 구조와 다국어 구조 변경 범위
8. API 변경 범위 (기존 Vue와 desktop client가 쓰는 경로에 영향이 있음)
9. 실험 흐름 구현 우선순위와 serial/network 지원 범위
10. 작업 순서: juproject DB 재설계를 먼저 할지, 두 프로젝트 공통 규칙을 먼저 정할지

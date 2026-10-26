# ChatGPT 통합 구조 설계 v1.1 역검토 (2026-10-25, Claude)

- 검토 대상: ChatGPT 설계 v1.1. 전제는 "SYS(JuProject) → JU(JuProvider) 단방향 선택 연동, JU는 단독으로 완전히 동작"이다.
- 근거
  - juprovider `d963da2`, juproject `98a94f0` 코드
  - juprovider baseline/seed V2.2
  - 노트북 DB
  - 앞서 쓴 조사 문서 `ai_system_architecture_status_2026-10-25.md`
- 아무것도 구현하거나 수정하지 않았다. 대상: 코드, DB, 파일
- 표기
  - **[사실]**: 코드나 DB에서 확인한 내용
  - **[의견]**: Claude의 검토 의견
  - `[설계 필요]`: ChatGPT가 정할 부분

---

## 1. v1.1 원칙과 현재 구조의 충돌 여부

**[사실]** 코드와 DB에는 충돌이 없다.

- juprovider 코드, 설정, SQL 어디에도 juproject, `sys_`, `tb_`를 참조하는 곳이 없다.
- `application.yml`의 외부 의존성은 MariaDB `juprovider` DB와 Redis(localhost)뿐이다.
- baseline 머리말이 이미 같은 원칙을 적어 두었다.
  - `01_ju_core_baseline.sql` 6행: `1) JU = product/core only; no SITE/DEPT/customer dependency.`
  - 따라서 v1.1은 새 방향이라기보다 **기존 baseline 원칙으로 돌아가는 것**에 가깝다.

**[사실]** 다만 **시드와 과거 Vue 파일에는 원칙과 어긋나는 흔적이 있다.**

| 위치 | 내용 |
|---|---|
| `02_ju_core_seed.sql` 메뉴 | `M01050000` 사이트관리 `/console/site/locations`, `M01060000` 부서관리 `/console/site/departments` |
| 권한 시드 | `AUTH0001`(어드민)의 `AUTH_ATTR`에 위 두 메뉴가 들어 있다 |
| 공통코드 | `SITE` 그룹(코드 없음. 그런데 다국어에 `CODE.SITE.SITE0000.NM`가 있다), `DEPT` 그룹(`DEPT0000` 기본부서) |
| Vue `ConsoleLayout.vue` (라우터 미연결) | `user.deptName` 표시 |

**[의견]** 위 항목은 정리 대상 후보다. 다만 사이트 메뉴 URL이 `site/locations`라서 "고객 사이트"가 아니라 **"장치 설치 위치"**를 뜻했을 가능성이 있다. 그래서 바로 지우지 말고 원래 의도를 먼저 확인해야 한다 (사용자 결정 1).

---

## 2. ju_user와 sys_user를 완전히 독립으로 둘 때

**[사실]**
- `ju_user`를 FK로 참조하는 테이블은 `ju_user_detail` 하나뿐이다.
- 실험, 실행, 명령, 데이터 테이블에는 사용자 컬럼이 없다. 실행 주체는 `CLIENT_ID`(문자열)로만 남는다.
- `ju_user.LOGIN_ID`는 varchar(100), juproject `tb_user.login_id`는 varchar(50)이다.

**[의견] 기술적인 문제는 없다.** 운영에서 생기는 문제는 다음과 같다.

1. 같은 사람이 두 시스템에 계정을 따로 갖는다. 비밀번호가 둘이고, 퇴사 등으로 계정을 막을 때도 양쪽을 각각 처리해야 한다.
   - SYS→JU 연동 단계에서 다룰 문제이고 지금은 영향이 없다.
2. 나중에 같은 사람으로 연결하려면 연결 키가 필요하다. 지금 미리 컬럼을 만들 필요는 없다 (9장).
3. **이름 혼동**: JU에 `ju_sys` 테이블(시스템 설정)이 이미 있다. SYS 쪽 접두어를 `sys_`로 하면 문서와 대화에서 "sys"가 두 가지 뜻이 된다. 표기 규칙만 정하면 된다.

---

## 3. 기존 ju_user / auth / menu / action에서 그대로 살릴 부분

| 대상 | 살릴 부분 | 근거 |
|---|---|---|
| `ju_user` + `ju_user_detail` | 테이블 구조 전체. 로그인 실패 횟수, 마지막 로그인, 비밀번호 변경일 컬럼이 이미 있다 | baseline 439~462행 |
| `AuthService` | `LOGIN_ID` + `USE_YN` 조회 → BCrypt 검증 → 권한 사용 여부 확인 흐름 | backend |
| `ju_auth` + `ju_auth_detail` | 권한 5단계 시드: 어드민 / 관리자 / 운영자 / 일반 / 제한 | seed 11~23행 |
| `ju_menu` + `ju_menu_detail` | 계층 메뉴(`UP_MNU_ID`), `MNU_CD`, URL, 다국어 키. 시드 29건 | baseline, seed |
| `ju_menu_action` + `_detail` | `ACT_CD`, `HANDLER_ID`, `ENABLED_YN` 구조 | core `MenuMapper.xml` |
| `ActionRegistry` / `DynamicActionService` | 메뉴+액션 → 핸들러 실행 구조. **권한 검사를 끼워 넣을 자리가 한 곳으로 모여 있다** | core |
| Redis 장애 시 DB 조회로 넘어가는 처리 | 단독 실행에 유리하다 | `SystemCodeCacheService`, `DeviceSyncService` 주석과 코드 |

---

## 4. JU 인증/권한을 완성하려면 실제로 바꿔야 할 부분

### 서버 (Spring)

| # | 대상 | 현재 | 필요한 변경 |
|---|---|---|---|
| 1 | `SecurityConfig` | `anyRequest().permitAll()` | 인증 필터 추가, 공개 경로 지정 (`/api/auth/login`, `/api/health`, 정적 파일) |
| 2 | 로그인 결과 | 사용자 정보만 반환 | 토큰 발급 (JWT 등) `[설계 필요]` |
| 3 | `/api/auth/me` | 없음 | 추가 |
| 4 | 로그인 부가 처리 | 없음 | `LOGIN_FAIL_CNT`, `LAST_LOGIN_DT` 갱신 (컬럼은 이미 있음) |
| 5 | `DynamicActionService` | 메뉴와 액션의 사용 여부만 확인 | 사용자 권한에 메뉴와 액션이 포함되는지 확인 |
| 6 | `GET /api/core/menus` | 전체 반환 | 로그인 사용자 권한으로 거름 |
| 7 | `/api/core/*` 조회 12개, `system-codes`, `sync/devices` | 액션을 거치지 않는 직접 API | 메뉴·액션 권한을 적용할지, "로그인만 필요"로 둘지 `[설계 필요]` |
| 8 | 권한 저장 방식 | `AUTH_ATTR` JSON(메뉴코드 배열). **액션 권한은 표현할 수 없다** | JSON 확장 또는 관계 테이블 `[설계 필요]` (아래 비교) |
| 9 | 사용자 1인 1권한 | `ju_user.AUTH_ID` 단일 FK | 여러 권한이 필요한지 사용자 결정 |

### DB와 시드

| # | 대상 | 필요한 변경 |
|---|---|---|
| 10 | `ju_menu_action`(+detail) | baseline/seed에 반영. 지금은 노트북 DB에만 있다 |
| 11 | 초기 관리자 | `ju_user` 시드가 0건이다. 비밀번호를 평문으로 시드에 넣지 않는 방식이 필요하다 (예: 첫 실행 시 설정) `[설계 필요]` |

### 클라이언트

| # | 대상 | 필요한 변경 |
|---|---|---|
| 12 | Vue | 로그인 화면, 토큰 저장, 라우터 가드. 라우트가 지금 1개뿐이라 이번에 함께 정리해야 한다 |
| 13 | desktop client | 지금은 인증 없이 `sync/devices`를 부른다. API를 보호하면 **바로 동작하지 않는다**. 사용자 로그인으로 할지, 클라이언트 자격(`CLIENT_ID` + 키)으로 할지 `[설계 필요]` |

**[사실]** desktop `LOCAL_USER` 테이블에 이미 `SERVER_USER_ID`, `OFFLINE_TOKEN`, `EXPIRE_DT`가 있다. 원래 "서버 토큰을 받아 오프라인에서도 일정 기간 쓰는" 설계를 의도한 것으로 보인다. 다만 이를 쓰는 코드는 없다.

### AUTH_ATTR JSON과 관계 테이블 비교 **[의견]**

| | JSON 유지/확장 | `ju_auth_menu` / `ju_auth_action` |
|---|---|---|
| 변경 비용 | 작다 (테이블 변경 없음) | 테이블 2개, 시드 5건 변환 |
| 무결성 | FK가 없다. 메뉴 코드를 바꾸거나 지우면 권한이 조용히 깨진다 | FK로 보장된다 |
| 조회 | "이 메뉴를 쓸 수 있는 권한"을 SQL로 찾기 어렵다 | 쉽다 |
| 액션 권한 | JSON 구조를 새로 정해야 한다 | 행으로 표현한다 |
| 권한 관리 화면 | JSON을 직접 편집하게 된다 | 일반 CRUD로 된다 |

- 메뉴 29개, 권한 5개 규모라 어느 쪽이든 성능 차이는 없다.
- 액션 권한과 권한 관리 화면이 필요하면 관계 테이블 쪽이 유리하다.

---

## 5. JuProvider에 Site/Dept가 필요한가

**[사실]**
- Protocol, Device, Data, Experiment, Run 테이블에 site/dept 컬럼이 없다. 이들을 참조하는 코드도 없다.
- 남은 흔적은 메뉴 시드 2건, 공통코드 그룹 2개, 과거 Vue의 `deptName`뿐이다 (1장).

**[의견]** **지금 JU 기능에는 필요 없다.** 앞으로 필요해질 수 있는 경우는 다음과 같다.
- 장치를 설치 위치별로 묶어 관리하는 경우. 메뉴 URL `site/locations`가 이 뜻일 수 있다.
- 사용자마다 볼 수 있는 장치나 실험 범위를 나누는 경우 (데이터 접근 범위)

그때도 SYS의 Site/Dept가 아니라 JU 자체 개념(예: 설치 위치, 장비 그룹)으로 따로 두는 것이 v1.1 원칙에 맞다. 지금 테이블을 추가할 이유는 없다.

---

## 6. 기존 자연키 / YENO / detail / 다국어를 유지할 때

| 항목 | 장점 | 단점 | 바꾸는 비용 |
|---|---|---|---|
| 자연키 (`DEV_CD`, `GRP_CD` 등) | 데이터만 봐도 뜻을 안다. desktop 동기화와 IPC가 이미 `DEV_CD`로 동작한다. 다른 DB나 SYS와 연결할 때 그대로 쓸 수 있다 | 코드 값을 바꾸려면 FK로 연결된 곳까지 함께 바꿔야 한다 | **크다**: FK 26개(baseline), 매퍼, desktop 로컬 DB, IPC |
| YENO (`varchar(8)` 공통코드) | 공통코드 체계와 일관되고, 다국어로 표시할 수 있다 | 저장 공간이 크고, 매번 `'YENO0001'` 문자열을 비교해야 한다. `USE_YN`과 `ENABLED_YN` 두 개가 함께 있다 | 크다: 모든 테이블과 매퍼 |
| `_detail` 1:1 분리 | 핵심 컬럼과 표시·부가 정보가 분리된다 | 조회할 때마다 JOIN이 필요하고, 저장할 때 테이블 두 개를 써야 한다 | 크다 |
| 다국어 (`*_NM_KEY` + `ju_multi_lang`) | 이미 동작한다 (조회 시 COALESCE로 대체값 사용) | 키 문자열을 수동으로 관리한다. 시드가 커진다 (284건) | 유지하면 비용 없음 |

**[의견]**
- 네 가지 모두 **유지 비용보다 변경 비용이 훨씬 크다.** v1.1의 "대규모 재설계 안 함" 방침과 맞는다.
- 실제로 고칠 것은 규칙 자체가 아니라 **규칙을 어긴 데이터**다.
  - `PTL_TYPE='POLLING'` 문자열
  - `DEV_TYPE` 코드 불일치
  - 매퍼의 대문자 테이블명

---

## 7. SYS에만 bigint PK + Y/N + snake_case를 적용해도 되는가

**[의견]** **문제없다.** DB를 공유하지 않으므로 서로의 규칙이 부딪히지 않는다. 확인할 점은 다음과 같다.

1. 앞으로 SYS→JU로 보낼 때는 **bigint id가 아니라 업무키**(예: `site_code`, `login_id`)를 보내야 한다. SYS에도 변하지 않는 업무키 UNIQUE가 필요하다. juproject는 이미 `login_id`, `group_code`에 UNIQUE를 걸어 두었다.
2. 한 사람이 두 규칙을 오가야 하므로 각 저장소에 규칙 문서를 따로 두는 것이 좋다.
3. collation도 각자 다르다 (JU `general_ci`, SYS `unicode_ci`). DB를 공유하지 않으므로 문제가 되지 않는다.

---

## 8. juproject `tb_*`를 `sys_*`로 바꾸는 비용

**[사실]** 테이블 이름을 쓰는 곳

| 위치 | 수 |
|---|---|
| `Configurations/*Configuration.cs`의 `ToTable("tb_...")` | 3줄 |
| 기존 마이그레이션 `InitialCreate` | 수정하지 않음. 새 마이그레이션에 `RenameTable` 3개 추가 (데이터 보존) |
| `database/schema/01_initial_create.sql` | 다시 생성 |
| PK 제약 이름 `PK_tb_user` 등 | 함께 바꿀지 선택 |
| API 경로, DTO, React | **영향 없음** (테이블 이름이 밖으로 드러나지 않음) |

**[의견]**
- 이름 변경 자체는 작다. 반나절 이내 규모다.
- 비용이 큰 부분은 이름이 아니라 v1.1이 제안한 **구조 추가**다: site, dept, auth, menu, auth_menu, auth_action.
- 공통코드도 이름을 `tb_code` → `sys_code`로 바꾸는 것으로 끝난다.

---

## 9. 앞으로 SYS→JU 연동에 필요한 최소 식별키·매핑 (지금은 만들지 않음)

**[사실]**
- JU에는 "이 JU 설치본이 어디 것인지"를 나타내는 값이 없다. `CLIENT_ID`는 desktop client 단위다.
- `ju_sys`(시스템 설정, 시드 10건)가 키-값 구조라 이런 값을 넣을 수는 있다.

**[의견]** 최소 구조 후보 (ChatGPT 검토용)

1. **JU 설치본 식별값**: 예를 들어 `ju_sys`에 `INSTANCE_CD`를 둔다. 테이블은 추가하지 않는다. SYS는 이 값으로 어느 JU인지 구분한다.
2. **외부 키 매핑**: 필요해지는 시점에 테이블 1개를 둔다. 예: `ju_ext_map(SRC_SYSTEM, SRC_TYPE, SRC_KEY, JU_TYPE, JU_KEY)`. JU 본 테이블에는 SYS 컬럼을 넣지 않는다.
3. **방향**
   - JU가 SYS에서 가져오는 방식(pull)이면 SYS가 꺼져 있어도 JU는 마지막 값으로 계속 동작한다.
   - SYS가 JU로 밀어 넣는 방식(push)이면 JU에 인증된 수신 API가 필요하다.
4. 연결 키는 SYS의 bigint id가 아니라 업무키(`login_id`, `site_code`)로 한다.

실제로 SYS의 무엇이 JU에 필요한지는 아직 근거가 없다. 고객과 사이트 정보가 후보로 보인다. 이 부분은 지금 정하지 않는 것이 맞다.

---

## 10. JU 완전 단독(Offline/Standalone) 실행 조건

단독 실행은 **두 단계**로 나누어 보아야 한다.

### (A) JU 서버가 SYS 없이 동작

| 필요 조건 | 현재 |
|---|---|
| MariaDB `juprovider` | ✅ |
| Redis | 장애 시 DB 조회로 넘어간다 (코드 확인). 실제로 Redis를 끄고 시험해 보지는 않았다 |
| 설치 시드 완결 | ❌ `ju_menu_action` 누락, 관리자 계정 없음 |
| 자체 인증 | ❌ (4장) |
| 외부 네트워크 | 실행 시 불필요. 빌드할 때 Vue용 Node를 내려받는 과정만 인터넷이 필요하다 |
| 기준 데이터 관리 화면 | ❌ 지금은 조회 API만 있다. 등록·수정은 SQL로만 할 수 있다 |

### (B) desktop client가 JU 서버 없이 동작

**[사실]**
- 서버 접속에 실패하면 `LOCAL_DEVICE`로 OFFLINE 모드가 된다. 이 부분은 구현되어 있다.
- 오프라인 로그인 `LOCAL_USER.OFFLINE_TOKEN`은 구현되어 있지 않다.
- 수집 데이터를 로컬에 쌓았다가 나중에 보내는 기능도 없다. 지금은 Debug 출력만 한다.

**[의견]** 서버 테이블 `ju_client_sync_receipt`, `ju_client_audit_hist(LOCAL_HIST_ID)`, `ju_client_error_log(LOCAL_ERROR_ID)`가 이미 "**client 로컬에 저장 → 나중에 서버로 동기화**"를 전제로 설계되어 있다. 따라서 (B)는 새로 설계하기보다 기존 의도를 이어서 완성하는 쪽이 된다. 실험 수집이 서버 장애 중에도 계속되어야 하는지는 사용자가 정해야 한다.

---

## 11. 기존 JuProvider 37개 테이블 분류

### 유지 (구조 그대로)

- `ju_com_group`(+detail), `ju_com_code`(+detail)
- `ju_language`, `ju_multi_lang`
- `ju_menu_detail`, `ju_auth_detail`, `ju_user_detail`
- `ju_protocol_group`(+detail), `ju_protocol`(+detail)
- `ju_device`(+detail)
- `ju_data_group`(+detail), `ju_data_tag`(+detail)
- `ju_experiment`(+detail)

### 수정

| 테이블 | 수정할 내용 |
|---|---|
| `ju_menu_action`(+detail) | baseline/seed에 반영 (구조 변경 아님. 누락 보완) |
| `ju_auth` | `AUTH_ATTR` 처리 방식 결정에 따라. 관계 테이블로 가면 `ju_auth_menu`, `ju_auth_action`을 추가한다 |
| `ju_user` | 초기 관리자 생성 방식. 감사 컬럼은 v1.1 "감사정보" 원칙을 어떻게 적용할지에 따라 정한다 |
| `ju_menu` (시드) | site/dept 메뉴 2건 처리. 메뉴 URL과 실제 Vue 라우트 맞춤. `menuId=15` 하드코딩 해소 |
| `ju_protocol` (시드) | `PTL_TYPE` 값을 공통코드로 |
| `ju_device` (시드) | `DEV_TYPE` 코드와 terminal 해석 일치 |
| `ju_sys` (시드) | `DOTNET_VERSION=9.0` 정정 |
| `ju_experiment_run`, `ju_experiment_command` | 실행하거나 명령한 **사용자** 컬럼이 없다. 인증과 연결할 지점이다 (12장) |

### 보류 (해당 트랙 단계에서 결정)

- `ju_protocol_packet`: protocol 단계
- `ju_experiment_data_group`, `ju_experiment_command`, `ju_experiment_data`, `ju_runtime_data`: experiment/run/storage 단계
- `ju_client_audit_hist`, `ju_client_error_log`, `ju_client_sync_receipt`: desktop 동기화 단계

정리 후보에는 들었지만 **삭제할 근거는 없다.** 모두 미구현 기능을 위해 미리 만든 테이블로 보인다.

---

## 12. Protocol → Device → Data → Experiment에서 인증/권한과 연결할 지점

| 지점 | 연결 방식 | 현재 |
|---|---|---|
| 기준정보 등록·수정 (protocol, device, data group/tag, experiment) | 메뉴 액션 권한 (`ju_menu_action` + 권한) | 등록·수정 API 자체가 없다 |
| 조회 (`/api/core/*`) | 로그인 필수 + 메뉴 조회 권한 여부 `[설계 필요]` | 공개 |
| 실험 Run 생성, Start/Pause/Stop | 액션 권한 + **누가 실행했는지 기록** | 테이블에 사용자 컬럼 없음 (`RUN_SOURCE`, `CLIENT_ID`만 있음) |
| client → 서버 (장치 동기화, 데이터 업로드, 이력/오류 전송) | **사용자 권한이 아니라 client 자격 인증** | 인증 없음 |
| Viewer, 데이터 조회 | 조회 권한. 범위 제한이 필요하면 5장의 데이터 접근 범위 문제와 연결된다 | 없음 |
| 이력 | `ju_client_audit_hist`에 사용자 식별값이 없다 | 미사용 |

---

## [SYS와 JU의 경계]

- **DB**: DB를 공유하지 않는다. SYS 테이블을 FK로 참조하지 않는다. 지금 코드에도 참조가 전혀 없다.
- **사용자·권한·메뉴·공통코드·다국어**: 각자 따로 가진다.
  - SYS: `sys_*`. bigint PK, Y/N, snake_case, EF Migrations
  - JU: `ju_*`. 자연키, YENO, detail, SQL baseline
- **장치·실험 도메인**: JU에만 있다.
- **연결 방식**: 앞으로 업무키 기반 API/Sync로만 연결한다. JU 본 테이블에는 SYS 컬럼을 넣지 않는다.

## [JuProvider 독립 실행 조건]

1. 설치 시드 완결: `ju_menu_action` 반영, 초기 관리자 생성 방식
2. 자체 인증: 토큰, `/me`, API 보호, 메뉴·액션 권한 검사
3. Redis 없이 동작 확인 (코드상 대체 경로는 있음. 실제 시험 필요)
4. desktop client 인증 방식 결정 (API 보호와 동시에 필요)
5. 기준정보 관리 API와 화면 (없으면 SQL로만 운영)
6. (선택) client 오프라인 수집과 나중 동기화

## [기존 JU 구조 유지 가능]

- 37개 테이블 중 21개는 구조 그대로 유지 (11장 "유지")
- 자연키, YENO, `_detail`, 다국어 규칙
- `AuthService` 로그인 검증, `ActionRegistry`/`DynamicActionService`, Redis 장애 시 DB 조회 처리
- 클라이언트 동기화와 이력 테이블의 원래 설계 의도 (로컬 ID + 수신 확인)

## [기존 JU 구조 수정 필요]

- `SecurityConfig`, 토큰, `/me`, 권한 검사 (4장 1~9)
- `ju_menu_action` baseline 반영, 관리자 시드 방식
- `AUTH_ATTR` 처리 방식 (JSON 확장 또는 관계 테이블)
- 시드 데이터 오류: site/dept 메뉴, `PTL_TYPE`, `DEV_TYPE`, `DOTNET_VERSION`, 메뉴 URL과 Vue 라우트 불일치
- 매퍼 대문자 테이블명 (Linux MariaDB에서 실패 가능)
- Run/Command 실행자 기록
- Vue 로그인과 라우터, desktop client 인증

## [SYS 구조 제안]

**[의견]**
- 1단계: `tb_*` → `sys_*` 이름 변경. 비용이 작다.
- 1단계 범위: `sys_user`, `sys_code_group`, `sys_code`. 지금 기능 그대로 이름만 바꾼다.
- 2단계: `sys_site`, `sys_dept`, `sys_auth`, `sys_menu`, `sys_auth_menu`
  - `sys_user`에 `site_id`/`dept_id`를 연결한다.
  - 지금의 `role_code`를 `sys_auth`로 바꾼다.
- `sys_auth_action`, `sys_language`/`sys_multi_lang`, 고객/서비스 관리는 화면 요구가 생길 때 추가한다.
- 모든 SYS 기준 테이블에 변하지 않는 업무키 UNIQUE를 둔다 (향후 JU 연동 키).
- v1.1이 내세운 공통 원칙 중 아직 SYS에 없는 것은 **감사정보(생성자/수정자)**다. 구조를 바꿀 때 함께 넣는 것이 비용이 적다.

## [Site/Dept의 JU 필요 여부]

- 지금은 **필요 없다.** 코드, FK, 업무 테이블 어디에도 쓰는 곳이 없고 baseline 원칙도 배제한다.
- 정리할 흔적: 메뉴 2건, 공통코드 `SITE`/`DEPT`, 권한 JSON 안의 해당 메뉴, 과거 Vue의 `deptName`
- 메뉴 `site/locations`가 "장치 설치 위치"를 뜻했다면 그것은 JU 자체 개념이다. SYS Site와 별개로 Device 단계에서 정한다.

## [SYS→JU 향후 연동 포인트]

1. JU 설치본 식별값 (`ju_sys`에 키 1개)
2. 업무키 기반 외부 매핑 테이블 1개 (필요해지는 시점에)
3. 연동 방향 (pull/push)과 수신 API 인증
4. 연동 후보 데이터: 사용자 계정 연결(선택), 고객/사이트 정보(표시용)
5. 끊김 대응: JU는 마지막으로 받은 값으로 계속 동작한다

## [과설계 가능성]

- 아래는 아직 요구가 확인되지 않았다. 지금 설계에 넣으면 과설계가 될 수 있다.
  - `sys_auth_action`, `sys_language`/`sys_multi_lang`, 고객/서비스 관리 테이블
  - JU에 Site/Dept나 외부 매핑 테이블을 미리 추가하는 것
- JU 권한을 메뉴 + 액션 + 데이터 범위까지 한 번에 설계하는 것: 지금 액션 핸들러가 2개뿐이므로 메뉴 권한 + 주요 액션 정도로 시작하는 편이 현실적이다.
- 사용자 1인 다중 권한: 시드와 화면에서 필요성이 보이지 않는다.
- SYS와 JU 규칙 문서를 하나로 묶는 것: v1.1이 이미 다르게 가도 된다고 했으므로 각각 두면 충분하다.

## [사용자 결정 필요 - 최대 7개]

1. JU 시드의 "사이트관리(`site/locations`)", "부서관리" 메뉴의 원래 의도. 장치 설치 위치였는지, 고객 조직이었는지, 그리고 정리 방식
2. JU 메뉴 권한 방식: `AUTH_ATTR` JSON 유지/확장 vs `ju_auth_menu`/`ju_auth_action` 관계 테이블
3. JU 인증 방식: JWT 등 토큰 vs 세션. desktop client는 사용자 로그인으로 할지 client 자격으로 할지
4. JU 초기 관리자 생성 방식: 첫 실행 설정 / 별도 스크립트 / 설치 시 입력
5. desktop 오프라인 범위: 서버 장애 중 실험 수집을 계속하고 나중에 동기화할지
6. SYS 1단계 범위: 이름만 `sys_*`로 바꿀지, site/dept/auth/menu까지 한 번에 할지
7. 진행 순서: JU 인증 트랙과 SYS 트랙 중 무엇을 먼저 할지, 동시에 할지

## [권장 다음 설계 단계]

**[의견]** 순서 제안

1. **JU 설치 완결성** (설계는 작고 효과는 큼)
   - `ju_menu_action` baseline 반영
   - 관리자 생성 방식
   - 시드 오류 정정 목록 확정
2. **JU 인증·권한 ERD/API 설계**
   - 토큰, `/me`, 권한 저장 방식 (결정 2)
   - API 보호 범위 (4장 7번)
   - client 인증 (결정 3)
3. **SYS 1단계**: `tb_*` → `sys_*` 이름 변경. 2단계 ERD(site/dept/auth/menu)는 별도 문서로
4. 이후 JU 도메인 트랙: protocol → device → data → experiment/run → storage/viewer
   - 각 단계에서 보류 테이블의 역할을 정한다.
   - 실행자 기록 등 인증 연결 지점(12장)을 그 단계에서 함께 반영한다.
5. SYS→JU 연동은 SYS 2단계와 JU 인증이 끝난 뒤에 9장 기준으로 설계한다.

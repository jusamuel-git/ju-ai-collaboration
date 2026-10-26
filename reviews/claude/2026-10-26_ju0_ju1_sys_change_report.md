# JU-0 / JU-1 / SYS-0+1 미커밋 변경 현황 보고 (2026-10-26, Claude)

- 목적: ChatGPT의 diff·빌드 검토용. 이 보고 이후 추가 구현이나 구조 변경은 하지 않았다.
- 기준: Claude 작업공간 clone에서 stash를 복원한 상태 (`git stash apply`. stash는 지우지 않고 그대로 둠)
  - juprovider `feature/ju-0-install` (HEAD `d963da2` = origin/main) + stash@{0}
  - juproject `feature/sys-core-schema` (HEAD `98a94f0` = origin/main) + stash@{0}
- 같은 내용은 노트북 `workspace\ai_changes`의 zip/patch에도 있다 (`ju0_juprovider`, `ju1_juprovider`, `sys_juproject`)
- **commit/push 하지 않음.** 실제 secret 값은 이 문서·patch·zip 어디에도 없다.

> **빌드 미실행.** 오늘 노트북 연결(device bridge)이 끊겨 로컬 빌드를 돌리지 못했다 (재시도 3회 실패). 작업공간은 Maven/npm/NuGet 저장소가 막혀 있어 빌드할 수 없다. 노트북이 연결되면 [BUILD] 순서대로 실행해 결과를 덧붙인다.

---

## [JUPROVIDER]

### git status
- 수정(M) 21, 신규(??) 18 항목 (디렉터리 단위 포함) → 파일 기준 **51개 변경, +2476 / −77**
- 삭제 파일 없음

### 변경 파일 목록 / diff --stat (요약)

| 영역 | 파일 | 변경 |
|---|---|---|
| 문서 | `AI_COLLABORATION.md` | v1.2 반영 (10장 아키텍처 기준) +89 |
| | `database/README.md` (신규) | 설치·업그레이드·권한 비트·setenv 변수·Client 등록 절차 +61 |
| DB | `database/baseline/01_ju_core_baseline.sql` | +46 (테이블 4개 추가, AUTH_ATTR 주석) |
| | `database/seed/02_ju_core_seed.sql` | +152/−? (V2.3) |
| | `database/migration/04_ju0_install_fix.sql` (신규) | +147 |
| | `database/migration/05_ju1_auth.sql` (신규) | +42 |
| core | `action/service/DynamicActionService.java` | 권한 검사 추가 +18 |
| | `security/*` 6개 (신규) | ExecutionContext, AuthorityAttribute, PermissionService, PermissionDeniedException, PermissionDao, ActionPermission |
| | `client/*` 4개 (신규) | JuClient, IssuedClientKey, ClientDao, ClientService |
| | `mapper/PermissionMapper.xml`, `mapper/ClientMapper.xml` (신규) | |
| backend | `pom.xml` | `spring-boot-starter-oauth2-resource-server` 추가 (BOM 관리) |
| | `config/SecurityConfig.java` | 전면 교체 +118 |
| | `config/JwtConfig.java` (신규) | +75 |
| | `security/` 3개 (신규) | JwtTokenService, ClientKeyAuthenticationFilter, JsonSecurityErrorHandler |
| | `service/AuthService.java` | 로그인·me·비밀번호 변경 +145 |
| | `controller/AuthController.java`, `ClientAdminController.java`(신규), `DynamicActionController.java` | |
| | `dto/` LoginResponse(변경), UserInfo·MeResponse·PasswordChangeRequest·ClientInfo·ClientRegisterRequest(신규) | |
| | `entity/JuUser.java`, `JuUserDetail.java` | 상태 변경 메서드만 추가 (컬럼 매핑 변경 없음) |
| | `exception/GlobalExceptionHandler.java` | 400(@Valid), 403(PermissionDenied) 추가 |
| | `JuProviderApplication.java` | MapperScan에 core.security.dao, core.client.dao 추가 |
| | `application.yml` | `juprovider.security.jwt.*` 추가 |
| Vue | `App.vue`, `api/api.js`, `router/index.js` (변경) / `api/authApi.js`, `auth/session.js`, `views/auth/LoginView.vue`, `views/auth/PasswordChangeView.vue` (신규) | |
| desktop | `juprovider.terminal/Runtime/DeviceRuntimeManager.cs` | 가상장치 판정 DEVI0003 → DEVI0000 |
| | `lib.data/Api/JuProviderApiClient.cs` | Client 자격 헤더 |
| | `juprovider.client/Program.cs`, `Services/ClientSettings.cs`(신규) | `config/client.json`에서 서버 주소·Client 자격 읽기 |

### JU-0 변경 내용 (설치 완결성)
1. `ju_menu_action`, `ju_menu_action_detail`을 baseline/seed에 추가 (노트북 DB 덤프와 같은 구조·데이터 10건, 메뉴 15 = 시스템장치관리)
2. 공통코드 그룹 `MACT`(메뉴 Action 종류) 신설. `COM_VAL` = 권한 비트
   - MACT0001 조회 `01`, MACT0002 실행 `10`, MACT0003 등록 `02`, MACT0004 수정 `04`, MACT0005 삭제 `08`, MACT0006 내보내기 `20`
   - 기존 노트북 DB의 MACT0003(편집)을 등록으로 좁히고 UPDATE→MACT0004, DELETE→MACT0005로 재분류
3. 다국어: `GROUP.MACT.NM`, `CODE.MACT.*.NM`, `ACTION.DEVICE.*.NM` (한/영)
4. 시드 값 정정: `ju_protocol.PTL_TYPE` `'POLLING'` → `PROT0000` (18건), `ju_sys.DOTNET_VERSION` 9.0 → 10.0, 장치 유형 VDEV→DEVI0000 / SDEV→DEVI0001 / NET→DEVI0002 (장치 `'11'`, DEVC는 그대로)
5. 초기 관리자 `admin` (BCrypt 해시, AUTH_ID 1). 기본 비밀번호는 `database/README.md`에 기재된 공개 기본값이며 `PW_CHANGE_DT = NULL`이라 첫 로그인 후 변경 강제
6. `04_ju0_install_fix.sql`: 위 내용을 기존 DB에 반영. 재실행 안전 (UPDATE 조건부, `CREATE TABLE IF NOT EXISTS`, `INSERT IGNORE`, `ON DUPLICATE KEY UPDATE`, admin은 사용자 0명일 때만)

### JU-1 변경 내용 (인증/권한)
- 사용자 JWT 인증, 비밀번호 변경 강제, Menu Action 권한 검사, Desktop Client 키 인증 + 관리자 발급 API, Vue 로그인/가드
- Desktop 로그인 UI와 Offline Token은 **포함하지 않음** (JU-1c)

### 새 DB 테이블/컬럼

| 테이블 | 구분 | 내용 |
|---|---|---|
| `ju_menu_action`, `ju_menu_action_detail` | baseline 반영 (노트북 DB에는 이미 있음) | 구조 변경 없음 |
| `ju_client` | 신규 | `CLIENT_ID` PK varchar(100), `KEY_HASH` varchar(64) SHA-256, `USE_YN`, `KEY_ISSUED_DT`, `LAST_SEEN_DT`, `CREATED_DT` |
| `ju_client_detail` | 신규 | `CLIENT_ID` PK/FK, `CLIENT_NM`, `CLIENT_DESC` |
| `ju_auth.AUTH_ATTR` | 데이터 형식 변경 | 메뉴코드(9) → 메뉴코드+비트(11). 어드민 `FF`, 그 외 `01`. 컬럼 주석만 변경 |
| 그 외 | — | 기존 테이블 컬럼 추가·삭제 없음 |

### 새 API

| 메서드·경로 | 인증 | 내용 |
|---|---|---|
| `POST /api/auth/login` | 공개 | **응답 변경**: `{accessToken, expiresAt, user{userId, loginId, userName, authId, authType, passwordChangeRequired}}` (이전: 사용자 정보 + authAttr, 토큰 없음) |
| `GET /api/auth/me?langCd=` | JWT (변경 전 허용) | 사용자 + 권한 메뉴 목록 (`permission` = 16진 2자리 비트) |
| `POST /api/auth/password` | JWT (변경 전 허용) | 현재/새 비밀번호(8~100자). 새 토큰 반환 |
| `GET /api/admin/clients` | JWT + 어드민 | Client 목록 (키 해시 제외) |
| `POST /api/admin/clients` | JWT + 어드민 | 등록, 키 원문 1회 반환. 논리 삭제된 ID면 새 키로 재활성화 |
| `POST /api/admin/clients/{clientId}/key` | JWT + 어드민 | 키 재발급 (이전 키 무효) |
| `DELETE /api/admin/clients/{clientId}` | JWT + 어드민 | 논리 삭제 |
| 기존 `POST /api/action/{menuId}/{actionCode}` | JWT | 경로 동일. 권한 없으면 403 |
| 기존 `/api/core/sync/devices` | **Client 키** | 경로·응답 동일. 헤더 `X-JU-Client-Id`, `X-JU-Client-Key` 필요 |
| 기존 `/api/core/*` 나머지 | JWT | 로그인만 필수 (메뉴 권한 미적용, v1.2 6장) |

### SecurityConfig 변경
`anyRequest().permitAll()` 단일 체인 → 3개 체인

| 순서 | 대상 | 인증 | 규칙 |
|---|---|---|---|
| 1 | `/api/core/sync/**`, `/api/client/**` | **Client 키** (`ClientKeyAuthenticationFilter`) | 권한 `CLIENT` 필요. 사용자 JWT로는 통과 불가 |
| 2 | `/api/**` | 사용자 JWT (oauth2 resource server) | login·health 공개 / me·password는 로그인만 / `/api/admin/**`은 `ROLE_AUTH0001` / 그 외 `PW_OK`(비밀번호 변경 완료) |
| 3 | 그 외 (Vue 정적 파일) | 없음 | 공개 |

- 세션 STATELESS, CSRF 비활성(토큰 방식), 401/403은 `ApiResponse` 형식 JSON
- User 인증(누가)과 Client 인증(어느 PC)은 체인부터 분리 — 사용자 지시 5번과 일치

### JWT 구현
- HS256, Nimbus (`NimbusJwtEncoder/Decoder`), issuer `juprovider`, 만료 60분, 발급자 검증
- 클레임: `sub`=USER_ID, `login_id`, `auth_id`, `auth_type`, `pwc`(비밀번호 변경 필요)
- 권한 변환: 항상 `USER`, `pwc=false`일 때만 `PW_OK`, `ROLE_{AUTH_TYPE}`
- Vue: 토큰은 sessionStorage, 요청마다 `Authorization: Bearer`, 401이면 세션 삭제 후 첫 화면으로 이동
- 로그인 실패 시 `LOGIN_FAIL_CNT` +1, 성공 시 0으로 초기화하고 `LAST_LOGIN_DT` 기록. 계정 잠금은 없음

**⚠ 지시 3번과 맞지 않는 점 (수정 필요, 아직 고치지 않음)**
- 현재 `JwtConfig`는 `JU_JWT_SECRET`이 비어 있으면 **모든 환경에서** 임시 랜덤 키를 만들고 경고만 남긴 채 정상 기동한다.
- 지시한 정책은 "운영/일반 환경에서는 미설정이면 기동 실패, 개발용 fallback은 개발 profile에만 허용"이다.
- 수정안 (승인 후 반영)
  1. 기본: secret이 없거나 32바이트 미만이면 `IllegalStateException`으로 기동 실패
  2. `dev` profile(`spring.profiles.active=dev`)에서만 임시 키 허용 + 경고
  3. 영향: 노트북 Tomcat `setenv.bat`에 `JU_JWT_SECRET`이 없으면 Jenkins 배포 후 Health Check가 실패한다. **반영 전에 setenv.bat 설정이 먼저 필요하다.**
  4. 현재 juprovider에는 profile 설정 파일이 없다 (`application.yml` 하나). `application-dev.yml`을 추가할지, 실행 인자로만 profile을 줄지 결정 필요

### 권한 구현
- `AUTH_ATTR` 형식: JSON 문자열 배열, 항목 = 메뉴코드(9) + 비트(16진 2). 비트 없는 9자리 항목 = 메뉴 표시만 허용
- 판정: `(AUTH_ATTR의 메뉴 비트) & (Action의 ACT_KIND → MACT.COM_VAL) != 0`
- 검사 위치: Core `PermissionService.checkAction`. `DynamicActionService.execute`가 핸들러 실행 전에 호출 (v1.2 4.1: 권한 검사는 Core)
- 권한 데이터는 매 요청 DB에서 읽음 → 권한을 바꾸면 재로그인 없이 바로 적용
- `/api/auth/me` 메뉴 = 사용·활성 메뉴 중 `AUTH_ATTR`에 있는 것
- 시드 권한: 어드민(AUTH0001) 전체 `FF`, 관리자·운영자·일반·제한(AUTH0002~0005)은 **조회 `01`만** — 지시 4번대로 확대하지 않음
- 미적용: `/api/core/*` 직접 조회 API의 메뉴 권한, Run/Command 실행자 기록(JU-5)

### seed/baseline 변경 요약
- baseline V2.3: `ju_menu_action`(+detail), `ju_client`(+detail) 추가, `ju_auth.AUTH_ATTR` 주석
- seed V2.3: MACT 그룹/코드/상세, 다국어 34건, 메뉴 Action 10건(+상세), PTL_TYPE·DOTNET_VERSION·DEV_TYPE 정정, admin 사용자, AUTH_ATTR 11자리
- migration 04(JU-0), 05(JU-1): 기존 설치 DB용. 05는 `REGEXP_REPLACE`로 AUTH_ATTR 변환 (11자리 항목은 건드리지 않음)
- **노트북 DB 적용 여부 미확인** (어제 안내만 했음)

---

## [JUPROJECT]

### git status
- 수정(M) 20, 신규(??) 13 항목 → **33개 파일, +447 / −28**, 삭제 없음
- Frontend 변경 없음 (API·화면 계약 유지)

### 변경 파일 목록 / diff --stat (요약)

| 계층 | 파일 |
|---|---|
| Domain | `BaseEntity`(created_by, updated_by), `Roles`(권한코드 상수만, IsValid 제거), `User`(role_code 제거 → AuthId, DeptId), `CommonCode`(CodeValue), `CodeGroup`(주석) / 신규 `Site`, `Dept`, `Authority`, `Menu`, `AuthorityMenu` |
| Application | `ICurrentUser`, `IAuthorityRepository`(신규), `UserService`(RoleCode → sys_auth 조회), `UserDtos`(RoleCode = Authority.AuthCode), `AuthService`(권한 없는 계정 로그인 거부) |
| Infrastructure | `AppDbContext`(DbSet 5개 추가, 감사 사용자 기록), Configuration 5개 신규 + 4개 변경(테이블명 `sys_*`), `AuthorityRepository`(신규), `UserRepository`(Authority Include), `JwtTokenService`(role 클레임 = auth_code), `DbSeeder`(ADMIN 권한 조회) |
| Api | `HttpCurrentUser`(신규), `Program.cs`(HttpContextAccessor, ICurrentUser 등록) |
| 문서 | `AI_COLLABORATION.md` v1.2 |

### sys_* 변경 내용

| 테이블 | 구분 | 주요 컬럼 |
|---|---|---|
| `sys_user` | `tb_user` 이름 변경 | `role_code` 삭제 → `auth_id` NOT NULL FK(`fk_user_auth`), `dept_id` NULL FK(`fk_user_dept`) |
| `sys_code_group` | `tb_code_group` 이름 변경 | 감사 컬럼 추가 |
| `sys_code` | `tb_code` 이름 변경 | `code_value` varchar(200) NULL, 감사 컬럼 |
| `sys_site` | 신규 | `site_code` UNIQUE, `site_name` |
| `sys_dept` | 신규 | `site_id` FK, `dept_code` UNIQUE, `parent_dept_id` 자기참조, `sort_order` |
| `sys_auth` | 신규 | `auth_code` UNIQUE, `auth_name`, `sort_order` |
| `sys_menu` | 신규 | `menu_code` UNIQUE, `parent_menu_id`, `route_path`, `component_key`, `icon_key`, `sort_order` |
| `sys_auth_menu` | 신규 | `auth_menu_id` PK, (`auth_id`, `menu_id`) UNIQUE |
| 공통 | 모든 테이블 | `use_yn`, `created_at`, `created_by`, `updated_at`, `updated_by` (by = sys_user.user_id, FK 없음, 시스템 처리는 NULL) |

### migration 상태
- **빌드: 성공** (2026-10-25 노트북 스크립트, `dotnet build JuProject.slnx` 경고 0, 오류 0)
- **migration 생성: 실패** — 원인은 코드가 아니라 노트북에 user-secrets `ConnectionStrings:Default`가 없어서다 (`dotnet ef`가 DbContext를 만들지 못함)
- 마이그레이션 파일(`SysCoreSchema`)은 아직 없음. user-secrets 등록 후 스크립트 재실행 필요

### 기존 ADMIN/USER 데이터 이전 방식 (마이그레이션 생성 후 Claude가 편집해서 넣을 내용)
EF가 자동 생성하는 마이그레이션은 `role_code` 삭제 + `auth_id` 추가(기본값 0)라서 **그대로 쓰면 권한 값이 사라지고 FK도 실패한다.** 생성된 `Up()`을 다음 순서로 고친다.

1. `tb_*` 3개 → `sys_*` RenameTable (데이터 보존)
2. 감사 컬럼, `code_value` 추가
3. `sys_auth`, `sys_site`, `sys_dept`, `sys_menu`, `sys_auth_menu` 생성
4. `sys_auth`에 `ADMIN`(관리자), `USER`(일반사용자) 삽입
5. `sys_user.auth_id`를 **NULL 허용으로 먼저 추가**
6. `UPDATE sys_user u JOIN sys_auth a ON a.auth_code = u.role_code SET u.auth_id = a.auth_id`
7. 검증: `auth_id`가 NULL인 행이 있으면 중단 (ADMIN/USER 외 값이 있으면 실패시켜 데이터 손실 방지)
8. `auth_id` NOT NULL로 변경 → FK, 인덱스 생성 → `role_code` 삭제
9. 초기 메뉴: 현재 React 메뉴 4개 (HOME `/`, USERS `/users`, CODE_GROUPS `/code-groups`, CODES `/codes`)
10. `sys_auth_menu`: ADMIN = 4개 전부, USER = USERS 제외 3개 (현재 화면 동작과 동일)
11. `Down()`: 역순 (role_code 복원 → auth_code 값으로 채움 → 신규 테이블 삭제 → 이름 원복)

기존 사용자·코드 데이터는 삭제하거나 덮어쓰지 않는다.

---

## [BUILD]

| 대상 | 명령 (노트북) | 결과 |
|---|---|---|
| juprovider.core | `mvn -B -f juprovider.core\pom.xml clean install` | **미실행** (노트북 연결 끊김) |
| juprovider.backend | `cd juprovider.backend && mvn -B clean package -Pvue` | **미실행** |
| juprovider.frontvue | 위 `-Pvue`에 포함 (`npm` + `vite build`) | **미실행** |
| juproject backend | `dotnet build backend\JuProject.Slnx -c Release` | 어제 Debug 빌드 **성공** (오늘 재확인 필요) |
| juproject frontend | `cd frontend && npm ci && npm run lint && npm run build` | **미실행** (변경 없음) |

작업공간에서 가능한 범위의 확인만 했다.
- Java: 변경된 Java 파일 전체 `javac` 구문 검사 통과 (의존성 미해결 오류만 남음 = 문법 오류 없음)
- `AuthorityAttribute` 단위 확인: 11자리·9자리 혼합, 같은 메뉴 비트 합산, 판정 결과 정상
- Vue JS 모듈 5개 `node --check` 통과 (`.vue` 템플릿은 vite build 필요)

**빌드 실행 조건**
- juprovider의 backend 빌드 전에 core install이 먼저 필요 (backend가 core 1.0.0-SNAPSHOT을 의존)
- backend의 `oauth2-resource-server` 의존성을 처음 받으므로 인터넷 필요
- juproject migration은 빌드와 별개 (user-secrets 필요)

---

## ChatGPT 검토 요청 포인트

1. JWT secret 정책 수정안 (위 ⚠) — profile 구성 방식 결정
2. `POST /api/auth/login` 응답 형식 변경 (토큰 포함, authAttr 제거) — API 계약 변경
3. `/api/core/*` 직접 조회 API를 "로그인만 필수"로 둔 것 (메뉴 권한 미적용)
4. Client 키 해시를 SHA-256(솔트 없음)으로 저장 — 서버 생성 32바이트 난수라서 BCrypt 대신 선택
5. 로그인 실패를 400(`IllegalArgumentException`)으로 응답 (기존 동작 유지, 401 아님)
6. AuthService는 기존대로 backend JPA에 둠 (v1.2 "SQL은 Core" 원칙과 다름. 권한·Client는 Core)
7. juproject `created_by/updated_by`를 FK 없는 bigint로 둔 것, `sys_auth_menu`의 대리키

# JU-1A 사전 조사 (Claude, 2026-10-26 15:58)

기준: juprovider `main 03f636c` + PC-A 실제 DB(V2.3, JU-0A 04 적용). **조사만, 제품 코드 변경 없음.** DB는 읽기 조회만.

## 1. `ju_user` / `ju_user_detail` / admin
- `ju_user`: USER_ID, LOGIN_ID(UK), USER_PW_HASH(255), AUTH_ID(FK→ju_auth), USE_YN
- `ju_user_detail`: USER_NM, USER_EXTRA, PHONE_NO, EMAIL, **LOGIN_FAIL_CNT**(int, 0), **LAST_LOGIN_DT**, **PW_CHANGE_DT**
- 사용자 1명: `admin`, AUTH_ID 1(AUTH0001=ADMIN), YENO0001, BCrypt(`$2a$`, 60자), **PW_CHANGE_DT NULL**, LOGIN_FAIL_CNT 0
→ 로그인 추적·최초 변경 강제에 필요한 컬럼이 **이미 있음**

## 2. Backend Security / JWT
- 의존성: `spring-boot-starter-security`만. JWT 라이브러리 없음 → **`spring-boot-starter-oauth2-resource-server`(Nimbus) 추가 필요** (10/25 결정)
- `SecurityConfig`: CSRF off, CORS default, **`anyRequest().permitAll()`**, `BCryptPasswordEncoder`
- JWT/토큰/필터 코드 없음

## 3. 로그인 API / Vue
- `POST /api/auth/login` 있음 (`AuthService`, JPA). 토큰 없음. 응답 `{userId, loginId, userName, authId, authType, authAttr}`. 실패는 `IllegalArgumentException` → **400**
- `/me`, 비밀번호 변경 API 없음. 실패 횟수·마지막 로그인 갱신 없음
- Vue: 라우트 2개(`/`, `/console/device/manage`), 가드 없음, axios에 토큰 헤더 없음. `layouts/ConsoleLayout.vue`·`PublicLayout.vue`가 **없는 파일**(`utils/auth.js`, `services/api.js`)을 import — 라우터에 연결 안 된 죽은 파일이라 빌드는 통과 (JU-1C에서 정리)

## 4. `ju_auth` / AUTH_ATTR (JU-1B 경계)
- `ju_auth`: AUTH_TYPE(AUTH0000~0005: DEFAULT/ADMIN/MANAGER/OPERATOR/USER/GUEST 공통코드), AUTH_ATTR(9자리 메뉴코드 JSON, 5개 권한)
- **JU-1A에서 건드리지 않음**: AUTH_ATTR 형식(11자리 변환), MACT 비트 검사, PermissionService, DynamicAction 권한, `ju_client`(현재 **없음**), migration 05
- JU-1A가 쓰는 것: `AUTH_ID`, `AUTH_TYPE`, `ju_auth.USE_YN`(로그인 허용 판단)만

## 5. `/api/core/sync/**`
- 현재 permitAll(전체 permitAll). Desktop(`JuProviderApiClient`)이 인증 헤더 없이 `api/core/sync/devices` GET/PUT 호출
- JU-1A: 보정 3대로 **임시 permitAll 유지**(명시적 matcher로 분리) → JU-1B Client Key로 닫음

## 6. 설정 (`application.yml` 1개뿐)
- DB: `${JU_DB_URL:…}`, `${JU_DB_USER:root}`, `${JU_DB_PASSWORD}`(기본값 없음 ✓). Redis localhost. profile 파일 없음
- Tomcat `setenv.bat`: `JU_DB_URL/USER/PASSWORD` SET, **`JU_JWT_SECRET` 없음**
- JU-1A 추가: `juprovider.security.jwt.secret: ${JU_JWT_SECRET:}` + 기동 검증(없거나 32바이트 미만이면 실패), `application-dev.yml`에만 `allow-random-secret: true` (보정 5). **배포 전 setenv에 `JU_JWT_SECRET` 추가 필요** (안 하면 Jenkins 배포 후 Tomcat 기동 실패 → Health Check 실패)

## 7. Core 최소 security read package
- 현재 Core에 security 패키지 없음 (action/device/language/menu/systemcode)
- 제안 위치: `juprovider.core/src/main/java/com/asdp/juprovider/core/security/`
  - JU-1A: `ExecutionContext`(userId, authId, clientId) 읽기 모델만 — stash에 있음, 재사용
  - JU-1B: `AuthorityAttribute`, `PermissionService`, `PermissionDao`, `ActionPermission`, `PermissionDeniedException`
- `/me`는 Backend가 JWT에서 userId를 읽고 사용자·권한 기본정보를 조회 → Core permission 없이 구현 가능

## 8. PW_CHANGE_DT
- admin NULL → JU-1A 규칙: `PW_CHANGE_DT IS NULL` = 변경 필요. 로그인/`/me` 응답에 `passwordChangeRequired`, 변경 전에는 `/me`·`/api/auth/password`·logout 외 사용자 API 거부(403 + 코드)
- 변경 성공 시 PW_CHANGE_DT 갱신. 토큰 발급 시각 < PW_CHANGE_DT인 토큰은 거부 가능(컬럼 추가 불필요)

## 9. 예상 변경 파일 / migration
| 구분 | 파일 |
|---|---|
| 의존성 | `juprovider.backend/pom.xml` (oauth2-resource-server) |
| 설정 | `application.yml`(jwt), **신규** `application-dev.yml` |
| Backend 신규 | `config/JwtConfig`, `security/JwtTokenService`, `security/JsonSecurityErrorHandler`, `dto/MeResponse`, `dto/PasswordChangeRequest`, `dto/UserInfo` (stash 재사용 후 Client 부분 제거) |
| Backend 수정 | `SecurityConfig`(user JWT chain + sync 임시 permitAll + health/static permitAll), `AuthController`(login/me/password), `AuthService`(토큰·실패 횟수·마지막 로그인·PW 변경), `LoginResponse`(토큰 포함, **authAttr 제거**), `JuUser`/`JuUserDetail`(setter), `GlobalExceptionHandler`(401/403) |
| Core 신규 | `core/security/ExecutionContext` |
| DB | **migration 불필요** (컬럼 모두 존재). seed 변경 없음 |
| 제외 (JU-1B) | `ClientKeyAuthenticationFilter`, `ClientAdminController`, `Client*`, `PermissionService`, DynamicAction 권한, migration 05 |

## 10. 영향
| 대상 | 영향 |
|---|---|
| `/api/core/*` 조회 | JU-1A 이후 **로그인 필요**(현재 무인증) → 현재 Vue(토큰 없음)의 장치 관리 화면 호출이 401 → **JU-1C 전까지 Vue 화면 일부 동작 불가**. R1대로 JU-1A·1B·1C 로컬 commit 후 함께 push하면 main에서는 문제 없음 |
| `/api/action/**` | 동일 (로그인 필요). 권한 검사는 JU-1B |
| `/api/core/sync/**` (Desktop) | 임시 permitAll → **영향 없음** |
| `/api/health`, 정적 Vue | permitAll 유지 → Jenkins Health Check 영향 없음 |
| 로그인 API 계약 | 실패 400→401, 응답에 토큰 추가·authAttr 제거 (승인된 변경) |
| Jenkins/Tomcat | `JU_JWT_SECRET` 미설정 시 기동 실패 → push 전 setenv 추가 필요 |
| Desktop | 영향 없음 (sync만 사용) |

## 결정·확인 필요
1. `/api/core/*` 조회를 JU-1A에서 바로 인증 필수로 할지, JU-1C 전까지 임시 허용할지 (R1 함께 push 전제면 바로 필수 권장)
2. 로그인 실패 잠금 정책 (LOGIN_FAIL_CNT 몇 회에 잠금? 이번엔 기록만 권장)
3. `JU_JWT_SECRET` 생성·setenv 추가 시점 (JU-1A 로컬 smoke 전, Claude가 PC-A에 생성 가능 — 값 미기록)

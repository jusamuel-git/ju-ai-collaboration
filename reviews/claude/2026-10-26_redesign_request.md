# ChatGPT 재설계 요청 — 2026-10-26 기준 현재 상태 (Claude)

- 목적: 10/25 진행한 v1.2 설계·구현을 **오늘 확정된 환경 기준**으로 다시 설계하기 위한 입력 자료
- 진행 방식: Claude 조사(이 문서) → **ChatGPT 재설계** → Claude 역검토 → 사용자 결정 → Claude 구현·로컬 빌드 → ChatGPT diff 검토 → 사용자 commit/push → Jenkins main 확인
- 함께 볼 문서 (workspace, 저장소 밖)
  - `DEV_ENVIRONMENT_STANDARD.md`: 개발 PC 기준
  - `BUILD_ENVIRONMENT_STANDARD.md`: 빌드 기준
  - `ai_dev_env_standard_report_2026-10-26.md`: 환경 조사 보고
  - `ai_decisions_v1.2_2026-10-25.md`: 10/25 사용자 결정 기록
  - `AI_ARCHITECTURE_DB_CORE_API_v1.2.md`: ChatGPT 설계 v1.2

---

## 1. 오늘 확정된 기준

| 항목 | 상태 |
|---|---|
| 기준 개발 PC | **PC-A `DESKTOP-CE5BGKK`**. PC-B(노트북)는 오늘 저녁 PC-A에 맞춘다 |
| 저장소 | 두 저장소 모두 `main` (juprovider `d963da2`, juproject `98a94f0`), PC-A 작업 사본에 변경 없음 |
| 환경 점검 | `ai_dev_env_check.ps1`: FAIL 0 (Tool 버전·PATH 정상) |
| 로컬 빌드 | **5개 대상 모두 PASS** (core install, backend+Vue WAR, desktop, juproject backend, juproject frontend) |
| 빌드 검증 방법 | 구현 → **PC-A 로컬 빌드**(`ai_local_build.ps1`) → ChatGPT 검토 → 승인 → commit/push → Jenkins `main` 최종 확인. Jenkins Job은 바꾸지 않는다 |
| Claude 실행 능력 (PC-A) | 파일 읽기·쓰기 가능. 명령 직접 실행 불가. 빌드는 `run_ai_local_build.cmd` 더블클릭으로 실행하고 로그를 읽는다 |

## 2. 10/25 작업의 현재 위치

| 작업 | 내용 요약 | 상태 |
|---|---|---|
| 협업 규칙 v1.2 | 두 저장소 `AI_COLLABORATION.md`에 10장(아키텍처 기준) 추가 | 미커밋 |
| **JU-0** 설치 완결성 (juprovider) | baseline/seed에 `ju_menu_action`(+detail), 공통코드 MACT 6개(비트), 다국어, 시드 오류 정정(PTL_TYPE, DOTNET_VERSION, 장치 유형 코드), 초기 admin(기본 비밀번호 + 변경 강제), terminal 가상장치 코드 `DEVI0000`, migration `04` | 미커밋, **빌드 미검증** |
| **JU-1** 인증/권한 (juprovider) | JWT(Nimbus HS256), `/api/auth/me`, `/api/auth/password`, Security 체인 3개(Client 키 / 사용자 JWT / 정적), `AUTH_ATTR` 비트 권한 검사(Core `PermissionService`), `ju_client`(+detail) + 관리자 키 발급 API, Vue 로그인·가드, desktop Client 키 헤더, migration `05` | 미커밋, **빌드 미검증** |
| **SYS-0+1** (juproject) | `tb_*`→`sys_*`, `sys_site/dept/auth/menu/auth_menu`, 감사 컬럼, `role_code`→`sys_auth`, API 계약 유지 | 미커밋. 노트북에서 **빌드 성공**. EF migration **미생성** (노트북 user-secrets 없음) |
| 환경 표준화 (오늘) | `AI_COLLABORATION.md` 4장 경로 표 갱신, Jenkinsfile `JU_TOMCAT_HOME` 변경안, `global.json` 변경안 | 미커밋 / 변경안은 승인 대기 |

- 위 변경은 **PC-A에는 아직 적용되지 않았다.** 사본 위치는 세 곳이다.
  - Claude 작업공간 stash
  - 노트북 `workspace\ai_changes` (zip/patch)
  - PC-A `workspace\ai_changes\devenv` (환경 변경안만)
- 브랜치 기준: `feature/ju-0-install`(juprovider), `feature/sys-core-schema`(juproject), `chore/dev-env-standard`(두 저장소)

## 3. 재설계 때 반영할 사항 (Claude 분석)

### 3-1. 사용자 결정 중 v1.2와 다른 것 (`ai_decisions_v1.2_2026-10-25.md`)
1. **JU Site 계층 유지**: 레벨 1 site = 부서의 상위, 하위 레벨 = 장치 위치. JU 자체 모델 설계 필요 (v1.2는 "추가하지 않음")
2. **권한은 `AUTH_ATTR` JSON 유지**: 항목 = 메뉴코드(9) + 16진 2자리 비트. 비트 단위는 MACT 공통코드 `COM_VAL`(조회 01, 등록 02, 수정 04, 삭제 08, 실행 10, 내보내기 20). 9자리 항목 = 메뉴 표시만 (v1.2 권장은 관계 테이블)
3. **SYS-0과 SYS-1을 한 번에**. 범위는 DB + 기존 기능 전환까지 (관리 화면은 다음 단계)
4. **Desktop**: Client 키(관리자 API 발급, 해시 저장). 오프라인 규칙은 "서버가 끊겼을 때 이전에 정상 로그인한 사용자가 있으면 통과, 없으면 로그인 불가"
5. 초기 admin: seed에 기본 비밀번호 + 첫 로그인 변경 강제
6. 비 ADMIN 권한은 조회 중심 유지. 각 도메인 Phase에서 확정

### 3-2. 구현하면서 드러난 설계 공백·수정 필요
| # | 내용 | 필요한 결정 |
|---|---|---|
| A | **JWT secret 정책**: 현재 구현은 `JU_JWT_SECRET`이 없으면 모든 환경에서 임시 키로 기동한다. 사용자 지시는 "운영/일반은 기동 실패, 개발 profile에만 fallback" | profile 구성(`application-dev.yml` 추가 여부, 실행 인자) |
| B | **로그인 API 응답 변경** (토큰 포함, `authAttr` 제거) — API 계약 변경 | 승인 |
| C | `/api/core/*` 직접 조회 API는 "로그인만 필수"로 둠 (메뉴 권한 미적용) | 유지 여부 |
| D | 사용자 인증은 기존 backend JPA에 두고, 권한·Client는 Core MyBatis에 둠 (v1.2 "SQL은 Core" 원칙과 부분 불일치) | 인증 로직을 Core로 옮길지 |
| E | Client 키 해시를 SHA-256(솔트 없음)으로 저장 (서버 생성 32바이트 난수) | 승인 |
| F | 로그인 실패를 400으로 응답 (기존 동작 유지) | 401로 바꿀지 |
| G | SYS migration: EF 자동 생성은 `role_code` 삭제 + `auth_id` 추가라서 기존 권한 값이 사라진다. Claude 안: `auth_id` NULL 허용 추가 → `role_code`로 채움 → 미매칭 행이 있으면 중단 → NOT NULL·FK → `role_code` 삭제, 초기 메뉴 4개와 권한-메뉴 매핑 | 승인 (생성은 PC-A user-secrets로 가능) |
| H | SYS 감사 컬럼 `created_by/updated_by` = bigint, FK 없음 / `sys_auth_menu` 대리키 | 승인 |
| I | JU-0의 MACT 비트를 JU-1 이전에 seed에 넣었음 (권한 코드는 JU-1에서 사용) | 단계 구분 유지 여부 |
| J | Desktop 사용자 로그인 UI와 오프라인 통과는 JU-1c로 미룸 | 범위 확인 |
| K | Run/Command 실행자 기록(JU-5), 데이터 접근 범위(Site 계층과 연결 가능) | 이후 Phase |

### 3-3. 환경 표준화에서 나온 승인 대기 항목
1. `global.json` (SDK `10.0.400`, `latestPatch`) — 두 저장소
2. Jenkinsfile Tomcat 경로 → `env.JU_TOMCAT_HOME` (Jenkins 전역 변수 먼저 추가), 포트 8081 → `HTTP_PORT`
3. `AI_COLLABORATION.md` 4장 경로 표 (PC-A 참고값 + 환경변수)

## 4. ChatGPT에 요청하는 재설계

1. **단계를 작게 나눠 주세요.** 단계마다 PC-A 로컬 빌드로 검증하고 따로 commit할 수 있는 크기가 좋다. Claude 제안 순서:
   - 0단계: 환경 변경안 3건 (3-3)
   - 1단계: JU-0 (seed/baseline/migration 04, terminal 코드). DB 변경은 migration 적용 승인 필요
   - 2단계: SYS-0+1 (EF migration 포함, G 반영)
   - 3단계: JU-1 서버 (A~F 결정 반영)
   - 4단계: JU-1 Vue
   - 5단계: JU-1c Desktop (로그인·오프라인)
2. 3-2의 A~K 중 **설계가 필요한 것은 결정안을, 사용자 결정이 필요한 것은 선택지를** 정리해 주세요.
3. 이미 구현된 코드는 재사용 후보다. 설계가 바뀌는 부분만 표시해 주시면 Claude가 차이를 역검토한다.
4. JU Site(위치) 계층 모델(3-1-1)은 JU-3(Device) 전에 설계하는 것으로 둘지 정해 주세요.

## 5. 지켜야 할 것 (변경 없음)
- commit/push는 사용자. 과거 history는 재작성하지 않는다
- DB 스키마, 인증/보안, API 계약, 공통 모델, 의존성, 배포 구조 변경은 사용자 승인 후 구현
- 비밀 값은 문서·patch·zip·Git에 넣지 않는다
- 각 단계 완료 기준: PC-A 로컬 빌드 PASS → ChatGPT diff 검토 → 승인 → commit/push → Jenkins main SUCCESS

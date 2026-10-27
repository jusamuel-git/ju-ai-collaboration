# PC-B 재현 검증 — `feature/protocol-ref` @ `157635a` (2026-10-27 22:30~22:45) — **PASS**

- 대상 PC: PC-B `JUSAMUEL` (노트북). 제품 코드 수정·commit·push 없음, main merge/push 없음, 실제 juprovider DB에 06 미적용
- 방식: 기존 작업 폴더에 10/25 미커밋 변경이 있어(아래) **사용자 선택에 따라 별도 git worktree**(`C:\MyData\MyDev\workspace_verify`)에서 검증. 기존 폴더·변경은 그대로
- 스크립트: `tools/ai_pcb_precheck.ps1`(읽기 전용) → `tools/ai_pcb_verify.ps1`(`ai_pr2.ps1`을 PC-B 경로·worktree용으로 바꾼 것, 제품 로직 동일) → `tools/ai_pcb_extra.ps1`(Device GET·501 보완) → `tools/ai_pcb_cleanup.ps1`

## 1. PC-B 상태와 환경 차이
**기존 작업 폴더 (변경하지 않음, 보고만)**
| 저장소 | 브랜치 | 상태 |
|---|---|---|
| `workspace\juprovider` | `feature/ju-0-install` @ `d963da2` (local main도 `d963da2`, origin보다 뒤) | 미커밋 40건 (수정 21·신규 18 등, 10/25 JU-0/1 작업). stash 없음 |
| `workspace\juproject` | `feature/sys-core-schema` @ `98a94f0` | 미커밋 36건 (10/25 SYS 작업). stash 없음 |

**환경 (`ai_dev_env_check.ps1` + PC-A baseline: PASS 22 / WARN 9 / FAIL 1)**
| 항목 | PC-A | PC-B | 판정 |
|---|---|---|---|
| JDK | 21.0.1 `MyDev\jdk` | 21.0.1 `MyTool\jdk` | 허용 (버전 같음, 경로만 다름) |
| Maven | 3.9.11 `MyDev\maven` | 3.9.11 `MyTool\maven` (저장소 `~/.m2`) | 허용 |
| JAVA_HOME / MAVEN_HOME | Machine, MyDev | Machine, MyTool | 허용 (빌드 영향 없음) |
| .NET SDK | 10.0.402 | 10.0.401 | 허용 (`global.json` 10.0.400 latestPatch) |
| Node / npm / Git / MariaDB | 24.14.0 / 11.9.0 / 2.36.1 / 10.6.16 | 같음 | PASS |
| CMake | 4.4.3 | 4.2.3 | 허용 (빌드 5종 미사용) |
| Visual Studio | 18.11 | 18.10 | 허용 |
| vcpkg | `MyTool\vcpkg` + VCPKG_ROOT | `MyTool\vcpkg-master`, VCPKG_ROOT 없음 | **FAIL(점검표 기준)**, 빌드 5종 미사용 → 이번 검증에는 영향 없음 |
| JU_WORKSPACE / JU_TOMCAT_HOME | 설정 | 미설정 | WARN (로컬 빌드·smoke 무관, Jenkins용) |
| Tomcat setenv | JU_DB_*, JU_JWT_SECRET | 같은 변수 모두 SET (JWT secret 32바이트 이상) | PASS |
| 로컬 juprovider DB | 04·05 적용 | ju_client 있음·AUTH_ATTR 11자리(10/25 작업), Action 10개 | 테스트 사본에 04·05 재실행 후 신규 설치와 **컬럼 구조 차이 0건** |

→ 모두 "빌드·검증 가능한 허용 차이". PC_B.md 정렬 항목(JDK/Maven 경로, vcpkg, 환경변수)은 아직 미정렬 상태 그대로

## 2. Git
- origin/main = `fce5048` ✅ / 검증 브랜치 `feature/protocol-ref` (worktree, origin 추적) HEAD = `157635a` ✅
- 계보 `fce5048 → 02ab18c → 157635a` ✅, juproject worktree = origin/main `68d610b` ✅, worktree 작업 트리 깨끗함 ✅

## 3. 결과 (PC-A와 비교)
| 항목 | PC-B | PC-A | 차이 |
|---|---|---|---|
| 로컬 빌드 5종 | **PASS** (core 10s, WAR+Vue 46s, desktop 14s, juproject backend 8s, frontend ci/lint/build) | PASS | 없음 |
| 단위 테스트 | **23/23** (ActionInputValidator 4, DynamicActionService 7, ProtocolContract 4, JwtConfig 4, AuthorityAttribute 4) | 23/23 | 없음 |
| migration 06 | 1회·2회 적용 무변경, Action 10개, **기존 DB+06 = 신규 설치** (Action·detail·다국어) | 같음 | PC-B는 사본에 04·05 먼저 재실행(재실행 안전) |
| HTTP smoke (`ai_pcb_verify`) | **64 / 64 PASS** (worktree·04/05·구조 비교 확인 포함) | 58/58 | 같은 58개 항목 모두 PASS + PC-B 전용 확인 6개 |
| 보완 smoke (`ai_pcb_extra`) | **14 / 14 PASS** | (PR-1에서 확인) | — |

**확인 항목별**
| 항목 | 결과 |
|---|---|
| MNU_CD + ACT_CD 호출 (`/api/action/M02010100/{ACT}`), X-JU-Request-Id | PASS |
| Protocol Handler 10개, contractVersion=1 (단위 테스트 + 응답 `contractVersion: 1`, 불일치 400) | PASS |
| Output Contract: `list={items,total}`, 항목 필드·순서 = 계약, RECORD, KEY 모양 | PASS |
| Input/Error Contract: REQUIRED·UNKNOWN_FIELD(중첩)·INVALID_CODE·TYPE_MISMATCH·MAX_LENGTH·DUPLICATE·INVALID_VALUE·CONTRACT_VERSION_MISMATCH | PASS |
| 관리자 CRUD + 다국어 키·LANG0001 | PASS |
| 비관리자(01) 조회 200 / 쓰기 403, 권한 없는 사용자 403 | PASS |
| 400 / 404(없는 대상·정의 없는 Action) / 409(중복·사용 중·삭제 그룹) / **501**(DEVICE.CREATE, MNU_CD 경로 DEVICE.STOP), 비관리자는 501보다 403 먼저 | PASS |
| GRP_CREATE 기본 Protocol `{그룹}0000` 생성 + 트리거 주입 실패 시 그룹·detail·다국어 전체 rollback | PASS |
| GRP_DELETE 장치+실험 전체 선검사(409 무변경, 장치만 해제해도 409), 해제 후 전체 논리 삭제, 마지막 단계 실패 시 rollback | PASS |
| CREATE 패킷 실패 rollback | PASS |
| 기존 Device SEARCH(배열 모양)·GET(menuId·MNU_CD 경로) 회귀 없음, 기동 WARN 8건(Device만) | PASS |
| 로그에 비밀번호 원문 없음 | PASS |

## 4. 정리
- 테스트 DB 4개 삭제 확인 (남은 DB: `juprovider`), 18081 LISTEN 없음, 검증용 java 프로세스 0
- 보완 smoke 직후 테스트 DB 1개(`juprovider_pcbxinst`)가 남아 정리 스크립트로 삭제 (PC-A 10/27 JU-1B 때와 같은 현상)
- 남겨 둔 것: worktree `C:\MyData\MyDev\workspace_verify\juprovider`(로컬 브랜치 `feature/protocol-ref`), `\juproject`(detached `68d610b`) — 이후 PC-B 작업용. 필요 없으면 `git worktree remove`로 정리
- 조작 실수: 정리 스크립트 실행 중 `ai_pcb_cleanup.ps1`이 메모장으로 한 번 열림 (변경 없음)

## 5. 판정
**PASS** — PC-A 작업분(`02ab18c`, `157635a`)이 PC-B에서 동일하게 재현됨. 실패 0건 → **제품 코드 수정 필요 없음**.
환경 차이는 모두 허용 범위. 별도 정리 권장(제품 무관): PC-B 기존 작업 폴더의 10/25 미커밋 변경 처리(보관 또는 폐기는 사용자 결정), PC_B.md 정렬 항목(JDK/Maven 경로, vcpkg·VCPKG_ROOT, JU_WORKSPACE/JU_TOMCAT_HOME)

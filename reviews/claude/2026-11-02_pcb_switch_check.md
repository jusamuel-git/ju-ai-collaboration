# PC-B 전환 1단계 점검 (2026-11-02 21:22, JUSAMUEL) — 차이 보고, 2단계 대기

조사만 수행: 환경 점검(읽기 전용), `git fetch`. 브랜치 전환·로컬 변경 처리·빌드·DB 변경 없음. 도구: `tools/pcb/ai_pcb_switch1.ps1` (+ 최신 `ai_local_build.ps1` 배치, 기존 것은 `.bak_pcb_20261102` 로 보존)

## 1. 브랜치·커밋 (누락 없음)
- fetch 결과 PC-A 에서 보존한 9개 모두 수신: collect-c1 `5723b03`, c2 `332c229`, c3 `ad9fda3`, c4 `66e9255`, **c5 `854da5c`**, integration-1 `14d1ab9`, protocol-ref `1d1c1ab`, sec-s1 `4187280`, web-01 `60bc008`. origin/main `fce5048`.
- PC-A 의 나머지 로컬 브랜치(action-contract, env-0, ju-0a/0b, ju-1a/1b/1c, ju-1c-desktop)는 커밋이 모두 origin 이력에 포함(이름만 없음) → 누락 커밋 없음.
- juproject: origin 에 main `68d610b`, feature/user-role-filter `f0d5467`(10/31, PC-A 현재 브랜치). PC-A 에만 있던 커밋 없음.

## 2. PC-B 로컬 상태 (보존 필요)
| 저장소 | 현재 브랜치 | 로컬 변경 | 비고 |
|---|---|---|---|
| juprovider | `feature/ju-0-install` @ `d963da2` (upstream 없음) | **수정 21 + 추가 19 (총 40)** — JU-1 인증 작업 이전 사본으로 보임(05 migration, security 패키지 등, 이미 main 에 반영된 내용과 겹침) | 로컬 main `d963da2` = origin/main 보다 7 뒤. `feature/protocol-ref`(157635a, 1 뒤)가 **별도 worktree** `C:\MyData\MyDev\workspace_verify\juprovider` 에 체크아웃됨 |
| juproject | `feature/sys-core-schema` @ `98a94f0` | **수정 21 + 추가 15 (총 36)** — SYS 스키마 작업 사본으로 보임 | 로컬 main 3 뒤. stash 없음 |

## 3. 환경 차이 (ai_dev_env_check: PASS 22 / WARN 9 / FAIL 1)
| 항목 | PC-B | 판정 | 영향 |
|---|---|---|---|
| vcpkg | 없음, VCPKG_ROOT 미설정 | **FAIL** | juproject/juprovider 빌드 5종에는 미사용(현재 빌드 스크립트 기준). 필요 시 설치(Tool 설치는 사용자) |
| git `core.autocrlf` (global) | **미설정** (PC-A: true) | 차이 | 커밋 시 줄끝이 PC-A 와 달라질 수 있음 → 설정 권장 |
| CMake | 4.2.3 (기준 4.4.3) | WARN | 빌드 5종 미사용 |
| Visual Studio | 18.10 (기준 18.11) | WARN | 빌드는 dotnet SDK 사용 |
| JDK 21.0.1 / Maven 3.9.11 | 버전 같음, 경로·환경변수 범위만 다름 | WARN | 없음 |
| JU_WORKSPACE·VCPKG_ROOT·JU_TOMCAT_HOME | 미설정 | WARN | 스크립트는 기본 경로 사용 |
| .NET SDK 10.0.401, Node 24.14.0/npm 11.9.0, Git 2.36.1, MariaDB 10.6.16(Running), Redis, Jenkins 2.580.1(Running), Tomcat 10.1.52 | 기준과 같음 | PASS | |
| Tomcat setenv `JU_DB_*`·`JU_JWT_SECRET`, juproject user-secrets | SET | PASS | 값 미출력 |
| COM 포트 | 없음 | — | GTEC 실장비 회귀는 장비 연결 후 |
| 8081 | 사용 중(기존 Tomcat) | — | 실서버 검증은 18081 사용 |

## 4. 2단계 제안 (승인 후)
1. 로컬 변경 보존: 각 저장소에서 현재 브랜치 기준 **로컬 백업 브랜치**(`backup/pcb-20261102-<branch>`)에 미커밋 변경 전부 커밋 + 패치 파일을 `C:\MyData\MyDev\backup` 에 저장 (push 없음, 삭제 없음)
2. 브랜치 복원: origin 의 feature 9개를 로컬 추적 브랜치로 생성, 로컬 main 은 fast-forward 만, worktree 의 protocol-ref 는 건드리지 않음(보고만)
3. juprovider `feature/collect-c5` 체크아웃 → 빌드 5종 + 테스트(기대 서버 34, Desktop 175), juproject 는 `main`(또는 user-role-filter) 빌드
4. C5a 상태 확인 + 실서버 회귀(테스트 DB 사본, 실제 DB 무변경) → 보고

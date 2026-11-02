# PC-B 개발 PC 전환 결과 (2026-11-02 21:30, JUSAMUEL) — PASS (환경변수 3개 설정 남음)

도구: `tools/pcb/ai_pcb_switch2.ps1`. push·main 병합·배포·실제 DB 변경·삭제 없음.

## 1. git
- `core.autocrlf` (global): 미설정 → **true** (PC-A 와 동일)
- 로컬 변경 보존 (로컬 전용, push 없음):
  | 저장소 | 원래 | 백업 브랜치 | 백업 파일 (`C:\MyData\MyDev\backup\pcb_20261102`) |
  |---|---|---|---|
  | juprovider | `feature/ju-0-install` @ d963da2, 변경 40 | `backup/pcb-20261102-feature-ju-0-install` @ `9bb4d51` | tracked patch 62 KB, status 목록, untracked 30개 zip |
  | juproject | `feature/sys-core-schema` @ 98a94f0, 변경 36 | `backup/pcb-20261102-feature-sys-core-schema` @ `bd156cf` | tracked patch 50 KB, status 목록, untracked 15개 zip |
- 복원: juprovider origin feature 8개 로컬 추적 브랜치 생성(collect-c1~c5, integration-1, sec-s1, web-01), main fast-forward d963da2→`fce5048`. juproject `feature/user-role-filter` 생성, main →`68d610b`.
- PC-A 기준 체크아웃: juprovider **`feature/collect-c5` @ `854da5c`**, juproject **`feature/user-role-filter` @ `f0d5467`** — PC-A 와 동일
- 그대로 둔 것: `feature/protocol-ref`(157635a, origin 보다 1 뒤)는 별도 worktree `C:\MyData\MyDev\workspace_verify\juprovider` 에 체크아웃 중이라 미변경. 기존 로컬 브랜치 `feature/ju-0-install`, `feature/sys-core-schema` 유지

## 2. 빌드·테스트 (PC-A 결과와 동일)
| 단계 | 결과 |
|---|---|
| 빌드 5종 (core, WAR+Vue, desktop, juproject backend, frontend ci·lint·build) | PASS |
| juprovider 서버 테스트 | 34/34 |
| Desktop 테스트 | 175/175 |
| `ai_local_build.ps1` | 최신본(Desktop 테스트 포함)으로 교체, 이전 것 `.bak_pcb_20261102` 보존 |

## 3. C5a 상태
- `feature/collect-c5` @ `854da5c` = origin 동일, 부모 `14d1ab9`(integration-1)·`66e9255`(collect-c4), 이후 추가 커밋 없음. migration 03~06 (C5 migration 미작성)
- 실서버 회귀 (PC-B DB 덤프 사본 + 06, 18081): **43/43 PASS** (PC-A 와 같은 결과). PC-B 실제 DB CHECKSUM 무변경, 로그 비밀 값 없음
- 다음 단계: C5b (migration 08 + 테스트 DB 검증) 승인 대기

## 4. 환경 (재점검 PASS 24 / WARN 9 / FAIL 1)
| 항목 | PC-B | PC-A 기준 | 조치 |
|---|---|---|---|
| vcpkg | 없음 | 2026-07-27 (C:\MyData\MyTool\vcpkg) | **설치 필요 (사용자)** — 현재 빌드 5종 미사용 |
| CMake | 4.2.3 | 4.4.3 | 업그레이드 필요 (사용자) |
| Visual Studio | 18.10 | 18.11 | 업데이트 필요 (사용자) |
| 환경변수 JU_WORKSPACE·VCPKG_ROOT·JU_TOMCAT_HOME | 미설정 | User 변수 | 설정 필요 (사용자, vcpkg 설치 후) |
| JAVA_HOME·MAVEN_HOME | Machine 범위 | User 범위 | 버전·경로 같음, 동작 영향 없음 |
| .NET SDK | 10.0.401 | 10.0.402 | global.json 범위 내 PASS |
| 그 외 JDK 21.0.1, Maven 3.9.11, Node 24.14.0, npm 11.9.0, Git, MariaDB 10.6.16, Redis, Jenkins 2.580.1, Tomcat 10.1.52, VS Code, 비밀 설정(SET) | 동일 | | |
- 도구 설치·업그레이드·시스템 환경변수는 작업 규칙상 직접 하지 않음 → 위 4건은 사용자 작업.

## 5. GTEC 포트
- PC-B 는 **COM3** (현재 연결 확인). `tools/ai_c4probe.ps1` 기본 포트 COM3(`-Port` 로 변경 가능), 포트 없으면 실행 전 중단. `tools/c4probe/Program.cs` 기본값·안내 문구도 포트 인자 사용
- seed 의 장치 설명(`SDEV_GTEC01` "COM6 / 115200") 은 DB 데이터라 미변경 — 연결값 로컬 설정(devices.local.json)은 이후 단계

## 6. 환경 재확인 (21:46, 사용자 정보 반영, `tools/pcb/ai_pcb_envvars.ps1`)
- vcpkg: `C:\MyData\MyTool\vcpkg-master\vcpkg.exe` 있음, PATH 등록, 버전 2026-09-26 (PC-A 2026-07-27 보다 새것) → **설치 문제 아님**. 점검 스크립트가 PC-A 경로(`C:\MyData\MyTool\vcpkg`)만 찾아 FAIL 로 표시됨
- `JU_WORKSPACE`·`VCPKG_ROOT`·`JU_TOMCAT_HOME`: User·Machine·현재 프로세스 **모두 미설정** (폴더는 있음). 설정 시 점검 PASS 예상
- CMake 4.2.3·VS 18.10: 재설치 아님, 선택적 소폭 업데이트(빌드 5종 미사용)

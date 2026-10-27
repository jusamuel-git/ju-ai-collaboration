# 지금 할 일 (2026-10-27 10:08 기준)

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → **JU-1C** → JU-1c Desktop
(JU-1A/1B/1C는 로컬 commit을 나누고, 1C까지 로컬 Build/Smoke 후 함께 push — ChatGPT 보정 R1)

## 대기 중
| 담당 | 내용 |
|---|---|
| ChatGPT | JU-1C 검토: [reviews/claude/2026-10-27_ju-1c_result.md](../reviews/claude/2026-10-27_ju-1c_result.md) → 1A~1C 묶음 push 판단 |
| 사용자 | **JU-1 통합 검증 재개**: ✅1 05 적용 ✅2 18081 UP ✅3 admin 로그인 (초기 기본 비밀번호를 Git 밖 PC-A 로컬 파일로 전달, 10:07 확인) → 4 최초 비밀번호 변경·메뉴 확인 → `run_ai_ju1_client_register.cmd` → Desktop 동기화 → `run_ai_ju1_local_stop.cmd` → push 판단. 비밀번호 변경 후 전달 파일 삭제. 운영 8081은 push·배포 전까지 사용 금지 |
| 참고 | **admin 로그인 불가 원인 (10:00, 읽기 전용 확인)**: JU-1A~1C·통합 준비 과정에서 실제 DB의 admin 비밀번호·`PW_CHANGE_DT`는 **변경되지 않았다**. 해시 지문(SHA-256 앞 10자리) `6ca10ed083` = 04 백업 직후·05 백업(09:34)·현재 모두 동일 = 저장소 seed/`04` 해시 (JU-0A `5dcc603`, 출처는 10-25 작업 stash). `PW_CHANGE_DT` NULL, `LAST_LOGIN_DT` NULL(성공 로그인 이력 없음), `LOGIN_FAIL_CNT` 1(이번 시도), USE_YN·AUTH 1 정상, 잠금 로직 없음. JU-1A~1C smoke는 테스트 DB의 `smoke_*` 사용자만 사용. **원인: 실제 DB admin 비밀번호는 JU-0A `04`가 넣은 "초기 기본값"이고, 사용자가 알고 있는 기존 비밀번호와 다르다.** 이 기본값은 10-25 stash의 미추적 `database/README.md`에만 있었고, JU-0A 보정 8에서 평문을 저장소에서 지우면서 "설치 담당자에게 별도 전달"로만 남아 실제로 전달되지 않았다. (Claude 작업공간에서 그 기본값이 현재 해시와 일치함을 확인. 값은 기록하지 않음) |
| 사용자 | juproject `admin` 비밀번호 변경 → PC-A user-secrets `Seed:AdminPassword` 새 값으로 |
| 사용자·Claude | 저녁 PC-B 정렬 ([environment/PC_B.md](../environment/PC_B.md)) |

## 미커밋 변경의 위치
| 작업 | 위치 | 상태 |
|---|---|---|
| JU-0 + JU-1 (juprovider) | Claude 작업공간 stash (`feature/ju-0-install`) | 재사용 후보. PC-A 미적용 |
| SYS-0+1 (juproject) | Claude 작업공간 stash (`feature/sys-core-schema`) | SYS-01에 필요한 부분 재사용 완료 |
| JU-1A | PC-A juprovider `feature/ju-1a` 로컬 commit `6fb591a` | PASS. push 보류 |
| JU-1C | PC-A juprovider `feature/ju-1c` **로컬 commit `acac1fa`** (← be1a664) | 빌드 5종·`/me` 메뉴·SPA forward·브라우저 smoke 9건 PASS. push 보류 |
| JU-1B | PC-A juprovider `feature/ju-1b` 로컬 commit `be1a664` (← 6fb591a, 재발급 보정 amend) | 빌드·테스트 8/8·05 테스트 DB·권한/Client/Desktop smoke + 재발급 보정 10건 PASS. push 보류. **실제 DB 05 적용됨 (10-27 09:34)** |

## 최근 확인
- 2026-10-26 10:31 PC-A `feature/env-0`: 환경검사 PASS 30 / WARN 4 / FAIL 0, 로컬 빌드 5종 PASS, `global.json` → SDK 10.0.402
- 2026-10-26 14:28 PC-A `feature/ju-0a`: 로컬 빌드 5종 PASS
- 2026-10-26 14:40 **ENV-0 완료**: Jenkins `juprovider-ai` #12 (`e36a0ed`, `HTTP_PORT` 8081·Health Check OK), `juproject-ai` #2 (`50d7ac3`, SDK 10.0.402) SUCCESS
- 2026-10-26 14:59 JU-0A 테스트 DB 검증 PASS (신규 설치 = 기존 설치+04 = PC-A 사본+04, 04 재실행 무변경)
- 2026-10-26 15:08 JU-0A 실제 DB 04 적용(백업 후) = 신규 설치 동일. JU-0B smoke PASS
- 2026-10-26 15:17 **JU-0A·JU-0B 완료**: juprovider `main` `03f636c` push, Jenkins `juprovider-ai` #13 SUCCESS (Health UP). 테스트 DB 3개 삭제
- 2026-10-26 15:40 SYS-01 migtest: Up/Down(원본 동일)/재Up, smoke 19/19 PASS
- 2026-10-26 15:46 **SYS-01 완료**: 실제 juproject DB Up(백업 후) 검증·smoke PASS, `adb3556` push, Jenkins `juproject-ai` #3 SUCCESS, migtest 삭제
- 2026-10-26 16:40 SEC-01 `68d610b` push, Jenkins `juproject-ai` #4 SUCCESS / JU-1A 로컬 commit `6fb591a` (smoke 26/26)
- 2026-10-27 08:20 JU-1B 로컬 commit `9cd1830` (FAIL 0)
- 2026-10-27 08:35 JU-1B 보정: 재발급은 사용 중 Client만, 재활성화는 재등록에서만 → amend `be1a664` (FAIL 0)
- 2026-10-27 09:15 JU-1C 로컬 commit `acac1fa` — 브라우저 smoke PASS (재로그인 토큰 버그 수정 포함)
- 2026-10-27 09:40 JU-1 통합 검증 스크립트·절차 준비 (PC-A workspace `run_ai_ju1_*.cmd`). 실제 DB 미변경, push 없음
- 2026-10-27 09:34 **실제 juprovider DB migration 05 적용** (사용자 승인): 백업 `C:\MyData\MyDev\backup\juprovider_20261027_0934_before_05.sql`(Dump completed) → 05 1회·재실행 무변경, ju_client 2테이블, 9자리 0건, AUTH0001 전부 FF·그 외 01, 사용자 수 1 불변 — FAIL 0
- 2026-10-27 09:37 `feature/ju-1c` `acac1fa` 로컬 빌드 5종 PASS → 18081 실제 DB로 기동 UP. push 없음
- 2026-10-27 10:00 admin 로그인 불가 조사 (읽기 전용, `run_ai_ju1_admincheck.cmd`): 비밀번호·PW_CHANGE_DT 변경 없음, 원인 = JU-0A 초기 기본 비밀번호 미전달. DB 수정·push 없음
- 2026-10-27 10:07 admin 로그인 해결: 원본 README(10-25 stash)를 `C:\MyData\MyDev\backup\`에만 저장해 전달 (값은 저장소·대화 미기록). DB 수정·push 없음

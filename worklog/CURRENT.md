# 지금 할 일 (2026-10-27 09:40 기준)

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → **JU-1C** → JU-1c Desktop
(JU-1A/1B/1C는 로컬 commit을 나누고, 1C까지 로컬 Build/Smoke 후 함께 push — ChatGPT 보정 R1)

## 대기 중
| 담당 | 내용 |
|---|---|
| ChatGPT | JU-1C 검토: [reviews/claude/2026-10-27_ju-1c_result.md](../reviews/claude/2026-10-27_ju-1c_result.md) → 1A~1C 묶음 push 판단 |
| 사용자 | **JU-1 통합 검증 (준비 완료, 미실행)**: [절차](../reviews/claude/2026-10-27_ju-1_integration_plan.md) — "05 실제 적용 승인" → `run_ai_ju1_db05.cmd`(백업→05→검증) → `run_ai_ju1_local_start.cmd`(18081) → admin 최초 비밀번호 변경·메뉴 확인 → `run_ai_ju1_client_register.cmd` → Desktop 동기화 → push 판단. 되돌리기 `run_ai_ju1_db05_rollback.cmd` |
| 사용자 | juproject `admin` 비밀번호 변경 → PC-A user-secrets `Seed:AdminPassword` 새 값으로 |
| 사용자·Claude | 저녁 PC-B 정렬 ([environment/PC_B.md](../environment/PC_B.md)) |

## 미커밋 변경의 위치
| 작업 | 위치 | 상태 |
|---|---|---|
| JU-0 + JU-1 (juprovider) | Claude 작업공간 stash (`feature/ju-0-install`) | 재사용 후보. PC-A 미적용 |
| SYS-0+1 (juproject) | Claude 작업공간 stash (`feature/sys-core-schema`) | SYS-01에 필요한 부분 재사용 완료 |
| JU-1A | PC-A juprovider `feature/ju-1a` 로컬 commit `6fb591a` | PASS. push 보류 |
| JU-1C | PC-A juprovider `feature/ju-1c` **로컬 commit `acac1fa`** (← be1a664) | 빌드 5종·`/me` 메뉴·SPA forward·브라우저 smoke 9건 PASS. push 보류 |
| JU-1B | PC-A juprovider `feature/ju-1b` 로컬 commit `be1a664` (← 6fb591a, 재발급 보정 amend) | 빌드·테스트 8/8·05 테스트 DB·권한/Client/Desktop smoke + 재발급 보정 10건 PASS. push 보류, 실제 DB 05 미적용 |

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

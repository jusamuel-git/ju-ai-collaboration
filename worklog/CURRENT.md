# 지금 할 일 (2026-10-26 16:30 기준)

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → **JU-1A** → JU-1B → JU-1C → JU-1c Desktop
(JU-1A/1B/1C는 로컬 commit을 나누고, 1C까지 로컬 Build/Smoke 후 함께 push — ChatGPT 보정 R1)

## 대기 중
| 담당 | 내용 |
|---|---|
| Claude | **JU-1A 코드 작성 완료 → PC-A 적용·검증 대기 (16:25 PC-A 연결 끊김)**. 재연결 시 `workspace\run_ai_ju1a.cmd` 실행: SEC-01 commit·push → JU-1A 반영·빌드·기동 조건·smoke → 로컬 commit. 코드 원문: [reviews/claude/2026-10-26_ju-1a.patch](../reviews/claude/2026-10-26_ju-1a.patch) |
| ChatGPT | JU-1A 코드 사전 검토 가능 (위 patch, 테스트 결과는 실행 후 추가) |
| 사용자 | juproject `admin` 비밀번호 변경 → PC-A user-secrets `Seed:AdminPassword` 새 값으로 (`dotnet user-secrets set "Seed:AdminPassword" "<새 값>" --project backend/src/JuProject.Api`) |
| 사용자·Claude | 저녁 PC-B 정렬 ([environment/PC_B.md](../environment/PC_B.md)) |

## 미커밋 변경의 위치
| 작업 | 위치 | 상태 |
|---|---|---|
| JU-0 + JU-1 (juprovider) | Claude 작업공간 stash (`feature/ju-0-install`) | 재사용 후보. PC-A 미적용 |
| SYS-0+1 (juproject) | Claude 작업공간 stash (`feature/sys-core-schema`) | SYS-01에 필요한 부분 재사용 완료 |
| SEC-01 | PC-A juproject `chore/sys-seed-secret` 미커밋 | **승인됨** — commit·push·Jenkins 대기 (`run_ai_ju1a.cmd` 1단계) |
| JU-1A | Claude 작업공간 `feature/ju-1a` (PC-A 미적용) | 코드 완료, PC-A 검증 대기 |

## 최근 확인
- 2026-10-26 10:31 PC-A `feature/env-0`: 환경검사 PASS 30 / WARN 4 / FAIL 0, 로컬 빌드 5종 PASS, `global.json` → SDK 10.0.402
- 2026-10-26 14:28 PC-A `feature/ju-0a`: 로컬 빌드 5종 PASS
- 2026-10-26 14:40 **ENV-0 완료**: Jenkins `juprovider-ai` #12 (`e36a0ed`, `HTTP_PORT` 8081·Health Check OK), `juproject-ai` #2 (`50d7ac3`, SDK 10.0.402) SUCCESS
- 2026-10-26 14:59 JU-0A 테스트 DB 검증 PASS (신규 설치 = 기존 설치+04 = PC-A 사본+04, 04 재실행 무변경)
- 2026-10-26 15:08 JU-0A 실제 DB 04 적용(백업 후) = 신규 설치 동일. JU-0B smoke PASS
- 2026-10-26 15:17 **JU-0A·JU-0B 완료**: juprovider `main` `03f636c` push, Jenkins `juprovider-ai` #13 SUCCESS (Health UP). 테스트 DB 3개 삭제
- 2026-10-26 15:40 SYS-01 migtest: Up/Down(원본 동일)/재Up, smoke 19/19 PASS
- 2026-10-26 15:46 **SYS-01 완료**: 실제 juproject DB Up(백업 후) 검증·smoke PASS, `adb3556` push, Jenkins `juproject-ai` #3 SUCCESS, migtest 삭제

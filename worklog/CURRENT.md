# 지금 할 일 (2026-10-26 14:30 기준)

단계 계획: v1.3 — ENV-0 → **JU-0A** → JU-0B → SYS-01 → JU-1A → JU-1B → JU-1C → JU-1c Desktop
(JU-1A/1B/1C는 로컬 commit을 나누고, 1C까지 로컬 Build/Smoke 후 함께 push — ChatGPT 보정 R1)

## 대기 중
| 담당 | 내용 |
|---|---|
| 사용자 | Jenkins `juprovider-ai`, `juproject-ai` **지금 빌드** 실행 후 SUCCESS 확인 (ENV-0 push 완료, 자동 트리거 없음) |
| ChatGPT | JU-0A diff 검토: [reviews/claude/2026-10-26_ju-0a_result.md](../reviews/claude/2026-10-26_ju-0a_result.md) |
| 사용자 | JU-0A SQL DB 검증 실행 승인 여부 |
| 사용자·Claude | 저녁 PC-B 정렬 ([environment/PC_B.md](../environment/PC_B.md)) |

## 미커밋 변경의 위치
| 작업 | 위치 | 상태 |
|---|---|---|
| ENV-0 | `main` push 완료 (`e36a0ed`, `50d7ac3`), Jenkins `JU_TOMCAT_HOME` 추가됨 | Jenkins 빌드 확인 대기 |
| JU-0A (juprovider database) | **PC-A `feature/ju-0a`** | 로컬 빌드 5종 PASS, 검토 대기 |
| JU-0 + JU-1 (juprovider) | Claude 작업공간 stash (`feature/ju-0-install`) | 재사용 후보. PC-A 미적용 |
| SYS-0+1 (juproject) | Claude 작업공간 stash (`feature/sys-core-schema`) | 재사용 후보. PC-A 미적용 |

## 최근 확인
- 2026-10-26 10:31 PC-A `feature/env-0`: 환경검사 PASS 30 / WARN 4 / FAIL 0, 로컬 빌드 5종 PASS, `global.json` → SDK 10.0.402
- 2026-10-26 14:28 PC-A `feature/ju-0a`: 로컬 빌드 5종 PASS

# 지금 할 일 (2026-10-26 10:40 기준)

단계 계획: v1.3 — **ENV-0** → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → JU-1C → JU-1c Desktop
(JU-1A/1B/1C는 로컬 commit을 나누고, 1C까지 로컬 Build/Smoke 후 함께 push — ChatGPT 보정 R1)

## 대기 중
| 담당 | 내용 |
|---|---|
| ChatGPT | ENV-0 diff·빌드 결과 검토: [reviews/claude/2026-10-26_env-0_result.md](../reviews/claude/2026-10-26_env-0_result.md) |
| 사용자 | Jenkins 전역 변수 `JU_TOMCAT_HOME` 추가 (push **전**) → `feature/env-0` commit/push → Jenkins `main` 확인 |
| 사용자 | PC-A에 Claude Code 설치, 제품 저장소 `CLAUDE.md` 추가 여부 결정 ([WORKFLOW_EFFICIENT.md](../WORKFLOW_EFFICIENT.md) 7장) |
| 사용자·Claude | 오늘 저녁 PC-B를 PC-A 기준에 맞춤 ([environment/PC_B.md](../environment/PC_B.md)) |

## 미커밋 변경의 위치
| 작업 | 위치 | 상태 |
|---|---|---|
| ENV-0 (두 저장소) | **PC-A 작업 사본 `feature/env-0`** | 로컬 빌드 5종 PASS, 검토 대기 |
| JU-0 + JU-1 (juprovider) | Claude 작업공간 stash (`feature/ju-0-install`) | 재사용 후보. PC-A 미적용 |
| SYS-0+1 (juproject) | Claude 작업공간 stash (`feature/sys-core-schema`) | 재사용 후보. PC-A 미적용 |

## 최근 확인
- 2026-10-26 10:31 PC-A `feature/env-0`: 환경검사 PASS 30 / WARN 4 / FAIL 0, 로컬 빌드 5종 PASS, `global.json` → SDK 10.0.402

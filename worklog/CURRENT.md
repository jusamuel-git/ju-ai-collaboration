# 지금 할 일 (2026-10-26 기준)

## 대기 중
| 담당 | 내용 |
|---|---|
| ChatGPT | [재설계 요청](../reviews/claude/2026-10-26_redesign_request.md) — JU-0 / SYS / JU-1을 작은 단계로 다시 설계 |
| 사용자 | 승인 대기 항목 결정 ([decisions/CURRENT.md](../decisions/CURRENT.md) 마지막 절) |
| 사용자·Claude | 오늘 저녁 PC-B를 PC-A 기준에 맞춤 ([environment/PC_B.md](../environment/PC_B.md)) |

## 미커밋 변경의 위치
| 작업 | 브랜치 (Claude 작업공간) | 사본 |
|---|---|---|
| JU-0 + JU-1 (juprovider) | `feature/ju-0-install` | Claude 작업공간 stash, PC-B `workspace\ai_changes` zip/patch |
| SYS-0+1 (juproject) | `feature/sys-core-schema` | 같음 |
| 환경 표준화 (두 저장소 `AI_COLLABORATION.md` 4장) | `chore/dev-env-standard` | PC-A `workspace\ai_changes\devenv` patch |

PC-A 작업 사본은 두 저장소 모두 `main`, 변경 없음.

## 최근 확인
- 2026-10-26 PC-A 환경 점검 FAIL 0, 로컬 빌드 5개 대상 PASS (`main` 기준)

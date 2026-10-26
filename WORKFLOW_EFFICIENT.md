# 토큰 절약 운영 방식 (v1.0, 2026-10-26)

- 목적: 초기 구조 설정(환경 표준·공유 저장소·빌드 스크립트)은 끝났다. 이후에는 **반복 작업을 정해진 틀로 처리**하고, Claude는 **구현에 토큰을 쓴다**.
- 적용: ENV-0 이후 모든 단계 (JU-0A부터)

## 1. 역할과 도구 분리

| 일 | 어디서 | 이유 |
|---|---|---|
| 설계·재설계, 큰 판단 | ChatGPT | 긴 문서 작성·검토는 ChatGPT가 담당 |
| **구현·빌드·수정 반복** | **Claude Code (PC-A, 저장소 폴더에서 실행)** | 셸 직접 실행. 화면 조작·파일 왕복 없음 → 토큰이 가장 적게 든다 |
| 공유 저장소 문서 정리, 원격 조사 | Claude (앱) | 필요할 때만 |
| 결정·commit/push | 사용자 | 변경 없음 |

- **Claude 앱에서 PC를 화면 조작(스크린샷·더블클릭)하는 방식은 비상용**이다. 스크린샷 1장이 수천 토큰이다.
- Claude Code는 저장소 루트의 `CLAUDE.md`를 자동으로 읽는다 → 규칙을 매번 설명할 필요가 없다 (`templates/CLAUDE.md`).

## 1-1. 사용자 지시 방식 (2026-10-26 합의)

- 사용자는 **단계명만** 말한다. 예: ChatGPT에 "ENV-0 결과 확인해줘", Claude Code에 "JU-0A 진행해줘".
- 두 AI는 이 저장소 `README.md → worklog/CURRENT.md → 현재 단계 지시문`을 직접 읽는다. 사용자가 문서를 옮기지 않는다.
- ChatGPT와 Claude 모두 이 저장소에 직접 commit/push한다. 제품 저장소 commit/push는 계속 사용자 승인 후 사용자가 한다.

## 2. 세션 시작 규칙 (읽는 양 고정)

1. `README.md` → `worklog/CURRENT.md`만 읽는다.
2. 현재 단계의 **지시 문서 1개**만 읽는다 (예: ChatGPT 단계 지시). 지난 검토 문서·과거 설계 전체는 다시 읽지 않는다.
3. 코드는 이번 단계에서 고칠 파일과 바로 연결된 파일만 연다. 저장소 전체 탐색 금지.
4. **단계 하나 = 세션 하나.** 단계가 끝나면 `worklog/CURRENT.md`를 갱신하고 새 세션에서 다음 단계를 시작한다 (긴 대화 요약 비용 방지).

## 3. 단계 지시 형식 (ChatGPT → Claude, 짧게)

```
단계: JU-0A
기준: reviews/chatgpt/<문서>.md 의 N장
범위: (파일/기능 목록)
금지: (DB 적용, push 등)
완료 기준: 로컬 빌드 5종 PASS + (추가 확인)
보고: reviews/claude/<날짜>_<단계>_result.md
```

## 4. 정해진 실행 틀 (다시 만들지 않는다)

| 할 일 | 명령 (PC-A, Claude Code) |
|---|---|
| 환경 확인 | `powershell -File tools\ai_dev_env_check.ps1` → **마지막 `합계:` 줄과 WARN/FAIL 줄만** 본다 |
| 로컬 빌드 5종 | `powershell -File tools\ai_local_build.ps1` → **`===== 요약 =====` 이하만** 본다. FAIL일 때만 해당 단계 로그를 연다 |
| 상태 기록 | `git status --short`, `git diff --stat`, `git log -1 --oneline` |

- 전체 로그를 대화에 붙이지 않는다. 요약 줄 → 실패 부분 순서로만 읽는다.
- 스크립트 원본은 이 저장소 `tools/`. PC-A `workspace`의 사본과 다르면 `tools/`가 기준.

## 5. 보고 형식 (Claude → ChatGPT, 1쪽 이내)

`reviews/claude/<날짜>_<단계>_result.md`

1. 결과 한 줄 (PASS/FAIL, 미커밋 여부)
2. 브랜치·HEAD·`git diff --stat`
3. 변경 이유 (파일별 1줄)
4. 빌드 요약표 (5종)
5. 남은 문제 / 결정 필요

- diff 전문은 넣지 않는다. ChatGPT는 브랜치 diff를 직접 보거나, 핵심 부분만 인용한다.
- 같은 내용을 README·worklog·결과 문서에 반복하지 않는다. README는 링크 1줄, worklog는 상태 1줄.

## 6. 하지 않는 것 (토큰 낭비)

- 이미 확정된 환경·결정을 다시 조사·설명하기
- 대화 중 진행 상황 해설, 긴 요약 반복
- 스크린샷으로 확인할 수 있는 것을 파일·명령으로 확인할 수 있는데 화면으로 보기
- 큰 파일을 통째로 읽기 (필요한 범위만 `Select-String`/`grep`, 줄 범위 읽기)
- 하나의 세션에서 여러 단계를 이어서 진행하기

## 7. 남은 준비 (1회)

1. PC-A에 Claude Code 설치·로그인 (사용자)
2. 두 제품 저장소 루트에 `CLAUDE.md` 추가 — **ENV-0에 포함 (ChatGPT 권장, PC-A `feature/env-0` 적용됨)**
3. `tools/` 스크립트를 PC-A `workspace`와 맞춤

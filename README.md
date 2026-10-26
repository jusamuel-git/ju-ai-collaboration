# JU AI Collaboration

ChatGPT와 Claude가 함께 쓰는 설계·조사·결정·검토·환경 문서 저장소.
**AI는 이 파일부터 읽는다.** 실제 소스는 아래 제품 저장소가 기준이다.

## 현재 기준 (Current Baseline)

| 구분 | 문서 |
|---|---|
| 협업 규칙 | [AI_COLLABORATION.md](AI_COLLABORATION.md) (v1.3) |
| 설계 | [architecture/DB_CORE_API.md](architecture/DB_CORE_API.md) (ChatGPT v1.2 — v1.3 재설계 승인, 단계별 구현 중) |
| 유효한 결정 | [decisions/CURRENT.md](decisions/CURRENT.md) |
| 지금 할 일 | [worklog/CURRENT.md](worklog/CURRENT.md) |
| **운영 방식 (토큰 절약)** | [WORKFLOW_EFFICIENT.md](WORKFLOW_EFFICIENT.md) — 세션 시작 때 읽는 범위, 단계 지시·보고 형식, Claude Code 구현 중심 |
| 개발 환경 | [environment/DEV_ENVIRONMENT_STANDARD.md](environment/DEV_ENVIRONMENT_STANDARD.md) |
| 빌드 환경 | [environment/BUILD_ENVIRONMENT_STANDARD.md](environment/BUILD_ENVIRONMENT_STANDARD.md) |
| PC별 상태 | [environment/PC_A.md](environment/PC_A.md) (기준 PC), [environment/PC_B.md](environment/PC_B.md) |

## 지금 진행 중

1. ChatGPT 재설계 v1.3 → Claude 역검토 → **ChatGPT 승인 (8개 보정)**
2. ENV-0: **완료** (main push, Jenkins 2개 SUCCESS)
3. JU-0A·JU-0B: **완료** (`03f636c` push, Jenkins #13 SUCCESS, PC-A DB 04 적용)
4. SYS-01: **완료** (실제 DB 적용, `adb3556` push, Jenkins #3 SUCCESS)
5. SEC-01: **완료** (`68d610b` push, Jenkins #4 SUCCESS)
6. JU-1A 로컬 commit `6fb591a` (push 보류)
7. **JU-1B 로컬 commit `9cd1830` (push 보류)**: [reviews/claude/2026-10-27_ju-1b_result.md](reviews/claude/2026-10-27_ju-1b_result.md)

## 제품 저장소

| 저장소 | 내용 |
|---|---|
| [jusamuel-git/juprovider](https://github.com/jusamuel-git/juprovider) | JuProvider (Spring Boot + Vue + WinForms desktop) — 독립 실행 제품 (JU) |
| [jusamuel-git/juproject](https://github.com/jusamuel-git/juproject) | JuProject (ASP.NET Core + React) — 상위 시스템 (SYS) |

## 폴더

| 폴더 | 내용 |
|---|---|
| `architecture/` | 현재 기준 설계 |
| `environment/` | 개발·빌드 환경 기준, PC별 상태 |
| `decisions/` | 사용자 결정 (`CURRENT.md` + 날짜별) |
| `reviews/claude/`, `reviews/chatgpt/` | 조사·검토·설계 요청 원문 (`YYYY-MM-DD_주제.md`) |
| `worklog/` | `CURRENT.md` + 날짜별 작업 기록 |
| `tools/` | 환경 점검·로컬 빌드 스크립트 |
| `templates/` | 제품 저장소용 `CLAUDE.md` 등 |

## 규칙 요약

- 비밀 값(DB password, JWT secret, Client Key, ConnectionString 비밀번호 등)은 넣지 않는다. 값 대신 `REQUIRED`, `SET/MISSING`, 저장 위치만 적는다.
- 이 저장소는 Claude가 직접 commit/push한다. 제품 저장소의 commit/push는 사용자가 한다.

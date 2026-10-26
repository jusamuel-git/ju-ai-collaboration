# Claude Code 작업 규칙 (이 저장소)

기준 문서: https://github.com/jusamuel-git/ju-ai-collaboration (README → worklog/CURRENT.md → 현재 단계 지시 1개만 읽는다)
운영 방식: 그 저장소의 `WORKFLOW_EFFICIENT.md`

## 반드시
- commit/push 하지 않는다 (사용자만). 작업은 지시된 `feature/<단계>` 브랜치에서.
- 비밀 값(비밀번호, JWT secret, Client Key, ConnectionString)은 코드·문서·로그·보고에 쓰지 않는다.
- DB migration 실제 적용, 스키마·인증·API 계약·의존성 변경은 지시 범위 안에서만. 범위 밖이면 멈추고 보고한다.
- stash 삭제, history 재작성, Tool 설치·업그레이드 금지.
- 지시 범위 밖 리팩터링 금지. 문제를 찾으면 보고만 한다.

## 검증
- 로컬 빌드: `powershell -File C:\MyData\MyDev\workspace\ai_local_build.ps1` → 요약표만 확인, FAIL 단계만 로그 확인
- 완료 기준: 5종 PASS + 단계 지시의 추가 확인

## 보고
- `ju-ai-collaboration/reviews/claude/<날짜>_<단계>_result.md` (1쪽: 결과, 브랜치/HEAD/diff --stat, 파일별 이유, 빌드표, 남은 문제)
- 공유 저장소는 commit/push 해도 된다. `worklog/CURRENT.md` 상태 1줄 갱신.

## 토큰 절약
- 저장소 전체 탐색·큰 파일 통째 읽기 금지. 필요한 파일·줄 범위만.
- 진행 해설 생략. 결과만 보고.

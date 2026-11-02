# PC-A 포맷 전 인수인계 (2026-11-02 12:12) — PC-B 이어서 개발

## 결과
- PC-A 미커밋 변경·stash·추적 안 된 파일: **없음** (juprovider, juproject 모두)
- juprovider 로컬 전용 브랜치 9개 → **origin 에 같은 이름으로 push 완료** (사용자 승인 12:10, main·병합·배포 없음, force 없음). 확인 9/9 PASS, origin/main `fce5048` 그대로
- juproject: 원격에 없는 커밋 없음 (현재 `feature/user-role-filter` = origin 동일)

| 브랜치 | HEAD | 내용 |
|---|---|---|
| `feature/collect-c5` | `854da5c` | **다음 작업 기준** = integration-1 + collect-c4 (C5a) |
| `feature/collect-c4` | `66e9255` | C4 내려받기 API·루틴·간격·시작 문자 + C4b 405 |
| `feature/collect-c1`~`c3` | `5723b03`·`332c229`·`ad9fda3` | C1~C3 |
| `feature/integration-1` | `14d1ab9` | INT-1 (web-01 + sec-s1 + SEC-S1b), 배포 G4·G5 대기 |
| `feature/protocol-ref` | `1d1c1ab` | PR-3 (기존 원격보다 1 커밋 앞 → fast-forward) |
| `feature/sec-s1`, `feature/web-01` | `4187280`, `60bc008` | INT-1 구성 브랜치 |

## PC-B 시작 절차
1. `git -C <workspace>\juprovider fetch origin` → `git checkout -b feature/collect-c5 origin/feature/collect-c5` (다른 브랜치도 같은 방식)
2. 공유 저장소 `tools/ai_local_build.ps1` 를 workspace 에 두고 빌드 5종 확인 (기대: 서버 34/34, Desktop 175/175)
3. 필요 환경: .NET SDK 10.0.400(global.json), JDK 21, Maven, Node(frontend), MariaDB 10.6, Tomcat `setenv.bat` 의 `JU_DB_*`·`JU_JWT_SECRET` (**비밀 값은 PC-B 에서 직접 설정, 문서·저장소에 쓰지 않음**)
4. 실서버 검증 도구: `tools/ai_c4srv.ps1 -Merge` + `tools/c4srvplan/` (경로 `C:\MyData\MyDev\workspace` 기준 — PC-B 경로가 다르면 `$ws` 수정), `ai_changes\ju1a\bcrypt.jsh` 필요(공유 저장소 `tools/bcrypt.jsh`)
5. 실장비(GTEC) 회귀: `tools/ai_c4probe.ps1` + `tools/c4probe/` (PC-B 의 COM 포트 번호 확인 후 인자 수정)

## PC-A 에만 있던 것 (보존 불필요 판단, 확인 요청)
- `workspace\ai_changes\`, 로그·스크립트 196개: 최종본은 공유 저장소 `tools/`·`reviews/` 에 있음
- `workspace\_archive\`, `.vscode\`: 내용 미확인 — 필요하면 직접 백업
- Tomcat `setenv.bat`(비밀 값), MariaDB 실제 DB 데이터: 이번 작업 범위 밖 — **DB 백업 여부는 직접 판단 필요**

## 대기 중 결정
- C5b 착수 (migration 08, 테스트 DB 검증만) / 07 지연 시 08 처리 방식
- G4(실제 DB 06)·G5(main push·Jenkins)
- `MethodArgumentTypeMismatchException` → 400 최소 수정 여부

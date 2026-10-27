# 지금 할 일 (2026-10-27 17:20 기준)

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → JU-1C ✅ → JU-1c Desktop ✅ → **Protocol Reference Implementation — PR-1 ✅(로컬 `02ab18c`), PR-2 구현 완료·PC-A 검증 대기**

## 대기 중
| 담당 | 내용 |
|---|---|
| Claude | **PR-2 Protocol Backend: 코드·스크립트 준비 완료, PC-A 연결 끊김으로 빌드·smoke 미실행** — [patch(초안)](../reviews/claude/2026-10-27_pr2-protocol-backend.patch), 스크립트 `tools/ai_pr2.ps1` (06 테스트 DB 1·2회·신규 설치 동일, Input/Output/Error Contract HTTP smoke, GRP_CREATE·GRP_DELETE·CREATE 원자성 트리거 주입 검증). PC-A 재연결 후 실행 → 결과 업로드 |
| 참고 | JU-1c 범위 밖 보고 항목: template.accdb의 이전 LOCAL_USER, DPAPI(D3), Terminal/IPC 인증(D8), `SyncDevicesToTerminalAsync` TEMP TEST 코드, `InitializeIpcAsync` 미사용, Updater Form1 |
| 사용자 | 운영 Desktop 사용 시 `desktop\app\config\client.json`의 ServerUrl을 18081 → `http://localhost:8081/juprovider/`로 변경 (키는 그대로 유효) |
| 사용자 | juproject `admin` 비밀번호 변경 → PC-A user-secrets `Seed:AdminPassword` 새 값으로 |
| 사용자·Claude | 저녁 PC-B 정렬 ([environment/PC_B.md](../environment/PC_B.md)) |

## 현재 상태
| 저장소 | main | 실제 DB | Jenkins |
|---|---|---|---|
| juprovider | `fce5048` (JU-0A·0B·1A·1B·1C·1c Desktop) | 04·05 적용, admin 비밀번호 변경 완료, Client `PCA_DESKTOP01` 등록 | `juprovider-ai` #15 SUCCESS (Desktop은 Jenkins 대상 아님 → PC-A 로컬 빌드로 검증) |
| juproject | `68d610b` (SYS-01·SEC-01) | SYS-01 적용 | `juproject-ai` #4 SUCCESS |

| 미커밋 | 위치 | 상태 |
|---|---|---|
| PR-1 Action Contract Core | PC-A juprovider `feature/action-contract` 로컬 commit `02ab18c` | **검토 PASS·승인**. push 보류 (PR-3까지 함께) |
| PR-2 Protocol Backend | Claude 작업공간 (PC-A 미반영) | 구현 완료, PC-A 빌드·smoke 대기 |
| JU-0 + JU-1 (juprovider) | Claude 작업공간 stash (`feature/ju-0-install`) | 서버·Vue 부분은 재사용 완료. Desktop 로그인 코드는 없음 |
| SYS-0+1 (juproject) | Claude 작업공간 stash (`feature/sys-core-schema`) | SYS-01에 필요한 부분 재사용 완료 |

## 최근 확인
- 2026-10-26 ENV-0 · JU-0A · JU-0B · SYS-01 · SEC-01 완료 (상세: [2026-10-26.md](2026-10-26.md))
- 2026-10-27 09:34 실제 juprovider DB migration 05 적용 (백업 `C:\MyData\MyDev\backup\juprovider_20261027_0934_before_05.sql`)
- 2026-10-27 10:38 **JU-1 통합 검증 PASS**: Web admin 로그인·최초 비밀번호 변경·권한 메뉴 29개·장치조회, `PCA_DESKTOP01` Client 인증·Desktop 동기화
- 2026-10-27 10:45 **JU-1 완료**: juprovider main `03f636c..acac1fa` push, Jenkins `juprovider-ai` #14 SUCCESS (테스트 8/8, Health UP, 8081 인증 경계 확인) (상세: [2026-10-27.md](2026-10-27.md))
- 2026-10-27 11:15 JU-1c Desktop 사전 조사 업로드 (코드 수정 없음)
- 2026-10-27 11:31 **JU-1c Desktop 로컬 commit `fce5048`**: 빌드 5종 PASS, online/offline smoke 42/42 (서버 401·CLIENT_REJECTED fallback 금지 확인), 테스트 DB 삭제. 발견: template.accdb의 LOCAL_USER가 다른 구성 → 재생성 처리
- 2026-10-27 14:20 JU-1c Desktop 사용자 실기 검증 PASS
- 2026-10-27 14:27 **JU-1c Desktop 완료**: juprovider main `acac1fa..fce5048` push (ff), Jenkins `juprovider-ai` #15 SUCCESS (rev `fce5048`, 테스트 8/8, Health UP). Jenkins 파이프라인은 Core·Backend WAR만 빌드 — Desktop은 PC-A 로컬 빌드 5종·smoke 42/42로 검증
- 2026-10-27 15:05 Action 호출 구조 조사 업로드: 골격(MNU_ID+ACT_CD → HANDLER_ID → Registry) 구현됨, Handler 2/10, Protocol 메뉴(M02010100) Action 없음, MENU_CD 호출·실행 주체 전달·정합성 검사 미구현 (코드 수정 없음)
- 2026-10-27 15:40 Action 계약 설계안 업로드: 지금 확정할 최소 계약 C1~C7(MNU_CD+ACT_CD 키, Input/Output/Error 계약, 실행 맥락, 변경 규칙, Protocol Action 10개)과 미룰 것(Screen/Component/Event/Binding 저장, Draft/Publish/Version/Rollback, 계약 조회 API 등) 구분 (코드 수정 없음)
- 2026-10-27 16:10 결정 AC1~AC13 기록(A1~A10 + contractVersion, UNKNOWN_FIELD, 결정적 다국어 키, Designer 미구현), Protocol Reference 구현 계획 업로드 (코드 수정 없음)
- 2026-10-27 16:35 **PR-1 Action Contract Core 로컬 commit `02ab18c`**: 빌드 5종 PASS, 테스트 19/19, Action smoke 18/18. 기존 응답 변화: Handler 없음 400→501, 정의 없음 400→404, 매핑 없는 경로 500→404
- 2026-10-27 16:39 PR-1 검토 PASS, `02ab18c` 승인
- 2026-10-27 17:20 PR-2 구현 완료 (24 files: migration 06, seed, Protocol DAO/Service/Handler 10개 contractVersion 1, 출력 정규화). PC-A 연결이 끊겨 빌드·smoke 대기

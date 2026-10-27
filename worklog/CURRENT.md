# 지금 할 일 (2026-10-27 15:05 기준)

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → JU-1C ✅ → JU-1c Desktop ✅ → **다음 단계 지시 대기**

## 대기 중
| 담당 | 내용 |
|---|---|
| ChatGPT·사용자 | **Action 호출 구조 재확인 → Protocol 첫 정식 적용 결정 P1~P8**: [reviews/claude/2026-10-27_action-structure_precheck.md](../reviews/claude/2026-10-27_action-structure_precheck.md). 제품 코드 수정 없음 |
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

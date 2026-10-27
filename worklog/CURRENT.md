# 지금 할 일 (2026-10-27 10:48 기준)

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → JU-1C ✅ → **JU-1c Desktop**
(JU-1A/1B/1C는 로컬 commit을 나누고, 1C까지 로컬 Build/Smoke 후 함께 push — ChatGPT 보정 R1)

## 대기 중
| 담당 | 내용 |
|---|---|
| ChatGPT | JU-1c Desktop 단계 지시 (후보: Client 화면에 동기화 상태 표시 — 현재 Form1은 Debug 출력만) |
| 사용자 | 운영 Desktop 사용 시 `desktop\app\config\client.json`의 ServerUrl을 18081 → `http://localhost:8081/juprovider/`로 변경 (키는 그대로 유효) |
| 사용자 | juproject `admin` 비밀번호 변경 → PC-A user-secrets `Seed:AdminPassword` 새 값으로 |
| 사용자·Claude | 저녁 PC-B 정렬 ([environment/PC_B.md](../environment/PC_B.md)) |

## 미커밋 변경의 위치
| 작업 | 위치 | 상태 |
|---|---|---|
| JU-0 + JU-1 (juprovider) | Claude 작업공간 stash (`feature/ju-0-install`) | 재사용 후보. PC-A 미적용 |
| SYS-0+1 (juproject) | Claude 작업공간 stash (`feature/sys-core-schema`) | SYS-01에 필요한 부분 재사용 완료 |
| JU-1A | juprovider main `6fb591a` | **push 완료** (10-27 10:42) |
| JU-1C | juprovider main `acac1fa` | **push 완료**, Jenkins `juprovider-ai` #14 SUCCESS |
| JU-1B | juprovider main `be1a664` | **push 완료**. 실제 DB 05 적용됨 (10-27 09:34) |

## 최근 확인
- 2026-10-26 10:31 PC-A `feature/env-0`: 환경검사 PASS 30 / WARN 4 / FAIL 0, 로컬 빌드 5종 PASS, `global.json` → SDK 10.0.402
- 2026-10-26 14:28 PC-A `feature/ju-0a`: 로컬 빌드 5종 PASS
- 2026-10-26 14:40 **ENV-0 완료**: Jenkins `juprovider-ai` #12 (`e36a0ed`, `HTTP_PORT` 8081·Health Check OK), `juproject-ai` #2 (`50d7ac3`, SDK 10.0.402) SUCCESS
- 2026-10-26 14:59 JU-0A 테스트 DB 검증 PASS (신규 설치 = 기존 설치+04 = PC-A 사본+04, 04 재실행 무변경)
- 2026-10-26 15:08 JU-0A 실제 DB 04 적용(백업 후) = 신규 설치 동일. JU-0B smoke PASS
- 2026-10-26 15:17 **JU-0A·JU-0B 완료**: juprovider `main` `03f636c` push, Jenkins `juprovider-ai` #13 SUCCESS (Health UP). 테스트 DB 3개 삭제
- 2026-10-26 15:40 SYS-01 migtest: Up/Down(원본 동일)/재Up, smoke 19/19 PASS
- 2026-10-26 15:46 **SYS-01 완료**: 실제 juproject DB Up(백업 후) 검증·smoke PASS, `adb3556` push, Jenkins `juproject-ai` #3 SUCCESS, migtest 삭제
- 2026-10-26 16:40 SEC-01 `68d610b` push, Jenkins `juproject-ai` #4 SUCCESS / JU-1A 로컬 commit `6fb591a` (smoke 26/26)
- 2026-10-27 08:20 JU-1B 로컬 commit `9cd1830` (FAIL 0)
- 2026-10-27 08:35 JU-1B 보정: 재발급은 사용 중 Client만, 재활성화는 재등록에서만 → amend `be1a664` (FAIL 0)
- 2026-10-27 09:15 JU-1C 로컬 commit `acac1fa` — 브라우저 smoke PASS (재로그인 토큰 버그 수정 포함)
- 2026-10-27 09:40 JU-1 통합 검증 스크립트·절차 준비 (PC-A workspace `run_ai_ju1_*.cmd`). 실제 DB 미변경, push 없음
- 2026-10-27 09:34 **실제 juprovider DB migration 05 적용** (사용자 승인): 백업 `C:\MyData\MyDev\backup\juprovider_20261027_0934_before_05.sql`(Dump completed) → 05 1회·재실행 무변경, ju_client 2테이블, 9자리 0건, AUTH0001 전부 FF·그 외 01, 사용자 수 1 불변 — FAIL 0
- 2026-10-27 09:37 `feature/ju-1c` `acac1fa` 로컬 빌드 5종 PASS → 18081 실제 DB로 기동 UP. push 없음
- 2026-10-27 10:00 admin 로그인 불가 조사 (읽기 전용, `run_ai_ju1_admincheck.cmd`): 비밀번호·PW_CHANGE_DT 변경 없음, 원인 = JU-0A 초기 기본 비밀번호 미전달. DB 수정·push 없음
- 2026-10-27 10:07 admin 로그인 해결: 원본 README(10-25 stash)를 `C:\MyData\MyDev\backup\`에만 저장해 전달 (값은 저장소·대화 미기록). DB 수정·push 없음
- 2026-10-27 10:22 `ai_ju1_client_register.ps1` 보정: 실행 폴더를 API 호출 전에 확인(`juprovider.client.exe` 없으면 중단, 기본값 `desktop\app` = Directory.Build.props OutputPath) / 사용 중 Client는 확인 후 `POST /api/admin/clients/{id}/key` 재발급, 사용 중지는 재등록 선택 / 키는 `{실행 폴더}\config\client.json`에만(콘솔·로그 미출력, `desktop/app/`은 .gitignore). DB 수정·product push 없음
- 2026-10-27 10:28 PC-A 반영 누락 정정: 10:22 보정본이 PC-A에 덮어써지지 않아(이전 파일 유지) 사용자 재실행에서 같은 400 발생 → `ai_ju1_client_register_v2.ps1`로 새로 배치하고 `run_ai_ju1_client_register.cmd`가 v2를 실행하도록 변경 (PC-A 파일 크기로 반영 확인). DB 변경 없음
- 2026-10-27 10:33 **Desktop 동기화 PASS** (읽기 전용 `run_ai_ju1_synccheck.cmd`): client.json 10:28:36 작성(18081, `PCA_DESKTOP01`, 키 길이 43) → Client 실행 후 `ju_client.LAST_SEEN_DT` 10:29:21 갱신(Client 키 인증 성공 시에만 갱신), 같은 시각 로컬 `data\juprovider.accdb` 갱신(서버 장치 목록 반영). USE_YN Y. 참고: Client 화면(Form1)은 동기화 결과를 표시하지 않음(Debug 출력만) → JU-1c Desktop 단계 후보
- 2026-10-27 10:38 **JU-1 통합 검증 PASS** (사용자 확인): Web admin 로그인·최초 비밀번호 변경·권한 메뉴 29개·장치조회, `PCA_DESKTOP01` Client 인증·Desktop 동기화
- 2026-10-27 10:42 **JU-1A~1C main push** `03f636c..acac1fa` (ff, `run_ai_ju1_push.cmd`): 18081 종료 확인, 초기 DB README(비밀번호 포함) 로컬 사본 삭제
- 2026-10-27 10:45 **Jenkins `juprovider-ai` #14 SUCCESS** (rev `acac1fa`, 테스트 8/8, Health UP). 8081 확인: 로그인 화면·`/console/**` forward 200, 토큰 없는 `/api/auth/me` 401, Client 키 없는 `/api/core/sync/**` 401

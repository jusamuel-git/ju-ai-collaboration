# 지금 할 일 (2026-10-28 08:30 기준 — 오늘 작업 PC는 PC-A, PC-B는 저녁 정리)

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → JU-1C ✅ → JU-1c Desktop ✅ → **Protocol Reference Implementation — PR-1 `02ab18c` + PR-2 `157635a` 원격 브랜치 `feature/protocol-ref` (**PC-B 재현 PASS**), PR-3 보류**

## 대기 중
| 담당 | 내용 |
|---|---|
| 사용자·ChatGPT | **SEC-S1 결과 검토**: [reviews/claude/2026-10-28_sec-s1_result.md](../reviews/claude/2026-10-28_sec-s1_result.md) — `feature/sec-s1` 로컬 commit `4187280` (push 없음), 빌드 5종·테스트 9/9·smoke 25/25 |
| ChatGPT·사용자 | **SYSINFO-01 조사·설계안 검토**: [reviews/claude/2026-10-28_sysinfo-01_precheck.md](../reviews/claude/2026-10-28_sysinfo-01_precheck.md) — 최소 계약 S1~S7, 결정 요청 SI-Q1~Q6, 후속 항목 분리 (코드 수정 없음) |
| ChatGPT·사용자 | **PC-B 재현 검증 PASS 검토**: [reviews/claude/2026-10-27_pcb-protocol-ref_verify.md](../reviews/claude/2026-10-27_pcb-protocol-ref_verify.md) — 빌드 5종 PASS, 테스트 23/23, 06(1·2회·신규 설치 동일), HTTP smoke 64/64 + 보완 14/14 (PC-A와 차이 없음). 다음: PR-2 검토 결과에 따라 PR-3 또는 main 반영 판단. **main merge/push 금지 유지** |
| ChatGPT | PR-2 결과 검토: [result](../reviews/claude/2026-10-27_pr2-protocol-backend_result.md) (PC-A 빌드 5종, 테스트 23/23, HTTP smoke 58/58) |
| Claude | **PR-3 Protocol Vue 구현 완료, PC-A 실행 대기** (화면 잠금): `feature/protocol-ref` 위 8파일 — `ProtocolManagement.vue`(Group Grid·Protocol Grid·상세 Form·Packet Grid·Group Dialog, 모두 Action v1), `actionApi.executeByCode`, `session.canAction`, 라우트 `/console/device/protocol`, 레거시 `/api/core/protocol-groups`·`/protocols/{grp}` 제거. 스크립트 `tools/ai_pr3.ps1`(빌드·06 테스트 DB·API smoke, 서버 유지) → 브라우저 smoke → `ai_pr3_finish.ps1`(종료·DB 삭제·로컬 commit). PR-2 ChatGPT 검토 문서는 아직 없음 |
| 참고 | JU-1c 범위 밖 보고 항목: template.accdb의 이전 LOCAL_USER, DPAPI(D3), Terminal/IPC 인증(D8), `SyncDevicesToTerminalAsync` TEMP TEST 코드, `InitializeIpcAsync` 미사용, Updater Form1 |
| 사용자 | 운영 Desktop 사용 시 `desktop\app\config\client.json`의 ServerUrl을 18081 → `http://localhost:8081/juprovider/`로 변경 (키는 그대로 유효) |
| 사용자 | juproject `admin` 비밀번호 변경 → PC-A user-secrets `Seed:AdminPassword` 새 값으로 |
| 사용자·Claude | **저녁 PC-B 정리** (사용자 결정 10/28): ① 기존 작업 폴더의 10/25 이전 미커밋 변경 **모두 삭제** (juprovider `feature/ju-0-install` 40건, juproject `feature/sys-core-schema` 36건) → origin 기준으로 정렬 ② PC-A와 같은 환경: JDK/Maven `MyDev` 경로, vcpkg(`MyTool\vcpkg` + VCPKG_ROOT), JAVA_HOME·JU_WORKSPACE·JU_TOMCAT_HOME 등 환경변수 ③ Desktop `desktop\app\config\template.accdb` 배치 (아래 참고) ④ 검증 worktree `workspace_verify` 정리 여부 결정 |
| 참고 | PC-B 사용자 확인(10/28): 서버 정상. Desktop Client는 `config\template.accdb` 없음으로 실행 안 됨 → **환경 문제로 판단**. `desktop/app/`은 .gitignore 대상이라 template이 저장소에 없음 (PC-A에는 로컬 파일만 있음). 저녁 정리 때 PC-A 파일을 복사해 배치. 저장소에 template을 둘지(예: `desktop/resources/`)는 별도 결정 사항 |

## 현재 상태
| 저장소 | main | 실제 DB | Jenkins |
|---|---|---|---|
| juprovider | `fce5048` (JU-0A·0B·1A·1B·1C·1c Desktop) | 04·05 적용, admin 비밀번호 변경 완료, Client `PCA_DESKTOP01` 등록 | `juprovider-ai` #15 SUCCESS (Desktop은 Jenkins 대상 아님 → PC-A 로컬 빌드로 검증) |
| juproject | `68d610b` (SYS-01·SEC-01) | SYS-01 적용 | `juproject-ai` #4 SUCCESS |

| 미커밋 | 위치 | 상태 |
|---|---|---|
| PR-1 + PR-2 | **원격 브랜치 `feature/protocol-ref` @ `157635a`** (main 미반영) | PR-1 검토 PASS, PR-2 PC-A PASS + **PC-B 재현 PASS**, 검토 대기 |
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
- 2026-10-27 17:05 **PR-2 Protocol Backend 로컬 commit `157635a`**: 빌드 5종, 테스트 23/23, 06(1·2회·신규 설치 동일), HTTP smoke 58/58 — 원자성(GRP_CREATE·GRP_DELETE·CREATE 트리거 주입 rollback), GRP_DELETE 장치+실험 전체 선검사 409 무변경
- 2026-10-27 17:04 **PC-A 작업 종료**: `feature/protocol-ref`(`02ab18c`, `157635a`)를 원격에 브랜치로만 push. origin/main은 `fce5048` 그대로. 제품 코드 수정 중단, PC-B 검증 대기
- 2026-10-27 22:45 **PC-B 재현 검증 PASS** (`JUSAMUEL`, worktree `workspace_verify`): HEAD `157635a`·계보 확인, 환경 PASS 22/WARN 9/FAIL 1(vcpkg, 빌드 무관), 빌드 5종 PASS, 테스트 23/23, 06 재실행 무변경·신규 설치 동일, HTTP smoke 64/64 + Device GET·501 보완 14/14. 테스트 DB·프로세스 정리. 제품 코드 수정·push 없음
- 2026-10-28 08:14 SYSINFO-01 결정: S1~S7 승인, SI-Q1~Q6 (로컬 override 우선, Client PUT 차단, template 저장소화, ju_schema_version, Sync 응답 변경은 PR-3 이후, 순서 SEC-S1 → PR-3 → SYSINFO-02 → SYSINFO-03 → SYNC-01)
- 2026-10-28 08:25 **SEC-S1 로컬 commit `4187280`** (`feature/sec-s1` ← main): Client 체인 sync GET만 허용, Device PUT 제거, Desktop SaveDeviceAsync 제거. 빌드 5종, 테스트 9/9, smoke 25/25, 장치 정의 무변경. 남은 문제: Client 403 메시지 문구
- 2026-10-28 08:30 SYSINFO-01 사전 조사 업로드: 버전 정보 노출·스키마 버전 테이블 없음, Device 전체 동기화만(비활성 장치 로컬 잔존), 장치 설정 전역 1벌(ClientId 구분 없음), Client→서버 장치 PUT 경로 존재(미호출), template.accdb 저장소 없음 (코드 수정 없음)
- 2026-10-28 07:53 사용자: PC-B 서버 정상 확인, Client는 template.accdb 없음(환경 문제). 오늘은 PC-A 작업, PC-B는 저녁에 미커밋 삭제·환경 정렬

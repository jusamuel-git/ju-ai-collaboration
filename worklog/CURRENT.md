# 지금 할 일 (2026-10-28 08:30 기준 — 오늘 작업 PC는 PC-A, PC-B는 저녁 정리)

> **우선 작업 (10/28 09:12 사용자 지시): 금요일(10/30) 17시까지 Protocol CRUD 안정화.** 신규 기능 확대 중단.
> 기준: PR-1 `02ab18c` · PR-2 `157635a` · PR-3 `1d1c1ab` (`feature/protocol-ref`), SEC-S1 `4187280` (별도 브랜치).
> 보류(금요일 이후): SYSINFO-02(계획 검토 완료), SYNC-01, Designer, Updater. main merge/push·실제 DB 06 적용은 사용자 승인 전 금지.

단계 계획: v1.3 — ENV-0 → JU-0A → JU-0B → SYS-01 → JU-1A → JU-1B → JU-1C ✅ → JU-1c Desktop ✅ → **Protocol Reference Implementation — PR-1 `02ab18c` + PR-2 `157635a` 원격 브랜치 `feature/protocol-ref` (**PC-B 재현 PASS**), PR-3 보류**

## 대기 중
| 담당 | 내용 |
|---|---|
| 사용자 | **C1 PASS** [결과](../reviews/claude/2026-10-30_c1_result.md) — `feature/collect-c1` @ `bcbd6f5` (← main), Desktop 테스트 63/63, push 없음 |
| ChatGPT | **과거 소스 ZIP 조사 구조 검토**: [reviews/claude/2026-10-30_legacy-zip_survey.md](../reviews/claude/2026-10-30_legacy-zip_survey.md) — `backup\juprovider-backup.zip`(10-16, 823파일) 1개. 기능 7개 영역 비교, 재사용 후보 5개(모두 참조 후 재작성), 미사용 항목, 결정 L-Q1~Q5. 과거 기능은 모두 동작 미검증. 조사만(코드·DB 변경 없음) |
| 사용자 | **INT-1 PASS 인정 (10/28 09:59), 배포 보류 — 금요일(10/30) 17시 이후 G4(실제 DB 06)·G5(main push·Jenkins) 승인 단계**: [결과](../reviews/claude/2026-10-28_int1_result.md) · [배포 체크리스트](../reviews/claude/2026-10-28_deploy_checklist.md). `feature/integration-1` @ `14d1ab9` 로컬 유지, 제품 코드 추가 수정 중단, 8081 기존 상태 유지 |
| 사용자 | **WEB-02/03 결과 검토**: [reviews/claude/2026-10-28_web-02-03_result.md](../reviews/claude/2026-10-28_web-02-03_result.md) — `feature/web-01` 로컬 commit `60bc008` (← protocol-ref `1d1c1ab`, push 없음), 공개 홈 `/`·콘솔 `/console/**` 분리, 자동 54/54 + 브라우저(복귀 URL·로그아웃·조회자·비밀번호 변경 필수) PASS. clearable은 Action Contract v2 후속 과제 |
| 사용자 | **PR-3 최종 확인 PASS (FAIL 0, 코드 수정 없음)**: [reviews/claude/2026-10-28_pr3-final-check.md](../reviews/claude/2026-10-28_pr3-final-check.md) — API smoke 12/12, 권한·자동생성·패킷 교체·논리삭제/재사용·참조 409 전부 PASS. 결정 대기: 선택 텍스트 지우기 최소 수정안(6파일, 계약 v1 유지) |
| 사용자·ChatGPT | **SYSINFO-02 단계별 계획 + 보완 과제 A1~A5 검토·승인 (G1)**: [reviews/claude/2026-10-28_sysinfo-02_plan.md](../reviews/claude/2026-10-28_sysinfo-02_plan.md) — 서버 build-info·`/api/system/version`, migration 07 `ju_schema_version`(기존 이력 검증 후 기록), Desktop 공통 Version, 빈 template.accdb·client.sample.json, 통합 절차(I-1~I-7), 결정 S2-Q1~Q5. **제품 코드 수정 없음, 승인 대기** |
| 사용자·ChatGPT | **SEC-S1 결과 검토**: [reviews/claude/2026-10-28_sec-s1_result.md](../reviews/claude/2026-10-28_sec-s1_result.md) — `feature/sec-s1` 로컬 commit `4187280` (push 없음), 빌드 5종·테스트 9/9·smoke 25/25 |
| ChatGPT·사용자 | **SYSINFO-01 조사·설계안 검토**: [reviews/claude/2026-10-28_sysinfo-01_precheck.md](../reviews/claude/2026-10-28_sysinfo-01_precheck.md) — 최소 계약 S1~S7, 결정 요청 SI-Q1~Q6, 후속 항목 분리 (코드 수정 없음) |
| ChatGPT·사용자 | **PC-B 재현 검증 PASS 검토**: [reviews/claude/2026-10-27_pcb-protocol-ref_verify.md](../reviews/claude/2026-10-27_pcb-protocol-ref_verify.md) — 빌드 5종 PASS, 테스트 23/23, 06(1·2회·신규 설치 동일), HTTP smoke 64/64 + 보완 14/14 (PC-A와 차이 없음). 다음: PR-2 검토 결과에 따라 PR-3 또는 main 반영 판단. **main merge/push 금지 유지** |
| ChatGPT | PR-2 결과 검토: [result](../reviews/claude/2026-10-27_pr2-protocol-backend_result.md) (PC-A 빌드 5종, 테스트 23/23, HTTP smoke 58/58) |
| 사용자·ChatGPT | **PR-3 결과 검토**: [reviews/claude/2026-10-28_pr3-protocol-vue_result.md](../reviews/claude/2026-10-28_pr3-protocol-vue_result.md) — `feature/protocol-ref` 로컬 commit `1d1c1ab` (push 없음), 빌드 5종·테스트 23/23·API smoke·브라우저 smoke(관리자·조회자) PASS. 다음: SYSINFO-02 단계 구현 계획. PR-2 ChatGPT 검토 문서는 아직 없음 |
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
- 2026-10-30 09:30 C1 로컬 commit `bcbd6f5` (표현식·Framer·Parser, 테스트 63/63, 빌드 스크립트에 Desktop 테스트 추가)
- 2026-10-30 08:49 사용자: C0 조건부 승인, C0-Q1~Q8 채택 → C1 구현 준비안 업로드 (코드·DB 변경 없음, 구현은 별도 승인)
- 2026-10-30 08:45 사용자: 수집 경로 설계 조건부 승인·구현 보류, C0 공통 계약 보완 요청 → 09:10 C0 설계 업로드 (설계만)
- 2026-10-30 08:50 수집 경로 설계 업로드 (설계만, 코드·DB 변경 없음). 사용자 방향: 현재 소스 기준, Protocol→Device→Data 우선, Experiment Data 별도, Viewer·Designer 선택형
- 2026-10-30 08:20 과거 JuProvider 소스 ZIP 조사 업로드 (조사만). 과거 application.yml에 평문 기본 비밀번호 있음 → 값 기록 안 함, 메일 비밀번호 변경 여부 결정 요청
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
- 2026-10-28 08:47 **PR-3 로컬 commit `1d1c1ab`** (`feature/protocol-ref`): ProtocolManagement.vue(Action v1만 사용), executeByCode, 권한 비트 버튼, 레거시 protocol 조회 API 제거. 브라우저 smoke: 필드 오류 표시(REQUIRED·INVALID_VALUE·DUPLICATE), 기본 프로토콜 자동생성, 409 무변경, 조회자 버튼 숨김·서버 403. 남은 문제: 선택 항목 비우기 불가(COALESCE)
- 2026-10-28 08:52 사용자 판단: PR-1 승인, PR-2 기능 PASS(최종 코드 검토 문서 없음), PR-3 조건부 승인, SEC-S1 통합 대기, main 금지 유지. 보완 과제 5건 + SYSINFO-02 계획 요청
- 2026-10-28 09:25 사용자: Protocol CRUD 완료 상태 유지, clearable은 Action Contract v2 설계 시 처리(후속). 새 작업 WEB-01 홈페이지/콘솔 분리
- 2026-10-28 09:47 18081 미리보기(web-01) 사용자 확인 OK
- 2026-10-28 09:59 사용자: INT-1 PASS 인정. 금요일 17시까지 통합 브랜치 유지·코드 수정 중단·06/main/Jenkins 금지·SYSINFO-02 보류. 배포 체크리스트 작성
- 2026-10-28 09:55 **INT-1 `feature/integration-1` @ `14d1ab9`** (로컬): web-01 + merge sec-s1(충돌 없음) + SEC-S1b 403 문구. 27/27, 회귀 75 PASS. 미리보기 서버·DB 정리
- 2026-10-28 09:41 **WEB-02/03 로컬 commit `60bc008`** (`feature/web-01`): Vue 7파일, 빌드 5종·테스트 23/23·Protocol CRUD 회귀 35/35·브라우저 인증 흐름 PASS
- 2026-10-28 09:18 PR-3 최종 확인 (`1d1c1ab`, PC-A): 빌드 5종, 테스트 23/23, API smoke 12/12, CRUD 최종 35항목 PASS. 수정 불필요 → commit 없음
- 2026-10-28 09:10 SYSINFO-02 계획 업로드 (A1 빈 문자열=지우기 계약, A2 PTL_CD 한계 기록, A3 403 문구 수정 계획, A4 smoke 재실행은 통합 검증에서, A5 통합·06 적용 절차) — 코드 수정 없음
- 2026-10-28 08:30 SYSINFO-01 사전 조사 업로드: 버전 정보 노출·스키마 버전 테이블 없음, Device 전체 동기화만(비활성 장치 로컬 잔존), 장치 설정 전역 1벌(ClientId 구분 없음), Client→서버 장치 PUT 경로 존재(미호출), template.accdb 저장소 없음 (코드 수정 없음)
- 2026-10-28 07:53 사용자: PC-B 서버 정상 확인, Client는 template.accdb 없음(환경 문제). 오늘은 PC-A 작업, PC-B는 저녁에 미커밋 삭제·환경 정렬

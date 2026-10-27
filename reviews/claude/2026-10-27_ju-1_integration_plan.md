# JU-1 통합 검증 절차 — 실제 juprovider DB migration 05 (준비 완료, 미실행)

- 대상: PC-A juprovider `feature/ju-1c` @ `acac1fa` (1A `6fb591a` ← 1B `be1a664` ← 1C). **push 안 함**
- 현재 실제 DB: V2.3(04 적용), 05 미적용 → `ju_client` 없음, `AUTH_ATTR` 9자리, 사용자 `admin` 1명
- 운영 Tomcat 8081(main `03f636c`)은 건드리지 않는다. 검증 서버는 `java -jar` 18081
- 스크립트: PC-A `C:\MyData\MyDev\workspace\run_ai_ju1_*.cmd` (사본 `tools/ai_ju1_*`). 비밀 값은 setenv.bat에서 읽어 환경변수로만 전달, 로그에 기록 안 함

## 주의 (적용 순서)
05 적용 후에는 **운영 Tomcat 8081의 main(03f636c)** 이 새 11자리 AUTH_ATTR을 읽는다. main은 JU-1 권한 비트를 모르므로 메뉴 코드 앞 9자리만 쓰는지 영향 확인 필요 → 05 적용 ~ 1A~1C push·Jenkins 배포 사이 시간을 짧게 두거나, 그 사이 8081은 사용하지 않는다.

## 절차
| # | 누가 | 실행 | 확인 |
|---|---|---|---|
| 0 | 사용자 | **승인**: "05 실제 적용 승인" | — |
| 1 | 사용자 또는 Claude | `run_ai_ju1_db05.cmd` | 로그 `ai_ju1_db05_DESKTOP-CE5BGKK.log` — 브랜치 확인 → 백업 `C:\MyData\MyDev\backup\juprovider_<ts>_before_05.sql`(Dump completed 확인, 실패 시 중단) → 05 적용 → 재실행 CHECKSUM 무변경 → ju_client 2테이블, 9자리 0건, AUTH0001 전부 FF, 그 외 전부 01, 사용자 수 불변. `FAIL 0` + `DB05-DONE` |
| 2 | 사용자 또는 Claude | `run_ai_ju1_local_start.cmd` | 로컬 빌드 5종 PASS → 18081 `UP` (실제 DB) |
| 3 | 사용자 | 브라우저 `http://localhost:18081/juprovider/` → `admin` 로그인 | 비밀번호 변경 화면으로 강제 이동 |
| 4 | 사용자 | 새 비밀번호로 변경 | 자동 재로그인 → 콘솔, 상단 세션 바, 메뉴 전체 표시(어드민) |
| 5 | 사용자 | 장치관리 등 메뉴 이동, 로그아웃/재로그인, 주소창에 `/juprovider/console/...` 직접 입력·새로고침 | 정상 표시. 로그아웃 후 콘솔 접근 → 로그인 화면 |
| 6 | 사용자 | `run_ai_ju1_client_register.cmd` (아이디·비밀번호·CLIENT_ID 입력) | Client 등록, `{Client 실행 폴더}\config\client.json` 생성 (키는 이 파일에만, 화면·로그 출력 없음) |
| 7 | 사용자 | Desktop Client 실행 (ServerUrl = 18081) | 서버 동기화 성공 (OFFLINE 아님) |
| 8 | 사용자 또는 Claude | `run_ai_ju1_local_stop.cmd` | 18081 종료 |
| 9 | 사용자 결정 | 1A~1C main ff/push → Jenkins `juprovider-ai` | 8081 Health UP, 로그인·메뉴 재확인, client.json ServerUrl을 8081로 |

## 되돌리기
- `run_ai_ju1_db05_rollback.cmd`: `ju_client`·`ju_client_detail` DROP → 1번에서 만든 백업으로 복원 (`ai_ju1_db05_lastbackup.txt`가 가리키는 파일). 로그 `ai_ju1_db05_rollback_DESKTOP-CE5BGKK.log`의 `ju_client 남음: 0`, `ROLLBACK-DONE`
- 4번(비밀번호 변경) 이후 되돌리면 admin 비밀번호도 05 이전 값으로 돌아간다

## 이미 검증된 것 (테스트 DB, JU-1B)
05 1·2회 적용 무변경, 기존 DB+05 = 신규 설치 구조 동일, 권한·Client·Desktop smoke PASS

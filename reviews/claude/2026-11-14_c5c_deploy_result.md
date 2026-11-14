# C5c 서버 배포 결과 — **PASS** (8081 = `4915759`)

- 일시: 2026-11-14 22:03 ~ 22:20, PC-B
- 승인: 사용자 22:01 "c5d로 배포하고 JU_TOMCAT_HOME도 설정해주고 8081로 기동해줘"
- 사전 검증: [2026-11-14_c5c_deploy_precheck.md](2026-11-14_c5c_deploy_precheck.md) · 체크리스트 [2026-11-14_c5c_deploy_checklist.md](2026-11-14_c5c_deploy_checklist.md)
- 도구
  - `tools/ai_c5c_deploy_go.ps1`: 백업, main fast-forward, push
  - `tools/ai_c5c_deploy_manual.ps1`: 배포. health가 실패하면 자동 복구
  - `tools/ai_c5c_deploy_status.ps1`: Jenkins·8081 상태 확인 (읽기 전용)

## 1. 결과

| 단계 | 내용 | 결과 |
|---|---|---|
| 백업 | `C:\MyData\MyDev\backup\c5c_deploy_20261114_220358\`<br>- 10/25 WAR: SHA256 `DBAF8738B0D7F42F…`, 사전 검증과 같음<br>- DB 덤프: 비교 해시 `12CD3AA09A237DBC`<br>Tomcat 쪽 백업: `tomcat\backup\juprovider-20261114-221943.war` | PASS |
| main | `fce5048` → `4915759` fast-forward로 origin push (G5) | PASS |
| 배포 | 정리 → 후보 WAR 복사 → `startup.bat` (Jenkinsfile 7~10단계와 같은 순서) | PASS |
| D-1 | health 200, `success=true`, `status=UP` (25초) | PASS |
| D-2~5 | 인증 없는 요청 모두 401: 없는 사용자 로그인, `sync/devices`, `sync/data-map`(키 없음), `languages`(JWT 없음) | PASS |
| D-6·7 | 공개 홈 `/` 200, 콘솔 직접 URL 200 | PASS |
| D-8 | Tomcat 로그 SEVERE/ERROR/Exception 0건 | PASS |
| D-9 | 배포 WAR SHA256 `EC80C07DA99241E4` = 사전 검증 후보 WAR. 회귀 59/59와 Tomcat 리허설을 통과한 WAR | PASS |
| D-10 | 실제 DB 덤프가 배포 전과 같음 (`12CD3AA09A237DBC`) | PASS |

## 2. Jenkins 대신 수동 배포한 이유

- **`JU_TOMCAT_HOME` 미설정**
  - Claude 앱 내장 브라우저의 Jenkins(localhost:8080)가 로그인 화면(403)이었다.
  - 사용자의 Chrome은 이 세션에서 연결되지 않았다.
  - 비밀번호는 Claude가 입력하지 않는다.
  - 그래서 Jenkins 전역 속성은 아직 비어 있다.
- **대신 한 일**
  - 사전 검증에서 리허설한 방식(H-1~H-11)으로 수동 배포했다.
  - 배포 WAR는 PC-B 로컬 빌드다. 커밋 `4915759`(= main)에서 빌드했고, 서버 테스트 62와 회귀 59/59를 통과했다.
  - Jenkins 빌드 기록(#1, 10/25)은 갱신되지 않았다.

## 3. 남은 일

- **Jenkins**
  - 사용자가 로그인한 뒤 `JU_TOMCAT_HOME`(`C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52`)을 추가해야 한다.
  - 그다음 빌드부터는 Jenkins로 배포할 수 있다 (같은 main `4915759`라 다시 빌드할 필요는 없음).
- **Desktop Client 등록 (체크리스트 4절)**
  - 실제 DB에 Client가 0건이라, 지금은 Desktop sync가 401이다.
  - C5d 배포 전에 관리자 API로 등록·키 발급이 필요하다 (사용자 승인 필요).
- **관리자 로그인 확인 (체크리스트 3-3·3-4)**: 로그인 후 GTEC 수집 설정 화면은 사용자가 확인해야 한다 (비밀번호 필요).
- **Tomcat 실행 방식**: Tomcat은 `startup.bat`이 연 별도 창에서 돈다. 그 창을 닫으면 Tomcat이 중지된다.
- **복구 방법**: 체크리스트 5절을 따른다.
  - 백업 WAR 2곳: 위 백업 폴더, `tomcat\backup`
  - 06·08이 적용된 DB에서 구 WAR가 동작하는 것은 리허설로 확인했다.

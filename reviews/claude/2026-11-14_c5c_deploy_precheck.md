# C5c 서버 배포 사전 검증 — 조건부 PASS (선행 조치 3건)

- 일시: 2026-11-14 19:46 ~ 19:53, PC-B
- 도구 (모두 읽기 전용 또는 테스트 DB·별도 포트만 사용)
  - `tools/ai_c5c_deploy_pre.ps1`
  - `tools/ai_c5c_deploy_env.ps1`
- 실제 환경 변경: **없음**
  - 실제 WAR 교체·main 병합·실제 DB 변경 없음
  - 실제 DB 덤프 해시가 시작과 끝 모두 `12CD3AA09A237DBC`(C5e 적용 직후 값과 같음)
  - main은 local·origin 모두 `fce5048`
  - 바뀐 것은 PC-B 작업 폴더 브랜치 하나: `feature/collect-c5d`로 checkout함
- 배포 체크리스트: [2026-11-14_c5c_deploy_checklist.md](2026-11-14_c5c_deploy_checklist.md)

## 1. 결과 요약

| # | 확인 항목 | 결과 |
|---|---|---|
| 1 | 배포 후보 브랜치·포함 관계 | **PASS**. 후보는 `feature/collect-c5d` @ `4915759` |
| 2 | 실제 DB 06·08 적용 상태 | **PASS**. 06 Action 10/10, 08 `8\|7\|4\|200\|7\|7`, C5e 이후 데이터 변화 없음 |
| 3 | Client Key/JWT 인증 및 기존 API 회귀 | **PASS 59/59** (테스트 DB = 실제 DB 사본) + Tomcat 리허설 인증 경계 PASS |
| 4 | WAR 빌드·백업·배포·복구 절차 | **PASS**. 빌드 5종, 서버 62, Desktop 189. 별도 Tomcat에서 배포 → 복구 리허설 PASS |
| 5 | Jenkins·main 병합 영향 | **조치 필요**. Jenkins에 `JU_TOMCAT_HOME`이 없어 지금 Jenkinsfile로는 배포 단계 전에 실패함 |
| 추가 | 현재 8081 | **중지 상태** (아래 3절) |

## 2. 상세

### 2.1 브랜치

**HEAD 확인**

| 브랜치 | HEAD (local = origin) |
|---|---|
| main | `fce5048` |
| c5b | `c8474c6` |
| c5c | `6e744be` |
| c5d | `4915759` |

**포함 관계**
- c5b ⊂ c5c ⊂ c5d
- integration-1, sec-s1, web-01, protocol-ref, collect-c4가 모두 c5d에 포함된다.

**main 병합 형태**
- main → c5d는 **fast-forward** 가능하다. c5d가 main보다 18 commit 앞서고, main에만 있는 commit은 0개다.

**배포 후보를 c5d로 정한 이유**
- 서버 쪽에서 c5c와 c5d의 차이는 regex 보완(D3, `ProtocolRules.java`)과 테스트뿐이다.
- c5c 브랜치만 배포하면 D3가 빠진다.
- c5d의 Desktop 변경은 WAR에 들어가지 않는다.

**main 대비 바뀌지 않은 것**
- Jenkinsfile, pom 2개, `package.json`, `application.yml`
- 의존성 변경 없음.

**migration 파일**
- c5d에 있는 파일: 03, 04, 05, 06, 08 (+ 08 check·down). 07은 없다.
- 실제 DB에는 06·08이 이미 적용되어 있다. 배포할 때 DB 작업은 없다.

### 2.2 실제 DB (읽기)

- 05 인증 데이터
  - 사용자 1명, 어드민 1명
  - AUTH_ATTR 미변환 0/5
- **ju_client 등록 0건.** PC-B에는 `desktop\app\config\client.json`도 없다.
  - 배포 후 Desktop sync는 Client 등록(키 발급) 전까지 401이 된다.
  - 지금 배포본은 키 없이도 허용하기 때문에 이 문제가 드러나지 않았다.

### 2.3 인증·회귀

**`ai_c4srv.ps1 -C5d` 결과 (59/59 PASS)**
- 테스트 DB에 06·08을 다시 실행해도 exit 0 (재실행 안전 재확인).
- Client Key
  - 정상 키 200
  - 헤더 누락, Id만, 잘못된 키, 없는 Id, JWT만 → 모두 401
  - 쓰기 메서드 403
- JWT
  - `/me`, admin API, `languages` 200
  - 로그인 실패 401, 형식 오류 400
- 기존 API: Action 경로, Protocol CRUD, sync revision, 참조 409, 405
- C5c API·서버값 계획 28개 항목
- 로그에 비밀 값 없음. 실제 DB CHECKSUM 같음.

### 2.4 Tomcat 배포·복구 리허설

- 환경: 별도 `CATALINA_BASE`, 포트 18082/18005, 테스트 DB 사본
- `JU_*` 값은 파일에 쓰지 않고 프로세스 환경으로만 전달했다.
- 순서는 Jenkinsfile 7~10단계와 같다: 정리 → WAR 복사 → `startup.bat` → health

**후보 WAR**
- 26초 만에 health UP (Jenkins 판정 기준 `success=true`, `status=UP`)
- 인증 없는 요청은 모두 401: 없는 사용자 로그인, `sync/devices`, `sync/data-map`, `languages`
- 홈 `/` 200, 콘솔 직접 URL 200
- Tomcat 로그 SEVERE·ERROR 0건
- `shutdown.bat`으로 정상 종료

**복구 (현재 배포본 10/25 WAR로 되돌림)**
- 24초 만에 health 200. 06·08이 적용된 DB에서도 구 WAR가 동작한다.
- 정리 완료: 임시 DB·폴더 삭제, 18082 닫힘.

**WAR 정보**

| WAR | 크기 | SHA256 | 비고 |
|---|---|---|---|
| 후보 (로컬 빌드) | 71,027,326 B | `EC80C07DA99241E4…` | Jenkins가 다시 빌드하므로 실제 배포 산출물은 아님 |
| 현재 배포본 | 69,720,964 B | `DBAF8738B0D7F42F…` | 10/25 15:54, Jenkins #1, rev `d963da2` |

- 현재 배포본은 main 인증 commit(10/26~27) 이전 버전이다. `JwtConfig`, `ClientKeyAuthenticationFilter`, `ProtocolSyncController`가 없다.
- 기존 백업: `tomcat\backup\juprovider-20261025-155414.war` 1개

### 2.5 Jenkins (PC-B)

**서비스와 job**
- 서비스 `Jenkins` 2.580.1: Running, 자동 시작, 계정 LocalSystem. 8080 `/login` 200.
- job `juprovider-ai`
  - 빌드 대상 `*/main`, Jenkinsfile 사용
  - **트리거 없음 (수동)**. main에 push해도 자동 배포되지 않는다.
  - 마지막 빌드 #1: 10/25 SUCCESS, rev `d963da2`

**문제**
- 지금 Jenkinsfile은 `e36a0ed` 이후 `JU_TOMCAT_HOME`을 요구한다.
- 그런데 PC-B Jenkins 전역 속성에 이 값이 없다.
- 시스템 환경변수에도 없고, 사용자 환경변수에만 있다. LocalSystem 계정으로 도는 Jenkins는 사용자 환경변수를 보지 못한다.
- → **이대로 빌드하면 Environment 단계에서 실패한다.** 실패 지점은 Tomcat을 멈추기 전이라 서비스 영향은 없다.

**도구 설정**
- `Maven3` 설정 있음
- `JDK21`: #1 빌드가 성공했으므로 설정되어 있음
- Jenkins workspace에 10/25 WAR가 남아 있다.

**배포 방식의 한계 (Jenkinsfile 구조)**
- 배포가 실패해도 자동 복구가 없다. WAR 백업 → 기존 배포 삭제 → 복사 → 기동 순서다.
- 실패하면 체크리스트 5절대로 직접 복구해야 한다.
- Jenkins가 띄운 Tomcat은 LocalSystem 계정으로 돈다.
  - `setenv.bat`(`CATALINA_HOME\bin`)은 계정과 상관없이 읽히므로 문제없다.

## 3. 현재 8081 중지 — 원인과 책임

- 8081이 listen하지 않는다.
- 마지막 Tomcat 로그는 11/12 21:30 기동, access log는 21:35까지 있다. 종료 기록은 없다. 마지막 부팅은 11/12 19:41이라 재부팅 때문도 아니다.
- **원인 추정**
  - C5e 적용 스크립트 창이 `startup.bat` 출력 대기로 남아 있었다.
  - 그 창을 닫을 때 같은 콘솔에 묶인 Tomcat이 함께 종료된 것으로 보인다.
  - 11/12 보고에서 "창을 닫아도 된다"고 안내한 것이 잘못이었다.
- 데이터 영향 없음: 실제 DB 해시가 C5e 직후와 같다.
- 지금 8081을 다시 켤지는 결정 항목이다 (체크리스트 0-4).

## 4. 결정 필요

1. **배포 대상을 c5d @ `4915759`로 할지.** c5c 단독 배포는 D3가 빠지므로 권장하지 않는다. main은 `fce5048` → `4915759`로 ff 병합하게 된다.
2. **Jenkins 전역 속성에 `JU_TOMCAT_HOME` 추가.** 값은 `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52`. Jenkins 설정 변경이므로 사용자가 직접 하거나 승인해야 한다.
3. **배포 직후 Desktop Client 등록.**
   - 실제 DB에 Client가 0건이라 Desktop sync를 쓰려면 관리자 API로 키를 발급해야 한다.
   - 키 원문은 사용자만 보관한다.
4. **8081을 지금 다시 켤지, 배포 때 켤지.**

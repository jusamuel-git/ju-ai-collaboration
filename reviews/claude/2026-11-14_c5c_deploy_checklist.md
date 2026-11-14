# C5c 서버 배포 체크리스트 — `feature/collect-c5d` @ `4915759` → 8081 (PC-B)

**기본 규칙**
- 모든 단계는 사용자 승인 후 진행한다.
- 실패하면 즉시 멈추고 5절로 간다.
- 근거 자료: [사전 검증 결과](2026-11-14_c5c_deploy_precheck.md)

**전제**
- 실제 DB에 06·08이 적용되어 있다 (C5e). 배포 때 DB 작업은 없다.
- 현재 배포본: 10/25 WAR (rev `d963da2`, SHA256 `DBAF8738B0D7F42F…`)

## 0. 사전 조치 (배포 전)
- [ ] 0-1 Jenkins 관리 > System > Global properties > Environment variables에 `JU_TOMCAT_HOME` = `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` 추가 (사용자)
- [ ] 0-2 현재 배포 WAR를 수동 백업한다. Jenkins 백업과 별도로 `C:\MyData\MyDev\backup\c5c_deploy_<ts>\juprovider_20261025.war`에 두고, SHA256 앞자리가 `DBAF8738B0D7F42F`인지 확인
- [ ] 0-3 실제 DB 덤프 1부 (C5e 방식). 배포 때 DB를 바꾸지는 않지만 비교 기준으로 쓴다.
- [ ] 0-4 8081 상태 확인. 지금은 중지 상태이며, 다시 켤지는 사용자가 결정한다.
- [ ] 0-5 admin 비밀번호를 사용자가 알고 있는지 확인. 배포 후 JWT 로그인과 Client 키 발급에 필요하다.

## 1. main 반영 (G5)
- [ ] 1-1 `git fetch` 후 origin/main = `fce5048`, origin/feature/collect-c5d = `4915759` 확인. 다르면 중단
- [ ] 1-2 `git checkout main && git merge --ff-only origin/feature/collect-c5d` → main = `4915759`
- [ ] 1-3 `git push origin main`
  - Jenkins는 트리거가 없어 push만으로는 배포되지 않는다.

## 2. Jenkins 배포
- [ ] 2-1 `juprovider-ai` 빌드를 수동 실행한다.
- [ ] 2-2 콘솔에서 확인:
  - rev `4915759`
  - Build Core / Backend 테스트 합계 62, Failures 0
  - Check WAR
  - Backup Current WAR (백업 파일명 기록)
  - Health UP
- [ ] 2-3 Environment 단계가 `JU_TOMCAT_HOME` 오류로 실패하면 0-1을 다시 확인한다.
  - 이 단계는 Tomcat 중지 전이라 서비스 영향이 없다.

## 3. 배포 후 확인 (8081)
- [ ] 3-1 `GET /juprovider/api/health` → 200, `success=true`, `status=UP`
- [ ] 3-2 인증 없는 요청이 401로 막히는지 확인:
  - 없는 사용자 로그인
  - `GET /api/core/sync/devices` (키 없음)
  - `GET /api/core/sync/data-map` (키 없음)
  - `GET /api/core/languages` (JWT 없음)
- [ ] 3-3 공개 홈 `/` 200 → 로그인 → 콘솔 이동. 로그아웃하면 홈으로 돌아가는지 확인
- [ ] 3-4 admin으로 프로토콜관리 GTEC 그룹 조회
  - 수집 설정이 200 / 500 / `GTEC0301,GTEC0001,GTEC0002,GTEC0100`인지 확인
  - 시험용 코드로 추가 → 삭제까지 해 본다.
- [ ] 3-5 Tomcat 로그(catalina, localhost)에 SEVERE·ERROR 0건
- [ ] 3-6 실제 DB 비교: 0-3 덤프 대비 바뀐 테이블이 로그인·테스트 흔적뿐인지 확인

## 4. Desktop 연결 (C5d 배포 전 준비)
- [ ] 4-1 관리자 API로 PC-B Desktop Client를 등록하고 키를 발급한다.
  - 키 원문은 사용자만 보관한다. 보고서·로그에는 Client ID만 쓴다.
- [ ] 4-2 `desktop\app\config\client.json` 작성
  - ServerUrl: `http://localhost:8081/juprovider/`
  - ClientId: 4-1에서 등록한 값
  - 키는 사용자가 직접 입력한다.
- [ ] 4-3 Desktop sync를 확인한다: `sync/protocols`, `sync/data-tags`, `sync/data-map`이 200이어야 한다.
  - 이 단계는 C5d 배포의 시작점이다.
  - 실장비 GTEC COM3 재확인은 C5d 단계에서 한다.

## 5. 실패 시 복구
1. **WAR·화면·API 이상**
   - Tomcat을 중지한다.
   - `webapps\juprovider` 폴더와 `juprovider.war`를 삭제한다.
   - 백업 WAR를 복사한다. Jenkins 백업(`tomcat\backup\juprovider-<ts>.war`) 또는 0-2 백업을 쓴다.
   - `startup.bat`으로 기동하고 health 200을 확인한다.
   - 사전 리허설 H-10: 06·08이 적용된 DB에서 구 WAR로 복구해 24초 만에 health 200이 나왔다.
2. **DB는 되돌리지 않는다.** 구 WAR가 06·08 DB에서 동작하는 것을 확인했다 (리허설 H-10·H-11, C5e W 단계).
   - 데이터가 이상하면 C5e 계획 4절을 따른다. 1차는 08 down, 2차는 `backup\c5e_20261112_213009` 복원이며 사용자 확인 후 진행한다.
3. **main 되돌리기는 사용자가 결정한다.** 방법은 `git revert` 또는 다음 수정.
   - history 재작성(force push)은 하지 않는다.
4. 복구한 뒤 health·로그인을 다시 확인하고, 원인과 조치를 `worklog/CURRENT.md`에 기록한다.

## 6. 주의
- Jenkinsfile은 실패해도 자동 복구가 없다.
  - Clean 단계 이후에 실패하면 8081이 비어 있는 상태가 된다.
  - 그러면 5-1로 바로 복구한다.
- Jenkins가 띄운 Tomcat은 LocalSystem 계정으로 돈다.
  - 수동으로 멈출 때는 `shutdown.bat`(포트 8005)을 쓴다. 이 방법은 계정과 상관없이 동작한다.
- 수동으로 기동할 때는 출력을 파이프로 받지 않는다.
  - 기동한 창을 닫으면 Tomcat이 함께 종료된다 (11/12 중지 원인으로 추정).

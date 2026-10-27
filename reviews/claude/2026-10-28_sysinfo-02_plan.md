# SYSINFO-02 단계별 구현 계획 + PR-1~3·SEC-S1 보완 과제

- 일시: 2026-10-28 (PC-A). **조사·설계만, 제품 코드 수정 없음. 승인 대기**
- 기준: juprovider `feature/protocol-ref` @ `1d1c1ab` (PR-1·2·3), `feature/sec-s1` @ `4187280`, main `fce5048`
- 범위: 서버 빌드 정보, `ju_schema_version`, Desktop 버전, template.accdb, client.sample.json, 호환성, PC-A/PC-B 재현
- 제외: SYSINFO-03 (Client 환경정보 서버 보고), SYNC-01 (Device 동기화 계약 변경)

---

## A. 보완 과제 1~5 (사용자 검토 10/28 08:52)

### A1. Protocol UPDATE: 빈 문자열 = 지우기, 미전송 = 유지 (계약 설계)
| 현재 | 원인 |
|---|---|
| 선택 텍스트를 비워 저장해도 기존 값 유지 | ① `ActionInputValidator.isMissing`이 빈 문자열을 "없음"으로 처리 ② Vue `compact()`가 `''`을 보내지 않음 ③ Mapper가 `COALESCE(#{x}, X)` |

제안 계약 (PR-D1):
- **필드 없음 = 유지 / `""` = 지우기(NULL) / 값 = 변경**. UPDATE 계열에서만 적용. CREATE는 지금처럼 `""` = 미입력.
- `FieldSpec`에 `clearable` 속성 추가 (선택 STRING만). 대상: GRP_UPDATE `ptlGrpDesc`, UPDATE `ptlDesc`·`ptlVal`, 패킷은 전체 교체라 해당 없음.
- 필수 필드에 `""` → 지금처럼 REQUIRED. `clearable`이 아닌 필드에 `""` → 지금처럼 무시(유지).
- `ActionInput`이 "보냈는지(has)"와 "지우기(isClear)"를 구분해 Service에 전달 → Mapper는 `<if>`로 SET 절 구성 (COALESCE 제거). 다국어 `LANG0001` 값도 함께 지움.
- Vue: 상세 원본과 비교해 **원래 값이 있었는데 비운 필드만 `""` 전송**.
- 계약 버전: v1 유지 제안. 현재 `""`는 무시되어 의존하는 호출자가 없음. 버전을 올릴지는 결정 필요(AC 변경 규칙상 의미 변경).
- 테스트: Validator 단위(clearable/비clearable/필수), HTTP smoke(미전송 유지·`""` NULL·값 변경), 브라우저(설명 비우기).

### A2. PR-2 Experiment 참조가 PTL_CD만 사용하는 한계 (기록)
- `ju_experiment_data_group.START/PAUSE/STOP_PTL_CD`에는 **그룹코드가 없다.** `ju_protocol` PK는 (PTL_GRP_CD, PTL_CD)라 같은 PTL_CD가 다른 그룹에 있을 수 있다.
- 결과: 다른 그룹의 같은 코드를 실험이 쓰면 **삭제가 막힘(409, 안전 쪽 오판)**. 반대로 잘못 지워지는 경우는 없음.
- 현재 데이터: 코드가 `{그룹}NNNN` 관례라 충돌 가능성이 낮음.
- 후속 선택지(결정 필요, 이번 범위 아님): ① 실험 구성에 PTL_GRP_CD 추가 ② PTL_CD 전역 고유 강제(UNIQUE) ③ 실험의 장치→그룹으로 추론. → 실험관리(Experiment Reference) 단계에서 결정. `decisions/CURRENT.md`에 PR-L1로 기록.

### A3. SEC-S1 Client 403 메시지 수정 계획
- 원인: `JsonSecurityErrorHandler.handle(AccessDenied)`가 `PASSWORD_OK` 권한이 없으면 "비밀번호를 먼저 변경해야 합니다."를 쓰는데, Client 인증에는 그 권한이 원래 없음.
- 수정: 인증 권한에 `CLIENT`가 있으면 → `403 FORBIDDEN "권한이 없습니다."`. 사용자 JWT는 기존 판단 그대로. (1개 파일, 약 3줄)
- 시점: PR-1이 같은 파일(`code` 필드)을 바꿨으므로 **통합 브랜치에서 sec-s1 merge 후 별도 commit (SEC-S1b)**.
- 테스트: Client PUT → 403 + `"code":"FORBIDDEN"` + "권한이 없습니다." / 비밀번호 미변경 사용자 → 기존 문구 유지 / 권한 없는 사용자 → "권한이 없습니다." 유지.

### A4. PR-3 contractVersion smoke 12/12 재실행
- 스크립트 기대값을 400으로 고쳤음(`tools/ai_pr3.ps1`). 제품 코드 무관.
- **C 단계(통합 검증)에서 재실행**해 12/12를 확보한다 (이번 턴은 조사·설계만이라 서버 기동 안 함). 승인 시 통합 전이라도 단독 재실행 가능(수정 없음, 테스트 DB만).

### A5. PR-1~3 + SEC-S1 통합 절차 (회귀 + migration 06)
| 순서 | 내용 | 승인 |
|---|---|---|
| I-1 | `feature/integration-1` ← `feature/protocol-ref@1d1c1ab`, `git merge --no-ff feature/sec-s1` (겹치는 파일 없음 확인) | 사용자 |
| I-2 | SEC-S1b(403 문구) commit, (승인 시) A1 clearable commit | 사용자 |
| I-3 | 로컬 빌드 5종 + 단위 테스트(현재 23 + sec-s1 1 + 신규) | — |
| I-4 | 테스트 DB(실제 DB 덤프) + 06 1회·2회(무변경) + 신규 설치(baseline+seed) 동일성 | — |
| I-5 | 회귀 smoke 묶음: PR-1 18 / PR-2 58 / PR-3 API 12 / SEC-S1 25 / JU-1c Desktop online·offline 42 / 브라우저(관리자·조회자) | — |
| I-6 | **실제 DB 백업** → 06 적용 → 확인 쿼리(M02010100 Action 10, 기존 Action 수 불변) | **사용자 승인** |
| I-7 | main merge/push → Jenkins → Health·로그인·프로토콜 화면 확인 | **사용자 승인** |
| 복구 | 06 실패/이상: 백업 SQL 복원(사용자 확인 후). 06은 INSERT만이라 `DELETE FROM ju_menu_action(_detail)/ju_multi_lang WHERE ... M02010100` 롤백 스크립트도 함께 준비 | 사용자 |

---

## B. SYSINFO-02 설계

### B0. 원칙 반영
- 버전 5종 분리: **Server Build**(WAR) / **DB Schema**(migration 번호) / **Client Build**(Desktop) / **Action Contract**(Action별, 기존) / **Sync Revision**(SYNC-01, 이번 제외).
- 버전·환경 정보에 비밀 값 없음: 커밋 해시·빌드 번호·시각·버전 문자열만. 접속 문자열·키·사용자 정보 없음.
- 의존성·Tool 추가 없음: Maven `spring-boot-maven-plugin`의 `build-info` goal(이미 쓰는 플러그인), .NET SDK 기본 기능만 사용.
- 기존 인증, 오프라인 로그인, Health 응답 필드는 그대로. 필드 추가만.

### B1. 버전 증가 규칙
| 대상 | 형식 | 원본 | 올리는 때 |
|---|---|---|---|
| Server Build | `MAJOR.MINOR.PATCH` (+build, commit) | `juprovider.backend/pom.xml` `<version>` | main 반영 단위. PATCH 수정, MINOR 기능·Action 추가, MAJOR 호환 깨짐 |
| Build 번호 | 정수 | Jenkins `BUILD_NUMBER` (로컬 `0`) | 자동 |
| Commit | 짧은 해시 7자 | Jenkins `GIT_COMMIT` / 로컬 빌드 스크립트 `git rev-parse` (없으면 `local`) | 자동 |
| DB Schema | 2자리 migration 번호 (`07`) | `database/migration/NN_*.sql` + `ju_schema_version` | 스키마·기본 데이터를 바꾸는 migration마다 +1 |
| 필요 Schema | 같은 번호 | 서버 코드 상수 `REQUIRED_SCHEMA` | 새 migration에 의존하는 코드를 넣을 때 |
| Client Build | `MAJOR.MINOR.PATCH` / FileVersion `MAJOR.MINOR.PATCH.BUILD` | `desktop/Directory.Build.props` `JuDesktopVersion` | Desktop 배포 단위. Server와 독립 |
| Action Contract | 정수 | Action별 `contractVersion` (기존) | 기존 AC 규칙 |
- Server와 Client 버전은 서로 맞출 필요 없음. 호환 판단은 Action Contract와 (SYSINFO-03 이후) 정책으로 한다.
- 첫 값: Server `1.1.0`(Action Contract·Protocol 반영), Desktop `1.0.0`, Schema `07`.

### B2. 단계 (각 단계 = 1 commit, 승인 지점 표시)
기반 브랜치: `feature/sysinfo-02` ← `feature/integration-1` (A5 I-1·I-2 후). 06에 이어 07을 번호로 쓰기 때문.

#### 단계 S2-A 서버 빌드 정보 (DB 변경 없음)
| 파일 | 변경 |
|---|---|
| `juprovider.backend/pom.xml` | `spring-boot-maven-plugin`에 `build-info` execution 추가, `additionalProperties`: `commit=${ju.build.commit}`, `number=${ju.build.number}`. 기본값 property `local`/`0`. version `1.0.0` → `1.1.0` |
| `Jenkinsfile` (Build Backend) | `mvn -B clean package -Pvue -Dju.build.commit=%GIT_COMMIT:~0,7% -Dju.build.number=%BUILD_NUMBER%` |
| `ai_local_build.ps1` (작업공간 도구) | 같은 `-D` 전달 (git 해시, number 0) |
| `controller/HealthController.java` | 응답에 `version` 1개 필드 추가 (기존 `status`, `application` 유지) |
| `controller/SystemVersionController.java` (신규) | `GET /api/system/version` — 로그인 사용자(JWT, 비밀번호 변경 완료) |
| `service/SystemVersionService.java` (신규) | `BuildProperties` + B2-B의 Schema 정보 조합 |

응답 예시:
```json
GET /api/health  (공개, 기존 호환)
{"success":true,"data":{"status":"UP","application":"JuProvider","version":"1.1.0"},"message":null}

GET /api/system/version  (JWT)
{"success":true,"data":{
  "server":{"version":"1.1.0","commit":"a1b2c3d","buildNumber":"17","buildTime":"2026-10-28T10:15:30Z"},
  "schema":{"current":"07","required":"07","status":"OK"}
}}
```
- 공개 Health에는 commit·빌드 번호·스키마를 넣지 않음 (노출 최소화). Jenkins 판정(`success`, `data.status`)은 그대로.
- `build-info.properties`가 없을 때(IDE 실행 등) → `version: "dev"`, 서버는 정상 기동.

#### 단계 S2-B DB `ju_schema_version` (**DB 변경 있음 — migration 07**)
테이블:
```sql
CREATE TABLE IF NOT EXISTS ju_schema_version (
  SCHEMA_VER   varchar(10)  NOT NULL COMMENT 'migration 번호 (예: 06)',
  SCRIPT_NM    varchar(100) NOT NULL COMMENT '파일명',
  APPLY_TYPE   varchar(10)  NOT NULL COMMENT 'APPLY(실행 기록) / VERIFY(기존 상태 검증 후 기록) / BASELINE',
  VERIFY_NOTE  varchar(500) DEFAULT NULL COMMENT '검증 근거 요약',
  APPLIED_DT   datetime(3)  NOT NULL DEFAULT current_timestamp(3),
  APPLIED_BY   varchar(100) DEFAULT NULL COMMENT 'DB 사용자 (CURRENT_USER)',
  PRIMARY KEY (SCHEMA_VER)
) COMMENT='DB 스키마 버전 이력';
```
`07_schema_version.sql` 내용 (재실행 안전):
1. 테이블 생성.
2. **기존 이력 검증 후 기록** (조건이 참일 때만 `INSERT IGNORE`, APPLY_TYPE=`VERIFY`):

| 번호 | 검증 조건 (모두 참이어야 기록) |
|---|---|
| `02` BASELINE | 핵심 테이블 존재 (ju_menu, ju_auth, ju_device, ju_protocol …) |
| `04` | `ju_menu_action` 존재 + 공통코드 `MACT` 6건 + `PTL_TYPE='POLLING'` 0건 + `DOTNET_VERSION='10.0'` |
| `05` | `ju_client`(+detail) 존재 + `AUTH_ATTR`에 비트 없는 9자리 항목 0건 |
| `06` | `M02010100` 활성 Action 10건 + HANDLER_ID `PROTOCOL.*` 10건 |
| `07` | 자기 자신 (APPLY) |
3. 마지막에 결과 조회: 기록된 번호와 **기록되지 않은 번호(검증 실패)** 목록 출력.
- 검증 실패 번호는 기록하지 않는다 → 서버가 `status: BEHIND`로 보고. 해당 migration 재실행 후 07 다시 실행.
- 03은 조회 전용이라 기록 대상 아님.
- 이후 08부터는 각 migration 마지막 줄에 `INSERT IGNORE INTO ju_schema_version ... 'APPLY'` 규칙.

코드:
| 파일 | 변경 |
|---|---|
| `database/migration/07_schema_version.sql` (신규) | 위 내용 |
| `database/migration/07_schema_version_check.sql` (신규) | 읽기 전용: 테이블·번호별 검증 결과 표 (적용 전 사전 점검용) |
| `database/baseline/01_*.sql` | 테이블 정의 추가 (신규 설치 동일성) |
| `database/README.md` | 신규 설치 = baseline + seed + **07**, 업그레이드 표에 07, 규칙 |
| `core/system/dao/SchemaVersionDao` + Mapper (신규) | 최대 번호·목록 조회 |
| `config/SchemaVersionCheck.java` (신규) | 기동 시 `current < required` → **WARN 로그만** (기동 차단 안 함). 테이블 없음 → `UNKNOWN` WARN |
- `status`: `OK`(같음) / `BEHIND`(DB가 낮음) / `AHEAD`(DB가 높음 — 구 WAR) / `UNKNOWN`(테이블 없음).

#### 단계 S2-C Desktop 버전 (DB 변경 없음)
| 파일 | 변경 |
|---|---|
| `desktop/Directory.Build.props` | 공통 `JuDesktopVersion=1.0.0`, `Version`, `FileVersion=$(JuDesktopVersion).$(JuBuildNumber)`(기본 0), `InformationalVersion`(SDK가 commit 자동 추가 — PC-A에서 확인), `Company/Product=JuProvider` |
| `juprovider.client/Services/AppLog.cs` 또는 신규 `VersionInfo.cs` | 시작 시 1줄: Client 버전 + 모듈 목록(`app\*.exe`, `app\libs\*.dll`, `app\service\*.exe`의 FileVersion). 서로 다른 FileVersion이 섞이면 WARN |
| `LoginForm.cs` / `MainForm.cs` | 하단 상태줄에 `v1.0.0 (a1b2c3d)` 표시 |
- 오프라인 로그인·서버 동기화 동작 변경 없음 (표시·로그만).
- 서버 버전 비교·업데이트 판단은 SYSINFO-03 이후 (Updater도 제외).

#### 단계 S2-D template.accdb + client.sample.json (DB 변경 없음, 로컬 파일)
| 파일 | 변경 |
|---|---|
| `desktop/resources/template.accdb` (신규, 바이너리) | **테이블 없는 빈 ACCDB**. 모든 LOCAL_* 테이블은 코드가 생성하므로 빈 파일이 가장 깨끗함. 사용자·자격·장치 데이터 없음 |
| `desktop/resources/client.sample.json` (신규) | `{"ServerUrl":"http://localhost:8081/juprovider/","ClientId":"","ClientKey":""}` 와 설명 주석은 README에 |
| `desktop/juprovider.client/juprovider.client.csproj` | 두 파일을 `config\`로 복사 (`CopyToOutputDirectory=PreserveNewest`, Link) |
| `.gitattributes` | `*.accdb binary` |
| `tools/ai_make_template.ps1` (공유 저장소) | PC-A ACE 공급자로 빈 ACCDB 생성(ADOX ProgID) + 검증(테이블 0개) |
| `desktop/README.md` (신규) | 설치 순서·파일 구분 |
- `client.json`은 복사하지 않음. 기존 `app\config\client.json`·`app\data\juprovider.accdb`는 빌드가 건드리지 않음 (template은 로컬 DB가 **없을 때만** 사용).
- 검증: 빈 template에서 첫 실행 → LOCAL_USER·LOCAL_DEVICE·LOCAL_SYNC_STATE 생성, 온라인 로그인→오프라인 로그인 정상 (JU-1c smoke 재사용).
- 저장소 검사: commit 전 template에 테이블 0개, 파일 크기 확인 / client.sample.json에 키 값 없음.

#### 단계 S2-E 문서 + 재현 검증
- `database/README.md`, `desktop/README.md`, 공유 저장소 `environment/` 설치 순서 갱신.

### B3. 신규 PC 설치 순서 (S2 완료 후 기준)
**서버 PC** (DB·Tomcat 있는 PC)
1. MariaDB 10.6+ → DB `juprovider` 생성
2. `baseline/01` → `seed/02` → `migration/07` 실행 → 07 결과에 `02·04·05·06·07` 모두 기록 확인
3. Tomcat `setenv.bat`에 `JU_DB_*`, `JU_JWT_SECRET` (저장소 밖)
4. WAR 배포 → `GET /api/health` `UP` + `version` / 로그인 후 `/api/system/version` `schema.status=OK`
5. admin 초기 비밀번호 변경 (별도 전달)

**Desktop PC**
1. 공통 배포물: `desktop\app\` 전체 (빌드 결과, `config\template.accdb`, `config\client.sample.json` 포함)
2. 서버 관리자가 Client 등록 → 등록 스크립트가 `config\client.json` 생성 (키는 이 파일에만, 화면·로그 출력 없음)
3. 첫 실행 → `data\juprovider.accdb` 자동 생성 → 온라인 로그인 1회 → 오프라인 자격 저장
4. 로그 첫 줄에서 Desktop 버전·모듈 FileVersion 확인

| 공통 배포 | PC별 생성 (복사·공유 금지) |
|---|---|
| exe/dll, `config\template.accdb`, `config\client.sample.json` | `config\client.json`, `data\juprovider.accdb`, `logs\` |

### B4. 호환성
| 대상 | 영향 |
|---|---|
| `/api/health` | 필드 추가만. Jenkins 판정·Desktop 영향 없음 (Desktop은 health 미사용) |
| 인증 | 체인 변경 없음. `/api/system/version`은 기존 API 체인(JWT, 비밀번호 변경 후) |
| Client 체인 | 변경 없음 (SEC-S1 그대로) |
| 오프라인 로그인 | 코드 경로 변경 없음. template 교체는 로컬 DB가 이미 있으면 영향 없음 |
| 기존 DB | 07은 테이블 추가 + 기록만. 기존 데이터 무변경 |
| 구 WAR + 새 DB | `ju_schema_version`을 모르므로 영향 없음 |
| 새 WAR + 07 미적용 DB | `UNKNOWN` WARN만, 정상 기동 |

### B5. 실패 시 복구
| 실패 | 복구 |
|---|---|
| 07 일부 번호 미기록 | 데이터 문제 아님. 해당 migration 확인·재실행 → 07 재실행 |
| 07 오류 | 07은 새 테이블만 만듦 → `DROP TABLE ju_schema_version` (사용자 승인), 실제 DB는 적용 전 백업 |
| build-info 누락 | `version: dev`로 기동. 빌드 인자 확인 후 재빌드 |
| 새 WAR 이상 | Jenkins가 남긴 백업 WAR로 되돌림 (기존 절차) |
| template 문제로 첫 실행 실패 | 이전 template로 교체하거나 `data\juprovider.accdb`가 있는 PC는 영향 없음. 로컬 DB 삭제는 사용자 확인 후 |
| Desktop 버전 표시 오류 | 기능 영향 없음, 다음 빌드에서 수정 |

### B6. 테스트
| 단계 | 테스트 |
|---|---|
| S2-A | 단위: 버전 서비스(build-info 있음/없음). HTTP: health 기존 필드+version, `/api/system/version` 무토큰 401·토큰 200·비밀번호 미변경 403, 응답에 비밀 값 패턴 없음. Jenkins: health 판정 통과 |
| S2-B | 테스트 DB: 실제 DB 덤프+06 → check → 07 1회·2회 동일 / 06 미적용 덤프 → 06 미기록·`BEHIND` / 신규 설치(baseline+seed+07) 동일 결과 / 서버 기동 WARN 확인 |
| S2-C | 빌드 후 모든 EXE/DLL FileVersion 동일, InformationalVersion에 commit, 로그 첫 줄·화면 표시 |
| S2-D | template 테이블 0개, 빈 PC 폴더 시나리오(로컬 DB 없음) 첫 실행 → 테이블 생성·로그인 / 기존 로컬 DB 있는 폴더 무영향 / 빌드 후 `client.json` 미생성·미변경 |
| 공통 | 로컬 빌드 5종, 기존 회귀 묶음(A5 I-5) |

### B7. PC-A / PC-B 재현 절차
1. PC-A: 단계별 스크립트(`ai_sysinfo02_*.ps1`)로 빌드·smoke, 결과 로그 공유
2. 브랜치 원격 push(main 아님) — **사용자 승인**
3. PC-B(저녁 정리 후 환경 정렬): `workspace_verify` 또는 정리된 작업 폴더에서 같은 브랜치 checkout → 같은 스크립트 → 비교 항목: 빌드 5종, 테스트 수, 07 결과 표, `/api/system/version` 값(commit 동일), Desktop FileVersion 동일, **빈 폴더 신규 설치(template만으로 첫 실행 성공)** — PC-B의 template 누락 문제 해소 확인
4. 차이는 환경 차이(JDK·Maven 경로 등)와 제품 차이로 구분해 보고

### B8. 승인 지점
| # | 승인 내용 |
|---|---|
| G1 | 이 계획 + A1~A5 방향 (특히 A1 계약 v1 유지 여부, A2 후속 처리) |
| G2 | 통합 브랜치 I-1·I-2 진행 |
| G3 | S2-A~S2-D 구현 착수 (단계별 결과 보고 후 다음 단계) |
| G4 | 실제 DB 06 → 07 적용 (백업 후) |
| G5 | 원격 브랜치 push / main merge·Jenkins |

### B9. 결정 요청
| # | 질문 | 제안 |
|---|---|---|
| S2-Q1 | `/api/system/version` 접근 범위 | 로그인 사용자 전체 (관리자 전용도 가능) |
| S2-Q2 | 스키마 불일치 시 기동 | 1차는 WARN만, 차단은 후속 |
| S2-Q3 | Server 첫 버전 | `1.1.0` |
| S2-Q4 | template.accdb 형태 | 테이블 없는 빈 ACCDB |
| S2-Q5 | A1 clearable 계약 버전 | v1 유지 (현재 `""` 의존 호출자 없음) |

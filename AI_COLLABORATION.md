# AI 협업 규칙 (ChatGPT · Claude)

> 이 문서의 원본은 AI 공용 협업 저장소 **ju-ai-collaboration**에 있습니다 (v1.3부터).
> juprovider, juproject 저장소의 `AI_COLLABORATION.md`는 이 문서를 가리키는 사본/안내로 유지합니다.
> 작업을 시작하는 AI는 이 문서를 먼저 읽고, 여기 적힌 규칙을 기준으로 작업합니다.

- 최초 작성: 2026-10-23 (Claude), ChatGPT 검토 반영: 2026-10-23
- v1.0: 2026-10-23 첫 정리 commit 기준
- v1.1: 2026-10-24 작업
- v1.2: 2026-10-25 시스템 아키텍처 기준(10장) 추가
- v1.3: 2026-10-26 AI 공용 협업 저장소(11장), PC-A 기준 개발 환경(4장)

## 1. 참여자와 역할

```
1. Claude    현재 상태 조사 (실제 코드·설정·Jenkins를 근거와 함께 보고)
      ▼
2. ChatGPT   조사 결과를 기준으로 설계 / 작업 범위 결정
      ▼
3. Claude    설계를 실제 코드에 대입해 검토 → 구현 → 빌드·테스트 → 변경 보고
      ▼
4. ChatGPT   실행 결과(diff, 빌드 로그)에 따른 문제점만 검토·요청
      ▼
5. 사용자    결정 / 승인 / commit·push
      ▼
   Git       확정된 소스의 기준점 (최종 빌드 판정: Jenkins)
```

| 참여자 | 역할 |
|---|---|
| 사용자 (JU) | 최종 결정, 우선순위 결정, 중요 변경 승인, commit/push |
| ChatGPT | juprovider·juproject 전체 설계와 검토. 조사 결과를 기준으로 구조·작업 범위·구현 방향 결정, DB/API/UI 구조 검토, 실행 결과에 따른 문제점 검토, 협업 규칙 관리 |
| Claude | juprovider·juproject 로컬 조사와 구현. 현재 상태 조사·보고, 설계의 현재 코드 적합성 검토, 소스 수정, 빌드·테스트, 변경 결과 보고 |

### 진행 규칙
- 작업은 항상 Claude의 현재 상태 조사로 시작합니다. ChatGPT는 조사 결과에 없는 코드·설정을 전제로 설계하지 않습니다.
- Claude는 설계가 현재 코드와 맞지 않으면 구현 전에 차이를 보고합니다. 임의로 다른 방향으로 구현하지 않습니다.
- ChatGPT 검토는 Claude의 변경 diff와 빌드 결과를 대상으로 합니다. Claude가 구현과 최종 검토를 혼자 하지 않습니다.
- 조사 결과, 설계, 결정, 검토 요청은 **ju-ai-collaboration 저장소**에 남깁니다 (11장). 사용자가 파일을 첨부해 옮기지 않아도 두 AI가 같은 문서를 읽습니다.
- 같은 파일을 두 AI가 동시에 고치지 않습니다.

 결과 보고 |

- 같은 파일을 두 AI가 동시에 고치지 않습니다.
- 판단이 갈리는 문제(구조 변경, DB 스키마, 파일 삭제)는 사용자가 결정합니다.

## 2. Source of Truth

- 현재 Git 저장소의 소스를 구현 상태의 최종 기준(Source of Truth)으로 합니다.
- ChatGPT의 기억, Claude의 이전 분석, README, 과거 대화와 현재 코드가 다르면 현재 코드를 먼저 조사합니다.
- 단, 코드가 설계 원칙과 다른 경우 임의로 변경하지 않고 차이를 보고합니다.

## 3. 변경 범위 원칙

- 요청받은 범위를 넘어선 대규모 리팩터링을 하지 않습니다.
- 기존 코드가 이상해 보인다는 이유만으로 임의 리팩터링하지 않습니다.
- 문제를 발견해도 현재 작업과 직접 관계가 없으면 임의 수정하지 않고 보고합니다.
- DB/API/공통 모델처럼 영향 범위가 큰 변경은 사용자의 승인 후 진행합니다.

### Claude가 바로 처리하는 범위 (처리 후 보고)
- 영향이 작고 의도가 명확한 수정: 하드코딩된 값을 이미 있는 변수로 교체, 효과 없는 옵션 제거, 문서·주석 오타, 문서와 실제 코드 불일치 수정
- 작업 기록(`AI_WORKLOG.md`) 갱신

### 항상 사용자 결정이 필요한 것
- 파일·폴더 삭제, DB 스키마, API 계약, 공통 모델, 의존성 추가·업그레이드
- 배포 방식, 보안·인증 정보 처리 방식, Jenkins 설정 중 권한·credential 관련
- 구조 변경 (프로젝트 추가·이동, 빌드 구조 변경)

## 4. 개발 환경 (개발 PC)

- 기준 문서: `environment/DEV_ENVIRONMENT_STANDARD.md`, 빌드는 `environment/BUILD_ENVIRONMENT_STANDARD.md`. 기준 PC는 PC-A `DESKTOP-CE5BGKK`이고, 다른 PC는 이 문서와 `tools/ai_dev_env_check.ps1` 결과에 맞춘다.
- 아래 경로는 **PC-A의 실제 설치 위치(참고값)** 다. 소스·빌드 설정은 이 경로를 직접 쓰지 않고 환경변수(`JAVA_HOME`, `MAVEN_HOME`, `VCPKG_ROOT`, `JU_TOMCAT_HOME` 등)나 Jenkins 도구 이름(`JDK21`, `Maven3`)을 쓴다.

| 항목 | 구분 | PC-A 경로 | 환경변수 |
|---|---|---|---|
| workspace | — | `C:\MyData\MyDev\workspace` | `JU_WORKSPACE` |
| JDK 21.0.1 | Portable | `C:\MyData\MyDev\jdk\jdk-21.0.1` | `JAVA_HOME` |
| Maven 3.9.11 | Portable | `C:\MyData\MyDev\maven\apache-maven-3.9.11` | `MAVEN_HOME` |
| Tomcat 10.1.52 | Portable | `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` | `JU_TOMCAT_HOME` |
| vcpkg | Portable | `C:\MyData\MyTool\vcpkg` | `VCPKG_ROOT` |
| .NET SDK 10.0.4xx | 설치형 | `C:\Program Files\dotnet` | — |
| Node.js | 설치형 | `C:\Program Files\nodejs` | — |
| CMake | 설치형 | `C:\Program Files\CMake` | — |
| MariaDB 10.6 | 설치형 | `C:\Program Files\MariaDB 10.6` (데이터 위치는 PC별 허용) | — |
| Redis | 설치형 | `C:\Program Files\Redis` | — |
| Git | 설치형 | `C:\Program Files\Git` | — |
| Jenkins | 설치형 (서비스, LocalSystem) | `C:\Program Files\Jenkins` | Jenkins 도구 설정 |
| Visual Studio 2026 | 설치형 | `C:\Program Files\Microsoft Visual Studio\18\Community` | — |
| VS Code | 사용자 설치 | `%LOCALAPPDATA%\Programs\Microsoft VS Code` | — |
| hMailServer | 설치형 | 시작 메뉴 등록 | — |

## 5. 저장소와 기술 스택

문서에 적는 Java/.NET/Spring Boot/Node 등의 버전은 과거 문서가 아니라 **현재 저장소의 project/build 설정에서 직접 확인한 값**을 사용합니다. 버전을 적을 때는 근거 파일도 함께 적습니다. 아래 값은 2026-10-23에 확인했습니다.

### juprovider — https://github.com/jusamuel-git/juprovider

| 폴더 | 내용 | 버전 (근거 파일) |
|---|---|---|
| `juprovider.backend` | Spring Boot WAR, MyBatis+JPA, MariaDB, Redis, Mail | Spring Boot 3.5.16, Java 21, mybatis-spring-boot-starter 3.0.4 (`juprovider.backend/pom.xml`) |
| `juprovider.core` | 공통 코어 모듈 (Action, Device, Menu, SystemCode, Language) | Java 21, Spring Boot BOM 3.5.16, MyBatis 3.5.19, mybatis-spring 3.0.5 (`juprovider.core/pom.xml`) |
| `juprovider.frontvue` | Vue 3 + Vite (공개 사이트 + 콘솔) | vue ^3.5.13, vue-router ^4.5.0, axios ^1.7.9, vite `latest` (`juprovider.frontvue/package.json`). Maven 통합 빌드 시 Node v22.14.0 / npm 10.9.2 (`juprovider.backend/pom.xml`) |
| `desktop` | WinForms 클라이언트·터미널·공용 라이브러리·업데이터 | net10.0-windows (`desktop/**/*.csproj`), System.Data.OleDb 10.0.13 (`juprovider.lib.data.csproj`) |
| `desktop/native` | C++ native library 영역 (6장) | — |
| `database` | baseline / seed / migration SQL (7장) | — |
| `Jenkinsfile` | CI 빌드 | JDK21, Maven3 |

### juproject — https://github.com/jusamuel-git/juproject

| 폴더 | 내용 | 버전 (근거 파일) |
|---|---|---|
| `backend` | ASP.NET Core — Api / Application / Domain / Infrastructure 계층 | net10.0 (`backend/src/*/*.csproj`), JwtBearer·OpenApi 10.0.13, EF Core Design 9.0.21, Pomelo.EntityFrameworkCore.MySql 9.0.0, dotnet-ef 9.0.21 (`backend/dotnet-tools.json`) |
| `frontend` | React + TypeScript + Vite | react ^19.3.1, react-router ^8.5.0, antd ^6.6.7, typescript ~6.0.3, vite ^8.3.4 (`frontend/package.json`) |
| `database/schema` | 초기 스키마 SQL | — |

## 6. 저장소에 올리지 않는 것 / 올리는 것

### 올리지 않는 것
빌드하거나 설치하면 다시 생기는 파일, 실행 중 생성되는 파일은 커밋하지 않습니다.

- 빌드 결과물: `bin/`, `obj/`, `target/`, `dist/`, `publish/`, `artifacts/`
- 패키지: `node_modules/`
- IDE 개인 설정: `.vs/`, `.vscode/`, `*.user`, `*.suo`
- 로그: `logs/`, `*.log`
- 비밀 정보: `.env`, `*.local`

이미 커밋된 것은 `git rm --cached`로 추적만 해제합니다 (로컬 파일은 남음).

### desktop/app
- `desktop/app/` 전체를 단순히 Git 제외 대상으로 정의하지 않습니다.
- 빌드 결과물과 실행 중 생성되는 파일은 Git에 포함하지 않습니다.
- 프로그램 실행에 필요한 원본 설정, template, schema 등은 소스 영역에서 별도로 관리하고, build/copy 과정에서 app으로 배포하는 구조를 사용합니다.
- `template.accdb`의 원본 위치는 desktop 구조를 확인한 후 결정합니다.

### desktop/native
- 삭제하지 않습니다. 현재 비어 있어도 유지합니다.
- JuProvider의 C++ native library 영역으로 사용합니다.
- 향후 OpenCV/OpenGL/Eigen/VTK/Qt 및 C# P/Invoke 연동 코드를 배치할 수 있습니다.

## 7. 코드·설정 규칙

### 비밀 정보
- 비밀번호, 토큰, 키를 설정 파일에 직접 쓰지 않습니다. 환경변수로 받습니다.
  - juprovider backend: `JU_DB_URL`, `JU_DB_USER`, `JU_DB_PASSWORD`
  - juproject backend: 개발용은 `dotnet user-secrets`, 운영은 환경변수
- 문서나 대화에 실제 비밀번호를 붙여넣지 않습니다.

### DB 원칙 (juprovider)
- MariaDB가 원본(Master), Redis는 서버 캐시·이벤트 용도
- C# 데스크톱은 Redis에 직접 연결하지 않습니다 (Backend API 경유)
- `USE_YN` 등 Y/N 값은 `VARCHAR(8)` 공통코드 사용: 사용 `YENO0001`, 미사용 `YENO0002`

### database 폴더
| 폴더 | 용도 |
|---|---|
| `baseline` | 신규 설치용 최신 전체 구조. 개발 중 바뀐 구조를 계속 반영 |
| `seed` | 신규 설치용 기본 데이터 |
| `migration` | 이미 배포된(기존 설치) DB 업그레이드용 SQL |

### 이름 규칙
- 폴더·프로젝트: juprovider는 `juprovider.<영역>` 소문자, juproject는 `JuProject.<계층>`
- 코드 식별자는 영어, 문서와 주석은 한국어

## 8. Git 규칙

- 기본 브랜치: `main`
- 작업 브랜치: `feature/<내용>`, `fix/<내용>`, `chore/<내용>`
- 커밋 메시지: `<type>: <요약>` (type: feat, fix, refactor, docs, chore, build, db)
- 제품 저장소(juprovider, juproject): AI가 만든 변경은 사용자가 확인한 뒤 커밋하고, 푸시는 사용자가 합니다.
- 협업 저장소(ju-ai-collaboration): Claude가 문서를 직접 commit/push할 수 있습니다 (11장).
- 과거 Git history는 다시 쓰지 않습니다 (history rewrite 금지, 사용자 별도 결정 시 예외).

## 9. 작업 기록

- 이 문서(`AI_COLLABORATION.md`)에는 협업 규칙만 둡니다. 작업 기록을 누적하지 않습니다.
- 확정된 변경 이력은 Git commit을 최종 기록으로 사용합니다.
- AI 간 인수인계가 필요한 현재 작업은 협업 저장소 `worklog/CURRENT.md`에 기록하고, 날짜별 기록은 `worklog/YYYY-MM-DD.md`에 남깁니다.
- 제품 저장소의 `AI_WORKLOG.md`는 그 저장소 코드에 직접 걸린 미해결 항목만 둡니다.

## 10. 시스템 아키텍처 기준 (v1.2, 2026-10-25)

상세 설계는 협업 저장소 `architecture/DB_CORE_API.md`를 기준으로 하며, 구현 전에는 항상 현재 Git 소스와 DB를 다시 조사합니다.

### 10.1 SYS(JuProject)와 JU(JuProvider)의 경계

- 방향은 **SYS(JuProject) → JU(JuProvider)** 입니다.
- JuProvider는 JuProject/SYS가 없어도 완전히 독립 실행되어야 합니다.
- 두 시스템은 DB를 공유하지 않습니다.
- SYS 테이블을 JU가 직접 FK로 참조하거나 SYS DB를 직접 조회하지 않습니다.
- 향후 연동은 API/Sync를 통해 업무키 기반으로 처리합니다.
- SYS 장애나 연결 단절이 JU의 Core/Device/Experiment 실행을 중단시키면 안 됩니다.

### 10.2 DB 설계 원칙

**JuProject / SYS**

- 시스템 테이블 접두어: `sys_`
- 기본 PK: `BIGINT` 대리키
- 외부 연동용 업무키: 별도 UNIQUE
- 상태값: `Y/N`
- 명명: lowercase snake_case
- 변경 관리: EF Migration
- 핵심 영역: Site / Dept / User / Auth / Menu / Common Code
- `sys_user`는 고객·조직·서비스 시스템 계정입니다.

**JuProvider / JU**

- 기존 `ju_` 구조를 기본으로 유지합니다.
- 자연키, YENO, `_detail`, 다국어 구조를 SYS 규칙에 맞추기 위해 일괄 변경하지 않습니다.
- `ju_user`는 JuProvider Core를 실행하기 위한 독립 사용자입니다.
- JU에 Site/Dept를 SYS와 같은 의미로 추가하지 않습니다.
- Protocol / Device / Data / Experiment / Run / Storage / Viewer는 JU 독립 도메인입니다.
- 기존 테이블은 미사용이라는 이유만으로 삭제하지 않고 해당 도메인 구현 단계에서 역할을 재검토합니다.

### 10.3 Core / API 책임

**juprovider**

- `juprovider.core`: 도메인 모델, Mapper/Repository, 업무 Service, ActionRegistry, DynamicActionService, 권한 검사, Protocol/Device/Data/Experiment 로직
- `juprovider.backend`: Spring Security, 인증 토큰, REST Controller, API DTO/Validation, HTTP와 Core 사이의 Adapter
- Core는 HTTP/Vue에 의존하지 않습니다.
- Backend는 업무 SQL을 중복 구현하지 않고 Core Service를 사용합니다.

**juproject**

- `Domain`: Entity와 Domain Rule
- `Application`: Use Case와 Application Service
- `Infrastructure`: EF Core, Repository, DB 구현
- `Api`: 인증/인가, Endpoint/Controller, API Contract
- React는 API를 통해서만 업무 기능을 사용합니다.

### 10.4 인증 주체 분리

JuProvider에서는 사용자와 Client를 같은 인증 주체로 취급하지 않습니다.

- User 인증: 누가 작업했는가
- Client 인증: 어느 Desktop/Client가 서버와 통신하는가

Web 사용자는 JU 자체 로그인과 권한으로 동작합니다. Desktop의 sync/upload/audit/error API는 Client 자격 인증을 사용하도록 설계합니다. 사용자 작업이 포함되면 User와 Client 정보를 함께 기록합니다.

### 10.5 구현 트랙

- **JU Track**: 1. 설치 완결성 → 2. 인증/권한 → 3. Protocol → 4. Device → 5. Data → 6. Experiment/Run → 7. Storage/Viewer/Offline Sync
- **SYS Track**: 1. `tb_*` → `sys_*` → 2. Site/Dept/Auth/Menu → 3. 고객/서비스 영역
- **Integration Track**: SYS와 JU의 기본 구조가 각각 완성된 뒤 별도 설계합니다. JU 독립 실행을 훼손하지 않는 것이 필수 조건입니다.

### 10.6 설계 변경 절차

DB/API/Core 구조 변경은 다음 순서를 따릅니다.

```
Claude 현재 상태 조사
→ ChatGPT 설계
→ Claude 영향/적합성 역검토
→ 사용자 결정
→ Claude 구현·빌드
→ ChatGPT diff/결과 검토
→ 사용자 commit/push
→ Jenkins 최종 확인
```

DB 스키마, 인증/보안, API 계약, 공통 모델, 의존성, 배포 구조 변경은 항상 사용자 승인 후 구현합니다.

## 11. AI 공용 협업 저장소 (ju-ai-collaboration, v1.3)

### 11.1 역할
| 저장소 | Source of Truth |
|---|---|
| juprovider, juproject | 실제 소스 코드, DB baseline/migration, 빌드 설정 |
| ju-ai-collaboration | 설계, 조사, 결정, 검토, 환경 기준, 작업 기록 |

- 진입점은 `README.md`다. 현재 기준 문서와 진행 중인 작업은 README에서 찾는다.
- 사용자는 문서를 옮기거나 첨부하지 않는다. "README 기준으로 현재 상태 확인하고 검토해 줘" 정도로 요청한다.

### 11.2 폴더
| 폴더 | 내용 | 작성 |
|---|---|---|
| `architecture/` | 현재 기준 설계 (덮어써서 최신 유지, 이력은 Git) | ChatGPT 설계 → Claude가 반영 |
| `environment/` | 개발·빌드 환경 기준, PC별 상태 | Claude |
| `decisions/` | 사용자 결정. `CURRENT.md`(유효한 결정 모음) + 날짜별 기록 | Claude 기록, 사용자 결정 |
| `reviews/claude/`, `reviews/chatgpt/` | 조사·검토·설계 요청 원문. 파일명 `YYYY-MM-DD_주제.md` | 각 AI |
| `worklog/` | `CURRENT.md`(지금 할 일·대기 중인 결정) + `YYYY-MM-DD.md` | Claude |
| `tools/` | 환경 점검·로컬 빌드 스크립트 (저장소 밖 실행용) | Claude |

### 11.3 commit/push
- Claude는 이 저장소의 문서를 직접 commit/push한다. 커밋 메시지 형식은 8장과 같다 (`docs:`, `chore:`).
- ChatGPT가 쓴 문서는 사용자가 전달하면 Claude가 `reviews/chatgpt/`에 원문 그대로 넣는다 (ChatGPT가 직접 push할 수 있게 되면 그 방식으로 바꾼다).
- 제품 저장소의 commit/push 규칙(8장)은 바뀌지 않는다.

### 11.4 금지
- 비밀 값을 넣지 않는다: DB password, `JU_JWT_SECRET`, Client Key, ConnectionString 비밀번호, 인증서·개인키, Jenkins credential.
- 환경 문서는 값 대신 `REQUIRED`, `SET/MISSING`, 저장 위치(예: `user-secrets`, `setenv.bat`)만 적는다.
- 이 저장소가 공개 저장소라면 내부 정보(초기 계정 기본값, 내부 주소 등)도 적지 않는다.

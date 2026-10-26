# JuProvider / JuProject 빌드 환경 기준

- 상태: v1.0 (2026-10-26). 기준 PC-A `DESKTOP-CE5BGKK`에서 실제 빌드가 성공한 구성을 기록했다.
- 목적: 앞으로 빌드 서버(Jenkins 에이전트 등)나 새 개발 PC를 구성할 때의 기준
- 관련 문서: `DEV_ENVIRONMENT_STANDARD.md` (개발 PC 전체 기준), 각 저장소의 `Jenkinsfile`
- 비밀 값은 적지 않는다. 빌드에는 비밀 값이 필요 없다 (배포·실행 단계에서만 필요).

## 1. 검증된 기준 (PC-A, 2026-10-26 09:10)

| 단계 | 명령 | 결과 | 시간 |
|---|---|---|---|
| juprovider.core install | `mvn -B -f juprovider.core\pom.xml clean install` | PASS | 13초 |
| juprovider backend + Vue | `cd juprovider.backend && mvn -B clean package -Pvue` | PASS (`target\juprovider.war`) | 40초 |
| juprovider desktop | `dotnet build desktop\JuProvider.Desktop.slnx -c Debug` | PASS (경고 0, 오류 0) | 7초 |
| juproject backend | `dotnet build backend\JuProject.slnx -c Release` | PASS (경고 0, 오류 0) | 4초 |
| juproject frontend | `cd frontend && npm ci && npm run lint && npm run build` | PASS (`dist\index.html`) | 30초 |

- 기준 커밋: juprovider `d963da2`, juproject `98a94f0` (`main`)
- 시간은 의존성 cache가 있는 상태 기준이다. cache가 없는 첫 빌드는 내려받는 시간이 더해진다.
- 남아 있는 경고 (빌드 실패 아님)
  - juproject lint 3건 (React `set-state-in-effect`)
  - frontend 번들 1.2MB (500kB 초과 경고)

## 2. 필요한 Toolchain

| Tool | 기준 버전 | 필요한 빌드 | 비고 |
|---|---|---|---|
| JDK | 21.0.1 | juprovider core·backend | `JAVA_HOME` 또는 Jenkins 도구 `JDK21` |
| Maven | 3.9.11 | juprovider core·backend | PATH의 `mvn` 또는 Jenkins 도구 `Maven3` |
| .NET SDK | 10.0.4xx (PC-A 10.0.402) | juprovider desktop, juproject backend | `net10.0`, `net10.0-windows`. desktop은 **Windows 빌드 환경 필수** (WinForms) |
| Node.js / npm | 24.14.0 / 11.9.0 | juproject frontend | PC 설치 Node 사용 |
| (자동) Node / npm | v22.14.0 / 10.9.2 | juprovider Vue | `frontend-maven-plugin`이 `juprovider.backend\target\node`에 직접 받는다. 설치 Node와 무관 |
| Git | 2.36.1 | checkout | |

빌드에 **필요 없는 것**: MariaDB, Redis, Tomcat, vcpkg, CMake. 앞의 셋은 배포·실행할 때, 뒤의 둘은 desktop/native를 쓰기 시작할 때 필요하다.

## 3. 빌드 순서와 의존 관계

```
juprovider
  1. juprovider.core  → mvn clean install   (로컬 Maven 저장소에 com.asdp:juprovider.core:1.0.0-SNAPSHOT 설치)
  2. juprovider.backend → mvn clean package -Pvue   (1이 먼저 있어야 함. Vue dist를 WAR static에 포함)
  3. desktop → dotnet build JuProvider.Desktop.slnx   (독립)

juproject
  4. backend → dotnet restore / build JuProject.slnx   (독립)
  5. frontend → npm ci → npm run lint → npm run build   (독립)
```

- backend는 core를 Maven 의존성으로 쓴다. aggregator pom이 없으므로 **core install이 항상 먼저**다.
- `-Pvue` 없이 빌드하면 WAR에 Vue 화면이 들어가지 않는다.

## 4. 네트워크 (첫 빌드·cache 없을 때)

| 대상 | 용도 |
|---|---|
| Maven Central (`repo.maven.apache.org`) | Spring Boot 등 Java 의존성, Maven 플러그인 |
| Node 배포 서버 (`nodejs.org/dist`) | `frontend-maven-plugin`의 Node v22.14.0 |
| npm registry (`registry.npmjs.org`) | Vue·React 의존성 |
| NuGet (`api.nuget.org`) | .NET 패키지 (EF Core, Pomelo 등) |
| GitHub | 소스 checkout |

인터넷이 막힌 빌드 서버라면 위 저장소의 내부 미러(Nexus 등)나 미리 채운 cache가 필요하다. 아직 구성하지 않았다.

## 5. Cache 위치

| Cache | 개발자 (PC-A) | Jenkins (LocalSystem) |
|---|---|---|
| Maven | `%USERPROFILE%\.m2\repository` | `C:\Windows\System32\config\systemprofile\.m2\repository` |
| NuGet | `%USERPROFILE%\.nuget\packages` | systemprofile 아래 |
| npm | `%LOCALAPPDATA%\npm-cache` | systemprofile 아래 |
| Vue용 Node | 저장소 `juprovider.backend\target\node` (clean 시 다시 받음) | 같음 (Jenkins workspace 안) |

- **개발자 cache와 빌드 서버 cache는 공유하지 않는다.** 계정과 권한이 섞이고 동시 빌드 때 잠금 충돌이 날 수 있다.
- cache는 필수 경로가 아니다. 지우면 다음 빌드에서 다시 받는다.

## 6. 빌드 산출물

| 저장소 | 산출물 | 위치 |
|---|---|---|
| juprovider | WAR | `juprovider.backend\target\juprovider.war` |
| juprovider | core jar | `juprovider.core\target\juprovider.core-1.0.0-SNAPSHOT.jar` (+ 로컬 Maven 저장소) |
| juprovider | desktop | `desktop\app` (Git 제외) |
| juproject | API | `dotnet publish` 결과. Jenkins는 `artifacts\backend` |
| juproject | frontend | `frontend\dist` |

산출물·`node_modules`·`target`·`bin`·`obj`·`dist`는 Git에 넣지 않는다 (`.gitignore`).

## 7. Jenkins와의 대응

| 로컬 단계 | `juprovider-ai` Jenkinsfile | `juproject-ai` Jenkinsfile |
|---|---|---|
| core install | `Build Core` | — |
| backend + Vue | `Build Backend` → `Check WAR` | — |
| desktop | 없음 (후순위) | — |
| juproject backend | — | `Backend Build` (restore + Release build) → `Backend Publish` |
| juproject frontend | — | `Frontend Build` (npm ci, lint, build) |
| 배포 | `Stop Tomcat` → `Backup` → `Clean` → `Deploy WAR` → `Start Tomcat` → `Health Check` | 없음 |

- Jenkins는 JDK/Maven을 **도구 이름**(`JDK21`, `Maven3`)으로 쓴다. 빌드 서버마다 Jenkins 도구 설정에 실제 경로를 등록한다.
- Node, .NET, Git은 Jenkins 서비스 계정의 PATH(Machine PATH)를 쓴다.
- 현재 juprovider Jenkinsfile은 Tomcat 경로를 절대경로로 쓴다. `JU_TOMCAT_HOME` 전역 환경변수로 바꾸는 변경안이 승인 대기 중이다.

## 8. 빌드 서버 구성 체크리스트

1. Windows (desktop WinForms 빌드 때문에 필요. desktop을 빌드하지 않는 서버는 Linux도 가능하지만 Jenkinsfile이 `bat`/`powershell` 기준이라 별도 작업이 필요)
2. JDK 21.0.1, Maven 3.9.11 설치 → Jenkins 도구 `JDK21`, `Maven3` 등록
3. .NET SDK 10.0.4xx, Node 24.x, Git 설치 → Machine PATH
4. 네트워크: 4장 저장소 접근, 또는 미러 구성
5. Jenkins 서비스 계정 결정 (현재 LocalSystem). 계정을 바꾸면 cache 위치도 바뀐다
6. Jenkins credential `juprovider-git` (GitHub 읽기)
7. 배포까지 하는 서버라면 추가: Tomcat 10.1.52 + `bin\setenv.bat`(`JU_DB_*`, `JU_JWT_SECRET`), MariaDB 10.6, Redis, 전역 환경변수 `JU_TOMCAT_HOME`
8. 검증: 1장의 명령을 그대로 실행해서 모두 PASS인지 확인 → Jenkins `main` 빌드 SUCCESS

## 9. 로컬 빌드 확인 도구 (저장소 밖, workspace)

| 파일 | 용도 |
|---|---|
| `ai_dev_env_check.ps1` | Tool 버전·경로·환경변수·PATH·secret(SET/MISSING) 검증. `-Baseline`이면 기준값 기록 |
| `dev_env_baseline.json` | PC-A 기준 버전 |
| `ai_local_build.ps1` | 1장 빌드를 순서대로 실행하고 `ai_local_build_<PC>.log`에 PASS/FAIL 기록 (배포·DB·git 변경 없음) |
| `run_ai_local_build.cmd` | 위 스크립트를 더블클릭으로 실행 |

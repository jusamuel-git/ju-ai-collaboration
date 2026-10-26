# JuProvider / JuProject 개발 환경 기준

- 상태: **초안 v0.2 (2026-10-26)** — PC-A 파일 실측 반영. 명령 실행이 필요한 항목(PATH, 환경변수, Node·Git 버전)은 `ai_dev_env_check.ps1 -Baseline` 후 확정
- 위치: `C:\MyData\MyDev\workspace\DEV_ENVIRONMENT_STANDARD.md` (저장소 밖. 두 저장소의 `AI_COLLABORATION.md` 4장이 이 문서를 가리킨다)
- 비밀번호·JWT secret·DB password·Client Key 같은 실제 비밀 값은 이 문서에 쓰지 않는다. 위치와 확인 방법만 적는다.

## 1. 원칙

1. **기준 PC는 PC-A `DESKTOP-CE5BGKK`** 다. 다른 PC는 PC-A에 맞춘다. 두 PC를 절충한 제3의 환경을 만들지 않는다.
2. PC-A에서 정상 동작하는 Tool은 **옮기거나 재설치하지 않는다.** 현재 설치 위치가 기준값이다.
3. **소스·빌드 설정은 PC 절대경로를 쓰지 않는다.** 환경변수, 상대경로, Jenkins 도구 이름(`JDK21`, `Maven3`)을 쓴다.
4. 개발자 환경변수는 **User 변수**가 기본이다. Machine 변수는 꼭 필요할 때만 쓴다 (관리자 권한 필요).
5. **Jenkins(LocalSystem) 환경은 개발자 환경과 분리한다.** 도구 경로는 Jenkins 도구 설정에, 실행 비밀 값은 Tomcat `setenv.bat`에 둔다. cache는 공유하지 않는다.
6. Tool 업그레이드는 이 문서를 먼저 고친 뒤 두 PC에 같이 적용한다.

## 2. 기준 PC와 Workspace

| 항목 | 값 |
|---|---|
| 기준 PC | PC-A `DESKTOP-CE5BGKK` (사용자 JUSAMUEL) |
| 다른 개발 PC | PC-B 노트북 `JUSAMUEL` |
| Workspace | `C:\MyData\MyDev\workspace` (`JU_WORKSPACE`) |
| 저장소 | `%JU_WORKSPACE%\juprovider`, `%JU_WORKSPACE%\juproject` |
| 저장소 밖 문서·스크립트 | `%JU_WORKSPACE%` 바로 아래 (`ai_*.md`, `ai_*.ps1`, 이 문서) |

## 3. Toolchain

| Tool | 기준 버전 | 구분 | PC-A 설치 위치 | 프로젝트가 쓰는 방법 | Jenkins |
|---|---|---|---|---|---|
| JDK | 21.0.1 | Portable | `C:\MyData\MyDev\jdk\jdk-21.0.1` | `JAVA_HOME` | 도구 `JDK21` |
| Maven | 3.9.11 | Portable | `C:\MyData\MyDev\maven\apache-maven-3.9.11` | `MAVEN_HOME`, PATH의 `mvn` | 도구 `Maven3` |
| Tomcat | 10.1.52 | Portable | `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` | `JU_TOMCAT_HOME` | 지금은 Jenkinsfile 절대경로 → Jenkins 전역 환경변수 `JU_TOMCAT_HOME`으로 전환 예정 (5장) |
| vcpkg | tool 2026-07-27 (git clone + `vcpkg.exe`) | Portable | `C:\MyData\MyTool\vcpkg` | `VCPKG_ROOT` | 아직 사용 안 함 (`desktop/native` 비어 있음) |
| .NET SDK | **10.0.4xx** (PC-A 10.0.402, 9.0.317 함께 설치) | 설치형 | `C:\Program Files\dotnet` | PATH, 저장소 `global.json`(제안) | Machine PATH |
| Node.js / npm | Node 실측 대기 / npm 11.9.0 | 설치형 (nvm 설치됨, nvm path = 이 폴더) | `C:\Program Files\nodejs` | PATH (juproject frontend) | Machine PATH |
| CMake | 4.4.x | 설치형 | `C:\Program Files\CMake` | PATH | 아직 사용 안 함 |
| Git | 2.36.1 (10/24 기준, 재확인 대기) | 설치형 | `C:\Program Files\Git` | PATH | 도구 `git.exe` |
| MariaDB | 10.6.16 (client 3.3.8) | 설치형 | `C:\Program Files\MariaDB 10.6` | 접속 정보만 (`JU_DB_URL` 등) | — |
| Redis | 3.x (Microsoft Windows 포트, 2016-07 빌드) | 설치형 | `C:\Program Files\Redis` | `localhost:6379` | — |
| Jenkins | 2.580.1 | 설치형 (서비스, LocalSystem) | `C:\Program Files\Jenkins`, 홈 `C:\ProgramData\Jenkins\.jenkins` | — | 서비스 자체가 `jenkins.xml`의 `<executable>`로 **JDK 21(`C:\MyData\MyDev\jdk\jdk-21.0.1\bin\java.exe`)** 에서 실행됨 |
| Visual Studio | 2026 Community | 설치형 | `C:\Program Files\Microsoft Visual Studio\18\Community` | desktop(.NET), juproject | — |
| VS Code | 실측 대기 | 사용자 설치 | `%LOCALAPPDATA%\Programs\Microsoft VS Code` | — | — |

"실측 대기"는 PC-A에서 `ai_dev_env_check.ps1 -Baseline`을 실행해 `dev_env_baseline.json`에 기록한 값을 기준으로 한다.

### PC-A에 있지만 기준에 넣지 않는 것 (2026-10-26 확인)
| 위치 | 내용 | 처리 |
|---|---|---|
| `C:\MyData\MyDev\jdk\` | JDK 21 외 `jdk-11.0.1`, `jdk-17.0.9`, `openjdk-1.8.0.252` | 다른 프로젝트용. 유지 (PATH 순서만 확인) |
| `C:\MyData\MyDev\maven\settings.xml` | `localRepository = C:/MyData/maven/repository` | **현재 미사용으로 판단** (Maven `conf\settings.xml`에 localRepository 없음 → 실제 저장소는 `%USERPROFILE%\.m2\repository`. juprovider.core도 여기에 install됨) |
| `C:\MyData\MyDev\maven\repository` | 과거 Maven 저장소 (juprovider.core 없음) | 미사용 추정. 유지 |
| `C:\MyData\MyDev\node`, `C:\MyData\MyDev\vscode` | 빈 폴더 | 기준 아님 |
| `C:\MyData\MyDev\gradle\gradle-9.6.0` | Gradle | 이 두 프로젝트는 사용 안 함 |
| `C:\MyData\MyTool\tomcat\` | 10.1.52 외 `8.5`, `9.0.115`, `tomcat-connectors-1.2.48` | 기준은 10.1.52만 |

### 참고: Node가 두 종류다
- **juprovider Vue 빌드**(`mvn package -Pvue`)는 `frontend-maven-plugin`이 `juprovider.backend/target/node`에 **Node v22.14.0 / npm 10.9.2를 직접 받아서** 쓴다. PC에 설치된 Node와 무관하다 (첫 빌드에 인터넷 필요).
- **juproject frontend**와 `juprovider.frontvue` 단독 개발(`npm run dev`)은 PC에 설치된 Node(`C:\Program Files\nodejs`)를 쓴다.

### 참고: MariaDB 데이터 위치
- 프로그램 버전(10.6.x)만 맞춘다. **데이터 디렉터리는 PC별로 달라도 된다** (Local Runtime Configuration).
  - PC-A: `C:\MyData\MyTool\MyDB\mariadb`
  - PC-B: `C:\Program Files\MariaDB 10.6\data`
- 같아야 하는 것은 DB 내용의 기준이다. juprovider는 `database/baseline` + `seed` + `migration`, juproject는 EF Migrations.

## 4. 환경변수

### 개발자 (User 변수)

| 변수 | PC-A 값 | 용도 |
|---|---|---|
| `JU_WORKSPACE` | `C:\MyData\MyDev\workspace` | 스크립트 기준 위치 |
| `JAVA_HOME` | `C:\MyData\MyDev\jdk\jdk-21.0.1` | Maven, IDE |
| `MAVEN_HOME` | `C:\MyData\MyDev\maven\apache-maven-3.9.11` | Maven |
| `VCPKG_ROOT` | `C:\MyData\MyTool\vcpkg` | native 빌드 (향후) |
| `JU_TOMCAT_HOME` | `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` | 수동 배포·확인 |

- 설정 도구: `ai_dev_env_set_user.ps1`. 기본은 미리보기이고, `-Apply`는 비어 있는 User 변수만 설정한다. 다른 값이 있으면 바꾸지 않고 CONFLICT로 보고한다.
- PATH는 이 스크립트로 바꾸지 않는다. Windows는 Machine PATH 안의 `%JAVA_HOME%`이 User 변수를 가리키면 펼치지 않는다. 그래서 PATH 정리는 `ai_dev_env_check.ps1`의 PATH 결과를 보고 따로 결정한다.

### Jenkins (LocalSystem)
- User 변수를 보지 않는다. JDK/Maven은 Jenkins 도구 설정, Node/.NET/Git은 Machine PATH를 쓴다.
- Tomcat 위치는 Jenkins 전역 환경변수 `JU_TOMCAT_HOME`으로 지정한다 (5장 Jenkinsfile 변경과 함께, 승인 후).

## 5. 프로젝트의 PC 경로 독립화

| 대상 | 현재 | 기준 |
|---|---|---|
| juprovider `Jenkinsfile` 13~15행 | Tomcat 절대경로 | `env.JU_TOMCAT_HOME`. 없으면 Environment 단계에서 명확한 오류. 변경안: `proposal_juprovider_Jenkinsfile_JU_TOMCAT_HOME.patch` |
| juprovider `Jenkinsfile` 347·357·362행 | 포트 `8081` 직접 사용 | 이미 있는 `HTTP_PORT` 변수 사용 (같은 patch에 포함) |
| `AI_COLLABORATION.md` 4장 | PC 경로 표 | PC-A 참고값 + 환경변수 표로 갱신 (이 문서를 가리킴) |
| 그 외 소스·빌드 설정 | PC 절대경로 없음 (2026-10-26 검색) | 유지 |

**적용 순서 (Jenkins를 깨뜨리지 않게)**
1. 각 PC Jenkins: 관리 > System > Global properties > Environment variables에 `JU_TOMCAT_HOME` 추가. 기존 Jenkinsfile은 이 값을 쓰지 않으므로 빌드에 영향이 없다.
2. Jenkinsfile 변경 commit/push
3. Jenkins main 빌드로 확인

## 6. .NET SDK 고정 (제안)

두 저장소 루트에 같은 `global.json`을 둔다.

```json
{ "sdk": { "version": "10.0.400", "rollForward": "latestPatch", "allowPrerelease": false } }
```

- 10.0.4xx 안에서는 설치된 최신 patch를 쓴다 (PC-A 10.0.402, PC-B 10.0.401 모두 허용). 10.0.1xx/10.0.3xx, 11.x는 쓰지 않는다.
- 10.0.4xx SDK가 없는 PC에서는 빌드가 명확한 오류로 실패한다.
- Visual Studio 2026은 `C:\Program Files\dotnet`의 SDK와 `global.json`을 따른다. VS 업데이트로 10.0.4xx가 지워지지 않는 한 영향 없음 (확인 항목: VS가 SDK 10.0.4xx를 인식하는지).
- Jenkins: `dotnet` 명령을 workspace 루트에서 실행하므로 루트 `global.json`이 적용된다.
- `dotnet-ef` 9.0.21(로컬 도구)은 SDK 선택과 무관하다.

## 7. Cache

- Maven, NuGet, npm cache는 **필수 경로가 아니다.** 없어도 dependency restore로 다시 만들어진다. 이번 표준화에서 옮기지 않는다.
- 현재 PC-A 개발자 cache (2026-10-26 확인)
  - Maven: `%USERPROFILE%\.m2\repository` (기본값. `com\asdp`(juprovider.core) 포함)
  - NuGet: `%USERPROFILE%\.nuget\packages` (기본값으로 추정)
  - npm: `%LOCALAPPDATA%\npm-cache` (기본값으로 추정)
- Jenkins cache는 LocalSystem 프로필(`C:\Windows\System32\config\systemprofile\...`)에 따로 있다. **개발자 cache와 공유하지 않는다.**
- juprovider.core는 개발자(`mvn install`)와 Jenkins(Build Core 단계)가 각자 자기 Maven 저장소에 install한다.

## 8. Secret / Local Config (Git에 저장하지 않음)

| 대상 | 위치 | 항목 | 확인 방법 |
|---|---|---|---|
| juprovider 서버 | `%JU_TOMCAT_HOME%\bin\setenv.bat` | `JU_DB_URL`, `JU_DB_USER`, `JU_DB_PASSWORD`, `JU_JWT_SECRET`(32자 이상, JU-1 이후) | `ai_dev_env_check.ps1` → SET/MISSING |
| juproject 서버 | `dotnet user-secrets` (`%APPDATA%\Microsoft\UserSecrets\<UserSecretsId>\secrets.json`) | `ConnectionStrings:Default`, `Jwt:SigningKey` | `ai_dev_env_check.ps1` → SET/MISSING, 또는 `dotnet user-secrets list --project backend\src\JuProject.Api` (값이 출력되므로 화면 공유 주의) |
| juprovider Desktop | `{app}\config\client.json` (JU-1 이후) | `ClientId`, `ClientKey` | 파일 존재 여부 |
| Jenkins | Jenkins credential | `juprovider-git` | Jenkins 관리 화면 |
| juproject 개발 시드 | `appsettings.Development.json`의 `Seed:AdminPassword` | 현재 평문으로 추적 중 | 별도 보안 정리 항목 (AI_WORKLOG) |

- 비밀 값은 PC마다 사람이 직접 입력한다. 문서·대화·patch·zip에 넣지 않는다.

## 9. 확인 명령

```
where git & git --version
where java & java -version
where mvn & mvn -version
where dotnet & dotnet --list-sdks
where node & node --version & npm --version
where cmake & cmake --version
"%VCPKG_ROOT%\vcpkg.exe" version
"C:\Program Files\MariaDB 10.6\bin\mysql.exe" --version
sc qc Jenkins
```

한 번에 확인: `powershell -ExecutionPolicy Bypass -File %JU_WORKSPACE%\ai_dev_env_check.ps1`

## 10. 새 PC 설정 절차

1. `C:\MyData\MyDev\workspace`를 만들고 두 저장소를 clone한다.
2. Portable Tool을 3장 위치에 압축 해제한다 (JDK 21.0.1, Maven 3.9.11, Tomcat 10.1.52, vcpkg). 다른 위치를 써야 하면 환경변수만 그 위치로 지정한다.
3. 설치형 Tool을 공식 경로에 설치한다 (.NET SDK 10.0.4xx, Node, CMake, Git, MariaDB 10.6, Redis, Jenkins, Visual Studio 2026).
4. `ai_dev_env_set_user.ps1`로 User 환경변수를 미리보기한 뒤 `-Apply`로 설정한다.
5. Secret을 설정한다: Tomcat `setenv.bat`, juproject user-secrets (8장).
6. DB를 준비한다: juprovider는 `database/README.md` 순서, juproject는 백업 복원 또는 EF migration.
7. Jenkins를 설정한다: 도구 `JDK21`, `Maven3`(이 PC 경로), 전역 환경변수 `JU_TOMCAT_HOME`, credential `juprovider-git`, 작업 `juprovider-ai`/`juproject-ai`(`*/main`).
8. `ai_dev_env_check.ps1`을 실행해 FAIL이 없는지 확인한다.

## 11. 검증 절차

1. **Environment Check**: `ai_dev_env_check.ps1` — FAIL 0. WARN은 사유를 기록한다.
2. **Dependency Restore / Local Build**
   - juprovider: `mvn -B -f juprovider.core\pom.xml clean install` → `cd juprovider.backend && mvn -B clean package -Pvue`
   - juproject: `dotnet build backend\JuProject.slnx -c Release`, `cd frontend && npm ci && npm run lint && npm run build`
3. **Jenkins main**: `juprovider-ai`(Health UP), `juproject-ai` SUCCESS

## 변경 이력

| 일자 | 내용 |
|---|---|
| 2026-10-26 | 초안 v0.1 — PC-A 기준 확정 방향 (ChatGPT 검토 전) |
| 2026-10-26 | v0.2 — PC-A 파일 실측 반영 (JDK/Maven/Tomcat/MariaDB/.NET/CMake/vcpkg/Jenkins 버전·도구 경로, Maven 실제 저장소, Jenkins 서비스 JDK) |

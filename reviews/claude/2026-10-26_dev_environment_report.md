# PC-A 기준 개발 환경 표준화 — 결과 보고 (2026-10-26, Claude)

> **실측 방법**: 이 세션이 PC-A(`desktop-ce5bgkk`)에 연결되었다 (08:50).
> 다만 이번 연결은 **파일 읽기만 가능하고 명령 실행(셸)은 불가**하다. 그래서 다음처럼 나눠 확인했다.
> - 버전·경로: 설치 폴더의 버전 파일(`release`, `RELEASE-NOTES`, jar 이름, 헤더, Jenkins 설정 XML)을 직접 읽어 확인
> - 명령이 필요한 값(PATH, User/Machine 환경변수, Node·Git 실행 버전): 확인하지 못했다. `ai_dev_env_check.ps1 -Baseline` 실행 결과로 확정한다.
> - 비밀 파일(`setenv.bat`, `secrets.json`, Jenkins `credentials.xml`)은 열지 않고 존재 여부만 확인했다.
>
> Tool 이동·삭제·업그레이드, DB·migration, Jenkins 설정, commit/push는 하지 않았다.

## [PC-A 확정 Toolchain]

PC-A `desktop-ce5bgkk`, 2026-10-26 08:5x 실측

| Tool | 기준 버전 (실측) | 구분 | PC-A 위치 | 확인 근거 |
|---|---|---|---|---|
| Workspace | — | — | `C:\MyData\MyDev\workspace` | 폴더 확인 (`juprovider`, `juproject`) |
| JDK | **21.0.1** (Oracle, 2023-10-17) | Portable | `C:\MyData\MyDev\jdk\jdk-21.0.1` | `release` 파일. 같은 폴더에 11.0.1, 17.0.9, openjdk 1.8.0.252도 있음 |
| Maven | **3.9.11** | Portable | `C:\MyData\MyDev\maven\apache-maven-3.9.11` | `lib\maven-core-3.9.11.jar` |
| Tomcat | **10.1.52** | Portable | `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` | `RELEASE-NOTES`. 같은 폴더에 8.5, 9.0.115도 있음 |
| vcpkg | tool **2026-07-27** | Portable | `C:\MyData\MyTool\vcpkg` | `scripts\vcpkg-tool-metadata.txt`, `vcpkg.exe` 있음 |
| .NET SDK | **10.0.402** (+ 9.0.317) | 설치형 | `C:\Program Files\dotnet` | `sdk\` 폴더 |
| Node.js | **미확인** (실행 필요) | 설치형 | `C:\Program Files\nodejs` | `node.exe` 있음. nvm `settings.txt`의 path가 이 폴더 |
| npm | **11.9.0** | 설치형 | `C:\Program Files\nodejs` | `node_modules\npm\package.json` |
| CMake | **4.4.x** | 설치형 | `C:\Program Files\CMake` | `share\cmake-4.4` |
| Git | 2.36.1 (10/24 값, **재확인 필요**) | 설치형 | `C:\Program Files\Git` | 이 세션에 Git 폴더가 연결되지 않음 |
| MariaDB | **10.6.16** (client 3.3.8) | 설치형 | `C:\Program Files\MariaDB 10.6`, 데이터 `C:\MyData\MyTool\MyDB\mariadb` | `include\mysql\mariadb_version.h` |
| Redis | 3.x (Windows 포트, 2016-07 빌드) | 설치형 | `C:\Program Files\Redis` | 파일 날짜 |
| Jenkins | **2.580.1** | 설치형, 서비스 | `C:\Program Files\Jenkins`, 홈 `C:\ProgramData\Jenkins\.jenkins` | `config.xml`, `lastExecVersion` |
| Visual Studio / VS Code | 미확인 | 설치형 | — | 연결 폴더 밖 |

**새로 확인된 사실**
1. **Jenkins 서비스 자체가 PC-A의 JDK 경로로 실행된다.** `jenkins.xml`에 `<executable>C:\MyData\MyDev\jdk\jdk-21.0.1\bin\java.exe`가 있다. PC-B에서 JDK를 옮기면 Jenkins 서비스 설정도 같이 바꿔야 한다.
2. **Jenkins 도구** `JDK21` = `C:\MyData\MyDev\jdk\jdk-21.0.1`, `Maven3` = `C:\MyData\MyDev\maven\apache-maven-3.9.11`, Git = `git.exe`(PATH). 전역 환경변수(`globalNodeProperties`)는 **비어 있다** → `JU_TOMCAT_HOME`은 아직 없음.
3. **Maven 실제 저장소는 `%USERPROFILE%\.m2\repository`** 다. `conf\settings.xml`에 localRepository가 없고, 여기에 `com\asdp`(juprovider.core)가 있다.
   - `C:\MyData\MyDev\maven\settings.xml`(`localRepository=C:/MyData/maven/repository`)과 `C:\MyData\MyDev\maven\repository`도 있지만 **기본 실행에서는 쓰이지 않는 과거 파일로 판단**한다 (`-s`로 지정할 때만 사용).
4. `C:\MyData\MyDev\node`, `C:\MyData\MyDev\vscode`는 **빈 폴더**다. Node와 VS Code는 설치형만 쓴다.
5. Jenkins workspace에 이름을 바꾸기 전 작업 폴더 `JuProvider-Backend`(+`@tmp`)가 남아 있다. 정리 후보로만 기록한다 (삭제하지 않음).
6. Secret 파일은 존재만 확인했다: Tomcat `bin\setenv.bat`(539 bytes), juproject user-secrets `secrets.json`(200 bytes).

## [환경변수]

User 변수 후보 (사용자 지시 그대로)

| 변수 | 값 | 현재 PC-A 상태 |
|---|---|---|
| `JU_WORKSPACE` | `C:\MyData\MyDev\workspace` | 신규로 추정 (사용처 없음) |
| `JAVA_HOME` | `C:\MyData\MyDev\jdk\jdk-21.0.1` | 10/24 기준 JDK 21을 가리킴 (같은 값으로 추정). **범위(User/Machine) 실측 대기** |
| `MAVEN_HOME` | `C:\MyData\MyDev\maven\apache-maven-3.9.11` | 실측 대기 |
| `VCPKG_ROOT` | `C:\MyData\MyTool\vcpkg` | 실측 대기 |
| `JU_TOMCAT_HOME` | `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` | 신규 |

- 적용 도구: `ai_dev_env_set_user.ps1`
  - 기본은 **미리보기**다.
  - `-Apply`는 비어 있는 User 변수만 설정한다.
  - 다른 값이 이미 있으면 바꾸지 않고 CONFLICT로 보고한다.
  - Machine 변수와 PATH는 건드리지 않는다.
- Jenkins(LocalSystem)는 User 변수를 보지 않으므로 영향이 없다.

## [PATH 충돌 여부]

- 10/24 기준 PC-A Machine PATH에는 JDK21, Maven, dotnet, nodejs, Git이 있다.
- 확인할 위험 (실측 대기)
  1. **JDK가 4개(8/11/17/21) 있다.** PATH에서 `java`가 JDK 21보다 먼저 다른 JDK를 찾는지 확인해야 한다.
  2. **nvm이 설치되어 있다.** nvm symlink 경로와 `C:\Program Files\nodejs`가 겹치는지 확인해야 한다.
  3. Machine PATH가 User 변수(`%JAVA_HOME%`)를 참조하면 Windows가 펼치지 못한다. PATH는 지금 형태(실제 경로)를 유지하는 것을 권장한다.
- `ai_dev_env_check.ps1`의 `PATH java/mvn/node/dotnet` 항목이 첫 번째 후보가 기준 위치인지 PASS/WARN으로 보여 준다.

## [.NET global.json 검토]

**적합하다. 변경 후보로 제안한다 (아직 저장소에 넣지 않음).**

```json
{ "sdk": { "version": "10.0.400", "rollForward": "latestPatch", "allowPrerelease": false } }
```

| 확인 항목 | 결과 |
|---|---|
| PC-A 10.0.402 / PC-B 10.0.401 | 둘 다 10.0.4xx라서 허용됨. 각 PC에 설치된 최신 patch를 쓴다 |
| 다른 feature band 차단 | 10.0.1xx·3xx·5xx, 11.x는 쓰지 않음. 10.0.4xx가 없으면 명확한 오류 |
| 대상 프로젝트 | juproject `net10.0` 4개, juprovider desktop `net10.0-windows` 11개 — 모두 10.0 SDK로 빌드 가능 |
| Jenkins | `dotnet` 명령을 workspace 루트에서 실행하므로 루트 `global.json`이 적용됨. Machine PATH의 `C:\Program Files\dotnet` 사용 |
| Visual Studio 2026 | `C:\Program Files\dotnet`의 SDK를 쓰고 `global.json`을 따른다. **실측 대기**: VS 설치 구성에 10.0.4xx SDK가 그대로 있는지 (VS가 다른 band를 따로 설치했어도 4xx가 있으면 문제 없음) |
| dotnet-ef 9.0.21 | 로컬 도구라서 SDK 선택과 무관 |
| 위치 | 두 저장소 루트 (`juprovider/global.json`, `juproject/global.json`) |
| 위험 | VS나 Windows Update로 10.0.4xx SDK가 제거되면 빌드가 실패함 → 실패 메시지가 명확해서 바로 알 수 있음 |

파일: `proposal_juprovider_global_json.patch`, `proposal_juproject_global_json.patch`

## [프로젝트 절대경로 의존]

두 저장소 `main` 추적 파일 전체 검색 (10/26). 빌드 산출물, `node_modules`, lock 파일은 제외했다.

| 파일:라인 | 현재 | 용도 | 처리 |
|---|---|---|---|
| juprovider `Jenkinsfile:13-15` | `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` | 배포 Tomcat | **변경안 준비 (미적용)** — `env.JU_TOMCAT_HOME` 사용. 값이 없거나 Tomcat이 없으면 Environment 단계에서 명확한 오류 |
| juprovider `Jenkinsfile:347, 357, 362` | 포트 `8081` 직접 사용 | 기동 대기 | 같은 변경안에서 이미 있는 `HTTP_PORT` 변수로 바꿈 (WORKLOG 정리 항목) |
| 양쪽 `AI_COLLABORATION.md` 4장 | PC 경로 표 | 문서 | **갱신함** — PC-A 참고값 + 구분 + 환경변수 열, `DEV_ENVIRONMENT_STANDARD.md` 참조 |
| juproject `Jenkinsfile:50` | `echo USERPROFILE=%USERPROFILE%` | 로그 출력 | 경로 의존 아님, 유지 |

- 그 밖의 Java, C#, Vue, React, SQL, pom, csproj, package.json에는 PC 절대경로가 없다.
- 호스트/포트 기본값(`localhost:8081/3306/6379/5103/5173`)은 개발 기본값이고, 대부분 환경변수로 덮어쓸 수 있다.

**Jenkinsfile 변경 적용 순서 (빌드를 깨뜨리지 않게)**
1. PC-A Jenkins: 관리 > System > Global properties > Environment variables에 `JU_TOMCAT_HOME = C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52`를 추가한다. 현재 Jenkinsfile은 이 값을 쓰지 않으므로 영향이 없다.
2. PC-B Jenkins도 같은 변수를 추가한다 (저녁 작업).
3. 승인 후 `proposal_juprovider_Jenkinsfile_JU_TOMCAT_HOME.patch`를 commit/push한다.
4. 두 PC에서 `juprovider-ai` main 빌드로 Health UP을 확인한다.

## [Jenkins와 Local 환경 분리]

| 항목 | 개발자 (User) | Jenkins (LocalSystem) |
|---|---|---|
| JDK / Maven | `JAVA_HOME`, `MAVEN_HOME` (User 변수) | Jenkins 도구 `JDK21`, `Maven3` |
| Tomcat | `JU_TOMCAT_HOME` (User 변수) | Jenkins 전역 환경변수 `JU_TOMCAT_HOME` (변경안 적용 후) |
| Node / .NET / Git | PATH | Machine PATH |
| Maven 저장소 | `%USERPROFILE%\.m2\repository` | `C:\Windows\System32\config\systemprofile\.m2` |
| NuGet / npm cache | 사용자 프로필 | systemprofile |
| 실행 비밀 값 | user-secrets (juproject) | Tomcat `setenv.bat` (juprovider) |

cache는 공유하지 않고 옮기지도 않는다 (필수 경로 아님, restore로 재생성 가능).

## [Secret/Local Config]

| 대상 | 위치 | 항목 | 이 보고의 상태 |
|---|---|---|---|
| juprovider | Tomcat `bin\setenv.bat` | `JU_DB_URL`, `JU_DB_USER`, `JU_DB_PASSWORD`, `JU_JWT_SECRET` | PC-A: `JU_DB_*` 설정 (10/24 사용자 입력). `JU_JWT_SECRET` 실측 대기 |
| juproject | `dotnet user-secrets` | `ConnectionStrings:Default`, `Jwt:SigningKey` | PC-A: 둘 다 설정 (10/24 확인) |
| Desktop | `{app}\config\client.json` | `ClientId`, `ClientKey` | JU-1 이후 (미적용) |
| Jenkins | credential | `juprovider-git` | 설정됨 |

`ai_dev_env_check.ps1`은 값 없이 SET/MISSING만 출력한다.

## [DEV_ENVIRONMENT_STANDARD.md]

초안 v0.2를 작성했다 (11장 구성, PC-A 파일 실측 반영).
- 원칙, 기준 PC/Workspace, Toolchain 표(버전·구분·PC-A 위치·프로젝트 사용 방법·Jenkins), 환경변수(User/Jenkins)
- 경로 독립화와 Jenkinsfile 적용 순서, `.NET global.json`
- Cache, Secret/Local Config, 확인 명령, 새 PC 설정 절차, 검증 절차
- 참고: Vue Maven 빌드는 `frontend-maven-plugin`의 자체 Node(v22.14.0)를 쓰고, MariaDB 데이터 위치는 PC별로 허용한다는 내용을 넣었다.
- 실제 비밀 값은 넣지 않았다.

## [Environment Check 결과]

**스크립트 미실행** — 이 세션은 PC-A에서 파일 읽기만 가능하고 명령은 실행할 수 없다. 파일로 확인한 값은 [PC-A 확정 Toolchain] 표에 반영했다.

준비한 스크립트: `ai_dev_env_check.ps1` (읽기 전용)
- 출력 열: Tool / ExpectedVersion / ActualVersion / Result(PASS/WARN/FAIL) / ActualPath / Note
- 검사 항목
  - workspace·저장소(브랜치·HEAD·변경 수)
  - Tool 13종
  - User 환경변수 5개 (User/Machine 충돌 포함)
  - PATH 첫 후보 (java, mvn, node, dotnet)
  - `global.json` 해석 (저장소에 있을 때)
  - secret SET/MISSING
- 고정 기준: JDK 21.0.1, Maven 3.9.11, Tomcat 10.1.52, .NET 10.0.4xx, MariaDB 10.6.x
- 나머지 Tool은 PC-A에서 `-Baseline`으로 기록한 값과 비교한다.

PC-A 실행 순서
```
powershell -ExecutionPolicy Bypass -File C:\MyData\MyDev\workspace\ai_dev_env_check.ps1 -Baseline
powershell -ExecutionPolicy Bypass -File C:\MyData\MyDev\workspace\ai_dev_env_set_user.ps1
```
두 번째는 미리보기만 한다. 결과를 보고 `-Apply` 여부를 정한다.

## [저녁 PC-B에서 해야 할 작업]

PC-B만 PC-A에 맞춘다.

| # | 작업 | 현재 PC-B | 기준 |
|---|---|---|---|
| 1 | JDK 위치 | `C:\MyData\MyTool\jdk\jdk-21.0.1` | `C:\MyData\MyDev\jdk\jdk-21.0.1` (복사 후 Jenkins `JDK21` 경로 변경, 기존 폴더는 확인 후 정리) |
| 2 | Maven 위치 | `C:\MyData\MyTool\maven\apache-maven-3.9.11` | `C:\MyData\MyDev\maven\apache-maven-3.9.11` (Jenkins `Maven3` 경로 변경) |
| 3 | Maven settings | `MyTool\maven\settings.xml` (localRepository `MyTool\maven\repository`) | PC-A처럼 기본값 (`%USERPROFILE%\.m2`). cache는 restore로 재생성 |
| 4 | vcpkg 폴더 이름 | `C:\MyData\MyTool\vcpkg-master` | `C:\MyData\MyTool\vcpkg` |
| 5 | .NET SDK | 10.0.401 | 10.0.4xx 허용 (`global.json` 적용 시 변경 불필요) |
| 6 | User 환경변수 | 미확인 | `ai_dev_env_set_user.ps1` (`-Apply`) |
| 7 | Jenkins 전역 환경변수 | 없음 | `JU_TOMCAT_HOME` 추가 |
| 7-1 | Jenkins 서비스 JDK | `jenkins.xml` `<executable>`이 PC-B JDK 경로로 되어 있을 것 (미확인) | JDK를 옮기면 `C:\MyData\MyDev\jdk\jdk-21.0.1\bin\java.exe`로 바꾼 뒤 서비스 재시작 (PC-A와 같은 값) |
| 8 | Secret | juproject user-secrets 없음 | user-secrets 2개 등록, `setenv.bat`에 `JU_JWT_SECRET` (JU-1 적용 전에 필요) |
| 9 | 검증 | — | `ai_dev_env_check.ps1` (PC-A의 `dev_env_baseline.json`을 PC-B workspace에 복사한 뒤 실행) → FAIL 0 |
| 10 | 유지 | MariaDB 데이터 `Program Files\MariaDB 10.6\data` | 그대로 둔다 (허용) |

## [git diff --stat]

두 저장소 모두 새 브랜치 `chore/dev-env-standard`(main 기준)에서 수정했다. commit하지 않았다.

```
juprovider  AI_COLLABORATION.md | 34 ++++++++++++++++++++--------------   (1 file, +20 −14)
juproject   AI_COLLABORATION.md | 34 ++++++++++++++++++++--------------   (1 file, +20 −14)
```

적용하지 않은 변경안 (승인 대기)
- `proposal_juprovider_Jenkinsfile_JU_TOMCAT_HOME.patch` — Jenkinsfile 1 file, +17 −6
- `proposal_juprovider_global_json.patch`, `proposal_juproject_global_json.patch` — 각 신규 1 file

참고: 어제의 JU-0/JU-1/SYS 미커밋 변경은 각 저장소 `stash@{0}`에 그대로 있다. 이 브랜치와는 별개다.

앞선 조사 결과를 기준으로 방향을 확정합니다.

현재 사용 중인 PC-A DESKTOP-CE5BGKK를 JuProvider/JuProject의 기준 개발 PC로 삼습니다.

오늘은 PC-A의 현재 정상 개발환경을 기준으로 표준 문서를 확정하고, 프로젝트가 PC-A의 실제 절대경로에 종속되지 않도록 정리합니다.

저녁에 PC-B를 이 기준에 맞출 예정입니다.

중요:
PC-A에서 정상 동작하는 Tool을 C:\MyData\MyDev\tools 등으로 이동하거나 재설치하지 않습니다.

현재 정상 설치 위치를 기준값으로 사용하되 프로젝트/스크립트에서는 환경변수 또는 상대경로를 사용합니다.

[1. PC-A 기준 환경 확정]

현재 실제 값을 다시 확인해서 다음을 PC-A 기준값으로 확정해 주세요.

Workspace:
C:\MyData\MyDev\workspace

JDK 21:
현재 실제 C:\MyData\MyDev\jdk\jdk-21.0.1

Maven 3.9.11:
현재 실제 C:\MyData\MyDev\maven\apache-maven-3.9.11

vcpkg:
현재 실제 C:\MyData\MyTool\vcpkg

Tomcat 10.1.52:
현재 실제 C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52

.NET:
C:\Program Files\dotnet

Node:
C:\Program Files\nodejs

CMake:
C:\Program Files\CMake

MariaDB:
C:\Program Files\MariaDB 10.6

Git:
C:\Program Files\Git

각 항목은 실제 명령으로 경로와 버전을 다시 확인해 주세요.

[2. PC-A 기준 문서]

workspace에 다음 문서를 작성해 주세요.

DEV_ENVIRONMENT_STANDARD.md

이 문서를 앞으로 두 개발 PC의 개발환경 기준 문서로 사용합니다.

최소 포함 내용:

기준 PC

Workspace

Tool 이름

기준 버전

PC-A 실제 설치 위치

프로젝트에서 사용하는 환경변수

설치형/Portable 구분

Jenkins에서 사용하는 방법

Local cache 위치

Local secret/config 위치

확인 명령

새 PC 설정 절차

검증 절차

중요:
실제 password, JWT secret, DB password 등은 기록하지 않습니다.

[3. 개발자 환경변수]

PC-A 개발자 User 환경변수 후보를 다음처럼 정리합니다.

JU_WORKSPACE=C:\MyData\MyDev\workspace
JAVA_HOME=C:\MyData\MyDev\jdk\jdk-21.0.1
MAVEN_HOME=C:\MyData\MyDev\maven\apache-maven-3.9.11
VCPKG_ROOT=C:\MyData\MyTool\vcpkg
JU_TOMCAT_HOME=C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52

현재 환경변수와 PATH를 조사해서 충돌이 없으면 적용 가능한 형태로 정리해 주세요.

관리자 권한이 필요한 Machine 변수로 무조건 바꾸지 않습니다.

개발자 환경은 User 변수를 기본으로 합니다.

Jenkins LocalSystem 환경은 별도로 유지합니다.

[4. 프로젝트의 로컬 경로 독립화]

두 저장소의 Git 추적 파일을 다시 확인하고 다음 원칙으로 정리합니다.

소스/빌드 설정에서:

C:\MyData\...

C:\MyTool\...

C:\Users\...

같은 개발 PC 절대경로를 직접 사용하지 않습니다.

우선 조사에서 발견된 JuProvider Jenkinsfile의 Tomcat 절대경로는:

JU_TOMCAT_HOME

같은 환경 설정으로 분리할 수 있도록 변경안을 준비해 주세요.

단, Jenkins 설정까지 즉시 변경해서 현재 빌드를 깨뜨리지 마세요.

Jenkinsfile 수정이 필요하면 변경 내용과 Jenkins 쪽에 필요한 설정을 함께 보고한 뒤 적용합니다.

AI_COLLABORATION.md의 경로 표는 실행 코드가 아니므로 PC-A 기준 문서로 갱신할 수 있습니다.

[5. .NET SDK 고정]

현재:

PC-A = .NET SDK 10.0.402
PC-B = 10.0.401

이고 global.json이 없습니다.

두 저장소에 .NET 10 feature band를 고정하는 global.json을 두는 것이 적합한지 확인해 주세요.

권장 방향:

SDK 기준 10.0.400
rollForward: latestPatch

이렇게 하면 10.0.401/402와 같은 patch 차이는 허용하면서 다른 feature band 사용은 방지하는 것이 목적입니다.

현재 Visual Studio 2026 / Jenkins / dotnet build와 충돌이 없는지 먼저 확인하고, 적합하면 변경 후보로 보고해 주세요.

사용자 승인 전 commit/push하지 않습니다.

[6. Node/CMake]

Node와 CMake는 PC-A의 공식 설치 경로를 유지합니다.

Node:
C:\Program Files\nodejs

CMake:
C:\Program Files\CMake

MyDev\tools로 이동하지 않습니다.

JuProvider Vue Maven build는 frontend-maven-plugin이 자체 Node를 사용하므로 PC 설치 Node와 분리되어 있다는 점도 문서에 기록합니다.

[7. MariaDB]

MariaDB 프로그램 버전은 기준 PC와 맞추되 데이터 디렉터리 위치는 표준화하지 않습니다.

PC-A와 PC-B의 MariaDB data directory가 달라도 허용합니다.

DB data directory는 Local Runtime Configuration으로 취급합니다.

DB 자체의 schema/baseline/migration이 동일한지가 중요합니다.

[8. Cache]

Maven/NuGet/npm cache는 소스 또는 개발환경의 필수 경로로 취급하지 않습니다.

cache가 없어도 dependency restore로 다시 생성 가능해야 합니다.

이번 PC-A 표준화에서 기존 cache를 이동하지 않습니다.

Jenkins cache와 개발자 cache도 공유하지 않습니다.

향후 별도 cache 경로가 필요할 때만 다시 검토합니다.

[9. Secret / Local Config]

다음은 Git에 저장하지 않습니다.

JU_DB_PASSWORD

JU_JWT_SECRET

Client Key

JuProject ConnectionStrings

기타 credential

문서에는 설정 위치와 존재 여부 확인 방법만 기록합니다.

JuProvider Tomcat:
setenv.bat

JuProject:
.NET user-secrets

등 현재 방식도 함께 기록합니다.

[10. Environment Check]

앞서 만든 ai_dev_env_collect.ps1을 바탕으로 PC-A 기준 환경을 검증하는 스크립트를 준비해 주세요.

예:

ai_dev_env_check.ps1

목적은 Tool 설치가 아니라 검증입니다.

검사 결과:

Tool

Expected Version

Actual Version

Expected Path/환경변수

Actual Path

PASS/WARN/FAIL

을 보여주세요.

secret은 값이 아니라 SET/MISSING만 출력합니다.

이 스크립트는 workspace의 저장소 밖에 두어도 됩니다.

[11. 이번에 하지 않을 것]

JU/SYS 기능 추가

DB schema 변경

migration 적용

Tool 이동

Tool 삭제

Tool 업그레이드

MariaDB data 이동

Jenkins Job 구조 변경

commit/push

하지 않습니다.

[12. 완료 결과]

다음만 보고해 주세요.

[PC-A 확정 Toolchain]
[환경변수]
[PATH 충돌 여부]
[.NET global.json 검토]
[프로젝트 절대경로 의존]
[Jenkins와 Local 환경 분리]
[Secret/Local Config]
[DEV_ENVIRONMENT_STANDARD.md]
[Environment Check 결과]
[저녁 PC-B에서 해야 할 작업]
[git diff --stat]

이 결과를 ChatGPT가 검토한 뒤 PC-A를 최종 기준으로 확정합니다.

그 다음 저녁에 PC-B에서 DEV_ENVIRONMENT_STANDARD.md와 Environment Check를 기준으로 PC-B만 PC-A에 맞춥니다.

중요:
PC-A를 PC-B와 절충해서 제3의 새로운 환경으로 만들지 않습니다.
현재 정상 동작하는 PC-A를 기준으로 삼습니다.
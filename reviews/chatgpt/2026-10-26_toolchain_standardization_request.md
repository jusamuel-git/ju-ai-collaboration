앞서 요청한 Local Build 표준화 작업을 잠시 보류하고, 먼저 두 개발 PC에서 동일한 개발환경을 재현할 수 있도록 Toolchain/경로 표준화를 진행합니다.

아직 JU/SYS 기능 개발은 하지 않습니다.

[목표]

두 개발 PC에서:

Repository 위치

JDK

Maven

Node/npm

CMake

vcpkg

.NET SDK

MariaDB

Git

Jenkins

의 실제 설치 위치와 버전을 비교하고 가능한 범위에서 동일하게 맞춥니다.

단, 소스 코드가 절대경로에 의존하도록 만들지는 않습니다.

[1. 표준 Root 후보]

다음을 표준 개발 Root로 사용합니다.

JU_DEV_ROOT=C:\MyData\MyDev

Workspace:

C:\MyData\MyDev\workspace

Repositories:

C:\MyData\MyDev\workspace\juprovider
C:\MyData\MyDev\workspace\juproject

Portable Tool 후보:

C:\MyData\MyDev\tools\jdk\jdk-21
C:\MyData\MyDev\tools\maven\apache-maven-3.9.11
C:\MyData\MyDev\tools\node
C:\MyData\MyDev\tools\cmake
C:\MyData\MyDev\tools\vcpkg

Local Cache 후보:

C:\MyData\MyDev\cache\maven
C:\MyData\MyDev\cache\nuget
C:\MyData\MyDev\cache\npm

Local Config 후보:

C:\MyData\MyDev\config\juprovider
C:\MyData\MyDev\config\juproject

설치형 프로그램은 무조건 위 경로로 옮기지 않습니다.

예:

C:\Program Files\MariaDB 10.6
C:\Program Files\dotnet
C:\Program Files\Git
C:\Program Files\Jenkins
Visual Studio
VS Code

는 공식 설치 경로를 유지해도 됩니다.

[2. 먼저 조사]

현재 PC에서 실제로 다음을 조사해서 표로 만들어 주세요.

항목 / 실제 경로 / 버전 / 표준 후보와 동일 여부 / PATH 등록 여부 / 권한 문제 가능성

대상:

Git

Java/JDK

Maven

.NET SDK

Node

npm

CMake

vcpkg

MariaDB

Jenkins

Visual Studio

VS Code

명령으로 확인 가능한 것은 실제 명령 결과를 사용합니다.

예:

where git
where java
where mvn
where dotnet
where node
where npm
where cmake

java -version
mvn -version
dotnet --info
node --version
npm --version
cmake --version
git --version

[3. 환경변수 후보]

두 PC에서 가능하면 다음 공통 환경변수를 사용합니다.

JU_DEV_ROOT=C:\MyData\MyDev
JU_WORKSPACE=%JU_DEV_ROOT%\workspace
JU_TOOLS=%JU_DEV_ROOT%\tools
JU_CACHE=%JU_DEV_ROOT%\cache

JAVA_HOME=%JU_TOOLS%\jdk\jdk-21
MAVEN_HOME=%JU_TOOLS%\maven\apache-maven-3.9.11
VCPKG_ROOT=%JU_TOOLS%\vcpkg

PATH에서는 가능하면 환경변수를 사용합니다.

단, 조사 없이 기존 환경변수를 바로 수정하지 마세요.

현재 값과 충돌 여부를 먼저 보고해 주세요.

[4. Cache]

현재 각 PC에서 다음 실제 경로를 확인합니다.

Maven local repository
NuGet global-packages
npm cache

사용자 프로필 경로에 묶여 있는지 확인합니다.

Local 개발용 cache를

C:\MyData\MyDev\cache

아래로 통일하는 것이 안전한지 검토해 주세요.

주의:
Jenkins 서비스와 Local 개발자가 동일 cache 디렉터리를 동시에 공유하는 구조는 만들지 않습니다.

Jenkins는 동일 Tool 버전/빌드 절차를 사용하되 cache는 Jenkins 실행계정/전용 영역을 유지할 수 있습니다.

[5. 권한 검사]

특히 다음 위치에 현재 로그인 사용자가 읽기/쓰기 가능한지 확인합니다.

C:\MyData\MyDev
workspace
tools
cache
config

Program Files 아래 Tool은 실행 권한만 확인합니다.

Jenkins 서비스 계정이 사용하는 경로와 Local 사용자 경로를 구분해서 조사합니다.

[6. 절대경로 검색]

juprovider와 juproject의 추적 소스에서 다음과 같은 개발 PC 종속 절대경로가 남아 있는지 검색해 주세요.

C:\MyData
C:\Users
Program Files
jdk 경로
maven 경로
vcpkg 경로
cmake 경로

발견해도 이번 단계에서 임의 수정하지 말고:

파일
라인
현재 값
용도
환경변수/상대경로로 변경 가능한지

를 보고해 주세요.

Build output, node_modules, target, bin, obj 등은 검색 대상에서 제외합니다.

[7. 아직 하지 않을 것]

JU/SYS 기능 추가

DB 변경

migration 적용

Jenkins Job 변경

commit/push

Tool 버전 업그레이드

기존 설치 Tool 삭제

를 하지 않습니다.

[8. 결과 문서]

workspace에 다음 문서를 만들어 주세요.

ai_dev_environment_status_2026-10-26.md

내용:

[현재 PC Tool 경로/버전]
[표준 경로와 차이]
[환경변수]
[PATH]
[Cache]
[권한]
[Jenkins 서비스 계정 환경]
[소스의 절대경로 의존]
[두 PC를 동일하게 만들기 위해 필요한 변경]
[사용자 결정 필요]

이 조사 결과를 ChatGPT에 전달합니다.

그 결과를 보고 표준 경로를 최종 확정한 뒤:

Tool/환경 경로 정리

Environment Check

Dependency Restore

Local Build

Local Verify

순서로 진행합니다.

중요:
이번 단계에서는 조사와 보고가 우선이며, 기존 Tool을 이동/삭제/재설치하지 마세요.
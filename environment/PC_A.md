# PC-A `DESKTOP-CE5BGKK` (기준 개발 PC)

- 실측: 2026-10-26 09:03 `tools/ai_dev_env_check.ps1 -Baseline` → **FAIL 0** (기준값: [pc_a_baseline.json](pc_a_baseline.json))
- 로컬 빌드: 2026-10-26 09:10 `tools/ai_local_build.ps1` → **5개 대상 PASS** (`main`)

## Tool
| Tool | 버전 | 위치 |
|---|---|---|
| JDK | 21.0.1 | `C:\MyData\MyDev\jdk\jdk-21.0.1` |
| Maven | 3.9.11 | `C:\MyData\MyDev\maven\apache-maven-3.9.11` |
| Tomcat | 10.1.52 | `C:\MyData\MyTool\tomcat\apache-tomcat-10.1.52` |
| vcpkg | 2026-07-27 | `C:\MyData\MyTool\vcpkg` |
| .NET SDK | 10.0.402 (+9.0.317) | `C:\Program Files\dotnet` |
| Node / npm | 24.14.0 / 11.9.0 | `C:\Program Files\nodejs` |
| CMake | 4.4.3 | `C:\Program Files\CMake` |
| Git | 2.36.1 | `C:\Program Files\Git` |
| MariaDB | 10.6.16 | `C:\Program Files\MariaDB 10.6` (데이터 `C:\MyData\MyTool\MyDB\mariadb`) |
| Redis | 3.0.504 | `C:\Program Files\Redis` |
| Jenkins | 2.580.1 (LocalSystem) | `C:\Program Files\Jenkins` |
| Visual Studio | 18.11 (2026 Community) | `C:\Program Files\Microsoft Visual Studio\18\Community` |
| VS Code | 1.143.1 | `%LOCALAPPDATA%\Programs\Microsoft VS Code` |

## 환경변수
| 변수 | 상태 |
|---|---|
| `JAVA_HOME` | Machine = JDK 21 경로 |
| `VCPKG_ROOT` | Machine = vcpkg 경로 |
| `JU_WORKSPACE`, `MAVEN_HOME`, `JU_TOMCAT_HOME` | 없음 (빌드에는 불필요. 설정은 보류) |

PATH: `java`, `mvn`, `node`, `dotnet` 모두 기준 위치가 첫 번째 (JDK 4개 중 21 우선)

## Jenkins
- 도구 `JDK21`, `Maven3` = 위 MyDev 경로, Git = `git.exe`
- 서비스 실행 JDK: `jenkins.xml` `<executable>` = JDK 21 경로
- 전역 환경변수 없음 (`JU_TOMCAT_HOME` 미설정)
- 작업 `juprovider-ai`, `juproject-ai` (`*/main`). 옛 작업 폴더 `workspace\JuProvider-Backend` 남아 있음 (정리 후보)

## Secret (값은 기록하지 않음)
| 항목 | 상태 |
|---|---|
| `setenv.bat` `JU_DB_URL/USER/PASSWORD` | SET |
| `setenv.bat` `JU_JWT_SECRET` | MISSING (JU-1 적용 전에 필요, REQUIRED) |
| juproject user-secrets `ConnectionStrings:Default`, `Jwt:SigningKey` | SET |

## Claude의 이 PC 접근
- 파일 읽기·쓰기: workspace, MyDev, MyTool, Jenkins, dotnet, nodejs, MariaDB, Redis, CMake, `.m2`, UserSecrets(존재 확인만)
- 명령 실행: 불가. 컴퓨터 사용으로 탐색기·PowerShell 클릭만 가능 → `.cmd` 더블클릭으로 스크립트 실행

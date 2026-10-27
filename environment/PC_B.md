# PC-B 노트북 `JUSAMUEL` — PC-A 기준에 맞출 항목

- 상태 기준: 2026-10-27 22:30 재측정 (`ai_dev_env_check` PASS 22 / WARN 9 / FAIL 1, 상세: [PC-B 검증](../reviews/claude/2026-10-27_pcb-protocol-ref_verify.md))
- **10/28 저녁 정리 예정** (사용자 결정): 10/25 이전 미커밋 변경 삭제 후 origin 기준 정렬, 아래 표 항목 정렬, Desktop `template.accdb` 배치
- 원칙: PC-A를 바꾸지 않고 PC-B만 맞춘다. 맞춘 뒤 `tools/ai_dev_env_check.ps1`(PC-A의 `pc_a_baseline.json`을 workspace에 `dev_env_baseline.json`으로 복사) → FAIL 0, `tools/ai_local_build.ps1` → 모두 PASS

| # | 항목 | 현재 PC-B | 맞출 값 (PC-A) |
|---|---|---|---|
| 1 | JDK | `C:\MyData\MyTool\jdk\jdk-21.0.1` | `C:\MyData\MyDev\jdk\jdk-21.0.1` (복사) |
| 2 | Maven | `C:\MyData\MyTool\maven\apache-maven-3.9.11` | `C:\MyData\MyDev\maven\apache-maven-3.9.11` |
| 3 | Maven settings | `MyTool\maven\settings.xml` (저장소 `MyTool\maven\repository`) | 기본값 (`%USERPROFILE%\.m2`), cache는 다시 받음 |
| 4 | vcpkg | `C:\MyData\MyTool\vcpkg-master` | `C:\MyData\MyTool\vcpkg` |
| 5 | .NET SDK | 10.0.401 | 10.0.4xx 허용 |
| 6 | 환경변수 | 미확인 | `JAVA_HOME`, `VCPKG_ROOT` (PC-A는 Machine 범위) |
| 7 | Jenkins 도구 | `JDK21`/`Maven3` = MyTool 경로 | MyDev 경로로 변경 |
| 8 | Jenkins 서비스 JDK | `jenkins.xml` `<executable>` 미확인 | JDK 21 MyDev 경로 → 서비스 재시작 |
| 9 | Secret | juproject user-secrets 없음 | `ConnectionStrings:Default`, `Jwt:SigningKey` SET (사용자 입력) |
| 10 | MariaDB 데이터 | `C:\Program Files\MariaDB 10.6\data` | 그대로 (허용) |
| 11 | workspace 정리 | `ai_changes`(10/25 zip/patch), `ai_sys_migration_add.log`(migration 생성 실패 로그) 등 | 재설계 확정 후 `_archive`로 이동 |

옛 폴더(`MyTool\jdk`, `MyTool\maven`, `vcpkg-master`)는 확인 후 사용자가 정리한다 (삭제는 사용자 결정).
| 12 | Desktop template | `desktop\app\config\template.accdb` 없음 → Client 실행 실패 | PC-A 파일 복사 (`desktop/app/`은 .gitignore) |
| 13 | 작업 폴더 Git | juprovider `feature/ju-0-install`(미커밋 40), juproject `feature/sys-core-schema`(미커밋 36) | 미커밋 삭제 → main 최신 + 작업 브랜치 (사용자 결정 10/28) |
| 14 | 검증 worktree | `C:\MyData\MyDev\workspace_verify` (feature/protocol-ref, juproject 68d610b) | 유지 또는 `git worktree remove` |

# 로컬 DB 마이그레이션 개선 결과 (2026-11-24, PC-B)

## 결과: PASS — DROP 재생성 제거, SCHEMA_VERSION 순차 마이그레이션·백업·실패 복구·지원하지 않는 스키마 오류

| 항목 | 값 |
|---|---|
| 브랜치 | `feature/local-db-migration` @ `69433f9` (← 템플릿 `4409ade`), origin 동일 |
| main | `4915759` 그대로. 서버 DB·WAR·Tomcat 서비스 변경 없음 |
| 템플릿 | 바뀌지 않음 (`FE2B566F8D3281E2`, 스키마 v1 그대로) |
| C6c | 11/24 21:11 사용자 결정: 장비 연결 테스트는 된 것으로 보고 잔여 실장비 검증은 진행하지 않음 (C6c 문서에 미검증으로 표시) |

## 설계
초기화 순서 (`LocalDatabase.InitializeAsync`)
1. DB 없음 → 표준 템플릿 복사 (덮어쓰기 없음, 기존 동작).
2. `LOCAL_SCHEMA_INFO.SCHEMA_VERSION` 읽기 (테이블·행 없으면 **v0** = 표준 이전 DB).
3. 앱보다 높음 → `LocalDatabaseSchemaException`, DB 건드리지 않음.
4. 낮음 → 마이그레이션 경로 계산 (n→n+1 연결, 빠지면 `LocalDatabaseSchemaException`, 백업 전이라 변경 없음) → `data\backup\juprovider_v{n}_{시각}.accdb` 백업 → 단계 적용 + 단계마다 버전 기록 → 실패하면 **백업으로 파일 복구** 후 `LocalDatabaseMigrationException`(FromVersion·FailedStep·BackupPath·Restored), 백업 파일은 남김.
5. 현재 버전인데 v1 필수 테이블·컬럼이 없으면 `LocalDatabaseSchemaException` — **지우거나 다시 만들지 않음**.

마이그레이션 목록 (`LocalSchema.Migrations`)
- **v0 → v1 (기준)**: 없는 테이블 생성 / 키 컬럼이 같으면 없는 컬럼만 `ALTER ADD`(행 보존, JU-1c offline 컬럼 추가도 여기에 포함) / 키가 다른 이전 구성(예: 이전 template 의 LOGIN_ID 키 LOCAL_USER)은 `{표}_LEGACY_{시각}` 으로 **전체 복사 → 행 수 일치 확인 후** 원래 표를 지우고 새로 생성. (코드에 남은 DROP TABLE 은 이 한 곳뿐이며 복사·확인 뒤에만 실행)
- 다음 버전 추가 방법: `LocalSchema` 에 (n→n+1) 추가 → `SchemaVersion` 올림 → 템플릿 재생성 (`Repo_Template_Is_Schema_Only_And_Matches_Code` 가 누락을 잡음).

## diff --stat (69433f9)
```
desktop/juprovider.client/Program.cs                        |   5 +    (마이그레이션 백업 경로 로그)
desktop/lib/juprovider.lib.data/Local/LocalDatabase.cs      | 598 +---- (테이블별 DROP 재생성 제거, 버전 확인·경로·백업·복구)
desktop/lib/juprovider.lib.data/Local/LocalSchema.cs        | 222 +    (신규: 표 정의·마이그레이션·예외·검증)
desktop/tests/juprovider.tests.protocol/LocalMigrationTests.cs | 232 + (신규)
desktop/tests/juprovider.tests.protocol/LocalTemplateTests.cs  |   2 -  (상위 버전 예외 형식)
5 files changed, 681 insertions(+), 378 deletions(-)
```

## 빌드·테스트
| 단계 | 결과 |
|---|---|
| 빌드 5종 (8단계) | 전부 PASS |
| 서버 테스트 | 62/62 |
| Desktop 테스트 | **217/217** (212 + LocalMigrationTests 5) |
| LocalMigration·LocalTemplate 상세 | 12/12 |

LocalMigrationTests 5건 (실제 ACE): v0 이전 DB(LOCAL_USER 키 다름·LOCAL_DEVICE 일부 컬럼·LOCAL_SYNC_STATE 없음) → v1, 행·값 보존, LEGACY 표 2행, 백업은 원본 그대로, 재실행 시 백업 추가 없음 / JU-1c 이전 LOCAL_USER 에 offline 컬럼 추가(행 보존) / v1→v2→v3 순서 적용·백업 1개 / v2→v3 실패 → v1 로 복구·행 보존·백업 남음·현재 앱 정상 / 경로 없음·v1 구조 불일치 → 오류, 변경·백업 없음.

## 실제 앱 (PC-B)
| 시험 | 결과 |
|---|---|
| 기존 설치 (사용자 DB v1) 재실행 | `schema v1`, 마이그레이션 없음. LOCAL_DEVICE 2·LOCAL_USER 1 그대로, 생성 시각 11/23 21:41 그대로 |
| 신규 설치 (app 복사본, data 없음) | 템플릿 복사 → `schema v1`, 빈 DB, backup 폴더 없음 |
| v0 DB (사용자 DB **복사본**에서 LOCAL_SCHEMA_INFO 삭제) | `마이그레이션 완료, 이전 DB 백업 …\data\backup\juprovider_v0_….accdb`, 이후 LOCAL_DEVICE 2·LOCAL_USER 1·SCHEMA_VERSION 1, 백업 안의 원본도 LOCAL_DEVICE 2 |
| 상위 버전 (복사본 SCHEMA_VERSION=9) | `[LOCAL DB ERROR] … version 9 is newer than this application (1)`, 데이터 그대로 |
임시 복사본은 시험 후 삭제. 사용자 DB 는 읽기와 앱 정상 실행만.

## 남은 문제 (보고만)
1. 백업 파일 보관 정책 없음 (`data\backup` 에 계속 쌓임) — 개수·기간 제한 결정 필요.
2. 마이그레이션 중 다른 프로세스가 DB 를 열고 있으면 백업·복구가 실패할 수 있음 (Client 시작 시 1회 실행이라 보통 없음). 복구 실패 시 예외 메시지에 백업 경로를 남김.
3. `_LEGACY_` 표 정리(삭제) 시점·방법 미정.
4. Client 는 마이그레이션 실패·상위 버전 시 기존처럼 "Local DB 초기화 실패" 메시지 후 종료 — 사용자 안내 문구 개선은 C6d 이후 검토.
5. C6c 실장비 잔여(CH4, 케이블 분리·복구, 앱 가상 장치·오프라인 캐시)는 사용자 결정으로 미검증 유지.

도구: `tools/ai_mig.ps1` (+ run cmd).

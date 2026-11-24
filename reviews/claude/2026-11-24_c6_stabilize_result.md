# C6 안정화 결과 (2026-11-24, PC-B)

## 결과: PASS — 백업 정책·LEGACY 표 이력·Client 오류 안내 구현, 사용자 데이터 보존 확인

| 항목 | 값 |
|---|---|
| 브랜치 | `feature/c6-stabilize` @ `f2e6d91` (← 마이그레이션 `69433f9`), origin 동일 |
| main | `4915759` 그대로. 서버 DB·WAR·Tomcat 서비스 변경 없음 |
| 템플릿 | 바뀌지 않음 (`FE2B566F8D3281E2`, 스키마 v1). DB 스키마 변경 없음 |
| C6c | 잔여 실장비는 미검증 유지 (C6d 차단 안 함) |

## 1. 로컬 DB 백업 정책 (`LocalBackupPolicy`)
- 정리 시점: **정상 마이그레이션 직후에만**. 실패·마이그레이션 없는 실행에서는 정리하지 않음.
- 대상: `data\backup` 바로 아래 정상 백업 `juprovider_v{n}_{yyyyMMdd_HHmmss_fff}.accdb` (이름의 시각 기준).
- 규칙: **최신 1개는 항상 유지**. 나머지 중 30일 지난 것, 최신 10개를 넘는 것 삭제.
- 보호(자동 삭제 안 함): `backup\incident\` (마이그레이션 실패 백업, `_restored`/`_restore-failed` 이름), `{파일}.keep` 표시 파일(incident 로 못 옮긴 경우), 이름 형식이 다른 파일(사용자 복사본 등), 다른 DB 이름.
- 로그: `[LOCAL DB BACKUP] 정리 {폴더}: 유지 n, 삭제 n [파일], 삭제 실패 n [파일: 이유], 보호 n`. 삭제 실패는 다음 정리 때 다시 대상.

## 2. LEGACY 표 관리 (`LocalLegacyTables`)
- 자동 DROP 없음 (삭제 기능 자체가 없음).
- 이력: v0→v1 마이그레이션이 `{표}_LEGACY_{시각}` 을 만들 때 `LOCAL_SCHEMA_INFO` 에 `LEGACY:{표}` 행 기록 — `source, rows(원본), copied(복사), verified(Y/N), at, by(마이그레이션)`. 기존 key/value 표를 써서 **스키마 변경 없음**.
- 상태: `verified`(복사 검증·현재 행 수 같음) / `rows-changed`(이후 바뀜) / `unverified`(복사 행 수 불일치) / `no-record`(이력 없는 표).
- Client 시작 시 `[LOCAL DB LEGACY] {표} 원본= 행= 상태= 생성= 원본행= 복사행=` 로그.
- **정리 절차 설계 (향후, 사용자 승인 후 — 이번 단계 미구현·미실행)**
  1. 목록 확인: LEGACY 표·상태·행 수를 화면/로그로 제시 (상태 `verified` 만 정리 후보, 그 외는 조사 대상).
  2. 사용자 승인: 표 이름 + 현재 행 수를 그대로 입력·확인 (다르면 거부).
  3. 정리 직전 DB 전체 백업 (`backup\incident\…_legacy-cleanup.accdb`, 자동 정리 대상 아님).
  4. 필요하면 LEGACY 행을 CSV 로 내보낸 뒤 해당 표만 DROP, `LOCAL_SCHEMA_INFO` 의 `LEGACY:{표}` 값에 `dropped=시각;approvedBy=` 기록 (이력 유지).
  5. 실패 시 3번 백업으로 복구. 이번 단계에서 실제 사용자 DB 의 LEGACY 표는 없고 삭제하지 않음.

## 3. Client 오류 안내 (`LocalDbErrorGuide`)
| 상황 | 로그 태그 | 안내 요지 |
|---|---|---|
| 상위 스키마 버전 | `[LOCAL DB ERROR:SCHEMA_NEWER]` | DB v{n} > 앱 v{m}, 최신 Client 로 업데이트, DB 변경 없음 |
| 경로 없음·구조 불일치 | `SCHEMA_UNSUPPORTED` | DB 변경 없음, data 폴더 지우지 말고 로그 전달 |
| 마이그레이션 실패·복구 성공 | `MIGRATION_RESTORED` | 이전 상태로 복구, 데이터 그대로, 조사용 백업 경로 (경고 아이콘) |
| 복구 실패 | `MIGRATION_RESTORE_FAILED` | 백업 경로, data·백업 지우거나 옮기지 말고 다시 실행하지 말고 관리자 연락 |
| 템플릿 없음 | `TEMPLATE_MISSING` | 재설치 |
| DB 파일 접근(잠김·권한·OLE DB 오류) | `FILE_ACCESS` | 다른 JuProvider/Access 창 닫기·권한 확인, DB 변경 없음 |
| 기타 | `UNKNOWN` | 로그 전달 |
메시지 창 제목에 상황, 본문 끝에 오류 코드. 로그는 `[LOCAL DB ERROR:{코드}] {예외 형식}: {메시지}`.

## diff --stat (f2e6d91)
```
desktop/juprovider.client/Program.cs                         |  29 ++-  (안내 창·로그 코드, 백업 정리·LEGACY 로그)
desktop/juprovider.client/Services/LocalDbErrorGuide.cs      |  70 +    (신규)
desktop/lib/juprovider.lib.data/Local/LocalBackupPolicy.cs   | 139 +    (신규)
desktop/lib/juprovider.lib.data/Local/LocalDatabase.cs       |  62 +-   (정상 후 정리, 실패 백업 incident 이동, 예외 종류)
desktop/lib/juprovider.lib.data/Local/LocalLegacyTables.cs   | 115 +    (신규)
desktop/lib/juprovider.lib.data/Local/LocalSchema.cs         |  39 +-   (예외 종류·버전, LEGACY 이력 기록)
desktop/tests/juprovider.tests.protocol/LocalStabilizeTests.cs | 245 + (신규)
7 files changed, 683 insertions(+), 16 deletions(-)
```

## 4. 검증
| 단계 | 결과 |
|---|---|
| 빌드 5종 (8단계) | 전부 PASS |
| 서버 테스트 | 62/62 |
| Desktop 테스트 | **223/223** (217 + LocalStabilizeTests 6) |
| LocalStabilize·Migration·Template 상세 | 18/18 |

LocalStabilizeTests 6건: 정책(14개 → 최신 10 유지·4 삭제, 보호 4 그대로) / 최신 1개는 40일 지나도 유지·잠긴 파일 삭제 실패 보고 / 실제 마이그레이션: 실패 백업 incident 이동·정리 안 함 → 정상 마이그레이션 후 12→10, incident 보존, 재실행 시 정리 없음 / 복구 실패 재현(백업 파일 사라짐) → `Restored=false`·안내 `MIGRATION_RESTORE_FAILED` / LEGACY 이력·상태(verified → rows-changed, no-record)·재실행해도 삭제 없음 / 안내 코드 전 종류 + 실제 파일 잠금(`FILE_ACCESS`, 파일 크기 그대로)·실제 상위 버전.

실제 앱 (PC-B):
| 시험 | 결과 |
|---|---|
| 기존 설치(사용자 DB v1) | `schema v1`, 마이그레이션·정리 없음, LOCAL_DEVICE 2·LOCAL_USER 1, 생성 시각 11/23 21:41 그대로 |
| 신규 설치 | `schema v1`, 빈 DB, backup 폴더 없음 |
| v0 업그레이드 (사용자 DB **복사본**: 스키마 정보 삭제 + 이전 구성 LOCAL_USER 1행 + 가짜 정상 백업 11개) | 백업 생성, `정리: 유지 10, 삭제 2 [11·10일 전 파일]`, `LOCAL_USER_LEGACY_… 원본=LOCAL_USER 행=1 상태=verified`, LOCAL_DEVICE 2 보존 |
| 재실행 | 마이그레이션·정리 없음, LEGACY 그대로 |
| 상위 버전(복사본 v9) | `[LOCAL DB ERROR:SCHEMA_NEWER]`, 데이터 그대로 |
| 파일 잠금(복사본) | `[LOCAL DB ERROR:FILE_ACCESS] OleDbException: … file already in use`, 해제 후 데이터 그대로 |
마이그레이션 실패·복구(성공/실패)는 앱에서 일으킬 방법이 없어 자동 테스트로만 확인. 안내 창 화면은 로그 코드로 확인(창 캡처 없음).

## 남은 문제 (보고만)
1. 백업 정리는 마이그레이션이 있을 때만 일어남 → 스키마가 안 바뀌면 백업이 늘지도 줄지도 않음(정상). incident 백업은 수동 정리 필요.
2. LEGACY 정리 기능은 설계만 (승인 후 구현).
3. 안내 문구는 개발자 초안 — 운영 문구 검토 필요.
4. C6c 실장비 잔여 미검증 유지.

도구: `tools/ai_stab.ps1` (+ run cmd).

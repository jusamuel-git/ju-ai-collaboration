# 로컬 DB 표준 템플릿 결과 (2026-11-24, PC-B)

## 결과: PASS — 스키마 전용 표준 템플릿을 Git 관리, 빌드 시 app\config 로 복사, 사용자 DB 보존 확인

| 항목 | 값 |
|---|---|
| 브랜치 | `feature/local-db-template` @ `4409ade` (← C6c `01d1775`), origin 동일 |
| main | `4915759` 그대로. 서버 DB·DEV_CONFIG·WAR·Tomcat 서비스 변경 없음 |
| 미커밋 잔여 | `juprovider.frontvue/package-lock.json` (이전부터, 범위 밖) |

## 조사 (현재 초기화 로직)
- `LocalDatabase.InitializeAsync`: `app\data\juprovider.accdb` 가 없으면 `app\config\template.accdb` 를 **복사만** 하고(`File.Copy` 덮어쓰기 없음), 테이블은 코드가 확인·생성.
- 테이블 3개(코드가 원본): LOCAL_USER(PK USER_ID), LOCAL_DEVICE(PK DEV_CD), LOCAL_SYNC_STATE(PK ENTITY_TYPE+ENTITY_KEY). 컬럼이 다르면 LOCAL_USER·LOCAL_DEVICE 는 DROP 후 재생성(개발 단계 기존 동작, 바꾸지 않음). LOCAL_USER 는 offline 컬럼 2개를 ALTER 로 추가.
- 인덱스: 모든 조회가 PK(WHERE USER_ID=?, DEV_CD=?, ORDER BY DEV_CD) → **추가 인덱스 불필요**.
- 스키마 버전: **없었음**. 템플릿 원본: Git 에 없음(`desktop/app/` 무시), PC-B 에는 11/23 임시 빈 ACCDB 뿐.

## 변경 (diff --stat 4409ade)
```
.gitattributes                                       |   2 +   (*.accdb binary)
desktop/juprovider.client/Program.cs                 |   7 +-  (로그에 schema v 표시)
desktop/juprovider.client/juprovider.client.csproj   |   5 +   (resources\template.accdb → app\config, PreserveNewest)
desktop/lib/juprovider.lib.data/Local/LocalDatabase.cs | 303 +++-
desktop/resources/template.accdb                     | Bin 229376 B (신규)
desktop/tests/juprovider.tests.protocol/LocalTemplateTests.cs | 224 + (신규)
6 files changed, 527 insertions(+), 14 deletions(-)
```
- **LocalDatabase.cs**: `SchemaVersion = 1` + `LOCAL_SCHEMA_INFO(INFO_KEY PK, INFO_VALUE, UPDATED_DT)` 에 `SCHEMA_VERSION` 기록(없으면 추가, 낮으면 갱신, **앱보다 높으면 열지 않고 오류** — 데이터 보호). 경로 지정 생성자(템플릿 생성·테스트용, 운영은 기존 기본 생성자). 템플릿 복사는 `.creating` 임시 파일 → `File.Move(덮어쓰기 없음)`. `CreateTemplateAsync`: ADOX 로 빈 ACCDB + 이 클래스의 스키마 적용(대상 파일이 있으면 거부).
- **template.accdb**: PC-B 임시 파일을 쓰지 않고 **코드로 새로 생성**(`JU_TEMPLATE_OUT` 생성 테스트). 내용: LOCAL_DEVICE 0행, LOCAL_SYNC_STATE 0행, LOCAL_USER 0행, LOCAL_SCHEMA_INFO 1행(`SCHEMA_VERSION=1`). 사용자·계정·토큰·비밀정보 없음.
- 템플릿 갱신 절차: 스키마 변경 시 `SchemaVersion` 올림 → 생성 테스트로 새 파일 → `desktop/resources/template.accdb` 교체. `Repo_Template_Is_Schema_Only_And_Matches_Code` 가 코드와 다르면 실패해 누락을 막음.

## 빌드·테스트
| 단계 | 결과 |
|---|---|
| 빌드 5종 (8단계) | 전부 PASS |
| 서버 테스트 | 62/62 |
| Desktop 테스트 | **212/212** (205 + LocalTemplateTests 7) |
| LocalTemplate·C6b·C6c 상세 | 15/15 |

LocalTemplateTests 7건 (실제 ACE): 템플릿=코드 스키마(테이블·컬럼·PK·인덱스) + 데이터 없음 + 빌드 복사본 해시 동일 / 신규 설치(템플릿 복사, 템플릿 불변) / 기존 설치·재실행 3회(데이터 보존, 템플릿 없어도 덮어쓰기 없음) / 스키마 정보 없는 이전 DB 제자리 업그레이드 / 상위 버전 거부(데이터 그대로) / DB 초기화(파일 삭제 → 빈 DB 재생성, 템플릿 없으면 명확한 오류) / 생성기.

## 실제 앱 확인 (PC-B)
| 확인 | 결과 |
|---|---|
| 해시 | 저장소 파일 = commit 내용 = app\config 복사본 = 생성 원본 `FE2B566F8D3281E2` |
| 기존 설치 (11/23 빈 ACCDB 로 만든 사용자 DB) 실행 | `[LOCAL DB] … schema v1`, LOCAL_DEVICE 2행·LOCAL_USER 1행 유지, SCHEMA_VERSION=1 추가. 생성 시각 11/23 21:41 그대로(파일 교체 없음) |
| 재실행 | `schema v1`, 이상 없음 |
| 신규 설치 (app 을 임시 폴더로 복사, data·client.json·connections.json 제외) | `schema v1`, 새 DB 229 KB 생성 후 임시 폴더 삭제 |

## 진행 중 문제와 조치 (우회 없음)
- 실행 스크립트 `ai_tpl.ps1` 의 해시 함수 이름 `H` 가 PowerShell 기본 별칭 `h`(Get-History)와 겹쳐 **해시 비교가 빈 값끼리 비교되어 통과**했고, 내용 점검(Inspect)도 PS 5.1 `GetOleDbSchemaTable` 오류로 비었음. commit 은 이미 진행됨.
  → `ai_tpl_verify.ps1`(읽기만)로 **사후 확인**: 위 해시 4개 동일, 템플릿·사용자 DB 행 수·컬럼 정상, 사용자 DB 생성 시각 불변. 공유 저장소 `tools/ai_tpl.ps1` 은 이름 수정본(다음 재사용용).
  → 빌드 전 사용자 DB 해시 원본 값은 남지 않음(대신 행 수·생성 시각으로 보존 확인).

## 남은 문제 (보고만)
1. 다른 PC 의 기존 사용자 DB(스키마 정보 없음)는 첫 실행 때 SCHEMA_VERSION=1 이 추가됨(데이터 보존, 테스트 확인). LOCAL_USER·LOCAL_DEVICE 컬럼 불일치 시 DROP 재생성은 기존 동작 그대로 — 제품 배포 전 마이그레이션 방식 결정 필요.
2. 템플릿 생성에는 Access Database Engine(ACE)·ADOX 필요 (PC-B 있음). Jenkins 빌드는 저장소 파일을 복사만 하므로 ACE 불필요.
3. `.gitattributes` 의 한글 주석은 PowerShell 5.1 기본 인코딩으로 읽으면 깨져 보임(내용·동작 영향 없음).
4. C6c 실장비 미검증 항목(CH4, 케이블 분리·복구, 앱 가상 장치·오프라인 캐시)은 그대로 남음.

도구: `tools/ai_tpl.ps1`, `ai_tpl_verify.ps1`, `ai_c6c_rd.ps1` (+ run cmd).

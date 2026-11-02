# juprovider database

MariaDB 10.6+ / DB `juprovider` / `utf8mb4_general_ci`

| 폴더 | 용도 |
|---|---|
| `baseline` | 신규 설치용 전체 구조 |
| `seed` | 신규 설치용 기본 데이터 |
| `migration` | 이미 설치된 DB 업그레이드·검증용 SQL (번호 순서대로 실행) |

## 신규 설치

```
mysql -u <user> -p juprovider < baseline/01_ju_core_baseline.sql
mysql -u <user> -p juprovider < seed/02_ju_core_seed.sql
mysql -u <user> -p juprovider < migration/03_validate_baseline.sql
```

## 기존 DB 업그레이드

| 파일 | 대상 | 내용 |
|---|---|---|
| `migration/04_ju0_install_fix.sql` | seed V2.2로 설치한 DB | 프로토콜 유형 코드, .NET 버전, 장치 유형 코드 정정, 초기 관리자 생성(사용자가 없을 때만), `ju_menu_action`(+detail), 메뉴 Action 종류 공통코드 MACT |
| `migration/05_ju1_auth.sql` | 04 적용 DB | `ju_client`(+detail) 생성, `AUTH_ATTR`를 메뉴코드+권한비트 형식으로 변환 (재실행 안전) |
| `migration/06_protocol_actions.sql` | 05 적용 DB | 프로토콜관리(`M02010100`) Menu Action 10개(+detail, 다국어). 스키마 변경 없음 (재실행 안전) |
| `migration/08_collect_settings.sql` | 06 적용 DB (07 있으면 07 다음) | 수집 설정 컬럼(그룹 `FRAME_RULE`·`CMD_GAP_MS`·`INIT_ROUTINE`·`INIT_DELAY_MS`, 프로토콜 `PTL_ROLES`·`PTL_ACTION`·`EXPECT_RULE`·`IDEMPOTENT_YN`), 공통코드 `PROL`·`PACT`, `ju_data_channel_map`, GTEC 검증값 정정 7개 + 채널 매핑 4개 (재실행 안전). 되돌리기 `08_collect_settings_down.sql`, 점검 `08_collect_settings_check.sql`(읽기 전용) |

- 08은 아직 baseline·seed에 반영하지 않았다. 신규 설치도 seed 다음에 `08_collect_settings.sql`을 실행한다.
- 08은 값이 비어 있는 행(새 컬럼 NULL)만 정정한다. 논리삭제(`USE_YN=YENO0002`) 행과 이미 설정한 값은 바꾸지 않는다.
- `ju_schema_version`(07)이 있으면 마지막에 `'08'`을 `APPLY`로 기록한다 (없으면 건너뜀).

## 수집 설정 공통코드 (08)

| 그룹 | 코드 | COM_VAL | 쓰는 곳 |
|---|---|---|---|
| PROL | PROL0001 / 0002 / 0003 | INFO / CONTROL / DATA | `ju_protocol.PTL_ROLES` (쉼표 목록) |
| PACT | PACT0000 / 0001 / 0002 / 0003 | NONE / START / PAUSE / STOP | `ju_protocol.PTL_ACTION` |

- `PTL_TYPE`: PROT0000 POLL · PROT0001 TX_ONLY · PROT0002 RX_STREAM · PROT0003 TX_RX
- `IDEMPOTENT_YN`: 명령별 명시값(YENO). NULL이면 Desktop 기본 규칙. STOP 자동 규칙 없음
- `ju_data_channel_map.CHANNEL_KEY`는 그대로 비교한다 (`"1"` ≠ `"01"`, 대소문자 구분)

## 초기 관리자

- 로그인 ID: `admin` (seed와 `04`가 사용자가 없을 때만 만든다. 비밀번호는 BCrypt 해시로만 저장)
- 초기 비밀번호는 **공개 저장소에 기록하지 않는다.** 설치 담당자에게 별도로 전달한다.
- 설치 후 첫 로그인에서 반드시 바꾼다. `ju_user_detail.PW_CHANGE_DT`가 NULL이면 변경 대상이다 (변경 강제는 JU-1에서 적용).

## 메뉴 Action 종류 (`MACT`)

| 코드 | 이름 | COM_VAL (권한 비트) |
|---|---|---|
| MACT0001 | 조회 | 01 |
| MACT0003 | 등록 | 02 |
| MACT0004 | 수정 | 04 |
| MACT0005 | 삭제 | 08 |
| MACT0002 | 실행 | 10 |
| MACT0006 | 내보내기 | 20 |

- `ju_menu_action.ACT_KIND`가 이 코드를 쓴다. 권한 비트는 아래 `AUTH_ATTR`에서 쓴다.

## 권한 (`ju_auth.AUTH_ATTR`)

- JSON 문자열 배열. 항목 = 메뉴코드(9자리) + 권한 비트(16진 2자리). 예: `["M01000000FF","M0201020001"]`
- 비트는 위 `MACT`의 COM_VAL. 어드민(AUTH0001) 초기값 `FF`, 그 외 `01`(조회)
- Menu Action 실행 허용: `메뉴 비트 & Action의 ACT_KIND 비트 != 0`
- 비트 없는 9자리 항목(이전 형식)은 메뉴 표시만 허용
- 권한은 요청마다 DB에서 읽으므로 바꾸면 바로 적용된다

## 서버 실행 설정 (Tomcat `bin\setenv.bat`, 저장소 밖)

| 변수 | 용도 |
|---|---|
| `JU_DB_URL`, `JU_DB_USER`, `JU_DB_PASSWORD` | DB 접속 |
| `JU_JWT_SECRET` | 사용자 토큰 서명키 (32바이트 이상 임의 문자열). **없거나 짧으면 서버가 시작되지 않는다** (개발 PC의 `dev` profile만 임시 키 허용) |

## Desktop Client 등록

1. 어드민으로 로그인해서 토큰을 받는다 (`POST /juprovider/api/auth/login`, 최초 비밀번호 변경 후).
2. `POST /juprovider/api/admin/clients` `{"clientId":"PC01","clientName":"실험실 PC"}` → 응답의 `clientKey`는 이때 한 번만 보인다 (서버에는 SHA-256 해시만 저장).
3. Desktop `{app}\config\client.json`에 `ServerUrl`, `ClientId`, `ClientKey`를 넣는다 (저장소에 올리지 않음).
4. 키를 잃어버리면 `POST /juprovider/api/admin/clients/{clientId}/key`로 재발급 (이전 키는 즉시 무효, **사용 중인 Client만**). `DELETE …/{clientId}`는 사용 중지.
   사용 중지된 Client를 다시 쓰려면 같은 `clientId`로 2번 등록을 다시 한다 (새 키 발급).
5. `/juprovider/api/core/sync/**`는 헤더 `X-JU-Client-Id`, `X-JU-Client-Key`가 맞아야 한다 (아니면 401).

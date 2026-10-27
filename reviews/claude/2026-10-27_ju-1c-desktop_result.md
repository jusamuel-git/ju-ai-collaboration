# JU-1c Desktop 결과 (2026-10-27 11:31) — PASS, 로컬 commit, push 안 함

- 브랜치: PC-A juprovider `feature/ju-1c-desktop` @ **`fce5048`** (← main `acac1fa`)
- `feat(desktop): add user login and offline authentication` — 10 files, +1466 / −135 (patch: [2026-10-27_ju-1c-desktop.patch](2026-10-27_ju-1c-desktop.patch))
- 결정: D1~D8 ([decisions/CURRENT.md](../../decisions/CURRENT.md)), D5는 `LOCAL_USER` 컬럼 추가
- 서버·DB 스키마·API 계약·의존성 변경 없음 (Desktop만)

## 파일별 이유
| 파일 | 내용 |
|---|---|
| `lib.data/Auth/DesktopAuthService.cs` (신규) | 연결 상태 ONLINE / OFFLINE(연결 실패·타임아웃·5xx) / CLIENT_REJECTED(401·403·자격 없음). 로그인: CLIENT_REJECTED 차단 → 온라인 로그인(4xx는 fallback 금지 + offline 허용 해제) → 서버 장애일 때만 offline |
| `lib.data/Auth/OfflineCredential.cs` (신규) | PBKDF2-SHA256 210,000회, 사용자별 salt, 고정시간 비교 (D1) |
| `lib.data/Local/LocalUserRepository.cs` (신규) | LOCAL_USER 저장·해제·실패 기록·잠금 (D2 7일, D5 5회) |
| `lib.data/Local/LocalDatabase.cs` | LOCAL_USER에 `OFFLINE_FAIL_CNT`, `OFFLINE_LOCK_YN` 추가 (기존 표준 컬럼이면 ALTER로 행 보존, template의 이전 구성이면 재생성 — 아래 발견 1) |
| `lib.data/Api/JuProviderApiClient.cs`, `AuthApiModels.cs` | `POST api/auth/login` (4xx는 응답으로, 5xx·연결 실패는 예외) |
| `client/LoginForm.cs` (신규) | 로그인 화면, 표시 직후 서버 상태 비동기 확인 |
| `client/MainForm.cs` | 사용자·로그인 모드·Client·서버 상태·마지막 확인·장치 수 표시, 메뉴 동기화/로그아웃 (D7) |
| `client/Program.cs` | 로그인 → 메인 → 로그아웃 시 로그인으로 반복. UI 스레드 동기화 대기 제거 (Local DB 초기화만 동기) |
| `client/Services/AppLog.cs` (신규) | `app\logs\client_yyyyMMdd.log` (비밀번호·토큰·키 미기록) |

## 빌드·smoke (PC-A)
| 항목 | 결과 |
|---|---|
| 로컬 빌드 5종 (core / WAR+Vue / desktop / juproject backend / frontend ci·lint·build) | PASS |
| Desktop online/offline smoke (테스트 DB `juprovider_ju1cdtest` + 18081, `tools/ju1cd_desksmoke`) | **42 / 42 PASS** |
| 스크립트·서버 로그에 비밀번호·Client 키 원문 | 없음 |
| 정리 | 18081 종료, 테스트 DB 삭제 (남은 DB: `juprovider`) |

smoke 시나리오: PBKDF2 형식·salt·변조 거부 / 상태 분류(유효 키, 잘못된 키, 자격 없음, 서버 없음, 503) / 온라인 로그인 + LOCAL_USER(검증자만, 7일) / offline 성공(서버 없음·503), 최초 사용자 불가, 다른 Client 불가 / 5회 실패 잠금·온라인 성공 시 해제 / 만료 / **서버 401 → fallback 없음 + offline 해제** / **CLIENT_REJECTED + 올바른 비밀번호 → 차단, LOCAL_USER 불변** / 비밀번호 변경 필요 → 거부·미저장 / 서버 비밀번호 변경 후 검증자 교체 / 기존 LOCAL_USER ALTER·행 보존

## 발견·남은 문제
1. **`config\template.accdb`의 LOCAL_USER는 다른 구성**(`LOGIN_ID, USER_NM, AUTH_CD, PW_SALT, PW_HASH, LAST_SERVER_LOGIN_DT, USE_YN`)이라 기존 코드의 LOCAL_USER 생성은 실제로 실행된 적이 없었다. JU-1c 전에는 어떤 코드도 LOCAL_USER를 쓰지 않았으므로, 표준 컬럼이 없으면 재생성하도록 했다 (LOCAL_DEVICE와 같은 개발 단계 방식). 사용자 PC의 `app\data\juprovider.accdb`도 새 Client 첫 실행 때 재생성된다. template 파일 자체 정리는 범위 밖(보고만)
2. UI 화면은 빌드·로직 smoke로 확인. 로그인 화면 실제 조작은 사용자 확인 권장 (8081 운영 서버 + `PCA_DESKTOP01`로 가능, 서버 변경 없음)
3. 범위 밖(보고만): `InitializeIpcAsync` 미사용, `client.json`·`OFFLINE_TOKEN` DPAPI 보호(D3), Terminal/IPC 인증(D8), `SyncDevicesToTerminalAsync`의 TEMP TEST 연결 요청 코드, Updater Form1
4. PC-A에서 smoke 실행 중 탐색기 조작 실수로 이전 로그 파일 1개(`ai_ju1c_finish_DESKTOP-CE5BGKK.log`)가 메모장으로 열렸음 (변경 없음)

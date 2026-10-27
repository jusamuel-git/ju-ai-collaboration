# JU-1c Desktop 사전 조사 (2026-10-27, 코드 수정 없음)

기준: juprovider main `acac1fa` / 계획 v1.3 §JU-1c "User Login / Offline Authentication", 결정 A8

## 1. 현재 Desktop 구조
| 구성 | 위치 | 현재 역할 |
|---|---|---|
| Client (WinForms) | `desktop/juprovider.client` → 빌드 `desktop\app\` | 시작 시 Local DB 초기화 → 서버 장치 동기화 → `MainForm`(빈 Form1) 표시. Terminal에 IPC로 장치 전달 |
| Terminal | `desktop/juprovider.terminal` → `app\service\` | 장치 런타임(가상 장치), IPC Pipe 서버. 인증 없음 |
| Updater | `desktop/service/juprovider.service.updater` | 빈 Form1 (JU-1c 범위 밖) |
| lib.data | `Api/JuProviderApiClient.cs`, `Local/LocalDatabase.cs`, `Local/LocalDeviceRepository.cs` | HTTP(타임아웃 5초) / Access(ACE OLEDB) `app\data\juprovider.accdb` |
| 설정 | `Services/ClientSettings.cs` → `app\config\client.json` | ServerUrl, ClientId, ClientKey(평문 파일, `desktop/app/`은 .gitignore) |

## 2. Client 인증·동기화 연결 지점 (JU-1B에서 붙인 것)
- `Program.Main` → `InitializeClientAsync()`를 UI 스레드에서 **동기 대기**(`GetAwaiter().GetResult()`) → `SyncDevicesFromServerAsync()`
- `ClientSettings.Load()` → `new JuProviderApiClient(ServerUrl, ClientId, ClientKey)` → 헤더 `X-JU-Client-Id/Key` → `GET api/core/sync/devices` → `UpsertAllAsync` → `true`(ONLINE)
- 예외는 모두 `false`(OFFLINE)로 처리: **네트워크 장애와 401(키 무효/Client 사용 중지)를 구분하지 않는다**
- 결과는 `Debug.WriteLine`만 → 화면·로그 파일 없음 (`app\logs`는 비어 있음)
- 서버: Client 체인 `/api/core/sync/**`, `/api/client/**` (ClientKey, 성공 시 `LAST_SEEN_DT` 갱신) / 사용자 체인 `/api/**` (`POST /api/auth/login` permitAll, `/me`·`/password`는 토큰 필요, JWT 60분, `pwv`로 비밀번호 변경 전 토큰 무효)

## 3. User 로그인·오프라인 관련 현황
- Desktop에 **사용자 로그인 코드 없음** (stash에도 없음). Desktop은 사용자 JWT가 필요한 API를 아직 호출하지 않는다
- Local DB에 `LOCAL_USER` 테이블은 이미 생성됨(미사용): `USER_ID` PK, `SERVER_USER_ID`, `DEVICE_ID`, `OFFLINE_TOKEN LONGTEXT`, `LAST_AUTH_DT`, `EXPIRE_DT`, `ENABLED_YN`
- `LOCAL_SYNC_STATE`(ENTITY_TYPE, ENTITY_KEY, SYNC_STATE, LAST_SYNC_DT, ERROR_MESSAGE)도 생성만 되고 미사용
- 서버 로그인 응답: `accessToken`, `expiresAt`, `user`(UserInfo), `passwordChangeRequired`

## 4. 구현 방향 (제안)
1. **시작 순서**: Local DB → Client 동기화(백그라운드) → **로그인 폼** → 메인 화면(상태 표시). UI 스레드 동기 대기 제거
2. **연결 상태 3분류**: `ONLINE` / `OFFLINE`(연결 실패·타임아웃·5xx) / `CLIENT_REJECTED`(401: 키 무효·사용 중지 → 오프라인 허용 안 함, 관리자 문의 표시)
3. **온라인 로그인**: `POST /api/auth/login` 성공 → `passwordChangeRequired`면 (D4) → 아니면 offline credential 갱신, 토큰은 메모리에만
4. **offline credential** (`LOCAL_USER.OFFLINE_TOKEN`): 서버 비밀번호 평문·서버 BCrypt 해시 저장 금지. 로컬 전용 검증자 `pbkdf2-sha256$반복$salt$hash` (.NET 기본 `Rfc2898DeriveBytes.Pbkdf2`, 의존성 추가 없음) → 스키마 변경 없이 기존 컬럼 사용. `DEVICE_ID`=ClientId, `SERVER_USER_ID`=서버 USER_ID, `EXPIRE_DT`=마지막 온라인 인증 + 유효기간(D2)
5. **오프라인 로그인**: OFFLINE으로 판정된 경우에만, 같은 ClientId에서 이전 온라인 로그인한 사용자 + 만료 전 + ENABLED_YN=Y + 검증자 일치 → 허용. 최초 사용자·만료·불일치 → 불가. 온라인에서 401(비밀번호 틀림)이면 오프라인으로 넘기지 않음
6. **서버 상태 반영**: 다음 온라인 로그인 때 검증자를 새 비밀번호로 교체. 서버 사용자 비활성·로그인 거부 시 `ENABLED_YN=N`
7. **화면 최소 범위**: 로그인 폼 + MainForm 상단 상태(ONLINE/OFFLINE/CLIENT_REJECTED, 사용자, 마지막 동기화 시각, 장치 수) + 로그 파일 `app\logs`

## 5. 결정 필요 (D1~D8)
| # | 항목 | Claude 권장 |
|---|---|---|
| D1 | offline 검증자 방식 | PBKDF2-SHA256 (반복 210,000 이상, 사용자별 salt) — 기본 라이브러리만 사용 |
| D2 | offline 유효기간 (`EXPIRE_DT`) | 마지막 온라인 인증 후 7일 (서버 설정값 없이 Desktop 상수로 시작, 이후 `ju_sys` 이전 가능) |
| D3 | 추가 보호 (DPAPI로 `OFFLINE_TOKEN`·`client.json` 암호화) | 이번 단계 제외, 보고만. 필요 시 별도 단계 (패키지·Windows 계정 의존 확인 필요) |
| D4 | `passwordChangeRequired=true`로 Desktop 로그인 | Desktop에서 변경하지 않고 "웹에서 먼저 변경" 안내 후 로그인 거부, offline credential 저장 안 함 |
| D5 | 오프라인 로그인 실패 제한 | 연속 5회 실패 시 해당 사용자 offline 잠금(다음 온라인 로그인 성공 시 해제). 로컬 카운트는 기존 컬럼 없음 → `LOCAL_SYNC_STATE`(ENTITY_TYPE=`USER_LOCK`) 사용 또는 컬럼 추가 중 선택 |
| D6 | CLIENT_REJECTED(키 401) 시 동작 | 로그인 차단 + "Client 키 확인 필요" 안내 (오프라인 허용 안 함) |
| D7 | 로그아웃·사용자 전환 | 메뉴로 로그아웃 → 로그인 폼 복귀. 토큰은 메모리에서 폐기 |
| D8 | Terminal/IPC 인증 | 이번 단계 제외 (Terminal은 Client가 띄운 로컬 프로세스) — 보고만 |

## 6. 검증 계획 (PC-A, Desktop + online/offline 시나리오)
빌드 5종 PASS + Desktop 단위 테스트(검증자 생성·검증·만료) + 18081 테스트 DB로 시나리오:
온라인 로그인 성공 / 비밀번호 틀림(온라인 401 → 오프라인 미전환) / 서버 중지 후 이전 사용자 오프라인 성공 / 서버 중지 + 최초 사용자 불가 / 만료 후 불가 / 키 재발급 후 이전 키 → CLIENT_REJECTED / 비밀번호 변경 후 온라인 재로그인 시 검증자 교체 / passwordChangeRequired 안내

## 7. 범위 밖으로 보고만 하는 것
- `InitializeIpcAsync()` 미사용 코드 (`TerminalConnectionService`가 대체)
- `client.json` ClientKey 평문 파일 저장 (D3)
- `LocalDatabase`가 `config\template.accdb`에 의존 — 파일이 없으면 Local DB 생성 실패
- MainForm/Updater Form 제목 `Form1`

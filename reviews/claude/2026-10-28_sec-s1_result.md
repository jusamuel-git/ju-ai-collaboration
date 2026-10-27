# SEC-S1 결과 — Client 인증 Device 쓰기 경로 차단

- 결과: **PASS** (빌드 5종 PASS, 테스트 9/9, HTTP smoke 25/25, FAIL 0)
- 브랜치: juprovider `feature/sec-s1` (← origin/main `fce5048`), 로컬 commit **`4187280`**, **push 없음**
- PC-A `DESKTOP-CE5BGKK`, 2026-10-28 08:18. 근거 결정: SYSINFO-01 S1, SI-Q2
- patch: [2026-10-28_sec-s1_result.patch](2026-10-28_sec-s1_result.patch) / 스크립트: `tools/ai_secs1.ps1`

## 범위 (확인 결과)
| 대상 | 현재 | 조치 |
|---|---|---|
| `PUT /api/core/sync/devices/{devCd}` | Client 키로 공통 장치 INSERT/UPDATE 가능. 호출처 없음 | **제거** |
| Client 체인 `/api/core/sync/**` | 모든 메서드 Client 권한이면 허용 | **GET만 허용**, 그 외 `denyAll` → 403 (방어 2중) |
| `/api/client/**` | 엔드포인트 없음 | 변경 없음 (SYSINFO-02 `POST /api/client/sysinfo` 자리) |
| Desktop `JuProviderApiClient.SaveDeviceAsync` | 정의만, 호출 없음 | **제거** |
| `DeviceSyncService.saveDevice`, DAO insert/update | 컨트롤러 외 사용처 없음 | 유지(보고만). 관리자 Device Action CREATE/UPDATE 구현 시 재사용 후보 |

## diff --stat
```
 desktop/.../Api/JuProviderApiClient.cs              | 53 ----
 backend/.../config/SecurityConfig.java              |  5 ++
 backend/.../controller/DeviceSyncController.java    | 30 +--
 backend/.../controller/DeviceSyncControllerTest.java| 30 ++++ (신규)
 4 files changed, 40 insertions(+), 78 deletions(-)
```

## 회귀 테스트
- 단위: `DeviceSyncControllerTest` — 매핑 메서드가 GET 2개뿐인지 확인 (보안 테스트 의존성 추가 없이)
- HTTP smoke (18081, 실제 DB 덤프 사본 `juprovider_secs1test`, 종료 후 삭제)

| 구분 | 확인 | 결과 |
|---|---|---|
| 조회 유지 | Client 키 GET 목록 200(활성 수 = DB 2), GET 단건 200, 무헤더 401, JWT만 401, LAST_SEEN_DT 갱신 | PASS |
| 쓰기 차단 | 유효 키 PUT 기존/신규 403, POST·PATCH·DELETE 403, 목록 POST 403 | PASS |
| 인증 | PUT 무헤더 401, 잘못된 키 401, 관리자 JWT 401 | PASS |
| 무변경 | ju_device+detail 전체 MD5 전후 동일, 신규 DEV_CD 미생성 | PASS |
| 회귀 | 관리자 Device Action 15/SEARCH·GET 200, `/api/admin/clients` 200, `/api/core/languages` 200 | PASS |
| 비밀 값 | 로그에 비밀번호·Client Key 원문 없음 | PASS |

- Desktop: 빌드 PASS. Desktop이 쓰는 경로는 GET 목록뿐이고 그대로 동작함 (smoke 7번).

## 남은 문제 (보고만)
1. **Client 403 메시지 오해 소지**: 403 본문이 `"비밀번호를 먼저 변경해야 합니다."`. `JsonSecurityErrorHandler`가 PASSWORD_OK 권한이 없으면 이 문구를 쓰는데, Client principal에는 원래 그 권한이 없음. 상태코드는 맞음. PR-1이 같은 파일(`code` 필드)을 바꿨으므로 **두 브랜치 반영 후 1줄 수정**을 제안함 (Client 인증이면 "권한이 없습니다." / `FORBIDDEN`).
2. `feature/sec-s1`과 `feature/protocol-ref`는 겹치는 파일이 없음 → 순서와 무관하게 충돌 없이 합칠 수 있음.
3. Redis 장치 캐시는 18081과 8081이 공유함 (쓰기가 막혀 이번 영향은 없음). 테스트 서버 격리는 후속 검토.

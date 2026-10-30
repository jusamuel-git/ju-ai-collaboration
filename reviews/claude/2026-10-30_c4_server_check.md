# C4 API 실서버 검증 (15:05) — 18/19 PASS, 1건 기존 공통 동작 보고

- 대상: `feature/collect-c4` @ `d3a560a` WAR, 18081, **테스트 DB `juprovider_c4test`**(실제 DB mysqldump 사본). 변경 검증은 테스트 DB에 넣은 테스트 데이터(C4T_*)로, 끝나고 DB 삭제
- 실제 DB: 덤프(읽기)만, CHECKSUM 11개 테이블 전·후 동일. 제품 코드 변경 없음
- 도구: `tools/ai_c4srv.ps1`, `tools/c4srvplan/` (Client 키·비밀번호는 메모리/환경 변수만, 로그 원문 없음 확인)

| # | 항목 | HTTP·응답 요약 | 결과 |
|---|---|---|---|
| 1-1 | protocols 전체 | 200, 그룹 1/DB 1, 프로토콜 17/17, 패킷 3/3, revision 64자, removed [] | PASS |
| 1-2 | protocols/GTEC | 200, 그룹 1, 프로토콜 17/17, timeoutMs 3000 | PASS |
| 1-3 | protocols/{없는 그룹} | 404 | PASS |
| 2-1 | data-tags 전체 | 200, 태그 8/DB 8 | PASS |
| 2-2 | data-tags?devCd=SDEV_GTEC01 | 200, 4/4 (CH1~CH4), 다른 장치 없음 | PASS |
| 2-3 | data-tags?devCd={없는 장치} | 200, 0건 | PASS |
| 3-1 | 인증 정상 키 (3개 경로) | 200/200/200 | PASS |
| 3-2~3-6 | 헤더 누락 / Id만 / 잘못된 키 / 없는 Id / 관리자 JWT만 | 모두 401/401/401 | PASS |
| 3-7 | POST /sync/protocols (조회 전용) | **500** (기대 405), 데이터 변경 없음 | **FAIL** |
| 4-1 | 프로토콜 USE_YN·순서 | 그룹 SORT_ORD 순(C4T_B→C4T_A), 삭제 그룹 제외, 삭제 프로토콜 P9 제외(P1,P2), 삭제 패킷 seq3 제외(1,2) | PASS |
| 4-2 | 논리삭제 그룹 단건 | 404 | PASS |
| 4-3 | 데이터 태그 USE_YN·순서 | T_A,T_B (삭제 태그·삭제 데이터 그룹 제외, SORT_ORD 순) | PASS |
| 5-1 | protocols revision | 같은 데이터 동일, TIMEOUT_MS 변경 시 갱신, 원복 시 원래 값 | PASS |
| 5-2 | data-tags revision · 패킷 변경 | 동일 유지, DAT_UNIT 변경 시 갱신, PACKET_EXPR 변경 시 protocols 갱신 | PASS |
| 6-1 | 실제 응답 → Desktop → CollectionPlan | `JuProviderApiClient` 역직렬화(전체 그룹 3·프로토콜 19·패킷 5), GTEC, 없는 그룹 null, 태그 4 → 계획: 프로토콜 14, 간격 200 ms, 루틴 STOP→확인→센서정보→모드, 시작 `{`, 매핑 4(CH1→DG_GTEC01/GTEC-DATA-01/1). 하위 10/10 | PASS |
| 7-1 | 로그 비밀 값 | 비밀번호·Client Key·토큰 원문 없음 | PASS |
| 8-1 | 실제 DB 무변경 | CHECKSUM 동일 | PASS |

## 실패 분석 (3-7, 수정 안 함)
- 원인: Spring이 지원하지 않는 메서드로 `HttpRequestMethodNotSupportedException`을 내는데, `GlobalExceptionHandler`의 `@ExceptionHandler(Exception.class)`(기존, be1a664)가 모두 500으로 바꿈. C4 코드 문제 아님 — 다른 API(예: `POST /api/core/sync/devices`)도 같은 동작.
- 영향: 처리·데이터 변경 없음(컨트롤러 미도달). 응답 코드만 부정확.
- 제안: `GlobalExceptionHandler`에 `HttpRequestMethodNotSupportedException` → 405 처리 추가 (공통 동작 변경이라 별도 승인 필요).

## 참고
- 1·2차 실행(15:00, 15:03)은 검증 도구 오류(PowerShell 5.1이 curl 인자의 JSON 따옴표를 제거 → 로그인 400)로 무효. 요청 본문을 파일로 넘기도록 도구만 고친 뒤 3차(15:05) 결과가 위 표.
- 계획 경고: seed의 GTEC0101~0105·0200·0201은 수집 설정이 없어 PTL_TYPE(POLLING) 그대로, GTEC0003·0401·0402는 송신 표현식 없음으로 제외 — C5에서 PTL_TYPE·역할 정정 시 해소.

## C4b 405 수정 (15:20) — PASS
- `feature/collect-c4` @ `66e9255` (← `d3a560a`), 별도 로컬 commit. `GlobalExceptionHandler` 에 `HttpRequestMethodNotSupportedException` → 405 + `Allow` 헤더, 단위 테스트 2. 2 files +52. 패치: [2026-10-30_c4b_result.patch](2026-10-30_c4b_result.patch)
- 빌드 5종 PASS, 서버 테스트 15/15, Desktop 175/175
- 실서버(테스트 DB) 재검증 **31/31 PASS**: 위 1~8 항목 전부 + **3-7 `POST /api/core/sync/protocols` → 405** + 기존 API 회귀 9-1~9-12(health 200, 로그인 오류 401·형식 오류 400, me 200, admin/clients 200, languages 200, sync/devices 200·단건 200·무헤더 401·DELETE 405, `POST /api/action/15/SEARCH` 200, 같은 경로 GET 405). 실제 DB 무변경, 로그 비밀 값 없음
- 참고(수정 안 함): 숫자 자리에 문자를 넣은 경로(`/api/action/M02010100/...`, 이 브랜치는 menuId 숫자)는 `MethodArgumentTypeMismatchException` 이 여전히 공통 처리로 500 — 400 이 맞음. 같은 방식의 최소 수정 가능, 승인 시 진행
- 1차 실행(15:15)은 검증 도구가 이 브랜치에 없는 메뉴 코드 경로를 써서 9-11 실패(제품 문제 아님) → 도구만 숫자 경로로 수정 후 재실행

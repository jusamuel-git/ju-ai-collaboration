# PR-1 Action Contract Core 결과 (2026-10-27 16:35) — PASS, 로컬 commit, push 안 함

- 브랜치: PC-A juprovider `feature/action-contract` @ **`02ab18c`** (← main `fce5048`)
- `feat(action): add action contract core and menu-code action path` — 30 files, +1455 / −69 ([patch](2026-10-27_pr1-action-contract.patch))
- 결정: AC1~AC13, PR-E1 ([decisions/CURRENT.md](../../decisions/CURRENT.md)). DB·스키마·의존성 변경 없음. Protocol(PR-2)·Vue(PR-3) 전

## 구현
| 영역 | 파일 | 내용 |
|---|---|---|
| 계약 모델 | `core/action/contract/*` | `ActionContract`(contractVersion, OutputKind, input/output `FieldSpec`), `FieldType` 8종, `ListOutput{items,total}`, `ActionInput`(형 변환된 입력), `ActionFieldError` |
| 입력 검증 | `ActionInputValidator` | REQUIRED · TYPE_MISMATCH · MAX_LENGTH · INVALID_CODE(ju_com_code 사용 중 값) · **UNKNOWN_FIELD**(중첩 object·list 원소 포함, 경로 `packets[0].y`) — 모아서 400 |
| 오류 계약 | `core/action/exception/*`, `GlobalExceptionHandler`, `JsonSecurityErrorHandler`, `ApiResponse` | 400 VALIDATION / 404 NOT_FOUND / 409 CONFLICT / 501 NOT_IMPLEMENTED, 기존 401·403·400에도 `code` 추가. `code`·`errors`·`contractVersion`은 값 있을 때만 출력 → 기존 응답 모양 유지. 매핑 없는 경로 500 → 404 |
| 실행 | `DynamicActionService` | 순서: 메뉴·Action 조회(없으면 404) → 권한(호출 대상 메뉴, 403) → Handler(없으면 501) → contractVersion·입력 검증 → 실행(쓰기 MACT 02/04/08/10은 트랜잭션, 실패 결과 rollback) → 출력 kind 확인 |
| 경로 | `DynamicActionController` | `POST /api/action/{M########}/{actCd}` 추가 (`X-JU-Request-Id` 헤더). 기존 `/api/action/{숫자}/{actCd}` 유지 |
| 실행 맥락 | `ActionRequest` | ExecutionContext, langCd, requestId, 검증된 input 추가 (기존 생성자·getter 유지) |
| 호환 | `ActionHandler.contract()` default null | 계약 없는 Handler(Device SEARCH/GET)는 기존 동작 그대로 |
| 정합성 | `ActionHandlerConsistencyCheck` | 기동 시 Handler 없는 활성 Action WARN |
| 조회 | `MenuMapper` `selectMenuByCode`, `selectActiveActionHandlers`, `ActionCodeMapper` | 소문자 테이블명 |

## 빌드·테스트·smoke (PC-A)
| 항목 | 결과 |
|---|---|
| 로컬 빌드 5종 | PASS |
| 단위 테스트 | 19/19 (신규: 검증기 4, DynamicActionService 7 — 404·501·권한 우선·version 불일치·UNKNOWN_FIELD·쓰기 트랜잭션·kind 불일치) |
| Action smoke (테스트 DB + 18081) | **18/18 PASS** |

smoke: 기존 menuId 경로 Device SEARCH(배열 모양 유지)·GET·비관리자 SEARCH 200 / `15/CREATE` 501 / 정의 없는 Action·menuId 404 / MNU_CD 경로 200 + 요청 ID 헤더 / 비관리자 CREATE 403(501보다 권한 먼저) / 관리자 CREATE 501 / 없는 MNU_CD 404 / Action 없는 `M02010100` 404 / 형식 아닌 경로 404 / 토큰 없음 401 `UNAUTHORIZED` / 잘못된 JSON 400 `BAD_REQUEST` / 로그인 실패 401 message 유지 / 기존 API에 code·errors 없음 / 기동 WARN 8건(DEVICE.CREATE~STOP) / 로그에 비밀번호 없음. 테스트 DB 삭제

## 참고·남은 것
- 1차 실행 FAIL 2건은 smoke 스크립트 문제: (1) 사용 중지 장치(`11`)로 GET → 400(기존과 같은 동작), 사용 장치로 변경 (2) PowerShell 5.1이 보안 필터 401 본문을 읽지 못함 → curl로 확인(본문 정상). 제품 코드 수정 없음
- 계약이 있는 Handler의 HTTP 경로 smoke(400 VALIDATION 응답 본문, contractVersion 응답, list 모양)는 Protocol Handler가 생기는 PR-2에서 수행
- 이번 변경으로 바뀌는 기존 응답: Handler 없는 Device Action 400 → **501**, 정의 없는 Action·menuId 400 → **404**, 매핑 없는 경로 500 → **404**

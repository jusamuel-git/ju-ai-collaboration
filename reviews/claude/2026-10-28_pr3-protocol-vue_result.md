# PR-3 결과 — Protocol Vue (프로토콜관리 화면)

- 결과: **PASS** (빌드 5종 PASS, 테스트 23/23, API smoke 11/12 + 기대값 오류 1건, 브라우저 smoke 전 항목 PASS)
- 브랜치: juprovider `feature/protocol-ref`, 로컬 commit **`1d1c1ab`** (← `157635a` PR-2 ← `02ab18c` PR-1), **push 없음**
- PC-A `DESKTOP-CE5BGKK`, 2026-10-28 08:37~08:47. 테스트 DB `juprovider_pr3test`(실제 DB 덤프 + 06) 사용 후 삭제, 18081 종료, smoke 자격 파일 삭제
- patch: [2026-10-28_pr3-protocol-vue_result.patch](2026-10-28_pr3-protocol-vue_result.patch) / 스크립트: `tools/ai_pr3.ps1`, `tools/ai_pr3_finish.ps1`

## diff --stat (8 files, +608 / −47)
| 파일 | 이유 |
|---|---|
| `views/device/ProtocolManagement.vue` (신규 519) | 그룹 Grid·프로토콜 Grid·상세 Form·패킷 Grid·그룹 Dialog. 열·필드는 계약 필드 정의 배열로 그림(Designer Binding 단위). 데이터는 모두 Action `M02010100` v1 |
| `api/actionApi.js` | `executeByCode(mnuCd, actCd, params, {contractVersion})`, `actionError`(errors[] → 필드별 메시지). 기존 `execute` 유지 |
| `auth/session.js` | `PERM`, `menuPermission`, `canAction` — `/auth/me` 권한 비트로 버튼 표시 |
| `router/index.js` | `/console/device/protocol`, `meta.menuCode: 'M02010100'` (DB MNU_URL 동일) |
| `CoreController` / `CoreQueryService` / `CoreQueryDao(.xml)` | 레거시 `/api/core/protocol-groups`, `/api/core/protocols/{grp}` 제거 (AC10, 사용처 없음 확인) |

## 검증
**API smoke (ai_pr3.ps1)**: 레거시 2경로 404, `/api/core/data-groups` 200(회귀), GRP_SEARCH v1 200 `{items,total}`, `/me` 권한(관리자 FF·menuUrl 일치 / 조회자 01), SPA 경로 200, 로그에 비밀번호 없음 — PASS.
`contractVersion 2` 항목은 스크립트가 409를 기대했으나 서버는 **400 VALIDATION + `CONTRACT_VERSION_MISMATCH`** (PR-1 설계·PR-2 smoke와 동일) → **스크립트 기대값 오류**, 제품 동작 정상. 스크립트·`actionApi.js` 주석을 400으로 수정함.

**브라우저 smoke (built-in browser, 18081)**
| 사용자 | 시나리오 | 결과 |
|---|---|---|
| 관리자 | 그룹 등록: 그룹명 누락 → `그룹명` 옆 "필수 입력 항목입니다."(REQUIRED) | PASS |
| 관리자 | Polling -5 → 해당 칸 "1 이상이어야 합니다."(INVALID_VALUE) | PASS |
| 관리자 | 그룹 SMKG3 등록 → 기본 프로토콜 `SMKG30000` 자동 생성 표시 | PASS |
| 관리자 | 프로토콜 SMKG3P1 등록(패킷 TX·RX 2건) | PASS |
| 관리자 | 패킷 순번 중복 → `packets[1].packetSeq` 칸 "패킷 순번이 중복됩니다."(DUPLICATE) | PASS |
| 관리자 | 이름 수정 + 패킷 1건 삭제 → 패킷 1 / 전부 삭제 → 패킷 0 (빈 목록 전송 시 전체 교체 확인) | PASS |
| 관리자 | 프로토콜 삭제 → 목록에서 사라짐, "사용안함 포함"에서 `아니오` → "다시 사용" → `예` | PASS |
| 관리자 | GTEC 그룹 삭제 → 409 CONFLICT, 장치 2·실험 참조 메시지, 무변경 | PASS |
| 관리자 | SMKG3 그룹 삭제 → 목록에서 사라짐 | PASS |
| 관리자 | GTEC 수정 Dialog: GRP_GET 값 채움, 그룹코드 읽기전용, 저장 성공 | PASS |
| 관리자 | 네트워크: 화면 데이터 호출은 `/api/action/M02010100/*`, 공통코드, `/auth/me`뿐. 콘솔 오류는 의도한 400·409만 | PASS |
| 조회자(01) | 신규·수정·삭제·저장 버튼 없음, 상세 Form 전 입력 비활성, 목록·상세 조회 가능 | PASS |
| 조회자(01) | 직접 GRP_CREATE 호출 → 403 FORBIDDEN (서버 검사) | PASS |

## 남은 문제 (보고만)
1. **선택 항목 지우기 불가**: UPDATE가 `COALESCE`라 설명 등 선택 텍스트를 비워 저장해도 기존 값 유지. 계약 수준 결정 필요(빈 문자열 = 지움 등).
2. 좁은 화면(브라우저 pane 약 500px)에서는 1열 배치로 동작함. 패킷 Grid는 가로 스크롤.
3. 삭제 확인은 `window.confirm`. Designer 단계에서 공통 확인 Dialog로 바꿀 후보.
4. PC-A 작업 폴더 브랜치는 `feature/protocol-ref` @ `1d1c1ab`. `feature/sec-s1` @ `4187280`는 별도 로컬 브랜치.

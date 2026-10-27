# Action 계약 설계안 — Designer 최종 목표 반영, Protocol = 첫 Reference Implementation (2026-10-27)

선행 조사: [2026-10-27_action-structure_precheck.md](2026-10-27_action-structure_precheck.md) (G1~G12, P1~P8). 제품 코드 수정 없음.

## 0. 최종 목표와 이번 범위
```
[Designer]  Screen(Web/Desktop) ─ Component ─ Event ──Binding──▶ MNU_CD + ACT_CD
                 │ Draft → Publish(Version) → Rollback
[Runtime]   Vue/Desktop Renderer가 Published 정의를 읽어 화면 구성
            Event 발생 → POST Action(MNU_CD, ACT_CD, input) → 권한 → Handler → Service → output
```
- Designer가 의존하는 것은 **Action 계약**(식별자·입력·출력·오류·권한)뿐이다. 이 계약이 바뀌면 이미 Publish된 화면이 깨진다 → **계약은 지금 확정**하고, 화면 정의 저장·Publish는 나중에 만든다.
- 이번 Protocol 단계 = 계약을 코드로 처음 구현하는 Reference. 화면은 손으로 만든 Vue지만 **Action만 호출**하고, Designer가 나중에 만들 구성(Grid·Form·Button)과 같은 모양으로 만든다.

## 1. 현재 구조에 빠진 것 (Designer 관점)
| 개념 | 현재 | 빠진 것 |
|---|---|---|
| Action 식별 | `MNU_ID`(설치마다 다를 수 있는 대리키) + `ACT_CD` | 설치·환경 간 이식 가능한 `MNU_CD + ACT_CD` 공개 키 |
| Input Contract | `Map<String,Object>`, 검증 없음 | 필드 이름·형·필수·길이·코드그룹 선언, 서버 검증 |
| Output Contract | Handler마다 임의 (Device SEARCH는 배열, GET은 Map) | 결과 종류(list/record/key/none)와 고정 모양 |
| Error Contract | 거의 모두 400 + message | 오류 코드, 필드 오류 목록, HTTP 상태 구분 |
| 실행 맥락 | Handler에 사용자·langCd 없음 | 사용자·권한·언어·요청 ID |
| 정합성 | DB HANDLER_ID ↔ 코드 검사 없음, Handler 2/10 | 기동 검사, 미구현은 501 |
| 계약 조회 | 없음 | Designer가 읽을 Action 목록·계약 API |
| Screen/Component/Event/Binding | 없음 (메뉴 = Vue 라우트 하나) | 화면 정의 모델 |
| Draft/Publish/Version/Rollback | 없음 | 화면 정의 버전 관리 |

## 2. 지금 확정할 최소 계약 (Protocol에서 구현)
### C1. Action 식별자
- 공개 키 = **`MNU_CD` + `ACT_CD`**. `MNU_ID`는 내부용
- API: `POST /api/action/{mnuCd}/{actCd}?langCd=` (기존 `/api/action/{menuId}/{actCd}`는 Device 화면 호환용으로 유지, Device 단계에서 정리)
- `ACT_CD` 규칙: `^[A-Z][A-Z0-9_]{0,19}$`. `HANDLER_ID` 규칙: `도메인.동작` (`PROTOCOL.SEARCH`)
- Action은 **leaf 메뉴**에 소속. 권한은 **호출 대상 메뉴** 기준 (다른 화면에서 `M02010100/GRP_SEARCH`를 불러도 Protocol 메뉴 조회 비트 필요)

### C2. Input Contract
- 요청 본문은 현재 형태 유지: `{ "parameters": { ... } }`
- Handler가 코드로 계약을 선언, 서버가 실행 전 검증 (단일 출처)
  - 필드: `name`(camelCase, 컬럼 약어 기준: `ptlGrpCd`), `type`, `required`, `maxLength`, `codeGroup`(공통코드 그룹), `items`(list 원소 계약)
  - type: `string | integer | decimal | boolean | datetime | code | object | list`
- 선언하지 않은 필드는 무시(경고 없음), 형 불일치·필수 누락·길이 초과는 400 `VALIDATION`

### C3. Output Contract (결과 종류 4가지로 고정)
| kind | `data` 모양 | 용도 |
|---|---|---|
| `list` | `{ "items": [ {…} ], "total": n }` | 목록 (Grid). 페이징 입력은 나중에 추가해도 모양 불변 |
| `record` | `{ … }` | 상세 (Form 채우기) |
| `key` | `{ "ptlGrpCd": "…", "ptlCd": "…" }` | 등록·수정·삭제 결과 = 대상의 자연키 (Event 후속: 목록 새로고침, 상세 열기) |
| `none` | `null` | 실행형 |
- 필드 이름은 Input과 같은 규칙. 다국어 표시값은 `…Nm` 필드로 함께 반환

### C4. Error Contract (응답 봉투에 필드 추가 — 기존 필드 유지)
```json
{ "success": false, "data": null, "message": "…",
  "code": "VALIDATION", "errors": [ { "field": "ptlCd", "code": "REQUIRED", "message": "…" } ] }
```
| code | HTTP | 경우 |
|---|---|---|
| VALIDATION | 400 | 입력 계약 위반 |
| UNAUTHORIZED | 401 | 토큰 없음·무효 |
| FORBIDDEN | 403 | 메뉴·Action 비트 없음 |
| NOT_FOUND | 404 | 대상 데이터 없음 / 정의되지 않은 Action |
| CONFLICT | 409 | 중복 키, 사용 중 데이터 삭제 |
| NOT_IMPLEMENTED | 501 | DB에 있으나 Handler 없음 |

### C5. 실행 맥락
- `ActionRequest`에 `ExecutionContext`(userId, authId) · `langCd` · `requestId` 추가. Handler는 사용자를 작성자 기록에 쓴다 (Run/Command actor 규칙은 기존 결정대로 JU-5)
- 쓰기 kind(등록·수정·삭제·실행)는 **Action 1건 = 트랜잭션 1건**

### C6. 계약 변경 규칙
- 허용(비파괴): 선택 입력 추가, 출력 필드 추가, 오류 메시지 변경
- 금지: 필드 이름·형 변경, 필수화, 출력 kind 변경 → **새 `ACT_CD`로 추가**하고 이전 것은 `ENABLED_YN`로 내림
- 기동 시 DB 활성 Action의 HANDLER_ID가 코드에 없으면 WARN 목록, 호출 시 501

### C7. Protocol Action 목록 (`M02010100`, 엔티티별로 분리 — 출력 계약이 한 모양이 되도록)
| ACT_CD | kind | MACT | 입력(요지) | 출력 |
|---|---|---|---|---|
| GRP_SEARCH | list | 조회 | keyword?, useYn? | 그룹 목록 |
| GRP_GET | record | 조회 | ptlGrpCd | 그룹 + 상세 |
| GRP_CREATE | key | 등록 | ptlGrpCd, ptlGrpNm, pollingIntval, timeoutMs, retryCnt … | {ptlGrpCd} |
| GRP_UPDATE | key | 수정 | 위 + ptlGrpCd | {ptlGrpCd} |
| GRP_DELETE | key | 삭제 | ptlGrpCd | {ptlGrpCd} (장치가 사용 중이면 409) |
| SEARCH | list | 조회 | ptlGrpCd, keyword? | 프로토콜 목록 |
| GET | record | 조회 | ptlGrpCd, ptlCd | 프로토콜 + 패킷 목록 |
| CREATE | key | 등록 | ptlGrpCd, ptlCd, ptlType(code PROT), ptlNm, packets[list] | {ptlGrpCd, ptlCd} |
| UPDATE | key | 수정 | 위 (packets 전체 교체) | {ptlGrpCd, ptlCd} |
| DELETE | key | 삭제 | ptlGrpCd, ptlCd | {ptlGrpCd, ptlCd} |
- 삭제 = 논리 삭제(USE_YN=YENO0002). 패킷은 프로토콜의 하위 목록으로 함께 저장(별도 Action 없음)
- migration 06: 위 Action·detail·다국어 seed (스키마 변경 없음). 비관리자는 기존 `01` → 조회만

## 3. 나중으로 미루는 것 (지금은 모델만 정함)
| 항목 | 미루는 이유 | 지금 남기는 제약 |
|---|---|---|
| Screen/Component/Event/Binding 저장 테이블 | Designer 단계에서 결정 | 화면 1개 = leaf 메뉴 1개(`MNU_CD`). Binding 대상은 항상 `MNU_CD+ACT_CD` |
| Draft/Publish/Version/Rollback | 화면 정의가 생긴 뒤 필요 | 아래 §4 모델을 전제로 함 |
| 계약 조회 API (`GET /api/action/{mnuCd}` → Action·계약 목록) | Designer가 소비자. 코드 선언(C2)이 있으면 언제든 노출 가능 | 계약은 코드에만 선언 (DB 중복 저장 안 함) |
| 페이징·정렬 입력 | Protocol 데이터 규모 작음 | `list` 모양 고정으로 나중에 입력만 추가 |
| 낙관적 동시성(버전 컬럼) | 스키마 변경 필요 | UPDATE 입력에 나중에 `version` 추가 가능 (C6 허용 범위) |
| 필드 단위 권한, 조건부 표시, 화면 검증 규칙 | Designer 기능 | 서버 검증(C2)이 항상 최종 |
| Event 연쇄·워크플로 | Designer 기능 | `key` 출력으로 후속 동작 연결 가능 |
| Desktop Renderer, Protocol Desktop 동기화 | 별도 단계 (G12) | Desktop도 같은 Action 계약 사용 |
| 기존 `/api/core/protocol*` 조회 | Protocol 화면 전환 후 제거 | 새 화면은 사용 금지 |
| Device Action 정리(leaf 이동, Handler 8개) | Device 단계 | 같은 C1~C6 적용 |

## 4. Draft/Publish 모델 (방향만, 구현은 Designer 단계)
- 화면 정의 = JSON 문서. `screen(SCR_CD=MNU_CD, TARGET=WEB|DESKTOP)` / `screen_version(VER_NO, STATUS=DRAFT|PUBLISHED|ARCHIVED, DEFINITION, CHECKSUM, 작성·발행자/일시)`
- 화면당 PUBLISHED는 1개. Rollback = 이전 버전을 다시 Publish (새 버전 번호로 기록)
- Publish 검증: 정의가 참조하는 모든 `MNU_CD+ACT_CD`가 존재·활성이고, Binding한 입력·출력 필드가 계약에 있는지 확인 → 실패 시 Publish 거부
- Runtime: Vue Renderer가 메뉴 진입 시 Published 정의를 읽어 그림 (재빌드 없이 갱신). 손으로 만든 화면과 Renderer 화면은 메뉴별로 공존

## 5. 결정 필요 (기존 P1~P8 갱신)
| # | 항목 | 권장 |
|---|---|---|
| A1 | 공개 키 `MNU_CD+ACT_CD`, 새 경로 `/api/action/{mnuCd}/{actCd}` (C1) | 승인 필요 (API 계약 추가) |
| A2 | 권한은 호출 대상 메뉴 기준, Action은 leaf 메뉴 소속 (C1) | 승인 |
| A3 | Input 계약 코드 선언 + 서버 검증, 형 8종 (C2) | 승인 |
| A4 | Output kind 4종과 `list = {items,total}` (C3) | 승인 — 지금 정하지 않으면 이후 Binding이 깨짐 |
| A5 | 응답 봉투에 `code`, `errors` 추가, HTTP 상태 표 (C4) | 승인 (기존 필드 유지, 추가만) |
| A6 | `ActionRequest` 실행 맥락, Action = 트랜잭션 (C5) | 승인 |
| A7 | 계약 변경 규칙, 기동 WARN + 501 (C6) | 승인 |
| A8 | Protocol Action 10개 엔티티별 분리, 패킷은 하위 목록, 논리 삭제 (C7) | 승인 (P3·P6 대체) |
| A9 | 다국어: 등록 시 `*_NM_KEY` 자동 생성, LANG0001 값 저장 | 기존 P8 유지 |
| A10 | `/api/core/protocol*` 제거 시점 = Protocol 화면 전환 후 | 기존 P7 유지 |

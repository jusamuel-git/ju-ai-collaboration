# PR-2 Protocol Backend 결과 (2026-10-27 17:05) — PASS, 로컬 commit, push 안 함

- 브랜치: PC-A juprovider `feature/protocol-ref` @ **`157635a`** (← `02ab18c` PR-1)
- `feat(protocol): add protocol reference actions with v1 contracts` — 24 files, +1484 / −6 ([patch](2026-10-27_pr2-protocol-backend.patch))
- 결정: AC1~AC13, PR-Q1~Q5, PR-E1. 테이블 구조 변경 없음. Vue(PR-3) 전

## 구현
| 영역 | 내용 |
|---|---|
| migration 06 + seed | `M02010100` Action 10개(GRP_SEARCH/GET/CREATE/UPDATE/DELETE, SEARCH/GET/CREATE/UPDATE/DELETE) + detail + LANG0001/0002 이름. MNU_CD로 조회, 재실행 안전. seed도 같은 내용(ACT_ID 11~20) |
| Handler 10개 | `PROTOCOL.{ACT_CD}`, 모두 **contractVersion 1** 입력·출력 계약 선언 (`ProtocolContracts`) |
| ProtocolService | GRP_CREATE: 그룹·detail·다국어 + **기본 프로토콜 `{그룹}0000`(PROT0000, "기본 TX/RX") 같은 트랜잭션** / GRP_DELETE: **사용 중 장치 + 하위 프로토콜의 사용 중 실험 참조 전체 선검사 → 하나라도 있으면 409(무변경)**, 없으면 Packet → Protocol → Group 논리 삭제 같은 트랜잭션 / DELETE: 실험 참조 선검사 / UPDATE: packets 전체 교체, useYn은 재사용(YENO0001)만 / 업무 검증: packetSeq ≥1·중복, direction TX/RX, 수치 범위 |
| 다국어 (AC9) | `PROTOCOL_GROUP.{grp}.NM/.DESC`, `PROTOCOL.{grp}.{cd}.NM/.DESC` + LANG0001 값 upsert |
| 조회 조건 | useYn 생략 = 사용 중만, `YENO0000` = 전체 |
| **추가 (PR-1 코드 보완)** | `ActionOutputNormalizer`: 계약 Handler 출력은 **선언 필드만·선언 순서·값 없으면 null** (DB NULL 컬럼이 응답에서 빠지는 문제 방지 → Binding 안정). 오류 코드 `INVALID_VALUE`, `DUPLICATE` 추가 |

## 검증 (PC-A)
| 항목 | 결과 |
|---|---|
| 로컬 빌드 5종 | PASS |
| 단위 테스트 | **23/23** (신규 ProtocolContractTest 4: 10개 Handler v1 계약, 입력 계약, 결정적 키, 출력 정규화) |
| migration 06 | 1·2회 적용 무변경, **기존 DB+06 = 신규 설치** (Action·detail·다국어) |
| HTTP smoke (테스트 DB + 18081) | **58 / 58 PASS** |

**Output Contract**: `list={items,total}`(total=항목 수), 항목 필드·순서 = 계약 출력(GRP_SEARCH 9개, SEARCH 9개), RECORD(GRP_GET 다국어 키, GET packets 목록), KEY 모양(`{ptlGrpCd}` / `{ptlGrpCd,ptlCd}`만), 응답 `contractVersion: 1`, `X-JU-Request-Id`
**Input/Error Contract**: REQUIRED · UNKNOWN_FIELD(최상위·중첩 `packets[0].bogus`) · INVALID_CODE · TYPE_MISMATCH · MAX_LENGTH(한 요청에서 모두 수집) · DUPLICATE · INVALID_VALUE · CONTRACT_VERSION_MISMATCH → 400 VALIDATION + errors[] / 404 없는 대상·정의 없는 Action / 409 중복·사용 중·삭제된 그룹에 등록 / 403 비관리자 쓰기·권한 없는 사용자 조회 / 비관리자(01) 조회 200
**GRP_DELETE 선검사**: GTEC(실제 장치 사용) 409 / 장치+실험 동시 참조 → 409, 메시지에 둘 다, **Group·Protocol·Packet 무변경** / 장치만 해제해도 실험 참조로 409 / 모두 해제 후 200 → Group·Protocol 2개(기본 포함)·Packet 모두 YENO0002
**원자성 (DB 트리거로 중간 실패 주입)**:
- GRP_CREATE 기본 프로토콜 INSERT 실패 → 500, 그룹·detail·다국어 **모두 없음**
- GRP_DELETE 마지막 단계(그룹 UPDATE) 실패 → 500, 앞서 바꾼 Packet·Protocol **YENO0001 그대로**
- CREATE 두 번째 패킷 실패 → 500, 프로토콜·detail·패킷·다국어 **모두 없음**
- → MyBatis 쓰기가 Action 트랜잭션(JpaTransactionManager)에 함께 묶임을 확인
**회귀**: Device menuId 경로 SEARCH 200(기존 배열 모양), 기동 WARN 8건(Device만, PROTOCOL 없음), 로그에 비밀번호 없음. 테스트 DB 삭제

## 남은 것
- PR-3 Protocol Vue (`ProtocolManagement.vue`, `actionApi.executeByCode`, 라우트, `/api/core/protocol*` 제거)
- 실험 참조는 `ju_experiment_data_group`에 그룹코드가 없어 **PTL_CD만으로 매칭** — 다른 그룹에 같은 PTL_CD가 있으면 보수적으로 409 (seed 코드는 모두 그룹 접두어라 현재 영향 없음)
- 수정 시 설명을 빈 값으로 지우는 기능 없음 (값을 보내지 않으면 유지)
- 그룹 재사용(GRP_UPDATE useYn=YENO0001) 시 하위 프로토콜은 자동 복구하지 않음 (개별 UPDATE)

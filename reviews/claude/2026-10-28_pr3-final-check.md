# PR-3 최종 확인 — Protocol CRUD 안정화 (금요일까지 우선 작업)

- 결과: **PASS, FAIL 0. 제품 코드 수정 없음 → 추가 commit 없음**
- 대상: `feature/protocol-ref` @ `1d1c1ab` (PC-A, 2026-10-28 09:14). 테스트 DB(실제 DB 덤프 + 06) 사용 후 삭제. git 변경 0건
- 스크립트: `tools/ai_pr3_final.ps1`

| 항목 | 결과 |
|---|---|
| 빌드 5종 / 테스트 | PASS / 23/23 |
| PR-3 API smoke (기대값 400 기준) | **12/12** (서버 1, 로그인 2, API 8, 비밀번호 로그 1) |
| 권한 | 조회자 GRP_SEARCH·SEARCH 200, 쓰기 6종 모두 403 |
| 기본 Protocol 자동생성 | GRP_CREATE → `{grp}0000` 생성, 중복 그룹 409 |
| 패킷 전체교체 | 미전송 → 유지 2 / 1건 → 1 / `[]` → 0 / 순번 중복 400 DUPLICATE·무변경 |
| 논리삭제·재사용 | DELETE 후 기본 조회 제외·전체 조회 YENO0002, 비활성화는 DELETE로만(400), 재사용 200, 중복 CREATE 409 |
| 참조 409 | 실험 참조 프로토콜 DELETE·그룹 GRP_DELETE 409(무변경), 장치 참조 그룹 409, GTEC 실데이터 409 |
| 그룹 삭제 | 참조 없음 200 → 그룹·프로토콜·패킷 활성 0/0/0, 삭제 그룹에 CREATE 409, 그룹 재사용 200 |
| 화면 | 08:40 브라우저 smoke(같은 코드)로 그룹·프로토콜 CRUD, 필드 오류 표시, 조회자 버튼 숨김 확인 — 재실행 불필요 |

## 선택 텍스트 지우기 — 현재 동작과 최소 수정안 (승인 전 구현 안 함)
- 현재: UPDATE `ptlDesc:''` → 200, DB 값 그대로(`desc1`). 오류 없이 무시됨.
- 최소 수정안 (약 6파일):
  1. `FieldSpec`에 `clearable` 표시 → 대상 3개만: GRP_UPDATE `ptlGrpDesc`, UPDATE `ptlDesc`·`ptlVal`
  2. `ActionInputValidator`: `clearable` 필드의 `""`만 `""`로 전달 (그 외는 지금처럼 무시)
  3. `ProtocolMapper.xml` 해당 3개 SET: `""` → NULL, null → 유지 (나머지 COALESCE 그대로)
  4. `ProtocolService`: 설명이 지워지면 다국어 LANG0001 값도 지움
  5. `ProtocolManagement.vue`: 원래 값이 있던 칸을 비운 경우만 `""` 전송
  6. 테스트: Validator 단위 + smoke 3건(미전송 유지 / `""` NULL / 값 변경)
- 계약 버전: 1 유지 제안 (지금 `""`에 의존하는 호출자 없음). 승인 필요.

## 남은 것
- SEC-S1 Client 403 문구: 통합 시 1줄 수정 (계획 A3), 승인 대기
- 통합·실제 DB 06 적용: 사용자 승인 전 금지 유지

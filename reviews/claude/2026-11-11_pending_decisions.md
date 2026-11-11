# 결정 대기 목록 (2026-11-11 C5d 완료 시점)

근거: [C5c 결과](2026-11-11_c5c_result.md), [C5d 결과](2026-11-11_c5d_result.md)

| # | 결정할 것 | Claude 제안 | 영향 |
|---|---|---|---|
| D1 | **C5e 실제 DB 08 적용** 승인 | 승인 시 `08_collect_settings_check.sql`로 사전 점검 → 백업 → 08 적용 → 사후 점검 순서 | C5c 서버·C5d Desktop 배포의 선행 조건 |
| D2 | 배포 순서 | C5e(실제 DB 08) → C5c 서버 → C5d Desktop | C5c 서버는 08 컬럼이 없는 DB에서 동작하지 않음 |
| D3 | Java에서만 되는 regex(예: `a++`)를 서버 저장에서 차단할지 | 차단 (.NET 기준으로 통일) | 지금은 Desktop이 경고 후 내장 설정으로 대체하므로 수집이 끊기지는 않음 |
| D4 | Desktop 내장 GTEC 설정 제거 (C5-Q7) | 당분간 유지 (서버 값이 없을 때만 쓰는 대체값). C5e 실DB 적용과 실장비 재확인 후 제거 | 서버 값만으로 실장비 22/22 PASS 확인됨 |
| D5 | 제품 feature 브랜치 원격 push (`collect-c5b`·`c5c`·`c5d`) | 승인 시 3개 push (main 제외) | PC 교체·백업 대비 |
| D6 | 기존 대기 항목 | MethodArgumentTypeMismatch → 400, G4(실DB 06), G5(main push·Jenkins), Action 계약 v2(값 비우기) | 변경 없음 |

참고 (보고만): PC-B Smart App Control 꺼짐 유지 필요, `package-lock.json` 로컬 변경, `feature/protocol-ref` 로컬이 origin보다 1 뒤.

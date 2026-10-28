# 배포 체크리스트 — feature/integration-1 @ 14d1ab9 → 8081 (금요일 10/30 이후)

대상: PR-1~3 + WEB-02/03 + SEC-S1(+S1b). 현재 main `fce5048`, 실제 DB는 04·05 적용 상태.
각 단계는 사용자 승인 후 진행. 실패하면 즉시 멈추고 6번.

## 1. PR-2 코드 검토
- [ ] `157635a` 최종 코드 검토 문서 (ChatGPT) — 미결 지적이 있으면 수정 여부 결정
- [ ] 기록된 한계 확인: PR-L1(실험 참조 PTL_CD만), PR-L2(clearable → Contract v2)

## 2. 실제 DB 백업 + migration 06 (G4)
- [ ] 8081 Tomcat 실행 중 그대로, 백업: `mysqldump --single-transaction --routines --triggers juprovider > backup\juprovider_<날짜>_before_06.sql`, 파일 크기 확인
- [ ] 사전 확인: `ju_menu_action` 총 개수, M02010100 Action 0건
- [ ] `database/migration/06_protocol_actions.sql` 적용 (재실행 안전)
- [ ] 사후 확인: M02010100 활성 Action 10, HANDLER_ID `PROTOCOL.*` 10, 다른 메뉴 Action 수 불변
- [ ] (구 WAR는 06과 무관하게 동작 — 이 시점 8081 영향 없음)

## 3. main 반영 (G5)
- [ ] `git fetch` 후 origin/main = `fce5048` 확인 (다르면 중단·보고)
- [ ] `git checkout main && git merge --ff-only feature/integration-1` → main = `14d1ab9`
- [ ] `git push origin main` (feature 브랜치 push는 선택)

## 4. Jenkins 배포
- [ ] `juprovider-ai` 빌드 실행 → rev `14d1ab9`, 테스트 27/27, Check WAR, Backup Current WAR(파일명 기록), Health UP

## 5. 배포 후 확인 (8081)
- [ ] `GET /juprovider/api/health` → UP
- [ ] `/juprovider/` 공개 홈, 로그인 버튼
- [ ] 콘솔 URL 직접 → 로그인 → 원래 URL 복귀 / 로그아웃 → 홈
- [ ] admin: 장치관리 조회, 프로토콜관리 그룹·프로토콜 조회·등록·수정·삭제(시험용 코드로 하고 삭제까지)
- [ ] 조회자 계정: 쓰기 버튼 없음
- [ ] Desktop(PCA_DESKTOP01, ServerUrl 8081): 로그인·동기화 정상 / 장치 PUT 경로 403
- [ ] 레거시 `/api/core/protocol-groups` 404

## 6. 실패 시 복구 순서
1. **화면·API 이상(WAR 문제)** → Jenkins가 남긴 백업 WAR(`juprovider-<timestamp>.war`)를 `webapps\juprovider.war`로 되돌리고 Tomcat 재시작 → Health 확인. main은 `git revert`로 되돌리거나(사용자 결정) 다음 수정으로 해결
2. **06 이상** → 구 WAR 상태에서 먼저 확인. 데이터 문제면 (a) M02010100 Action 삭제(`ju_menu_action_detail`·`ju_multi_lang` PROTOCOL 키 → `ju_menu_action`), 또는 (b) 2번 백업 SQL 복원 — **복원은 사용자 확인 후**
3. 순서: WAR 먼저 되돌림 → DB 판단 → 복구 후 Health·로그인·Desktop 동기화 재확인 → CURRENT.md에 원인·조치 기록

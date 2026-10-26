# 유효한 결정 (2026-10-26 기준)

날짜별 원문은 같은 폴더의 `YYYY-MM-DD_*.md`. 바뀐 결정은 여기서 고치고 원문은 남긴다.

## 협업·운영
| # | 결정 | 일자 |
|---|---|---|
| O1 | 진행 순서: Claude 조사 → ChatGPT 설계 → Claude 역검토 → 사용자 결정 → Claude 구현·로컬 빌드 → ChatGPT diff 검토 → 사용자 commit/push → Jenkins main 확인 | 10/24, 10/26 |
| O2 | 제품 저장소 commit/push는 사용자. 협업 저장소(ju-ai-collaboration)는 Claude가 직접 commit/push | 10/26 |
| O3 | Jenkins는 `main` 최종 검증용. Job 구조는 바꾸지 않는다. 미커밋 변경은 PC-A 로컬 빌드로 검증 | 10/26 |
| O4 | 기준 개발 PC = PC-A `DESKTOP-CE5BGKK`. PC-B는 PC-A에 맞춘다. PC-A Tool은 옮기지 않는다 | 10/26 |
| O5 | 개발자 환경변수는 User 범위 기본. Jenkins(LocalSystem) 환경은 분리. cache 공유하지 않음 | 10/26 |
| O6 | Node/CMake는 설치형 유지. MariaDB 데이터 위치는 PC별 허용 | 10/26 |
| O7 | 비밀 값은 Git·문서·patch·zip에 넣지 않는다 | 10/23~ |

## 아키텍처 (v1.2 기준 + 사용자 결정)
| # | 결정 | 일자 |
|---|---|---|
| A1 | SYS(JuProject) → JU(JuProvider) 단방향·선택적 연동. JU는 SYS 없이 독립 실행. DB 공유 없음 | 10/25 |
| A2 | JU에 Site 계층 유지: 레벨 1 site = 부서 상위, 하위 레벨 = 장치 위치 (JU 자체 모델, 설계 필요) | 10/25 |
| A3 | JU 권한은 `ju_auth.AUTH_ATTR` JSON 유지. 항목 = 메뉴코드(9) + 16진 2자리 비트. 9자리 = 메뉴 표시만 | 10/25 |
| A4 | 비트 단위 = 메뉴 Action 종류 공통코드 MACT의 `COM_VAL` (조회 01, 등록 02, 수정 04, 삭제 08, 실행 10, 내보내기 20) | 10/25 |
| A5 | 기존 9자리 AUTH_ATTR는 11자리로 변환 (어드민 FF, 그 외 01) | 10/25 |
| A6 | 비 ADMIN 권한은 조회 중심 유지. 각 도메인 Phase에서 확정 | 10/26 |
| A7 | JU Web 인증 = JWT (`spring-boot-starter-oauth2-resource-server`) | 10/25 |
| A8 | Desktop = Client 인증(관리자 API 발급 키, 해시 저장)과 User 인증 분리. 오프라인: 이전 정상 로그인 사용자가 있으면 통과, 없으면 불가 (UI는 JU-1c) | 10/25, 10/26 |
| A9 | JU 초기 admin: seed 기본 비밀번호 + 첫 로그인 변경 강제 | 10/25 |
| A10 | `JU_JWT_SECRET` 미설정 시 운영/일반은 기동 실패, 개발 profile에만 fallback (구현 수정 필요) | 10/26 |
| A11 | SYS-0과 SYS-1 한 번에. 범위 = DB + 기존 기능 전환. 기존 ADMIN/USER 데이터 보존 이전 | 10/25, 10/26 |
| A12 | 장치 유형 코드(DEVI) 시드 정정은 JU-0에서 | 10/25 |
| A13 | Desktop offline 실험 수집 범위는 JU-6에서 결정 | 10/25 |

## 승인 대기
- `global.json` (SDK 10.0.400, latestPatch) — 두 제품 저장소
- Jenkinsfile Tomcat 경로 → `JU_TOMCAT_HOME`, 포트 → `HTTP_PORT`
- 제품 저장소 `AI_COLLABORATION.md`를 이 저장소를 가리키는 안내로 바꾸는 것
- 재설계 요청서의 A~K 항목

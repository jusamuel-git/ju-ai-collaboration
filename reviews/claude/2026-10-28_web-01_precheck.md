# WEB-01 조사 — JuProvider 홈페이지/콘솔 분리

- 기준: juprovider `feature/protocol-ref` @ `1d1c1ab`. JuProject 변경 없음

## 1. 현재 구조
| 파일 | 현재 동작 |
|---|---|
| `router/index.js` | `/` → `/console/device/manage`로 **redirect** (공개 화면 없음). `/login` public. 나머지 전부 로그인 필요. 가드: 미로그인 → `/login?redirect=원래경로`, `/auth/me` 재조회, 비밀번호 변경 필요 → `/password-change`, `meta.menuCode` 권한 없음 → `/forbidden` |
| `App.vue` | 공개 화면이 아니면 상단 바(권한 메뉴 수·사용자·로그아웃) 표시. **로그아웃 → `/login`** |
| `LoginView.vue` | 로그인 후 `redirect`(안전 경로만) 또는 기본 `/`. 비밀번호 변경 필요 시 `/password-change`(redirect 유지) |
| `PasswordChangeView.vue` | 변경 후 재로그인 → `redirect` 또는 `/` |
| `api/api.js` | 401이면 세션 삭제 후 `/juprovider/login?redirect=…` |
| `SpaForwardController` | `/login`, `/password-change`, `/forbidden`, `/console/**` → index.html. `/`는 Spring 기본 index.html |
| 콘솔 메뉴 | **화면 메뉴 없음** (URL 직접 이동) |

## 2. 기존 홈페이지 코드
- `layouts/PublicLayout.vue`, `layouts/ConsoleLayout.vue`: **어디서도 import 안 함 (죽은 코드)**. 없는 파일(`services/api.js`, `utils/auth.js`, `utils/menuTree.js`)을 import → 그대로 재사용 불가. 회사소개·제품·다운로드 등 링크도 대상 화면 없음.
- `assets/site.css`: `.container/.hero/.section/.cards/.card/.btn` 공개 화면용 스타일 있음 → **재사용**.
- `assets/company/career-*.jpg`: 개인 경력 이미지로 보임 → 사용 안 함.
- 결론: 구 레이아웃은 건드리지 않고(삭제는 별도 승인) 새 최소 레이아웃 2개를 추가.

## 3. 최소 변경 (Vue만 7파일, 서버·DB·인증 변경 없음)
| 파일 | 변경 |
|---|---|
| `router/index.js` | `/` = PublicShell + HomeView(public). `/console` = ConsoleShell 아래 장치·프로토콜 화면. `/password-change`, `/forbidden`은 **주소 그대로** ConsoleShell 안(로그아웃 가능 유지). 로그인 상태 `/login` → `/console`. 가드 로직 그대로 |
| `App.vue` | `<router-view/>`만 (상단 바는 ConsoleShell로 이동) |
| `layouts/PublicShell.vue` (신규) | 헤더(로그인 / 로그인 상태면 콘솔로 이동), 푸터 |
| `layouts/ConsoleShell.vue` (신규) | 콘솔 메뉴(route `meta.menuCode` ∩ `/auth/me` 메뉴), 사용자, 로그아웃 → `/` |
| `views/public/HomeView.vue` (신규) | 최소 소개(제목·3개 카드). 디자인·다국어는 WEB-04 |
| `LoginView.vue`, `PasswordChangeView.vue` | 기본 이동 `/` → `/console` (각 1줄) |
- 메뉴명은 서버 메뉴명 사용. seed의 장치관리(M02010000) MNU_URL이 NULL이라 메뉴 URL 대신 route 기준으로 표시.

## 4. 회귀 테스트
SPA 경로 200(`/`, `/login`, `/console`, `/console/device/protocol`, `/password-change`, `/forbidden`) · PR-3 API smoke 12 · Protocol CRUD 35 · 브라우저: 비로그인 `/` 공개 / `/console/...` → 로그인 → 원래 URL / 로그아웃 → `/` / 로그인 상태 `/login` → `/console` / 비밀번호 변경 필수 사용자 → 변경 → 원래 URL / 조회자 버튼 숨김·관리자 CRUD / 권한 없는 메뉴 → forbidden · 빌드 5종

## 5. 동작 변화 (기존 영향 — 의도된 것)
- `/` 진입: 콘솔 redirect → 공개 홈. 로그아웃: `/login` → `/`. 로그인 기본 이동: `/` → `/console`(=장치관리, 이전과 같은 화면)
- 그 외 인증·권한·API는 동일

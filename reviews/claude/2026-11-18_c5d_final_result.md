# C5d Desktop 최종 실장비 검증 — **PASS** (실서버 8081 + GTEC COM3)

- 일시: 2026-11-18 21:18 ~ 21:28, PC-B
- 대상
  - 서버 8081 = main `4915759` (Jenkins #3)
  - Desktop 라이브러리 = `feature/collect-c5d` @ `4915759`
- 도구
  - `tools/ai_c5d_connect.ps1`: 등록, 키 인증, 동기화, 계획
  - `tools/ai_c5d_realprobe.ps1` + `c5dprobe`: COM3 실장비
  - `tools/ai_admin_pw_reset.ps1`: 승인된 admin 임시 재설정
- 지킨 것
  - DB 구조 변경, WAR 재배포, main 변경 없음
  - 비밀번호·Client Key 원문은 어디에도 기록하지 않음. 키는 `desktop\app\config\client.json`(git 제외 경로)에만 저장

## 결과

| # | 항목 | 결과 |
|---|---|---|
| 0 | admin 복구 (11/18 승인 방법 B) | PASS. 임시 비밀번호로 재설정 (기존 값 백업 `backup\admin_pw_20261118_211913`) → 로그인 200·변경 필요 True → 사용자가 최종 비밀번호로 변경 → 이후 로그인 200, 변경 필요 False |
| 1 | Jenkins/Tomcat 8081 | PASS. health 200 (11/18 21:02부터 숨김 실행 유지). Jenkins 서비스 Running, 마지막 빌드 #3 SUCCESS |
| 2 | Client 등록·키 발급 | PASS. 기존 등록 0건 → `PCB-DESKTOP-01` 신규 등록 (HTTP 200, 키 43자). DB `PCB-DESKTOP-01:YENO0001` |
| 3 | Client Key 인증·동기화 | PASS<br>- 정상 키: `sync/devices` 200, 장치 2개 = DB 2개<br>- 401: 키 틀림, 키 없음, Id 없음, 없는 Id, JWT만 사용<br>- 쓰기 메서드: 403<br>- `sync/protocols`·`protocols/GTEC`·`data-tags`·`data-map`: 모두 200<br>- `LAST_SEEN_DT` 갱신 |
| 4 | GTEC 서버 설정·data-map 수신 | PASS<br>- 간격 200, 대기 500, 루틴 `GTEC0301→0001→0002→0100`, frameRule 있음<br>- data-map 4채널 `1~4 → GTEC-DATA-01~04`<br>- Desktop 라이브러리로 만든 서버값 CollectionPlan 16/16 |
| 5 | COM3 INIT → START → 수집 → STOP | PASS<br>- 초기화 4단계 모두 Completed (약 0.8초)<br>- 5초 동안 값 150개(≈50프레임), 품질 Good 150<br>- STOP 후 수신 없음 |
| 6 | 케이블 분리·재연결 | PASS<br>- 분리 → Suspended<br>- 재연결 4회차에 Recovered → 초기화 루틴 자동 재실행 (STOP 먼저, 모두 Completed)<br>- 수집 재개: 150개 Good<br>- STOP 후 수신 없음 |
| 확인 | 서버 설정 우선 적용 | PASS. 계획 출처가 frame·cmdGapMs·initDelayMs·각 프로토콜 tx/roles/action/pattern 모두 `server`. 내장 설정 미사용 |
| 확인 | 채널별 TAG_ID 매핑 | PASS. `CH1~3 → DG_GTEC01/GTEC-DATA-01~03` (예: CH1 = 59.25). data-map 4행 사용, `CH<n>` 임시 변환 미사용 |

- 실장비 OK 24건
- 경고 0건, 처리 안 된 프레임 0건, 초기화 루틴 2회
- 제품 저장소 변경 없음 (`package-lock.json`은 기존 npm 변경)

## 알아 둘 점 (조치 안 함)

- **"Desktop 실행" 범위**
  - 현재 Desktop 앱(`juprovider.client.exe`)은 로그인할 때 `sync/devices`만 받는다.
  - GTEC 프로토콜·data-map을 받아 CollectionPlan으로 수집하는 기능은 아직 앱 화면·서비스에 연결되어 있지 않다.
  - 그래서 4~6번은 앱과 같은 Desktop 라이브러리(`JuProviderApiClient`, `CollectionPlanBuilder`, 세션·링크)를 쓰는 검증 도구로 확인했다.
  - 앱에 연결하는 작업은 다음 단계에서 결정이 필요하다.
- **계획 경고 (기존 데이터, C5d 설계대로 대체 동작)**
  - GTEC0101~0105·0200·0201: 서버 역할이 없어 PTL_TYPE 사용
  - GTEC0003·0401·0402: 송신 표현식 없음
  - GTEC0000: 비JSON 해석 규칙
  - 서버 설정을 보완할지는 별도 결정
- **8081 실행 방식**: 지금은 숨김 `catalina.bat run`으로 돌고 있어 재부팅하면 내려간다. Windows 서비스 등록은 승인 대기.
- **GTEC 수집 설정 "웹 화면" 확인**: 이번에는 서버 sync 응답(K-6)으로 같은 값을 확인했다. 관리자 화면에서 직접 보는 것은 사용자 로그인 세션에서 추가로 확인할 수 있다.

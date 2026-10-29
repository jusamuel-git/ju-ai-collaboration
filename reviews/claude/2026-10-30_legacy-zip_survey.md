# 과거 JuProvider 소스 ZIP 조사 — 재사용 가능 기능 (ChatGPT 구조 검토용)

- 일시: 2026-10-30 (PC-A `DESKTOP-CE5BGKK`). **조사만**: 소스 수정·복사·병합·DB 변경·제품 commit 없음
- 압축 해제 위치: Claude 클라우드 작업공간의 별도 임시 폴더(PC-A workspace에 풀지 않음). 실행·빌드하지 않음
- 비교 기준: 현재 main `fce5048`, 로컬 통합 브랜치 `feature/integration-1` @ `14d1ab9`

## 1. 발견한 ZIP
| 항목 | 값 |
|---|---|
| 경로 | `C:\MyData\MyDev\backup\juprovider-backup.zip` |
| 수정일 | 2026-10-16 11:38 |
| 크기 | 3,862,832 bytes (압축 해제 15.2MB, 823개 파일) |
| 내부 날짜 | 10-14 628개, 10-15 47개, 10-16 131개 |
| 내부 안내 | `FINAL_README.txt` "JuProvider FINAL SOURCE - 2026-10-13" |

- 검색 범위: `C:\MyData\MyDev`(backup, dbbackup, workspace, workspace\_archive) — **ZIP은 이 1개뿐**. `Downloads`, `Documents` 등 연결되지 않은 폴더는 검색하지 못함(필요 시 폴더 접근 승인 후 추가 확인).
- 같은 폴더의 `.sql` 백업 4개는 DB 덤프(소스 아님).

### 내부 구조
| 폴더 | 내용 | 규모 |
|---|---|---|
| `juprovider.backend` | Spring Boot **2.7.18**, Java 17, JPA + JdbcTemplate | Java 114개 |
| `juprovider.frontvue` | Vue 화면 28개 (회사·제품·사이트·부서·실험·데이터 등) | 약 3,000줄 |
| `juprovider.frontreact` | React 화면 (Vue와 같은 기능 일부) | 약 1,100줄 |
| `desktop` | .NET **9** WinForms: client + service 7개(devicemanager, protocolmanager, datamanager, experimentmanager, viewer, designer, updater) + lib 9개 + control 2개 | C# 약 12,400줄 |
| `desktop/resource` | 아이콘·이미지 307개 | |
| `desktop/app` | `config\juprovider.accdb`, `project\sample.jup`, 컨트롤 DLL 2개 | 빌드 결과 일부 |
| `deploy` | 최종 DB SQL(10-10, 10-14, 10-15), APPLY SQL 3개, Tomcat 배포·릴리스 등록 스크립트 | |

## 2. 검증 상태 (과거 소스 전체)
| 확인 | 결과 |
|---|---|
| Vue 빌드 | **실패 기록**: `juprovider.frontvue/build-error.txt` = `MISSING_EXPORT "languageApi" is not exported by src/services/api.js`. `App.vue`·`Home.vue`·`Product.vue` 0바이트 |
| Desktop 빌드 | ZIP에 빌드 결과 없음(README 명시). `build-all.bat` 있으나 README가 말하는 `build-distribution.ps1` **없음**. 대상 .NET 9 (현재 10) |
| Backend 빌드 | 결과물 없음. Spring Boot 2.7 → 현재 3.5 (javax→jakarta, Security 설정 방식 다름) |
| DB | `JU_SITE`, `JU_DEPT`, `JU_FILE`, `JU_DEVICE_LINK` 등 **현재 baseline V2.4와 다른 스키마** (현재 원칙 "SITE/DEPT 의존 없음"과 충돌). 실험 실행 테이블은 별도 APPLY SQL |
| 보안 | `SecurityConfig` 주석 "다수의 업무 API를 permitAll()로 열어 둠". Client 동기화가 `clientId=Environment.MachineName` (키 인증 없음) |
| 비밀 값 | `application.yml`에 **DB·메일 비밀번호 기본값이 평문으로 들어 있음**(값은 이 문서에 쓰지 않음). 메일 계정 비밀번호가 실제 값이면 **변경 권장**. 이 파일은 공개 저장소에 올리면 안 됨 |
| 로컬 DB 파일 | `desktop/app/config/juprovider.accdb` — 사용자·데이터가 들어 있을 수 있어 **template 용도로 재사용 금지**(열어 보지 않음) |
| 실행·테스트 | 이번 조사에서 실행 안 함. 과거 테스트 코드 없음 → **모든 과거 기능은 "구현 존재"만 확인, "정상 동작"은 미검증** |

## 3. 기능별 비교

판정: **유지**(현재 것을 그대로) / **참조 후 재작성**(과거 로직을 보고 현재 구조로 새로 작성) / **재개발**(과거 코드 사용 안 함) / **미사용**

### 3.1 Protocol
| 항목 | 과거 소스 | 현재 소스 | 재사용 가능성 |
|---|---|---|---|
| 구현 기능 | 프로토콜 그룹·항목 CRUD, 상세(패킷) 편집, 다음 코드 발급, 수식 파싱 API / Desktop 프로토콜 관리 화면·테스트 전송 / 바이트 수식 변환, GTEC 프레임 분리·파싱 | 그룹·프로토콜·패킷 CRUD (Action v1, 논리삭제·참조 409), Web 화면 | 관리 CRUD: **유지(현재)**. 송수신·파싱: **참조 후 재작성** |
| 코드 근거 | backend `ProtocolController`(`/api/protocols/groups…`, `/parse`), `ProtocolService`, `ProtocolExpressionParser` / desktop `lib.protocol/ProtocolExpression.ToBytes·ToDisplay·Hex`, `GtecProtocolParser.ExtractFrames·TryParse·TryParseSensorInfo`(ParseRule Channels/Samples), `ProtocolEngine.FromJson·Parse`, `service.protocolmanager/MainForm·ProtocolLocalStore·TestTransport` | `core/protocol/service/ProtocolService`, `action/ProtocolContracts`, `ProtocolMapper.xml`, Vue `views/device/ProtocolManagement.vue` (통합 브랜치). Desktop `lib.protocol/Class1.cs` 빈 파일 | 파서·수식 변환은 순수 함수(약 250줄)라 단위 테스트로 검증하기 쉬움 |
| 정보·제어·데이터 구분 | 공통코드 PROT(폴링/제어/TX·RX)와 응답 프로토콜 지정 | PTL_TYPE PROT 코드, 패킷 `responsePtlCd`·`parseRule` 필드 있음 | 실행 엔진이 없어 필드만 있음 |
| 검증 상태 | 미검증(빌드·실행 기록 없음) | PC-A·PC-B 빌드·테스트·smoke·브라우저 PASS | 이식 시 실제 장비(GTEC) 또는 가상 장치로 검증 필요 |
| 변경 영향 | — | Desktop Terminal에 파서 추가 → 서버 계약 영향 없음 | `parseRule` 텍스트 형식을 계약으로 확정해야 함 |

### 3.2 Device
| 항목 | 과거 소스 | 현재 소스 | 재사용 가능성 |
|---|---|---|---|
| 구현 기능 | TCP·Serial·가상(ScLogger)·Echo 연결, 재연결(3회), 송수신 트래픽 기록, Serial 단순 테스트 창, Gateway 설정(host/port/최대 클라이언트), 장치 편집(Serial/Network JSON), 장치-프로토콜 연결 설정, 개발용 예제 장치 생성 | 서버: 장치 조회 Action(SEARCH/GET), Client 동기화 GET. Desktop: 가상 장치 런타임만, IPC로 Terminal 전달 | 연결 계층: **참조 후 재작성**. 장치 편집 UI: **재개발**(Web) |
| 코드 근거 | `service.devicemanager/DeviceConnectionManager`(`TcpConnection`, `SerialConnection`, `ScLoggerVirtualConnection`, `EchoConnection`, `RetryExchangeAsync`, `QuickReconnectAttempts=3`), `SerialPortTestDialog`, `DeviceEditDialog.BuildSerialJson·BuildNetworkJson·IsGatewayDevice`, `DeviceTrafficSessionStore`, `DevelopmentExampleSeeder`; backend `DeviceController`, `DeviceProtocolSettingController`, `DeviceLinkController` | `core/device/*`, `DeviceSyncController`(SEC-S1 GET만), Vue `DeviceManagement.vue`(조회), Desktop `juprovider.terminal/Runtime/DeviceRuntimeManager·VirtualDeviceRuntime`, `lib.device/Models/DeviceSyncModel` | Serial/TCP·재연결 로직은 Terminal 런타임에 가장 큰 재사용 가치 |
| 다중 장치·연결 테스트 | 장치별 연결 관리, 테스트 Pipe(`ProtocolTestPipeServer`) | 다중 가상 장치 동기화만 | |
| 검증 상태 | 미검증 | 가상 장치·동기화 PASS | 실제 COM 포트·Gateway 장비로 검증 필요 |
| 변경 영향 | — | **PC별 연결값(COM 포트 등)은 SYSINFO-01 결정대로 로컬 override** — 과거처럼 공통 장치 정의(`DEV_CONFIG`)에 넣지 않음 | 장치 CREATE/UPDATE는 관리자 Action으로 (SEC-S1 원칙) |

### 3.3 Data (채널·데이터 그룹·매핑)
| 항목 | 과거 소스 | 현재 소스 | 재사용 가능성 |
|---|---|---|---|
| 구현 기능 | 데이터 그룹·태그 설정 화면(Web·Desktop), 채널 카탈로그, 수집값→태그 매핑(ProtocolTag Index/Scale/Offset/Unit) | 테이블(`ju_data_group`, `ju_data_tag`)과 레거시 조회 API만, 화면·Action 없음 | **참조 후 재작성** (Protocol과 같은 Action 패턴) |
| 코드 근거 | backend `ExperimentDataSettingController/Service`; Vue `DataGroupSetting.vue`; desktop `service.datamanager/MainForm·DataLocalStore·EditDialogs`, `lib.project/DataCatalog`, `ProtocolEngine.ProtocolTag` | `CoreController` `/api/core/data-groups`, `/data-tags/{grp}`, baseline 테이블 | Scale/Offset/Unit 매핑 규칙은 재사용 가치 있음 |
| 검증 상태 | 미검증 | 조회만, 화면 검증 없음 | |

### 3.4 Experiment
| 항목 | 과거 소스 | 현재 소스 | 재사용 가능성 |
|---|---|---|---|
| 구현 기능 | 실험 생성·수정·삭제, 데이터 그룹 선택, 시작·일시정지·중지 명령 큐(중복 방지, STOP이 대기 명령 취소), Client 명령 조회·응답(ack), 실행(Run) 기록, 설정 이력 | 테이블(`ju_experiment`(+detail/data_group), `ju_experiment_run`, `ju_experiment_command`)과 레거시 조회만 | 명령 큐 규칙: **참조 후 재작성**. 화면: **재개발** |
| 코드 근거 | backend `ExperimentController`(CRUD), `ExperimentManageController` `/start·/pause·/stop`, `/client/commands`, `/client/commands/{id}/ack`, `ExperimentManageService`(START/PAUSE/STOP 검증, 취소 규칙), `ExperimentSnapshotService`; Vue `ExperimentCreate·ExperimentManage·ExperimentSettingHistory.vue`; desktop `service.experimentmanager/*`, `viewer/ExperimentProtocolCommandClient.SendExperimentAsync·SendAsync` | `CoreController` `/experiments`, `/experiment-runs`; 테이블 PK에 CLIENT_ID 있음 | 현재 테이블이 과거 설계에서 왔으므로 개념 일치. 명령 전달은 Client 키 체인으로 다시 설계 필요 |
| 검증 상태 | 미검증 | 없음 | 서버↔Client 명령 왕복 시나리오 테스트 필요 |
| 변경 영향 | 과거 Client 경로는 permitAll | Client 경로는 키 인증 + GET 위주(SEC-S1) | 쓰기(ack·업로드)는 `/api/client/**` 신규 계약 필요 → SYNC-01 범위 |

### 3.5 Experiment Data (수집·저장·이력)
| 항목 | 과거 소스 | 현재 소스 | 재사용 가능성 |
|---|---|---|---|
| 구현 기능 | 실시간 값 버스(일자별 `.jsonl` 파일 누적), 서버 일괄 전송, 로컬 Access 저장(LOCAL_EXPERIMENT_DATA, LOCAL_RUNTIME_DATA), 미전송 큐(LOCAL_SYNC_OUTBOX), 실험 데이터·Run·오류로그·감사 일괄 동기화, 데이터 조회 화면, **Excel(xlsx) 내보내기(외부 라이브러리 없이)** | 서버 테이블(`ju_runtime_data`, `ju_experiment_data`, `ju_client_*` 멱등 키)만, 업로드 API 없음. 로컬 LOCAL_SYNC_STATE 미사용 | 버스·Outbox·일괄 전송: **참조 후 재작성**. Excel 내보내기: **수정 후 재사용 후보** |
| 코드 근거 | `lib.data/RuntimeDataBus.PublishAsync·ReadRecent`, `ServerDataSender.SendAsync`, `juprovider.client/Sync/ExperimentDataSynchronizer·ExperimentRunSynchronizer·ErrorLogSynchronizer·ClientAuditSynchronizer`, `Storage/ExperimentLocalStore·LocalErrorLogStore`, `LocalAccessStore`(LOCAL_SYNC_OUTBOX 등 약 30개 테이블); backend `ClientSyncController` `/api/client-sync/experiment-data/batch` 등, `RuntimeDataController` `/api/runtime-data/batch`; `ExperimentExcelExporter.Write` | baseline `ju_client_sync_receipt`·`ju_client_audit_hist`·`ju_client_error_log` (`CLIENT_ID+LOCAL_*_ID` UNIQUE) | 현재 테이블 설계가 과거 Outbox 방식과 맞음 → 업로드 계약만 새로 정하면 됨 |
| 검증 상태 | 미검증 | 없음 | 대량 데이터·중복 전송·오프라인 누적 시험 필요 |

### 3.6 Viewer / Designer
| 항목 | 과거 소스 | 현재 소스 | 재사용 가능성 |
|---|---|---|---|
| 구현 기능 | 화면 설계기(도구상자, 끌어 놓기·크기 조절, 속성창, 사용자 컨트롤 DLL 불러오기), 채널 선택(바인딩), 프로젝트 파일 `.jup`(JSON) 저장, Viewer(설계 화면 실행, 실시간 값 반영, 그래프, 실험 선택·시작/중지, 설계 파일 변경 감지 후 다시 불러오기), 기본 위젯(Label, Numeric, LED, Gauge, Graph, Grid), 리본 UI | 없음 (Directory.Build.props에 `control\` 출력 경로만) | 모델·위젯: **참조 후 재작성**. Designer 최종 목표(Screen/Component/Event/Binding, Draft/Publish)의 **가장 큰 참고 자료** |
| 코드 근거 | `lib.project/Models.cs` `JuProjectDefinition·JuControlDefinition·JuChannelBinding·JuProjectFile.SaveAsync`; `lib.controls/Designer/DesignerControls`(`ISingleChannelWidget`, `IMultiChannelWidget`, `GaugeControl`, `GraphControl`, `DesignerGrid`), `Ribbon/RibbonMainForm`; `service.designer/MainForm·ChannelPickerDialog·ControlLibraryDialog·DesignerPropertyView`; `service.viewer/MainForm`(`RefreshLiveData`, `ApplySingle/ApplyMulti`, `WatchDesignFile`, `RuntimeGraph`); `control.basic/BasicControls`, `app/project/sample.jup` | — | 과거 바인딩은 "채널" 단위. 현재 결정(AC: Designer는 Action Contract 필드에 Binding)과 맞추려면 바인딩 대상을 재정의해야 함 |
| 검증 상태 | 미검증 | — | |

### 3.7 공통
| 항목 | 과거 소스 | 현재 소스 | 재사용 가능성 |
|---|---|---|---|
| 인증·권한 | 사용자 로그인·인증번호(메일), 권한·메뉴·부서·사이트 관리, 다수 API permitAll, Desktop 로그인 `/api/client/auth/login` | JWT + `/auth/me` + 메뉴 권한 비트 + 비밀번호 변경 강제, Client 키 인증, 오프라인 로그인(PBKDF2·잠금) | **유지(현재)**. 과거 인증 **미사용** |
| 로컬 DB | Access 약 30개 LOCAL_* 테이블, API_ENDPOINT 테이블로 서버 주소 관리 | LOCAL_USER·LOCAL_DEVICE(+미사용 LOCAL_SYNC_STATE), template 복사 방식 | 테이블 목록은 SYNC-01 설계 참고. 과거 accdb 파일 **미사용** |
| 서버 동기화 | 장치·프로토콜·데이터그룹·태그 내려받기, 실험데이터·Run·오류·감사 올리기, 설정 동기화 | 장치 내려받기만(전체) | 내려받기 범위·Outbox 방식 **참조 후 재작성** (SYNC-01) |
| IPC | 테스트용 Named Pipe(장치관리 ↔ 프로토콜 테스트), 자식 프로세스 Job 관리 | Client ↔ Terminal Named Pipe(장치 동기화·연결·상태·데이터 메시지) | **유지(현재)**. `ChildProcessJob`(자식 프로세스 정리)은 참고 |
| 배포·업데이트 | 릴리스 API(`/api/public/releases`, `/modules`), 파일 관리, Updater(전체 ZIP + 모듈 FileVersion 비교), 릴리스 등록 스크립트 | Updater 빈 화면, SYSINFO-02 계획(보류) | SYSINFO-02·Updater 단계에서 **참조 후 재작성** |
| 기타 | AI 문의(OpenAI), 회사소개·연락처·다운로드 페이지, React 프론트 | 공개 홈 최소본(WEB-02) | 홈 콘텐츠는 WEB-04 참고. AI·React는 현재 범위 아님 |

## 4. 요약
- **현재가 기준**: 인증·권한·Action Contract·Protocol CRUD·Client 키·오프라인 로그인은 현재 쪽이 더 안전하고 검증됨 → 과거 코드로 바꾸지 않음.
- **재사용 가치가 큰 것 (모두 "참조 후 재작성", 소단위)**
  1. Protocol 송수신·파싱: `ProtocolExpression`, `GtecProtocolParser`, `ProtocolEngine`
  2. Device 연결 계층: `DeviceConnectionManager`(TCP/Serial/재연결), Serial 테스트
  3. 실험 명령 큐 규칙: `ExperimentManageService`(START/PAUSE/STOP·ack·취소)
  4. 수집 데이터 파이프라인: `RuntimeDataBus`, Outbox, 일괄 동기화, xlsx 내보내기
  5. Designer/Viewer 모델과 위젯: `JuProjectDefinition`·`JuChannelBinding`, 위젯 6종
- **사용하지 않을 것**: 과거 DB 스키마(SITE/DEPT), Security(permitAll), Desktop 인증 방식, `application.yml`(평문 기본 비밀번호), `app/config/juprovider.accdb`, 빌드 실패 상태의 Vue 소스
- 과거 기능은 모두 **구현 존재만 확인, 정상 동작 미검증**.

## 5. 다음에 정할 것 (ChatGPT 구조 검토 후)
| # | 질문 |
|---|---|
| L-Q1 | 재사용 1순위를 Desktop 수집 경로(장치 연결 → 파싱 → 로컬 저장)로 할지, 서버 쪽(Data·Experiment Action)으로 할지 |
| L-Q2 | 과거 소스 동작 확인을 위해 **격리 폴더에서 빌드만** 시도할지 (.NET 9 / Spring Boot 2.7, 현재 workspace와 분리) |
| L-Q3 | 메일 계정 비밀번호 변경 여부 (과거 `application.yml`에 기본값으로 들어 있음) |
| L-Q4 | Designer 바인딩 단위: 과거 "채널" vs 현재 결정 "Action Contract 필드" — 둘 다 지원할지 |
| L-Q5 | 연결되지 않은 폴더(Downloads 등)도 추가 ZIP 검색할지 |

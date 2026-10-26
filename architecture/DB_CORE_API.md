# JuProvider / JuProject DB·Core·API 전체 아키텍처 설계 v1.2

-   작성 기준: 2026-10-25 Claude 역검토 결과
-   목적: 구현 전 DB, Core, API, Client의 책임과 SYS→JU 경계를 확정하기
    위한 설계 기준
-   상태: 설계안. 사용자 승인 및 Claude 재검토 후 구현 단계로 전환
-   최상위 원칙: **SYS(JuProject) → JU(JuProvider)는 선택적 연동이며,
    JuProvider는 SYS 없이 완전 독립 실행한다.**

------------------------------------------------------------------------

## 1. 시스템 경계

### 1.1 JuProject / SYS

JuProject는 고객·조직·계정·서비스를 관리하는 상위 시스템이다.

-   SYS DB는 `juproject` DB만 사용한다.
-   시스템 기준 테이블은 `sys_` 접두어를 사용한다.
-   내부 PK는 `BIGINT` 대리키를 기본으로 한다.
-   외부 연동에 사용할 변경되지 않는 업무키를 별도 UNIQUE로 둔다.
-   `Y/N`, lowercase snake_case, EF Migration을 기본 규칙으로 한다.
-   SYS의 bigint PK를 JU로 전달하거나 JU FK로 사용하지 않는다.

목표 논리 모델:

``` text
sys_site
  └─ sys_dept
       └─ sys_user
            └─ sys_auth
                 └─ sys_auth_menu
                      └─ sys_menu

sys_code_group
  └─ sys_code
```

추후 요구가 확인될 때만 추가:

``` text
sys_auth_action
sys_language
sys_multi_lang
고객/서비스 관리 테이블
```

### 1.2 JuProvider / JU

JuProvider는 자동화·장치·실험을 수행하는 독립 제품이다.

-   JU DB는 `juprovider` DB만 사용한다.
-   SYS DB를 직접 조회하거나 FK로 참조하지 않는다.
-   기존 `ju_` 자연키, YENO, detail, 다국어 구조는 기본적으로 유지한다.
-   기존 구조를 SYS 규칙에 맞추기 위한 대규모 PK/컬럼 재설계는 하지
    않는다.
-   Site/Dept는 현재 JU Core에 추가하지 않는다.
-   설치 위치가 필요해질 경우 SYS Site가 아닌 JU 자체 Device/Location
    개념으로 설계한다.

JU Core:

``` text
ju_sys
ju_language
ju_multi_lang

ju_com_group
ju_com_group_detail
ju_com_code
ju_com_code_detail

ju_user
ju_user_detail
ju_auth
ju_auth_detail

ju_menu
ju_menu_detail
ju_menu_action
ju_menu_action_detail
```

JU 업무 도메인:

``` text
Protocol
  ↓
Device
  ↓
Data
  ↓
Experiment
  ↓
Run / Command
  ↓
Collection / Runtime Data
  ↓
Storage
  ↓
Viewer
```

------------------------------------------------------------------------

## 2. SYS DB 설계

### 2.1 1차 핵심 테이블

#### sys_site

-   `site_id` BIGINT PK
-   `site_code` VARCHAR UNIQUE
-   `site_name`
-   `use_yn`
-   `created_at`, `created_by`
-   `updated_at`, `updated_by`

#### sys_dept

-   `dept_id` BIGINT PK
-   `site_id` FK → sys_site
-   `dept_code` VARCHAR UNIQUE
-   `dept_name`
-   `parent_dept_id` nullable self FK
-   `sort_order`
-   공통 감사 컬럼

#### sys_user

-   `user_id` BIGINT PK
-   `dept_id` nullable FK → sys_dept
-   `login_id` VARCHAR UNIQUE
-   `password_hash`
-   `user_name`
-   `auth_id` FK → sys_auth
-   `use_yn`
-   `last_login_at`
-   공통 감사 컬럼

초기 설계는 사용자 1명당 기본 부서 1개, 기본 권한 1개로 단순화한다. 다중
부서·다중 권한은 실제 요구가 생길 때 확장한다.

#### sys_auth

-   `auth_id` BIGINT PK
-   `auth_code` VARCHAR UNIQUE
-   `auth_name`
-   `sort_order`
-   `use_yn`
-   공통 감사 컬럼

#### sys_menu

-   `menu_id` BIGINT PK
-   `parent_menu_id` nullable self FK
-   `menu_code` VARCHAR UNIQUE
-   `menu_name`
-   `route_path`
-   `component_key` nullable
-   `icon_key` nullable
-   `sort_order`
-   `use_yn`
-   공통 감사 컬럼

#### sys_auth_menu

-   `auth_id` FK
-   `menu_id` FK
-   복합 UNIQUE 또는 복합 PK
-   `use_yn`
-   공통 감사 컬럼

#### sys_code_group

-   기존 `tb_code_group`의 기능을 유지하면서 `sys_` 명명으로 전환
-   `code_group_id` BIGINT PK
-   `group_code` VARCHAR UNIQUE
-   `group_name`
-   `use_yn`
-   공통 감사 컬럼

#### sys_code

-   기존 `tb_code`의 기능을 유지하면서 `sys_` 명명으로 전환
-   `code_id` BIGINT PK
-   `code_group_id` FK
-   `code`
-   `code_name`
-   `code_value` nullable
-   `sort_order`
-   `use_yn`
-   `(code_group_id, code)` UNIQUE
-   공통 감사 컬럼

### 2.2 SYS 단계별 DB 적용

Phase SYS-0: - `tb_user` → `sys_user` - `tb_code_group` →
`sys_code_group` - `tb_code` → `sys_code` - 기존 데이터 보존 Rename
Migration - API 계약은 변경하지 않는다.

Phase SYS-1: - `sys_site` - `sys_dept` - `sys_auth` - `sys_menu` -
`sys_auth_menu` - `sys_user`에 조직/권한 FK 연결 - 기존 `role_code`를
`sys_auth` 기반으로 전환

Phase SYS-2: - 고객/서비스 관리 요구 확정 후 확장 - `sys_auth_action`,
다국어는 실제 화면 요구가 있을 때만 추가

------------------------------------------------------------------------

## 3. JU DB 설계

### 3.1 유지 원칙

다음 기존 설계는 유지한다.

-   자연키: `DEV_CD`, `PTL_CD`, `GRP_CD` 등
-   `YENO0001 / YENO0002` 기반 사용 여부
-   `_detail` 분리
-   `*_NM_KEY + ju_multi_lang` 다국어
-   Protocol/Device/Data/Experiment 기존 테이블
-   Desktop 동기화용 코드 기반 식별

변경 대상은 규칙 자체가 아니라 현재 규칙을 위반한 데이터와 누락 구조다.

### 3.2 JU 설치 완결성

신규 설치만으로 JU가 실행되어야 한다.

반드시 baseline/seed에 포함: - `ju_menu_action` -
`ju_menu_action_detail` - 정상적인 Menu/Action seed - 정상적인
Protocol/Device type code - 현재 Runtime과 일치하는 `DOTNET_VERSION`

정리 대상: - JU에서 고객 조직 의미의 Site/Dept 메뉴/코드는 제거 후보 -
단, `site/locations`가 장치 설치 위치 의미였다면 Device 단계에서 별도 JU
Location 개념으로 재설계

### 3.3 JU 권한 모델

권장안:

``` text
ju_user
   │
   └─ AUTH_ID
       ↓
ju_auth
   ├─ ju_auth_menu
   └─ ju_auth_action

ju_menu
   └─ ju_menu_action
```

`AUTH_ATTR` JSON은 기존 데이터 migration 기간의 호환 입력으로만
사용하고, 최종 권한의 Source of Truth는 관계 테이블로 전환하는 것을
권장한다.

#### ju_auth_menu

-   `AUTH_ID`
-   `MNU_ID` 또는 현재 menu PK
-   `USE_YN`
-   기존 JU 키 규칙에 맞춤

#### ju_auth_action

-   `AUTH_ID`
-   `MNU_ID`
-   `ACT_CD`
-   `USE_YN`

이 구조로 메뉴 표시 권한과 실제 Action 실행 권한을 분리한다.

### 3.4 실행자 기록

인증 이후 다음 업무에는 실행자를 남긴다.

-   Experiment Run 생성
-   Start / Pause / Stop
-   Experiment Command
-   주요 기준정보 변경

기존 `CLIENT_ID`, `RUN_SOURCE`는 실행 채널/클라이언트 정보로 유지하고,
사용자 실행은 별도 `USER_ID` 또는 JU 사용자 업무키로 기록한다.

------------------------------------------------------------------------

## 4. Core / API 책임 분리

### 4.1 JuProvider

``` text
Vue Web
   │
   │ HTTP + User JWT
   ▼
juprovider.backend
   ├─ Spring Security
   ├─ Auth API
   ├─ REST Controller
   ├─ API DTO / Validation
   └─ HTTP ↔ Core 변환
          │
          ▼
juprovider.core
   ├─ Domain Model
   ├─ Service / Use Case
   ├─ Mapper / Repository
   ├─ ActionRegistry
   ├─ DynamicActionService
   ├─ Permission Service
   ├─ Protocol / Device / Data / Experiment Logic
   ├─ Redis Cache Adapter
   └─ MariaDB Access
          │
          ▼
      juprovider DB
```

원칙: - `core`는 HTTP, Controller, Vue를 알지 않는다. - `backend`는
SQL을 직접 소유하지 않고 Core 서비스를 호출한다. - 업무 규칙은 Core에
둔다. - 인증 토큰 해석은 Backend가 담당한다. - 인증된 사용자/Client의
식별정보를 Core의 실행 Context로 전달한다. - Dynamic Action의 실제 권한
검사는 Core의 Permission Service를 통해 수행한다.

### 4.2 JuProject

현재 .NET 계층 구조를 유지한다.

``` text
React
  │
  │ HTTP + JWT
  ▼
JuProject.Api
  ├─ Authentication / Authorization
  ├─ Controller / Endpoint
  └─ API Contract
        │
        ▼
JuProject.Application
  ├─ Use Case
  ├─ DTO
  └─ Application Service
        │
        ▼
JuProject.Domain
  ├─ Entity
  └─ Domain Rule
        ▲
        │
JuProject.Infrastructure
  ├─ EF Core DbContext
  ├─ Repository
  └─ MariaDB
```

원칙: - API는 Application을 통해 업무를 수행한다. - Domain은 EF/HTTP에
종속되지 않는다. - Infrastructure가 DB 구현을 담당한다. - `sys_*`
테이블명은 Infrastructure Configuration에서 매핑한다.

------------------------------------------------------------------------

## 5. 인증 아키텍처

### 5.1 JU Web 사용자

``` text
POST /api/auth/login
  ↓
ju_user + ju_auth 검증
  ↓
JWT Access Token
  ↓
GET /api/auth/me
  ↓
권한 기반 Menu Tree
  ↓
Vue Router / Menu
  ↓
Menu Action Permission
```

공개 경로 후보: - `/api/auth/login` - `/api/health` - 정적 Vue 파일

나머지 API는 기본 인증 필요로 전환한다.

### 5.2 JU Desktop Client

Desktop과 사용자는 인증 목적이 다르므로 분리한다.

``` text
Desktop Client Identity
  ├─ CLIENT_ID
  └─ Client Credential
        ↓
Client Authentication
        ↓
sync / upload / audit / error API
```

사용자 작업이 필요한 경우:

``` text
Desktop Client 인증
        +
JU User 로그인/Offline Token
        ↓
실행 사용자 + 실행 Client를 함께 기록
```

즉: - Client 인증 = "어느 프로그램/설치본이 요청했는가" - User 인증 =
"누가 작업했는가"

로 분리한다.

### 5.3 JU Offline

단계적으로 완성한다.

1.  서버 장애 시 Local Device 사용 --- 기존 구현 유지
2.  `LOCAL_USER.OFFLINE_TOKEN` 기반 오프라인 사용자 인증
3.  로컬 Audit/Error/Collection 저장
4.  서버 복구 후 Sync Receipt 기반 재전송/확인

실험 데이터까지 Offline 수집할지는 별도 사용자 결정 후 구현한다.

------------------------------------------------------------------------

## 6. Menu / Action / API 연결

JU의 동적 Action 구조를 중심으로 통일한다.

``` text
Menu
  ↓
Menu Action
  ↓
Permission Check
  ↓
HANDLER_ID
  ↓
ActionRegistry
  ↓
Handler
  ↓
Core Service
```

기준정보 화면: - SEARCH - GET - CREATE - UPDATE - DELETE(logical)

실험 화면: - CREATE_RUN - START - PAUSE - STOP - VIEW - EXPORT

직접 REST 조회 API도 최소한 로그인은 필수로 한다. 변경/실행 API는
메뉴·액션 권한을 반드시 검사한다.

------------------------------------------------------------------------

## 7. Protocol → Device → Data → Experiment 처리 아키텍처

``` text
Protocol Definition
   ↓
Protocol Packet / RX / TX / POLLING
   ↓
Device Configuration
   ↓
Communication Adapter
   ├─ Virtual
   ├─ Serial
   └─ Network
   ↓
Raw Receive
   ↓
Protocol Parser
   ↓
Data Tag Mapping
   ↓
DATA_RECEIVED Event
   ↓
Runtime Data
   ↓
Experiment Run
   ↓
Experiment Data / File
   ↓
Viewer
```

Core가 Protocol/Device/Data/Experiment 규칙을 담당한다.

Desktop은: - 장치 연결 - 실제 통신 - 실시간 수집 - 로컬 기록 - Viewer

를 담당할 수 있다.

Backend는: - 기준정보 - 권한 - 동기화 - 중앙 저장 - Web 조회

를 담당한다.

실제 실험 실행 위치가 Desktop인지 Server인지 각 Experiment 단계 설계 시
확정한다.

------------------------------------------------------------------------

## 8. SYS → JU 연동 아키텍처

지금은 구현하지 않는다.

원칙:

``` text
SYS DB
  ↓
JuProject Application/API
  ↓
Business Key DTO
  ↓
Authenticated Integration API
  ↓
JU Integration Adapter
  ↓
JU Local Copy / Mapping
```

금지: - JU가 SYS DB 직접 조회 - SYS bigint PK를 JU FK로 저장 - JU 실행이
SYS 가용성에 의존 - JU Core 테이블에 `sys_*` FK 추가

향후 최소 후보: - `ju_sys.INSTANCE_CD` - 필요 시 `ju_ext_map` - 업무키
기반 mapping - 마지막 동기화 값 유지

SYS 연결 장애 시 JU는 마지막 정상 동기화 데이터로 계속 실행한다.

------------------------------------------------------------------------

## 9. 구현 절차

### Track A --- JU 독립 실행 기반

Phase JU-0 설치 완결성 - menu_action baseline/seed - seed 오류 정리 -
초기 관리자 생성 방식 확정

Phase JU-1 인증/권한 - JWT - `/me` - SecurityConfig - ju_auth_menu /
ju_auth_action - 권한별 Menu Tree - DynamicAction 권한 검사 - Vue
login/router guard - Desktop client 인증 설계

Phase JU-2 Protocol - Protocol CRUD - Packet/RX/TX/POLLING 정의 -
공통코드 정합성

Phase JU-3 Device - Device CRUD - Virtual/Serial/Network - Connection
Test - Client Sync

Phase JU-4 Data - Data Group/Tag CRUD - Parser - Runtime Data

Phase JU-5 Experiment - Experiment CRUD - Run 생성 - Start/Pause/Stop -
실행자 기록

Phase JU-6 Storage/Viewer - Experiment Data - File Recording - History -
Viewer/Graph - Export - Offline Sync 범위 확정 및 구현

### Track B --- SYS

Phase SYS-0 명명 정리 - tb\_\* → sys\_\* - 데이터 보존 migration

Phase SYS-1 조직/권한/메뉴 - Site - Dept - Auth - Menu - Auth Menu -
User 연결

Phase SYS-2 고객/서비스 - 실제 요구를 확인한 뒤 설계

### Track C --- SYS→JU Integration

SYS-1과 JU-1 이후 별도 설계한다. JU 독립 실행을 훼손하지 않는 것이 통과
조건이다.

------------------------------------------------------------------------

## 10. 구현 전 결정 Gate

다음은 구현 전에 사용자 결정을 받는다.

1.  JU Site/Dept 과거 메뉴의 실제 의미
2.  JU 권한을 관계 테이블(`ju_auth_menu`, `ju_auth_action`)로 전환할지
3.  JU Web 인증을 JWT로 확정할지
4.  Desktop client credential 방식
5.  JU 초기 관리자 생성 방식
6.  Desktop Offline 실험 수집 범위
7.  SYS-0과 SYS-1을 한 번에 구현할지 단계적으로 할지

------------------------------------------------------------------------

## 11. 설계 변경 통제

-   DB 구조 변경은 설계 문서 → Claude 영향 검토 → 사용자 승인 →
    migration/baseline 순서로 한다.
-   API 계약 변경도 같은 절차를 따른다.
-   미사용 테이블은 코드 참조가 없다는 이유만으로 삭제하지 않는다.
-   JU의 기존 37개 테이블은 각 도메인 Phase에서 역할을 확인한 뒤
    유지/변경/폐기를 결정한다.
-   Jenkins 성공을 각 구현 단계의 최종 빌드 기준으로 한다.

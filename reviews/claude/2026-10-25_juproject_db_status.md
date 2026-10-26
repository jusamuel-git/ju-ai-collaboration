# juproject DB 현재 상태 조사 (2026-10-25, Claude)

ChatGPT DB 설계용 기초 자료. 근거는 GitHub `main`(`98a94f0`)의 실제 코드와 노트북에 복원된 실제 DB.
설계 판단은 넣지 않고 사실과 관찰만 적음.

---

## 1. 실제 DB (노트북 복원본)

- 위치: MariaDB 10.6.16, `C:\Program Files\MariaDB 10.6\data\juproject`
- 테이블 4개: `tb_user`, `tb_code_group`, `tb_code`, `__EFMigrationsHistory`
- 코드의 EF 모델(3개 엔티티)과 테이블 구성이 일치함
- 적용된 마이그레이션: `20261022081635_InitialCreate` 1개 (EF ProductVersion 9.0.21)
- 행 수(데이터)는 SQL 조회 수단이 없어 확인하지 못함 (각 테이블 파일 크기 80~98KB로 소량으로 보임)

## 2. 테이블 정의

### tb_user (엔티티 `User`)
| 컬럼 | 타입 | NULL | 비고 |
|---|---|---|---|
| user_id | bigint AUTO_INCREMENT | N | PK |
| login_id | varchar(50) | N | UNIQUE `uk_user_login_id` |
| password_hash | varchar(255) | N | ASP.NET Core PasswordHasher |
| user_name | varchar(100) | N | |
| email | varchar(200) | Y | |
| phone | varchar(30) | Y | |
| role_code | varchar(30) | N | 값은 코드 상수 `ADMIN` / `USER` (`Domain/Common/Roles.cs`). 공통코드 테이블과 연결 안 됨 |
| last_login_at | datetime(6) | Y | 로그인 성공 시 UTC로 갱신 |
| use_yn | char(1) | N | 기본 'Y' |
| created_at | datetime(6) | N | |
| updated_at | datetime(6) | Y | |

### tb_code_group (엔티티 `CodeGroup`)
| 컬럼 | 타입 | NULL | 비고 |
|---|---|---|---|
| code_group_id | bigint AUTO_INCREMENT | N | PK |
| group_code | varchar(50) | N | UNIQUE `uk_code_group_code`. 입력 규칙 `^[A-Z0-9_]+$`, 생성 후 수정 불가 |
| group_name | varchar(100) | N | |
| description | varchar(500) | Y | |
| sort_order | int | N | |
| use_yn / created_at / updated_at | | | 공통 컬럼 |

### tb_code (엔티티 `CommonCode`)
| 컬럼 | 타입 | NULL | 비고 |
|---|---|---|---|
| code_id | bigint AUTO_INCREMENT | N | PK |
| code_group_id | bigint | N | FK `fk_code_group` → tb_code_group, ON DELETE RESTRICT |
| code | varchar(50) | N | UNIQUE `uk_code` (code_group_id, code). 생성 후 수정 불가 |
| code_name | varchar(100) | N | |
| description | varchar(500) | Y | |
| sort_order | int | N | INDEX `ix_code_group_sort` (code_group_id, sort_order) |
| use_yn / created_at / updated_at | | | 공통 컬럼 |

전체: charset `utf8mb4`, collation `utf8mb4_unicode_ci` (모든 테이블·문자 컬럼)

## 3. 현재 적용된 설계 규칙 (코드에서 확인)

| 규칙 | 내용 | 근거 |
|---|---|---|
| 테이블 이름 | `tb_` 접두어 + snake_case 소문자 | `Persistence/Configurations/*.cs` |
| PK | 대리키 `bigint AUTO_INCREMENT` (`<테이블>_id`) | 동일 |
| 업무키 | 별도 UNIQUE 인덱스 (login_id, group_code, (group, code)) | 동일 |
| 공통 컬럼 | `use_yn`, `created_at`, `updated_at` (`BaseEntity`) | `Domain/Common/BaseEntity.cs` |
| 삭제 | 논리 삭제 `use_yn='N'`. EF 전역 쿼리 필터로 기본 조회에서 제외 | `BaseEntityConfiguration.cs` |
| 재등록 | 삭제된 동일 업무키가 있으면 새 행 대신 기존 행을 복구(`Restore`) | `*Service.cs` CreateAsync |
| 일시 | `SaveChangesAsync`에서 UTC로 자동 기록. 생성자/수정자 컬럼 없음 (코드 주석: "2차 과제") | `AppDbContext.cs` |
| Y/N 값 | `char(1)` 'Y'/'N' 상수 (`YesNo.cs`) | `Domain/Common/YesNo.cs` |
| 권한 | `role_code` 문자열 + 코드 상수 2개. 권한 테이블 없음 | `Roles.cs` |
| 다국어 | 없음 (이름/설명 단일 컬럼) | — |
| FK 삭제 | RESTRICT. 코드 그룹은 활성 코드가 있으면 서비스에서 삭제 거부 | `CodeGroupService.cs` |

## 4. 스키마 변경 방식 (현재)

- EF Core Code First + Migrations (`Pomelo.EntityFrameworkCore.MySql 9.0.0`, `dotnet-ef 9.0.21`, `MariaDbServerVersion 10.6.16` 고정)
- `database/schema/01_initial_create.sql`은 마이그레이션에서 생성한 idempotent 스크립트 (`__EFMigrationsHistory` 확인 후 실행)
- 관리자 시드: Development 환경 실행 시 `DbSeeder.SeedAdminAsync`가 `admin` 계정 생성 (비밀번호는 `Seed:AdminPassword`)
- 접속 문자열·JWT 키: user-secrets (`ConnectionStrings:Default`, `Jwt:SigningKey`)

## 5. DB 변경 시 영향 범위 (계층별 파일)

| 계층 | 파일 | 영향 |
|---|---|---|
| Domain | `Entities/User.cs`, `CodeGroup.cs`, `CommonCode.cs`, `Common/BaseEntity.cs`, `YesNo.cs`, `Roles.cs` | 엔티티 속성 |
| Infrastructure | `Persistence/AppDbContext.cs`, `Configurations/*.cs`, `Migrations/*`, `DbSeeder.cs` | 테이블·컬럼 매핑, 마이그레이션 |
| Infrastructure | `Repositories/*Repository.cs` | 조회 조건(업무키, 논리 삭제) |
| Application | `*/ *Dtos.cs`, `*/ *Service.cs` | DTO 필드, 입력 검증(DataAnnotations), 업무 규칙 |
| Api | `Controllers/*Controller.cs` | 라우트 (`api/users`, `api/code-groups`, `api/code-groups/{groupCode}/codes`, `api/codes`) |
| Frontend | `src/api/types.ts`, `users.ts`, `codeGroups.ts`, `codes.ts`, `src/auth/types.ts`, `pages/*.tsx` | DTO 타입(1:1), 화면 폼 검증, `RoleCode = 'ADMIN' \| 'USER'` |
| DB 스크립트 | `database/schema/01_initial_create.sql` | 재생성 필요 |

## 6. 관찰 (설계 판단 아님)

- 목록 응답 형식이 리소스마다 다름: 사용자는 `PagedResult<T>`, 코드 그룹·코드는 배열
- 코드 목록만 그룹 코드 기반 경로(`/code-groups/{groupCode}/codes`)를 씀
- 입력 검증이 Backend(DataAnnotations)와 Frontend(폼 규칙) 두 곳에 있음
- 권한이 코드 상수라서 권한 추가 시 Backend·Frontend 코드를 함께 바꿔야 함
- Y/N이 `char(1)`이고 공통코드와 연결되지 않음

## 7. 참고: juprovider DB 규칙 (비교용)

근거: juprovider `database/baseline/01_ju_core_baseline.sql` (테이블 35개)

| 항목 | juprovider | juproject (현재) |
|---|---|---|
| 테이블 이름 | `ju_` 접두어 + 소문자 | `tb_` 접두어 + 소문자 |
| 컬럼 이름 | 대문자 약어 (`USER_ID`, `GRP_CD`, `SORT_ORD`, `USE_YN`) | snake_case 소문자 |
| 기본/표시 정보 분리 | 본 테이블 + `_detail` 테이블 (1:1, 표시명·설명·다국어 키) | 단일 테이블 |
| 사용 여부 | `varchar(8)` 공통코드 (`YENO0001`=사용, `YENO0002`=미사용) | `char(1)` 'Y'/'N' |
| 공통코드 키 | 자연키 `GRP_CD varchar(20)`, (`GRP_CD`, `COM_CD`) 복합 PK | 대리키 bigint + UNIQUE |
| 공통코드 부가 | `COM_VAL`(실제 값), `COM_ATTR`(추가 속성) | 없음 |
| 다국어 | `*_NM_KEY`, `*_DESC_KEY` + `ju_multi_lang` | 없음 |
| 권한 | `ju_auth`(+detail), 사용자 → `AUTH_ID` FK, 권한 JSON(`AUTH_ATTR`) | `role_code` 문자열 |
| 사용자 부가정보 | `ju_user_detail` (로그인 실패 횟수, 비밀번호 변경일 등) | `tb_user` 안에 일부 |
| 생성/수정 일시 | 없음 | `created_at`, `updated_at` |
| collation | `utf8mb4_general_ci` | `utf8mb4_unicode_ci` |
| 스키마 관리 | SQL baseline/seed/migration (MyBatis·JPA) | EF Core Migrations |

## 7-1. 사용자가 다른 대화에서 진행한 설계 메모 (화면 캡처로 확인한 부분만)

- "리소스 정의를 단일 원천(Single Source of Truth)으로": Resource 정의(C# 1개 파일)에 라우트, 업무키, 권한, DTO+속성(검증·표시·검색)을 모으는 개념
- 같은 화면에서 6장의 불일치 3가지(목록 응답 형식, 코드 목록 특수 주소, 검증 이중화)가 지적됨
- 전체 내용은 이 조사에 포함되지 않음 — 원문은 해당 대화 참고

## 8. ChatGPT 설계 시 결정이 필요한 항목 (체크리스트)

1. 명명 규칙: juprovider 방식으로 통일할지, juproject 현재 방식 유지할지
2. 키 전략: 대리키(bigint) / 자연키(코드) / 혼합
3. 사용 여부: `char(1)` Y/N 유지 / juprovider식 공통코드(`YENO`)
4. 기본·표시 정보 분리(`_detail`)와 다국어 키 도입 여부
5. 권한 모델: `role_code` 유지 / 권한 테이블(메뉴·기능 권한) 도입
6. 감사 컬럼: 생성자·수정자 추가 여부, 일시 기준(UTC 유지 여부)
7. 공통코드 확장 컬럼(`COM_VAL`, `COM_ATTR` 같은) 필요 여부
8. 기존 데이터 처리: 마이그레이션으로 변환 / 새 스키마로 재생성 (현재 마이그레이션 1개, 데이터 소량으로 보임)
9. 스키마 관리 방식: EF Migrations 유지 / SQL baseline 병행
10. 7-1의 "리소스 정의 단일 원천" 개념을 DB 설계 범위에 포함할지 (API·화면까지 영향)

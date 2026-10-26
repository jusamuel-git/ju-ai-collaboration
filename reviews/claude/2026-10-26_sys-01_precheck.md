# SYS-01 사전 역검토 (Claude, 2026-10-26 15:25)

**결론: stash 코드는 현재 `main`에 충돌 없이 재사용 가능. 단 EF migration은 stash에 없음(미생성) → 수작업 staged migration을 새로 작성해야 함. 수정 필요 1건(#9-a).**
실제 DB는 읽기 전용 조회만 했다 (변경 없음).

## 1. 현재 실제 juproject DB (PC-A, MariaDB 10.6.16)
| 테이블 | 행 | 비고 |
|---|---|---|
| `tb_user` | 3 | `role_code` ADMIN 1 / USER 2, 모두 `use_yn=Y`. 그 외 값 **없음** |
| `tb_code_group` | 2 | `TEST_566048`, `USE_STATUS` |
| `tb_code` | 4 | 모두 `use_yn=N`, 고아 0 |
| `__efmigrationshistory` | 1 | `20261022081635_InitialCreate` (EF 9.0.21) |

- 키/인덱스: PK는 MariaDB에서 모두 `PRIMARY`. `uk_user_login_id`, `uk_code_group_code`, `uk_code`, `ix_code_group_sort`, FK `fk_code_group`(tb_code→tb_code_group) — 이름이 테이블명과 무관해 rename 후에도 유지된다.
- 컬럼: 감사 컬럼은 `created_at`/`updated_at`만. 테이블 collation `utf8mb4_unicode_ci`.

## 2. stash(`feature/sys-core-schema`) ↔ 현재 main
- stash 기준 `98a94f0` 이후 main 변경은 ENV-0(`AI_COLLABORATION.md`, `CLAUDE.md`, `global.json`)뿐. **backend/frontend 변경 없음 → 코드 충돌 없음**.
- 재사용: Domain(`Site`, `Dept`, `Authority`, `Menu`, `AuthorityMenu`, `User.AuthId/DeptId`, `BaseEntity.CreatedBy/UpdatedBy`, `CommonCode.CodeValue`), Configurations(`ToTable("sys_*")`), `ICurrentUser`/`HttpCurrentUser`, `AuthorityRepository`, `UserService`/`AuthService`/`JwtTokenService`/`UserRepository`/`DbSeeder` 수정
- **제외**: stash의 `AI_COLLABORATION.md` 변경(ENV-0로 대체)
- **없음**: EF migration (노트북 user-secrets 부재로 미생성). 새로 작성

## 3~6. Migration 설계 (새로 작성할 `SysCoreSchema`, 수작업 편집)
EF 자동 생성은 `role_code` DropColumn + `auth_id` AddColumn(NOT NULL)이 되어 데이터가 사라진다 → 아래 순서로 직접 편집한다.

**Up**
1. `RenameTable` tb_code_group→sys_code_group, tb_code→sys_code, tb_user→sys_user (Drop/Create 금지. EF가 만드는 `DropPrimaryKey/AddPrimaryKey(PK_tb_*)`는 MariaDB에서 의미 없으므로 제거)
2. `CreateTable` sys_site, sys_dept, sys_auth, sys_menu, sys_auth_menu
3. sys_auth 시드 `ADMIN`, `USER` (auth_code 기준)
4. `AddColumn` sys_user.auth_id **bigint NULL**, dept_id NULL / 세 테이블 created_by·updated_by NULL / sys_code.code_value NULL
5. `UPDATE sys_user u JOIN sys_auth a ON a.auth_code = u.role_code SET u.auth_id = a.auth_id`
6. **NULL 검증**: `auth_id IS NULL`이 있으면 `SIGNAL SQLSTATE '45000'`로 중단 (MariaDB `BEGIN NOT ATOMIC … END`)
7. `AlterColumn` auth_id NOT NULL → FK `fk_user_auth`, `fk_user_dept` (Restrict) + 인덱스
8. `DropColumn` role_code (**파괴적 단계는 마지막**)
9. 초기 메뉴 4개 + ADMIN/USER 권한-메뉴 매핑

**Down** (역순, 데이터 복원)
1. 메뉴·매핑 삭제 → 2. `role_code varchar(30) NULL` 추가 → 3. `UPDATE … SET role_code = a.auth_code` → 4. NULL 검증 → NOT NULL → 5. FK·auth_id·dept_id·감사 컬럼·code_value 삭제 → 6. 새 테이블 Drop → 7. `RenameTable` sys_*→tb_*
- 복원 범위: 기존 3개 테이블 행·`role_code` 값 완전 복원. SYS-01에서 새로 생긴 데이터(dept/menu/감사 사용자 값)는 Down 시 사라짐(의도).
- **주의: MariaDB DDL은 트랜잭션이 안 된다.** 중간 실패 시 부분 적용 상태가 남는다 → 6번 검증을 파괴적 단계 앞에 두고, 실제 DB는 백업 후 실행.

## 7~8. 확인
| 항목 | stash | 판정 |
|---|---|---|
| `created_by`/`updated_by` | `long?`, `HasColumnName`만, FK 없음 | OK |
| `sys_auth_menu` | PK `auth_menu_id` + `uk_auth_menu(auth_id, menu_id)` UNIQUE | OK |

## 9. API / React 계약
- `UserDto.RoleCode`·JWT role claim은 `Authority.AuthCode`("ADMIN"/"USER")로 채움 → React(`roleCode === 'ADMIN'`, `RoleCode = 'ADMIN' | 'USER'`)와 Swagger 계약 **유지**. 요청 `roleCode`는 `sys_auth.auth_code`로 해석.
- **#9-a 수정 필요**: `BaseEntity`에 전역 필터 `UseYn == Y`가 있고 `User.AuthId`는 필수 FK다. `Include(u => u.Authority)`가 INNER JOIN + 필터가 되어, **권한이 미사용(N)이 된 사용자는 사용자 목록·상세 조회에서 사라진다** (관리자가 그 사용자를 볼 수도 고칠 수도 없음. EF 경고 10622). → 관리 조회는 `IgnoreQueryFilters()` 또는 Authority 필터 제외, 로그인에서만 권한 사용 여부 검사. 현재 데이터(모두 Y)에서는 영향 없음.
- ADMIN/USER 동작: `AdminOnly` 정책은 role claim 문자열 그대로라 변화 없음. `DbSeeder`는 sys_auth ADMIN이 없으면 예외 → migration 3번이 먼저 실행돼야 함 (기동 시 migrate 순서 확인 필요).

## 10. 검증 계획 (승인 후)
1. 로컬: Backend Release + Frontend lint/build PASS
2. **`juproject_migtest`** 생성 ← 실제 DB `mysqldump` 적재 → `dotnet ef database update SysCoreSchema` → 확인(행 수, role→auth 매핑 3건, FK/NOT NULL, `__efmigrationshistory`) → `database update InitialCreate`(Down) → 원본 덤프와 tb_* 데이터 비교 → 다시 Up (재적용 확인)
3. migtest 대상으로 API smoke: 로그인(ADMIN/USER), `/me` roleCode, 사용자 목록·생성·수정, 코드 조회, USER의 관리자 API 403
4. 실제 DB: `C:\MyData\MyDev\backup\juproject_<시각>_before_sys01.sql` 백업 → Up → 같은 확인 (별도 승인)
- 연결 문자열은 user-secrets에서 읽고 database 이름만 바꿔 쓴다 (값은 기록하지 않음)

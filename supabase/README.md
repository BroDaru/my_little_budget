# Supabase table sync v2

이 구성은 여러 기기를 동시에 사용하지 않는 단일 사용자를 대상으로 한다. Realtime 구독은 사용하지 않으며, 앱에서 데이터를 변경할 때 즉시 업로드하고 앱 시작 시 마지막 revision 이후의 변경분만 내려받는 방식이다.

## 실행 전 준비

1. Supabase Dashboard에서 대상 프로젝트를 연다.
2. `Authentication > Sign In / Providers`에서 Email 공급자가 활성화되어 있는지 확인하고, `Authentication > Users`에서 이 앱에 사용할 이메일/비밀번호 사용자를 하나 만든다.
3. Project Settings의 API Keys에서 클라이언트용 `sb_publishable_...` 키를 준비한다. Legacy `anon` 키도 동작하지만 새 설정에는 publishable key를 권장한다.
4. 앱에 URL, 키, 이메일, 비밀번호를 입력하고 `설정 저장`을 누른다. 앱은 로그인한 사용자의 refresh token만 보안 저장소에 보관하며 비밀번호는 저장하지 않는다. 이 시점의 테이블 없음 오류는 정상이다.
5. `sb_secret_...` 또는 legacy `service_role` 키는 앱에 입력하거나 저장하지 않는다. 이 키들은 RLS를 우회한다.

`auth.users`에 이메일 사용자가 정확히 1명이 아니면 SQL은 변경사항을 적용하기 전에 명확한 오류로 중단된다. 사용자 UUID를 SQL에 직접 복사할 필요는 없다. SQL이 등록된 이메일 사용자를 찾아 기존 행과 RLS 정책에 자동 적용한다. 이전 버전이 만든 익명 사용자가 남아 있어도 실행할 수 있으며, 그 익명 사용자가 소유한 기존 행은 이메일 사용자에게 이전된다.

## 스키마 설치와 기존 스키마 마이그레이션

SQL Editor의 새 쿼리 하나에 `table_sync_v2_schema.sql` 전체를 붙여넣고 한 번에 실행한다. 이 단일 스크립트가 10개 테이블 설치·마이그레이션, PostgREST 스키마 캐시 갱신, 설치 개수 확인까지 모두 처리한다. 마지막 결과의 `installed_table_count`와 `expected_table_count`가 모두 `10`이면 완료다. 별도의 `to_regclass` 또는 `NOTIFY pgrst` 쿼리를 만들 필요가 없다.

스크립트는 하나의 트랜잭션으로 동작하므로 설치 중 실패하면 변경사항이 롤백된다. 같은 프로젝트에서 다시 실행해도 기존 revision을 유지하며 누락된 설정만 보완한다.

이전의 anon 읽기 전용 스키마가 이미 설치되어 있다면 다음 작업이 자동으로 수행된다.

- 소유자가 없거나 기존 익명 Auth 사용자가 소유한 모든 행의 `owner_id`를 이메일 사용자로 이전
- 기존 모든 행에 `sync_revision` 부여
- 기존 `mlb_sync_read_anon`을 포함한 낡은 정책 제거
- `anon`과 `public`의 테이블 및 sequence 권한 제거
- authenticated 사용자 전용 SELECT, INSERT, UPDATE 정책 설치
- DELETE 권한을 부여하지 않고 soft tombstone만 사용

기존 행에 익명 사용자가 아닌 다른 이메일 사용자의 `owner_id`가 발견되면 데이터 소유권을 임의로 바꾸지 않고 전체 마이그레이션이 중단된다.

## 동기화 테이블

- `mlb_accounts`
- `mlb_categories`
- `mlb_transactions`
- `mlb_budget_groups`
- `mlb_monthly_income`
- `mlb_investments`
- `mlb_recurring_transactions`
- `mlb_transaction_presets`
- `mlb_tags`
- `mlb_calendar_events`

각 테이블은 다음 공통 열을 사용한다.

| 열 | 용도 |
| --- | --- |
| `uuid` | 기기 간 동일 엔티티를 식별하는 기본 키 |
| `payload` | 로컬 엔티티의 JSON 데이터 |
| `owner_id` | SQL 실행 당시 발견한 이메일 Auth 사용자 |
| `updated_at` | 트리거가 기록하는 서버 변경 시각 |
| `deleted_at` | 삭제된 행을 유지하는 서버 시각 tombstone |
| `sync_revision` | 서버의 모든 행 변경에 부여되는 증가 번호 |
| `sync_status` | 서버에서는 항상 `synced`로 정규화 |

`owner_id`, `updated_at`, `sync_revision`, `sync_status`는 서버 트리거가 결정한다. 클라이언트가 보낸 값은 신뢰하지 않는다.

## 보안 모델

앱은 publishable key로 `SupabaseClient`를 만들고 설정 저장 때 입력받은 이메일과 비밀번호로 `signInWithPassword()`를 호출한다. 로그인 이후 비밀번호는 폐기하고 refresh token만 운영체제 보안 저장소에 보관한다. 이 세션의 DB 요청은 `authenticated` 역할을 사용하며 인증되지 않은 `anon` 요청은 모든 동기화 테이블에 접근할 수 없다.

RLS는 다음 조건을 모두 확인한다.

- 요청 JWT의 `auth.uid()`와 행의 `owner_id`가 같음
- 요청 JWT의 `auth.uid()`가 스키마 설치 시 발견된 단일 사용자와 같음

따라서 설치 후 실수로 다른 Auth 사용자가 추가되어도 그 사용자는 기존 데이터를 읽거나 자신의 행을 만들 수 없다. 사용자를 교체하려면 먼저 데이터 소유권 이전 절차를 별도로 설계해야 한다.

`owner_id` 외래키는 이메일 Auth 사용자 삭제 시 연결된 동기화 행도 제거하도록 구성된다. 앱을 삭제해 보안 저장소의 refresh token을 잃더라도 같은 이메일과 비밀번호로 다시 로그인할 수 있다. 단, Supabase에서 해당 Auth 사용자를 삭제하면 연결된 동기화 행도 제거된다.

UPDATE와 upsert가 정상 동작하려면 SELECT 정책도 필요하므로 세 정책을 함께 유지한다. DELETE 정책과 DELETE 권한은 의도적으로 제공하지 않는다.

## 업로드와 삭제

일반 추가·수정은 `uuid`, 전체 `payload`, `deleted_at: null`을 `uuid` 충돌 기준으로 upsert한다. 성공 응답에서 서버가 발급한 revision을 확인한 뒤에만 로컬 재시도 항목을 제거한다.

```dart
final row = await client
    .from(table)
    .upsert({
      'uuid': uuid,
      'payload': payload,
      'deleted_at': null,
    }, onConflict: 'uuid')
    .select('uuid,updated_at,deleted_at,sync_revision')
    .single();
```

삭제도 같은 upsert를 사용하되 `deleted_at`에 null이 아닌 ISO 8601 값을 보낸다. 그 값 자체는 삭제 의사 표시일 뿐이며, 트리거가 실제 서버 시각으로 교체한다.
기존 행을 삭제하는 경우 트리거는 마지막 live payload를 tombstone에 보존한다. 서버에 올라가기 전에 삭제된 행은 로컬 outbox가 이름·유형 같은 최소 자연 키 payload를 함께 보낸다. 새 설치의 기본 데이터와 자연 키를 대조할 때만 사용하며 삭제 행을 화면에 복원하지 않는다.

```dart
final row = await client
    .from(table)
    .upsert({
      'uuid': uuid,
      'payload': tombstoneNaturalKeyPayload,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uuid')
    .select('uuid,updated_at,deleted_at,sync_revision')
    .single();
```

tombstone 행은 물리적으로 제거하지 않는다. 다만 이 구성은 여러 기기의 동시 실행을 지원하지 않으므로, 동일 UUID를 `deleted_at: null`과 전체 payload로 명시적으로 upsert하면 백업 복원으로 간주해 행을 되살릴 수 있다. 클라이언트는 서버 응답의 `deleted_at`을 확인한 뒤에만 로컬 재시도 항목을 제거한다.

## 앱 시작 시 변경분 조회

앱은 테이블별 마지막 `sync_revision`을 로컬에 저장한다. 최초 연결은 cursor `0`부터 조회하므로 전체 초기 데이터가 내려오며, 이후 실행부터 변경분만 내려온다.

```dart
final rows = await client
    .from(table)
    .select('uuid,payload,updated_at,deleted_at,sync_revision')
    .gt('sync_revision', lastRevision)
    .order('sync_revision', ascending: true)
    .limit(200);
```

페이지를 로컬 DB 트랜잭션으로 완전히 반영한 뒤 마지막 행의 revision으로 cursor를 갱신한다. 실패한 페이지는 cursor를 올리지 않고 다음 실행에서 다시 받는다. sequence 번호는 롤백 등에 의해 중간 값이 비어 있을 수 있지만 감소하거나 재사용되지는 않는다.

revision 트리거는 모든 동기화 테이블에 공통 advisory transaction lock을 사용한다. 동시에 여러 HTTP 쓰기가 도착하더라도 더 작은 revision의 트랜잭션이 나중에 커밋되어 증분 조회에서 누락되는 상황을 방지한다.

## Realtime과 Storage

이 SQL은 Realtime publication이나 채널을 만들지 않는다. 실행 중인 다른 기기의 즉시 반영은 범위에 포함하지 않으며, 앱 시작 시 증분 pull과 쓰기 직후 push만 사용한다.

이 SQL은 Supabase Storage bucket과 `storage.objects` 정책을 변경하지 않는다. 기존 JSON 백업/복원은 DB 증분 동기화와 별도 기능이므로 bucket과 Storage 정책을 따로 구성해야 한다.

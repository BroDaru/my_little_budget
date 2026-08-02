-- My Little Budget table sync v2.
--
-- Prerequisite: exactly one email/password Supabase Auth user must exist.
-- Create that user in Authentication, then sign in from the app.
-- This migration intentionally fails before changing anything when auth.users
-- does not contain exactly one email user. Legacy anonymous users are allowed
-- so their existing rows can be transferred to the email user.
--
-- The app uses authenticated PostgREST requests only. Realtime is not enabled.
-- Run this whole file once. It installs or migrates all sync tables, refreshes
-- the PostgREST schema cache, and reports the installed/expected table count.

begin;
set transaction isolation level serializable;

do $auth_check$
declare
  email_user_count bigint;
begin
  select
    count(*) filter (where is_anonymous is false and email is not null)
  into email_user_count
  from auth.users;

  if email_user_count <> 1 then
    raise exception using
      errcode = 'P0001',
      message = format(
        'My Little Budget sync setup requires exactly one email Auth user; found %s.',
        email_user_count
      ),
      hint = 'Create one email/password user in Authentication, sign in from the app, then run this SQL again.';
  end if;
end
$auth_check$;

-- Coordinate reruns of this migration with writes already using the trigger.
select pg_catalog.pg_advisory_xact_lock(7840420260713::bigint);

create sequence if not exists public.mlb_sync_revision_seq as bigint;

revoke all privileges
  on sequence public.mlb_sync_revision_seq
  from public, anon, authenticated;
grant usage
  on sequence public.mlb_sync_revision_seq
  to authenticated;

-- Every visible row change receives a globally increasing revision. The
-- transaction-scoped advisory lock makes revision allocation follow commit
-- order even if more than one HTTP write reaches Postgres at the same time.
create or replace function public.mlb_stamp_sync_row()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  request_user_id uuid := auth.uid();
begin
  if request_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'My Little Budget sync writes require an authenticated user.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(7840420260713::bigint);

  if tg_op = 'INSERT' then
    new.owner_id := request_user_id;

    if new.deleted_at is not null then
      new.deleted_at := pg_catalog.clock_timestamp();
    end if;
  else
    -- owner_id is immutable. This app intentionally targets one active device,
    -- so an explicit live upsert may restore the same UUID (for example after
    -- importing a backup). A repeated delete keeps the original tombstone.
    new.owner_id := old.owner_id;

    if old.deleted_at is not null and new.deleted_at is not null then
      new.deleted_at := old.deleted_at;
      new.payload := old.payload;
    elsif old.deleted_at is null and new.deleted_at is not null then
      new.deleted_at := pg_catalog.clock_timestamp();
      -- Keep the last live payload so a fresh device can reconcile a
      -- tombstoned default row by its natural key instead of recreating it.
      new.payload := old.payload;
    elsif old.deleted_at is not null and new.deleted_at is null then
      -- Explicit restoration. The client still verifies the returned row
      -- before acknowledging its durable outbox entry.
      new.deleted_at := null;
    end if;
  end if;

  new.updated_at := pg_catalog.clock_timestamp();
  new.sync_revision := pg_catalog.nextval(
    'public.mlb_sync_revision_seq'::pg_catalog.regclass
  );
  new.sync_status := 'synced';
  return new;
end
$function$;

revoke all privileges
  on function public.mlb_stamp_sync_row()
  from public, anon, authenticated;
grant execute
  on function public.mlb_stamp_sync_row()
  to authenticated;

do $schema_setup$
declare
  table_name text;
  foreign_key_name text;
  existing_policy_name text;
  sync_owner_id uuid;
  owner_mismatch_count bigint;
  table_max_revision bigint;
  max_existing_revision bigint := 0;
  sequence_last_value bigint;
  owner_policy_expression text;
  sync_tables constant text[] := array[
    'mlb_accounts',
    'mlb_categories',
    'mlb_transactions',
    'mlb_budget_groups',
    'mlb_monthly_income',
    'mlb_investments',
    'mlb_recurring_transactions',
    'mlb_transaction_presets',
    'mlb_tags',
    'mlb_calendar_events'
  ];
begin
  select id into strict sync_owner_id
    from auth.users
    where is_anonymous is false and email is not null;

  -- First create/migrate the tables and adopt rows from the previous anon-read
  -- schema. Triggers are temporarily removed so rerunning this migration from
  -- the SQL Editor does not require an end-user JWT.
  foreach table_name in array sync_tables
  loop
    execute format(
      'create table if not exists public.%I (
        uuid text primary key,
        payload jsonb not null default ''{}''::jsonb,
        updated_at timestamptz not null default now(),
        deleted_at timestamptz,
        sync_status text not null default ''pending'',
        owner_id uuid,
        sync_revision bigint
      )',
      table_name
    );

    execute format(
      'drop trigger if exists mlb_stamp_sync_row on public.%I',
      table_name
    );
    execute format(
      'alter table public.%I add column if not exists owner_id uuid',
      table_name
    );
    execute format(
      'alter table public.%I add column if not exists sync_revision bigint',
      table_name
    );

    execute format(
      'select count(*) from public.%I as sync_row
       where sync_row.owner_id is not null
         and sync_row.owner_id <> $1
         and not exists (
           select 1 from auth.users as auth_user
           where auth_user.id = sync_row.owner_id
             and auth_user.is_anonymous is true
         )',
      table_name
    ) into owner_mismatch_count using sync_owner_id;

    if owner_mismatch_count > 0 then
      raise exception using
        errcode = 'P0001',
        message = format(
          'Table public.%I contains %s row(s) owned by a different Auth user.',
          table_name,
          owner_mismatch_count
        ),
        hint = 'Do not reassign financial data automatically. Restore the original Auth user or review the rows manually before rerunning this migration.';
    end if;

    execute format(
      'update public.%I as sync_row
       set owner_id = $1
       where sync_row.owner_id is null
          or exists (
            select 1 from auth.users as auth_user
            where auth_user.id = sync_row.owner_id
              and auth_user.is_anonymous is true
          )',
      table_name
    ) using sync_owner_id;
    execute format(
      'update public.%I set sync_status = ''synced'' where sync_status is distinct from ''synced''',
      table_name
    );

    foreign_key_name := table_name || '_owner_id_fkey';
    if not exists (
      select 1
      from pg_catalog.pg_constraint
      where conrelid = pg_catalog.to_regclass(
        format('public.%I', table_name)
      )
        and conname = foreign_key_name
    ) then
      execute format(
        'alter table public.%I add constraint %I foreign key (owner_id) references auth.users(id) on delete cascade',
        table_name,
        foreign_key_name
      );
    end if;

    execute format(
      'alter table public.%I alter column owner_id set not null',
      table_name
    );
    execute format(
      'select coalesce(max(sync_revision), 0) from public.%I',
      table_name
    ) into table_max_revision;
    max_existing_revision := greatest(
      max_existing_revision,
      table_max_revision
    );
  end loop;

  -- Continue after the largest revision already present. This keeps the script
  -- idempotent and safely resumes a previously completed installation.
  select last_value
    into sequence_last_value
    from public.mlb_sync_revision_seq;
  perform pg_catalog.setval(
    'public.mlb_sync_revision_seq'::pg_catalog.regclass,
    greatest(max_existing_revision, sequence_last_value, 1),
    true
  );

  foreach table_name in array sync_tables
  loop
    execute format(
      'update public.%I set sync_revision = pg_catalog.nextval(''public.mlb_sync_revision_seq''::pg_catalog.regclass) where sync_revision is null',
      table_name
    );
    execute format(
      'alter table public.%I alter column sync_revision set not null',
      table_name
    );

    execute format(
      'create unique index if not exists %I on public.%I (owner_id, sync_revision)',
      'idx_' || table_name || '_owner_revision',
      table_name
    );

    execute format(
      'alter table public.%I enable row level security',
      table_name
    );
    execute format(
      'alter table public.%I force row level security',
      table_name
    );

    -- These tables are owned by this migration, so remove the previous anon
    -- policy and any other stale policy before installing the complete set.
    for existing_policy_name in
      select policy.polname
      from pg_catalog.pg_policy as policy
      where policy.polrelid = pg_catalog.to_regclass(
        format('public.%I', table_name)
      )
    loop
      execute format(
        'drop policy %I on public.%I',
        existing_policy_name,
        table_name
      );
    end loop;

    execute format(
      'revoke all privileges on table public.%I from public, anon, authenticated',
      table_name
    );
    execute format(
      'grant select, insert, update on table public.%I to authenticated',
      table_name
    );

    -- Besides matching owner_id, policies are pinned to the one Auth user that
    -- existed at setup time. A later accidental signup cannot use these tables.
    owner_policy_expression := format(
      '((select auth.uid()) = owner_id and (select auth.uid()) = %L::uuid)',
      sync_owner_id::text
    );

    execute format(
      'create policy mlb_sync_select_own on public.%I for select to authenticated using (%s)',
      table_name,
      owner_policy_expression
    );
    execute format(
      'create policy mlb_sync_insert_own on public.%I for insert to authenticated with check (%s)',
      table_name,
      owner_policy_expression
    );
    execute format(
      'create policy mlb_sync_update_own on public.%I for update to authenticated using (%s) with check (%s)',
      table_name,
      owner_policy_expression,
      owner_policy_expression
    );

    execute format(
      'create trigger mlb_stamp_sync_row before insert or update on public.%I for each row execute function public.mlb_stamp_sync_row()',
      table_name
    );
  end loop;
end
$schema_setup$;

commit;

-- PostgREST normally notices DDL automatically, but requesting a reload here
-- makes this single script sufficient even when its schema cache is stale.
notify pgrst, 'reload schema';

-- A successful installation finishes with installed_table_count = 10 and
-- expected_table_count = 10. No separate verification query is required.
with expected(table_name) as (
  values
    ('mlb_accounts'),
    ('mlb_categories'),
    ('mlb_transactions'),
    ('mlb_budget_groups'),
    ('mlb_monthly_income'),
    ('mlb_investments'),
    ('mlb_recurring_transactions'),
    ('mlb_transaction_presets'),
    ('mlb_tags'),
    ('mlb_calendar_events')
)
select
  count(*) filter (
    where pg_catalog.to_regclass(
      pg_catalog.format('public.%I', table_name)
    ) is not null
  ) as installed_table_count,
  count(*) as expected_table_count
from expected;

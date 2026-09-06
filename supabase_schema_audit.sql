-- TimeTrack schema audit (READ ONLY)
-- Run this in the intended Supabase project's SQL Editor.
-- It makes no schema or data changes. Save/export each result set before
-- creating migrations, then compare it with the local setup scripts.

-- 1. The exact columns, defaults, and nullability used by the applications.
select
  table_name,
  ordinal_position,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles', 'attendance', 'leave_requests')
order by table_name, ordinal_position;

-- 2. Primary keys, unique constraints, foreign keys, and checks.
select
  table_name,
  constraint_name,
  constraint_type,
  pg_get_constraintdef(pg_constraint.oid) as definition
from information_schema.table_constraints
join pg_constraint
  on pg_constraint.conname = constraint_name
 and pg_constraint.conrelid = (
   quote_ident(table_schema) || '.' || quote_ident(table_name)
 )::regclass
where table_schema = 'public'
  and table_name in ('profiles', 'attendance', 'leave_requests')
order by table_name, constraint_type, constraint_name;

-- 3. Row Level Security state and policies. This is the authorization baseline.
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('profiles', 'attendance', 'leave_requests')
order by c.relname;

select
  tablename,
  policyname,
  roles,
  cmd,
  qual as using_expression,
  with_check as with_check_expression
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles', 'attendance', 'leave_requests')
order by tablename, policyname;

-- 4. Explicit table privileges granted to browser/mobile roles.
select
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('profiles', 'attendance', 'leave_requests')
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type;

-- 5. Indexes supporting employee and manager portal queries.
select
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('profiles', 'attendance', 'leave_requests')
order by tablename, indexname;

-- 6. Existing triggers affecting these tables or new-auth-user provisioning.
select
  event_object_schema as table_schema,
  event_object_table as table_name,
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
from information_schema.triggers
where (event_object_schema = 'public'
       and event_object_table in ('profiles', 'attendance', 'leave_requests'))
   or (event_object_schema = 'auth' and event_object_table = 'users')
order by table_schema, table_name, trigger_name;

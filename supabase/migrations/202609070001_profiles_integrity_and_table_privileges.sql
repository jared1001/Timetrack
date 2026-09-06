-- TimeTrack migration 202609070001
-- Purpose: formalize verified profile integrity and least-privilege table grants.
--
-- Preconditions verified in the production audit on 2026-09-07:
--   * public.profiles contains no orphan auth-user references.
--   * public.profiles contains no null/invalid roles.
--   * public.profiles contains no null employee numbers.
--
-- Run once through the Supabase migration workflow or SQL Editor after review.
-- This migration assumes public.profiles, public.attendance, and
-- public.leave_requests already exist. It does not create duplicate tables.

begin;

-- public.profiles is an extension of auth.users, not an independent identity
-- store. Auth user deletion will now remove the corresponding profile.
alter table public.profiles
  alter column id drop default,
  alter column role set not null,
  alter column employee_number set not null,
  add constraint profiles_id_fkey
    foreign key (id)
    references auth.users(id)
    on delete cascade,
  add constraint profiles_role_check
    check (role in ('employee', 'manager', 'admin'));

-- The browser/mobile clients do not need DELETE, TRUNCATE, REFERENCES, or
-- TRIGGER access. RLS remains the row-level authorization layer.
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.attendance from anon, authenticated;
revoke all on table public.leave_requests from anon, authenticated;

-- Both apps require profile reads; public signup can insert only through the
-- restrictive RLS policy installed by the emergency hardening script.
grant select, insert on table public.profiles to authenticated;

-- Employees create and update their own attendance; managers/admins read it.
grant select, insert, update on table public.attendance to authenticated;

-- Employees submit/view leave; managers/admins review it. Limiting UPDATE to
-- the review columns prevents direct client changes to request ownership/dates.
grant select, insert on table public.leave_requests to authenticated;
grant update (status, reviewed_at, reviewed_by)
  on table public.leave_requests to authenticated;

commit;

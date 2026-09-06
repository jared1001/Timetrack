-- EMERGENCY: close public role-escalation paths on public.profiles.
-- Review and run once in the intended Supabase project's SQL Editor.
--
-- This script changes RLS policies only. It does NOT create or alter the
-- profiles table, alter existing profile data, or assign roles.
-- Existing manager/admin role assignment remains an administrator-only
-- database operation until a dedicated administrative workflow is designed.

begin;

drop policy if exists "Enable insert for authenticated users only" on public.profiles;
drop policy if exists "Enable read access for all users" on public.profiles;
drop policy if exists "Policy with table joins" on public.profiles;

-- Required by both apps: the employee app reads the signed-in user's profile;
-- the manager portal reads employee profiles for its directory and reports.
-- This preserves the current application behavior while role-aware profile
-- visibility is designed and tested separately.
create policy "Authenticated users can read profiles"
on public.profiles
for select
to authenticated
using (true);

-- Public signup may create only the caller's own employee profile.
-- It cannot create an arbitrary profile or grant itself manager/admin access.
create policy "Users can create their own employee profile"
on public.profiles
for insert
to authenticated
with check (
  id = auth.uid()
  and role = 'employee'
);

-- Intentionally no UPDATE policy:
-- normal clients cannot change their own role or any profile fields.
-- Authorized administrators can still manage roles through a privileged,
-- audited server-side/database process that bypasses RLS.

commit;

-- Verification (read only): only the two policies above should remain for
-- public.profiles, and neither should permit client-side UPDATE.
select policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'profiles'
order by policyname;

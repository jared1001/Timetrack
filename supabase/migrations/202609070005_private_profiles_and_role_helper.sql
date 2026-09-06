-- TimeTrack migration 202609070005
-- Purpose: restrict profile visibility and centralize manager/admin checks.

begin;

create or replace function public.is_manager_or_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('manager', 'admin')
  )
$$;

revoke all on function public.is_manager_or_admin() from public, anon, authenticated;
grant execute on function public.is_manager_or_admin() to authenticated;

drop policy if exists "Authenticated users can read profiles" on public.profiles;

create policy "Users can view their own profile"
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy "Managers and admins can view profiles"
on public.profiles
for select
to authenticated
using (public.is_manager_or_admin());

-- Use the security-definer role helper rather than querying profiles inside
-- other RLS policies. This avoids policy recursion and keeps the rule central.
drop policy if exists "Managers and admins can view attendance" on public.attendance;
create policy "Managers and admins can view attendance"
on public.attendance
for select
to authenticated
using (public.is_manager_or_admin());

drop policy if exists "Managers and admins can view leave requests" on public.leave_requests;
create policy "Managers and admins can view leave requests"
on public.leave_requests
for select
to authenticated
using (public.is_manager_or_admin());

commit;

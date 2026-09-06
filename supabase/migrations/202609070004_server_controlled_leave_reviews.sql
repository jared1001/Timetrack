-- TimeTrack migration 202609070004
-- Purpose: protect leave submission and make reviews atomic and auditable.
-- Apply the matching manager-portal dashboard.js update before this migration.

begin;

drop policy if exists "Employees can submit their own leave requests" on public.leave_requests;
drop policy if exists "Managers and admins can review leave requests" on public.leave_requests;

create policy "Employees can submit their own pending leave requests"
on public.leave_requests
for insert
to authenticated
with check (
  user_id = auth.uid()
  and status = 'pending'
  and reviewed_at is null
  and reviewed_by is null
  and exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'employee'
  )
);

create or replace function public.review_leave_request(request_id bigint, decision text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reviewed_request public.leave_requests;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('manager', 'admin')
  ) then
    raise exception 'Only manager or admin accounts can review leave requests.';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Leave decision must be approved or rejected.';
  end if;

  update public.leave_requests
  set status = decision,
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = request_id
    and status = 'pending'
  returning * into reviewed_request;

  if reviewed_request.id is null then
    raise exception 'Leave request was not found or has already been reviewed.';
  end if;

  return to_jsonb(reviewed_request);
end;
$$;

-- No client can directly change requests after submission. Employees receive
-- INSERT rights only for the fields a submission is allowed to set.
revoke insert, update on table public.leave_requests from authenticated;
grant insert (user_id, leave_type, start_date, end_date, reason)
  on table public.leave_requests to authenticated;

revoke all on function public.review_leave_request(bigint, text)
  from public, anon, authenticated;
grant execute on function public.review_leave_request(bigint, text)
  to authenticated;

commit;

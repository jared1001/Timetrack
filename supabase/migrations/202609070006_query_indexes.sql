-- TimeTrack migration 202609070006
-- Purpose: add indexes for existing employee and manager portal queries.
-- These indexes do not alter rows or business behavior.

begin;

-- Manager dashboard: count employees by role and list employees by name.
create index if not exists profiles_role_full_name_idx
  on public.profiles (role, full_name);

-- Manager dashboard: count attendance records for a given date.
create index if not exists attendance_date_idx
  on public.attendance (date);

-- Employee history and manager leave lists, newest first.
create index if not exists leave_requests_user_created_at_idx
  on public.leave_requests (user_id, created_at desc);

-- Manager dashboard: pending-review count and queue ordering.
create index if not exists leave_requests_status_created_at_idx
  on public.leave_requests (status, created_at desc);

commit;

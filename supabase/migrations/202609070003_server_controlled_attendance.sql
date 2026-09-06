-- TimeTrack migration 202609070003
-- Purpose: enforce attendance actions with server time in Asia/Manila.
-- Apply the matching Flutter AttendanceService update before this migration.

begin;

create or replace function public.clock_in()
returns jsonb language plpgsql security definer set search_path = public as $$
declare attendance_row public.attendance;
  business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null then raise exception 'Authentication is required.'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'employee') then
    raise exception 'Only employee accounts can record attendance.';
  end if;
  insert into public.attendance (user_id, date, time_in)
  values (auth.uid(), business_date, now())
  on conflict (user_id, date) do nothing returning * into attendance_row;
  if attendance_row.id is null then raise exception 'You have already timed in today.'; end if;
  return to_jsonb(attendance_row);
end;
$$;

create or replace function public.start_break()
returns jsonb language plpgsql security definer set search_path = public as $$
declare attendance_row public.attendance;
  business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'employee'
  ) then raise exception 'Only authenticated employee accounts can record attendance.'; end if;
  update public.attendance set break_in = now()
  where user_id = auth.uid() and date = business_date and time_in is not null
    and break_in is null and break_out is null and time_out is null
  returning * into attendance_row;
  if attendance_row.id is null then raise exception 'A current Time In is required before Break In.'; end if;
  return to_jsonb(attendance_row);
end;
$$;

create or replace function public.end_break()
returns jsonb language plpgsql security definer set search_path = public as $$
declare attendance_row public.attendance;
  business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'employee'
  ) then raise exception 'Only authenticated employee accounts can record attendance.'; end if;
  update public.attendance set break_out = now()
  where user_id = auth.uid() and date = business_date and time_in is not null
    and break_in is not null and break_out is null and time_out is null
  returning * into attendance_row;
  if attendance_row.id is null then raise exception 'A current Break In is required before Break Out.'; end if;
  return to_jsonb(attendance_row);
end;
$$;

create or replace function public.clock_out()
returns jsonb language plpgsql security definer set search_path = public as $$
declare attendance_row public.attendance;
  business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'employee'
  ) then raise exception 'Only authenticated employee accounts can record attendance.'; end if;
  update public.attendance set time_out = now()
  where user_id = auth.uid() and date = business_date and time_in is not null
    and break_in is not null and break_out is not null and time_out is null
  returning * into attendance_row;
  if attendance_row.id is null then raise exception 'A completed break is required before Time Out.'; end if;
  return to_jsonb(attendance_row);
end;
$$;

create or replace function public.get_current_attendance()
returns jsonb language sql security definer set search_path = public stable as $$
  select to_jsonb(attendance)
  from public.attendance
  where user_id = auth.uid()
    and date = (now() at time zone 'Asia/Manila')::date
$$;

-- Attendance writes now happen only through the guarded server functions.
revoke insert, update on table public.attendance from authenticated;

revoke all on function public.clock_in() from public, anon, authenticated;
revoke all on function public.start_break() from public, anon, authenticated;
revoke all on function public.end_break() from public, anon, authenticated;
revoke all on function public.clock_out() from public, anon, authenticated;
revoke all on function public.get_current_attendance() from public, anon, authenticated;

grant execute on function public.clock_in() to authenticated;
grant execute on function public.start_break() to authenticated;
grant execute on function public.end_break() to authenticated;
grant execute on function public.clock_out() to authenticated;
grant execute on function public.get_current_attendance() to authenticated;

commit;

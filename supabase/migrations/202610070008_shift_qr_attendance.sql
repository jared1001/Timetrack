-- TimeTrack migration 202610070008
-- Purpose: issue short-lived manager QR sessions for shift and overtime scans.
-- Apply after migrations 202609070003, 202609070005, and 202609070007.

begin;

alter table public.attendance
  add column if not exists shift_type text not null default 'day',
  add column if not exists pay_type text not null default 'normal',
  add column if not exists overtime_in timestamptz,
  add column if not exists overtime_out timestamptz,
  add column if not exists overtime_pay_type text not null default 'normal';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'attendance_shift_type_check'
      and conrelid = 'public.attendance'::regclass
  ) then
    alter table public.attendance
      add constraint attendance_shift_type_check
      check (shift_type in ('day', 'night'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'attendance_pay_type_check'
      and conrelid = 'public.attendance'::regclass
  ) then
    alter table public.attendance
      add constraint attendance_pay_type_check
      check (pay_type in ('normal', 'double'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'attendance_overtime_pay_type_check'
      and conrelid = 'public.attendance'::regclass
  ) then
    alter table public.attendance
      add constraint attendance_overtime_pay_type_check
      check (overtime_pay_type in ('normal', 'double'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'attendance_overtime_pair_check'
      and conrelid = 'public.attendance'::regclass
  ) then
    alter table public.attendance
      add constraint attendance_overtime_pair_check
      check (overtime_in is null or time_out is not null);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'attendance_overtime_order_check'
      and conrelid = 'public.attendance'::regclass
  ) then
    alter table public.attendance
      add constraint attendance_overtime_order_check
      check (overtime_out is null or overtime_in is not null);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'attendance_overtime_time_order_check'
      and conrelid = 'public.attendance'::regclass
  ) then
    alter table public.attendance
      add constraint attendance_overtime_time_order_check
      check (overtime_out is null or overtime_out >= overtime_in);
  end if;
end;
$$;

create table if not exists public.attendance_qr_sessions (
  token uuid primary key default gen_random_uuid(),
  qr_action text not null check (qr_action in ('time_in', 'overtime_in', 'overtime_out')),
  shift_type text not null check (shift_type in ('day', 'night')),
  pay_type text not null check (pay_type in ('normal', 'double')),
  overtime_pay_type text not null check (overtime_pay_type in ('normal', 'double')),
  work_date date not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  is_active boolean not null default true
);

create index if not exists attendance_qr_sessions_active_lookup
  on public.attendance_qr_sessions (qr_action, shift_type, work_date, expires_at)
  where is_active;
create index if not exists attendance_qr_sessions_creator_rate_limit
  on public.attendance_qr_sessions (created_by, created_at);

alter table public.attendance_qr_sessions enable row level security;
revoke all on public.attendance_qr_sessions from anon, authenticated;
revoke insert, update, delete on public.attendance from anon, authenticated;
grant select on public.attendance to authenticated;

drop function if exists public.create_attendance_qr(text, text, text, text);

create or replace function public.create_attendance_qr(
  p_qr_action text,
  p_shift_type text,
  p_pay_type text,
  p_overtime_pay_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_manager_id uuid := auth.uid();
  v_work_date date := (now() at time zone 'Asia/Manila')::date;
  v_session public.attendance_qr_sessions;
begin
  if v_manager_id is null or not public.is_manager_or_admin() then
    raise exception 'Only manager or admin accounts can generate attendance QR codes.';
  end if;

  if p_qr_action is null
    or p_qr_action not in ('time_in', 'overtime_in', 'overtime_out') then
    raise exception 'Choose a valid attendance QR action.';
  end if;
  if p_shift_type is null or p_shift_type not in ('day', 'night') then
    raise exception 'Choose a day or night shift.';
  end if;
  if p_pay_type is null or p_pay_type not in ('normal', 'double') then
    raise exception 'Choose a valid shift pay type.';
  end if;
  if p_overtime_pay_type is null
    or p_overtime_pay_type not in ('normal', 'double') then
    raise exception 'Choose a valid overtime pay type.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manager:' || v_manager_id::text, 0)
  );
  if (
    select count(*)
    from public.attendance_qr_sessions
    where created_by = v_manager_id
      and created_at > now() - interval '10 minutes'
  ) >= 20 then
    raise exception 'QR generation is temporarily rate limited. Try again in a few minutes.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'session:' || p_qr_action || ':' || p_shift_type || ':' || v_work_date::text,
      0
    )
  );

  delete from public.attendance_qr_sessions
  where expires_at < now() - interval '1 day';

  update public.attendance_qr_sessions
  set is_active = false
  where qr_action = p_qr_action
    and shift_type = p_shift_type
    and work_date = v_work_date
    and is_active;

  insert into public.attendance_qr_sessions (
    qr_action,
    shift_type,
    pay_type,
    overtime_pay_type,
    work_date,
    created_by,
    expires_at
  )
  values (
    p_qr_action,
    p_shift_type,
    p_pay_type,
    p_overtime_pay_type,
    v_work_date,
    v_manager_id,
    now() + interval '10 minutes'
  )
  returning * into v_session;

  return jsonb_build_object(
    'token', v_session.token,
    'qr_action', v_session.qr_action,
    'shift_type', v_session.shift_type,
    'pay_type', v_session.pay_type,
    'overtime_pay_type', v_session.overtime_pay_type,
    'expires_at', v_session.expires_at
  );
end;
$$;

create or replace function public.consume_attendance_qr(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.attendance_qr_sessions;
  v_attendance public.attendance;
  v_business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if v_user_id is null or not exists (
    select 1 from public.profiles
    where id = v_user_id and role = 'employee'
  ) then
    raise exception 'Only authenticated employee accounts can scan attendance QR codes.';
  end if;

  select * into v_session
  from public.attendance_qr_sessions
  where token = p_token
    and is_active
    and expires_at > now()
  for update;

  if v_session.token is null then
    raise exception 'This QR code is invalid, expired, or has been replaced.';
  end if;

  if v_session.qr_action = 'time_in' then
    insert into public.attendance (
      user_id, date, time_in, shift_type, pay_type, overtime_pay_type
    )
    values (
      v_user_id,
      v_session.work_date,
      now(),
      v_session.shift_type,
      v_session.pay_type,
      v_session.overtime_pay_type
    )
    on conflict (user_id, date) do nothing
    returning * into v_attendance;

    if v_attendance.id is null then
      raise exception 'An attendance record already exists for this work date.';
    end if;
  elsif v_session.qr_action = 'overtime_in' then
    select * into v_attendance
    from public.attendance
    where user_id = v_user_id
      and shift_type = v_session.shift_type
      and date = case
        when v_session.shift_type = 'night'
          and extract(hour from v_session.created_at at time zone 'Asia/Manila') < 12
          then v_session.work_date - 1
        else v_session.work_date
      end
      and time_out is not null
      and overtime_in is null
      and overtime_out is null
      and (v_session.shift_type = 'night' or date = v_session.work_date)
    order by date desc
    limit 1
    for update;

    if v_attendance.id is null then
      raise exception 'A completed matching shift is required before Overtime In.';
    end if;

    update public.attendance
    set overtime_in = now(),
        overtime_pay_type = v_session.overtime_pay_type
    where id = v_attendance.id
    returning * into v_attendance;
  else
    select * into v_attendance
    from public.attendance
    where user_id = v_user_id
      and shift_type = v_session.shift_type
      and date = case
        when v_session.shift_type = 'night'
          and extract(hour from v_session.created_at at time zone 'Asia/Manila') < 12
          then v_session.work_date - 1
        else v_session.work_date
      end
      and overtime_in is not null
      and overtime_out is null
      and overtime_in < now()
      and (v_session.shift_type = 'night' or date = v_session.work_date)
    order by date desc
    limit 1
    for update;

    if v_attendance.id is null then
      raise exception 'A matching Overtime In is required before Overtime Out.';
    end if;

    update public.attendance
    set overtime_out = now()
    where id = v_attendance.id
    returning * into v_attendance;
  end if;

  return to_jsonb(v_attendance);
end;
$$;

-- A night shift may start on the prior Manila work date and continue past
-- midnight; its breaks and clock-out remain attached to that original record.
create or replace function public.start_break()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attendance_row public.attendance;
  business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'employee'
  ) then
    raise exception 'Only authenticated employee accounts can record attendance.';
  end if;

  update public.attendance
  set break_in = now()
  where id = (
    select id from public.attendance
    where user_id = auth.uid()
      and (date = business_date or (date = business_date - 1 and shift_type = 'night'))
      and time_in is not null
      and break_in is null
      and break_out is null
      and time_out is null
    order by date desc
    limit 1
  )
    and time_in is not null
    and break_in is null
    and break_out is null
    and time_out is null
  returning * into attendance_row;

  if attendance_row.id is null then
    raise exception 'A current Time In is required before Break In.';
  end if;
  return to_jsonb(attendance_row);
end;
$$;

create or replace function public.end_break()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attendance_row public.attendance;
  business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'employee'
  ) then
    raise exception 'Only authenticated employee accounts can record attendance.';
  end if;

  update public.attendance
  set break_out = now()
  where id = (
    select id from public.attendance
    where user_id = auth.uid()
      and (date = business_date or (date = business_date - 1 and shift_type = 'night'))
      and time_in is not null
      and break_in is not null
      and break_out is null
      and time_out is null
    order by date desc
    limit 1
  )
    and time_in is not null
    and break_in is not null
    and break_out is null
    and time_out is null
  returning * into attendance_row;

  if attendance_row.id is null then
    raise exception 'A current Break In is required before Break Out.';
  end if;
  return to_jsonb(attendance_row);
end;
$$;

create or replace function public.clock_out()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attendance_row public.attendance;
  business_date date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'employee'
  ) then
    raise exception 'Only authenticated employee accounts can record attendance.';
  end if;

  update public.attendance
  set time_out = now()
  where id = (
    select id from public.attendance
    where user_id = auth.uid()
      and (date = business_date or (date = business_date - 1 and shift_type = 'night'))
      and time_in is not null
      and break_in is not null
      and break_out is not null
      and time_out is null
    order by date desc
    limit 1
  )
    and time_in is not null
    and break_in is not null
    and break_out is not null
    and time_out is null
  returning * into attendance_row;

  if attendance_row.id is null then
    raise exception 'A completed break is required before Time Out.';
  end if;
  return to_jsonb(attendance_row);
end;
$$;

create or replace function public.get_current_attendance()
returns jsonb
language sql
security definer
set search_path = ''
stable
as $$
  select to_jsonb(attendance)
  from public.attendance
  where user_id = auth.uid()
    and (
      date = (now() at time zone 'Asia/Manila')::date
      or (
        date = (now() at time zone 'Asia/Manila')::date - 1
        and shift_type = 'night'
      )
    )
  order by date desc
  limit 1
$$;

-- Shift start must be QR-authorized; all writes continue through guarded RPCs.
revoke all on function public.clock_in() from public, anon, authenticated;
revoke all on function public.start_break() from public, anon, authenticated;
revoke all on function public.end_break() from public, anon, authenticated;
revoke all on function public.clock_out() from public, anon, authenticated;
revoke all on function public.get_current_attendance() from public, anon, authenticated;
revoke all on function public.create_attendance_qr(text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.consume_attendance_qr(uuid)
  from public, anon, authenticated;

grant execute on function public.start_break() to authenticated;
grant execute on function public.end_break() to authenticated;
grant execute on function public.clock_out() to authenticated;
grant execute on function public.get_current_attendance() to authenticated;
grant execute on function public.create_attendance_qr(text, text, text, text)
  to authenticated;
grant execute on function public.consume_attendance_qr(uuid)
  to authenticated;

-- Keep monthly estimates consistent with QR-recorded overtime and shift pay.
create or replace function public.get_my_monthly_pay_summary()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  with bounds as (
    select
      date_trunc('month', now() at time zone 'Asia/Manila')::date as start_date,
      (date_trunc('month', now() at time zone 'Asia/Manila') + interval '1 month')::date as end_date
  ), completed_work as (
    select
      attendance.date,
      attendance.pay_type,
      attendance.overtime_pay_type,
      greatest(
        0,
        extract(epoch from (
          (attendance.time_out - attendance.time_in)
          - coalesce(attendance.break_out - attendance.break_in, interval '0')
        )) / 3600.0
      ) as worked_hours,
      greatest(
        0,
        extract(epoch from (attendance.overtime_out - attendance.overtime_in)) / 3600.0
      ) as separate_overtime_hours
    from public.attendance as attendance
    cross join bounds
    where attendance.user_id = auth.uid()
      and attendance.date >= bounds.start_date
      and attendance.date < bounds.end_date
      and attendance.time_in is not null
      and attendance.time_out is not null
  ), rated_work as (
    select
      work.*,
      rate.daily_rate,
      rate.regular_hours_per_day,
      rate.overtime_multiplier
    from completed_work as work
    join lateral (
      select daily_rate, regular_hours_per_day, overtime_multiplier
      from public.pay_rates
      where effective_date <= work.date
      order by effective_date desc
      limit 1
    ) as rate on true
  ), totals as (
    select
      coalesce(sum(least(worked_hours, regular_hours_per_day)), 0) as regular_hours,
      coalesce(sum(
        greatest(worked_hours - regular_hours_per_day, 0)
          + separate_overtime_hours
      ), 0) as overtime_hours,
      coalesce(sum(
        case when overtime_pay_type = 'normal' then separate_overtime_hours else 0 end
      ), 0) as regular_overtime_hours,
      coalesce(sum(
        case when overtime_pay_type = 'double' then separate_overtime_hours else 0 end
      ), 0) as double_overtime_hours,
      coalesce(sum(
        least(worked_hours, regular_hours_per_day)
          * (daily_rate / regular_hours_per_day)
          * case when pay_type = 'double' then 2 else 1 end
        + greatest(worked_hours - regular_hours_per_day, 0)
          * (daily_rate / regular_hours_per_day) * overtime_multiplier
        + separate_overtime_hours
          * (daily_rate / regular_hours_per_day)
          * case
              when overtime_pay_type = 'double' then 2
              else overtime_multiplier
            end
      ), 0) as estimated_gross_pay,
      count(*) as completed_days
    from rated_work
  )
  select jsonb_build_object(
    'period_start', (select start_date from bounds),
    'period_end', (select end_date - 1 from bounds),
    'regular_hours', round(regular_hours::numeric, 2),
    'overtime_hours', round(overtime_hours::numeric, 2),
    'regular_overtime_hours', round(regular_overtime_hours::numeric, 2),
    'double_overtime_hours', round(double_overtime_hours::numeric, 2),
    'estimated_gross_pay', round(estimated_gross_pay::numeric, 2),
    'completed_days', completed_days
  )
  from totals
$$;

revoke all on function public.get_my_monthly_pay_summary()
  from public, anon, authenticated;
grant execute on function public.get_my_monthly_pay_summary()
  to authenticated;

notify pgrst, 'reload schema';
commit;

-- TimeTrack migration 202609070007
-- Purpose: effective-dated pay assumptions and employee monthly estimates.
-- Initial policy: PHP 755/day from 2026-01-01, 8 regular hours/day,
-- then 1.25x for overtime. This is an estimate, not a payroll settlement.

begin;

create table public.pay_rates (
  effective_date date primary key,
  daily_rate numeric(12, 2) not null check (daily_rate >= 0),
  regular_hours_per_day numeric(5, 2) not null check (regular_hours_per_day > 0),
  overtime_multiplier numeric(5, 2) not null check (overtime_multiplier >= 1),
  created_at timestamptz not null default now()
);

insert into public.pay_rates (
  effective_date, daily_rate, regular_hours_per_day, overtime_multiplier
)
values ('2026-01-01', 755.00, 8.00, 1.25);

alter table public.pay_rates enable row level security;

-- Rates are delivered only through the employee-summary function. Maintain
-- rates via reviewed migration or trusted server-side administration.
revoke all on table public.pay_rates from anon, authenticated;

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
      greatest(
        0,
        extract(epoch from (
          (attendance.time_out - attendance.time_in)
          - coalesce(attendance.break_out - attendance.break_in, interval '0')
        )) / 3600.0
      ) as worked_hours
    from public.attendance
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
      coalesce(sum(greatest(worked_hours - regular_hours_per_day, 0)), 0) as overtime_hours,
      coalesce(sum(
        least(worked_hours, regular_hours_per_day)
          * (daily_rate / regular_hours_per_day)
        + greatest(worked_hours - regular_hours_per_day, 0)
          * (daily_rate / regular_hours_per_day) * overtime_multiplier
      ), 0) as estimated_gross_pay,
      count(*) as completed_days
    from rated_work
  )
  select jsonb_build_object(
    'period_start', (select start_date from bounds),
    'period_end', (select end_date - 1 from bounds),
    'regular_hours', round(regular_hours::numeric, 2),
    'overtime_hours', round(overtime_hours::numeric, 2),
    'estimated_gross_pay', round(estimated_gross_pay::numeric, 2),
    'completed_days', completed_days
  )
  from totals
$$;

revoke all on function public.get_my_monthly_pay_summary()
  from public, anon, authenticated;
grant execute on function public.get_my_monthly_pay_summary() to authenticated;

commit;

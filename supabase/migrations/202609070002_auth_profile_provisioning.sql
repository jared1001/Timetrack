-- TimeTrack migration 202609070002
-- Purpose: provision employee profiles atomically when Supabase Auth users are created.
--
-- Apply the corresponding Flutter code update before or at the same time as
-- this migration. New signups must send full_name and employee_number as Auth
-- metadata. Existing profiles are not modified.

begin;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    full_name,
    email,
    employee_number,
    role
  )
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    new.email,
    nullif(trim(new.raw_user_meta_data ->> 'employee_number'), ''),
    'employee'
  );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_auth_user();

-- Profile inserts are now database-owned. Public clients can read profiles,
-- but cannot create one directly or choose a role.
drop policy if exists "Users can create their own employee profile" on public.profiles;
revoke insert on table public.profiles from authenticated;

-- The function is invoked only by the database trigger; clients must not call
-- it directly.
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

commit;

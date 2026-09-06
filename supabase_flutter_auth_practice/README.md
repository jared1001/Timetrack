# TimeTrack Employee App

Flutter employee application for the TimeTrack system. It uses Supabase Auth and the shared `public.profiles`, `public.attendance`, and `public.leave_requests` tables.

## Current architecture

- Authentication: Supabase Auth email/password.
- Public signup: sends the employee name and number as Auth metadata. A database trigger creates the employee profile. Manager and admin roles are assigned through an authorized administrative process.
- Attendance: cloud-only. The application writes directly to `public.attendance`; it does not use SQLite.
- Leave: employees submit requests through `public.leave_requests`; managers and admins review them in the TimeTrack Manager Portal.

## Data contract

`public.profiles` already exists in the connected Supabase project and is authoritative. It is shared with the manager portal and includes `id`, `full_name`, `employee_number`, `email`, and `role`. Do not create a duplicate profiles table.

The setup SQL scripts in the workspace currently cover attendance and leave requests. They are development setup scripts, not yet a complete versioned migration history.

## Before changing database SQL

1. Export or document the live schema, constraints, indexes, grants, functions, triggers, and RLS policies from the intended Supabase project.
2. Compare that baseline with the local SQL files and application queries.
3. Make only additive, reviewed migrations. Test them in a non-production Supabase project before production.
4. Never use a service-role key in this Flutter app or the browser portal.

## Local development

Configure the Supabase URL and publishable/anon key in `lib/supabase_config.dart`, then run:

```sh
flutter pub get
flutter run
```

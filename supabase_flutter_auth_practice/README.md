# TimeTrack Employee App

Flutter employee application for the TimeTrack system. It uses Supabase Auth and the shared `public.profiles`, `public.attendance`, and `public.leave_requests` tables.

## Current architecture

- Authentication: Supabase Auth email/password.
- Public signup: sends the employee name and number as Auth metadata. A database trigger creates the employee profile. Manager and admin roles are assigned through an authorized administrative process.
- Attendance: cloud-only. Employee actions use guarded Supabase RPCs; shift Time In and separate overtime checkpoints are recorded by scanning manager-issued QR codes. The app does not use SQLite.
- Leave: employees submit requests through `public.leave_requests`; managers and admins review them in the TimeTrack Manager Portal.

## Data contract

`public.profiles` already exists in the connected Supabase project and is authoritative. It is shared with the manager portal and includes `id`, `full_name`, `employee_number`, `email`, and `role`. Do not create a duplicate profiles table.

The additive migrations in `../supabase/migrations` extend the existing attendance and leave schema. Apply migrations in order to a test Supabase project before production. Migration `202610070008_shift_qr_attendance.sql` adds manager-issued, expiring shift and overtime QR sessions and corresponding attendance RPCs; apply it before deploying the portal or using the updated app.

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

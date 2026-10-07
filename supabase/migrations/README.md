# TimeTrack database migrations

These migrations are additive changes for the existing Supabase project. They
do not create a duplicate profile table.

Before running a migration:

1. Run the read-only `supabase_schema_audit.sql` against the intended project.
2. Confirm the migration preconditions and back up production data.
3. Apply and test it in a separate Supabase development project first.
4. Apply the same file once, in order, to production and record the result.

Never create a second `public.profiles` table. The existing table is shared by
the Flutter employee app and TimeTrack Manager Portal.

Apply migrations in filename order. Migration
`202610070008_shift_qr_attendance.sql` depends on the server-controlled
attendance RPCs and manager/admin role helper from migrations `003` and `005`,
and on the effective-dated pay table from migration `007`. It must be applied
before deploying the portal's QR controls or the app's QR scanner. It enables
day/night shift codes and independently rates regular-pay and double-rate
overtime scans.

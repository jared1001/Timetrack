# TimeTrack database migrations

These migrations are additive changes for the existing Supabase project. They
are not a replacement for the original setup scripts at the workspace root.

Before running a migration:

1. Run the read-only `supabase_schema_audit.sql` against the intended project.
2. Confirm the migration preconditions and back up production data.
3. Apply and test it in a separate Supabase development project first.
4. Apply the same file once, in order, to production and record the result.

Never create a second `public.profiles` table. The existing table is shared by
the Flutter employee app and TimeTrack Manager Portal.

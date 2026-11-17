-- Swift UUID.uuidString is uppercase; auth.uid()::text is lowercase.
-- Case-sensitive folder match caused "new row violates row-level security policy" on upload.

drop policy if exists "scan_packages_select_own" on storage.objects;
drop policy if exists "scan_packages_insert_own" on storage.objects;
drop policy if exists "scan_packages_update_own" on storage.objects;
drop policy if exists "scan_packages_delete_own" on storage.objects;

create policy "scan_packages_select_own"
  on storage.objects for select
  using (
    bucket_id = 'scan-packages'
    and lower((storage.foldername(name))[1]) = (select auth.uid()::text)
  );

create policy "scan_packages_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'scan-packages'
    and lower((storage.foldername(name))[1]) = (select auth.uid()::text)
  );

create policy "scan_packages_update_own"
  on storage.objects for update
  using (
    bucket_id = 'scan-packages'
    and lower((storage.foldername(name))[1]) = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'scan-packages'
    and lower((storage.foldername(name))[1]) = (select auth.uid()::text)
  );

create policy "scan_packages_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'scan-packages'
    and lower((storage.foldername(name))[1]) = (select auth.uid()::text)
  );

-- Scans may only attach to projects the user owns (prevents orphan inserts).
drop policy if exists "scans_insert_own" on public.scans;
create policy "scans_insert_own" on public.scans
  for insert with check (
    (select auth.uid()) = owner_id
    and exists (
      select 1 from public.projects p
      where p.id = project_id and p.owner_id = (select auth.uid())
    )
  );

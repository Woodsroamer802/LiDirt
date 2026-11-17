-- LiDirt core schema: profiles, projects, scans + RLS + scan-packages storage

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using ((select auth.uid()) = id);
create policy "profiles_insert_own" on public.profiles
  for insert with check ((select auth.uid()) = id);
create policy "profiles_update_own" on public.profiles
  for update using ((select auth.uid()) = id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  address text,
  job_site jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists projects_owner_id_idx on public.projects (owner_id);

alter table public.projects enable row level security;

create policy "projects_select_own" on public.projects
  for select using ((select auth.uid()) = owner_id);
create policy "projects_insert_own" on public.projects
  for insert with check ((select auth.uid()) = owner_id);
create policy "projects_update_own" on public.projects
  for update using ((select auth.uid()) = owner_id);
create policy "projects_delete_own" on public.projects
  for delete using ((select auth.uid()) = owner_id);

create table if not exists public.scans (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  captured_at timestamptz not null default now(),
  quality_score int,
  coverage_ratio double precision,
  pass_count int not null default 0,
  upload_status text not null default 'accepted',
  storage_path text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index if not exists scans_project_id_idx on public.scans (project_id);
create index if not exists scans_owner_id_idx on public.scans (owner_id);

alter table public.scans enable row level security;

create policy "scans_select_own" on public.scans
  for select using ((select auth.uid()) = owner_id);
create policy "scans_insert_own" on public.scans
  for insert with check ((select auth.uid()) = owner_id);
create policy "scans_update_own" on public.scans
  for update using ((select auth.uid()) = owner_id);
create policy "scans_delete_own" on public.scans
  for delete using ((select auth.uid()) = owner_id);

insert into storage.buckets (id, name, public, file_size_limit)
values ('scan-packages', 'scan-packages', false, 524288000)
on conflict (id) do nothing;

create policy "scan_packages_select_own"
  on storage.objects for select
  using (
    bucket_id = 'scan-packages'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "scan_packages_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'scan-packages'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "scan_packages_update_own"
  on storage.objects for update
  using (
    bucket_id = 'scan-packages'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "scan_packages_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'scan-packages'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

-- Silas Academy: one-time database setup for Supabase (free tier).
-- Paste the whole file into Supabase → SQL Editor → New query → Run.
-- Before running, replace both ADMIN_EMAIL_HERE with the email the admin will sign up with.

-- Profiles: one row per learner. Passwords stay in Supabase Auth (hashed); they are never stored or readable here.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  email text not null default '',
  created_at timestamptz not null default now(),
  last_login timestamptz,
  last_seen timestamptz,
  logins integer not null default 0,
  total_seconds integer not null default 0,
  is_admin boolean not null default false
);

-- Sessions: one row per visit, with the time spent in it.
create table if not exists public.sessions (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  last_ping timestamptz not null default now(),
  seconds integer not null default 0,
  device text not null default ''
);
create index if not exists sessions_user_idx on public.sessions(user_id, started_at desc);

-- Course progress, synced across devices.
create table if not exists public.progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  course text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, course)
);

-- New sign-up → profile row (name comes from the sign-up form).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, is_admin)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', ''), coalesce(new.email, ''), lower(coalesce(new.email, '')) = lower('ADMIN_EMAIL_HERE'))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Admin check used by the access rules below.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- Start a visit: counts a login and opens a session. Returns the session id.
create or replace function public.start_session(p_device text) returns bigint
language plpgsql security definer set search_path = public as $$
declare sid bigint;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  update public.profiles set logins = logins + 1, last_login = now(), last_seen = now() where id = auth.uid();
  insert into public.sessions (user_id, device) values (auth.uid(), left(coalesce(p_device, ''), 200)) returning id into sid;
  return sid;
end $$;

-- Heartbeat while the page is open and visible: adds the active seconds (capped, so a stuck tab can't inflate time).
create or replace function public.heartbeat(p_session bigint, p_seconds integer) returns void
language plpgsql security definer set search_path = public as $$
declare add_s integer := greatest(0, least(coalesce(p_seconds, 0), 120));
begin
  if auth.uid() is null then return; end if;
  update public.sessions set seconds = seconds + add_s, last_ping = now() where id = p_session and user_id = auth.uid();
  if found then update public.profiles set total_seconds = total_seconds + add_s, last_seen = now() where id = auth.uid(); end if;
end $$;

-- Access rules: everyone sees and edits only their own rows; the admin can read everything.
alter table public.profiles enable row level security;
alter table public.sessions enable row level security;
alter table public.progress enable row level security;

drop policy if exists "own profile read" on public.profiles;
drop policy if exists "own profile update" on public.profiles;
drop policy if exists "own sessions read" on public.sessions;
drop policy if exists "own progress" on public.progress;
drop policy if exists "admin progress read" on public.progress;

create policy "own profile read" on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "own profile update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid() and is_admin = (select p.is_admin from public.profiles p where p.id = auth.uid()));
create policy "own sessions read" on public.sessions for select using (user_id = auth.uid() or public.is_admin());
create policy "own progress" on public.progress for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "admin progress read" on public.progress for select using (public.is_admin());

grant execute on function public.start_session(text) to authenticated;
grant execute on function public.heartbeat(bigint, integer) to authenticated;
grant execute on function public.is_admin() to authenticated;

-- The admin account: whoever signs up with ADMIN_EMAIL_HERE becomes admin automatically. This line also covers an admin who signed up earlier.
update public.profiles set is_admin = true where lower(email) = lower('ADMIN_EMAIL_HERE');

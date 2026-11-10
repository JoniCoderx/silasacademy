-- Silas Academy: lock the course material behind sign-in.
-- The course pages (/strategy/, /advanced/, /corporate/, /career/) carry their lessons and questions encrypted.
-- This table holds the key. Row-level security lets only signed-in, unblocked learners read it; visitors and
-- search engines see the public course page and the free guides. Run once in Supabase → SQL Editor → New query.
-- The key itself is NOT stored in this repository: replace PASTE_THE_KEY_HERE with the key you were given privately.

create table if not exists public.app_keys (id text primary key, k text not null);
alter table public.app_keys enable row level security;
revoke all on public.app_keys from anon;
grant select on public.app_keys to authenticated;

drop policy if exists "learners read the content key" on public.app_keys;
create policy "learners read the content key" on public.app_keys for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and coalesce(p.blocked, false) = false));

insert into public.app_keys (id, k) values ('content', 'PASTE_THE_KEY_HERE')
  on conflict (id) do update set k = excluded.k;

-- Check: one row, key_length 64.
select id, length(k) as key_length from public.app_keys;

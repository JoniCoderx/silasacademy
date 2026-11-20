-- Silas Academy: let the admin block or unblock a user's access, with a message the user sees.
-- Run once in Supabase → SQL Editor (after supabase-setup.sql).

alter table public.profiles add column if not exists blocked boolean not null default false;
alter table public.profiles add column if not exists block_message text not null default '';

-- Only an admin can change these, and never on another admin.
create or replace function public.set_block(p_user uuid, p_blocked boolean, p_message text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.profiles set blocked = coalesce(p_blocked, false), block_message = left(coalesce(p_message, ''), 500)
  where id = p_user and not is_admin;
end $$;
grant execute on function public.set_block(uuid, boolean, text) to authenticated;

create or replace function public.is_blocked() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select blocked from public.profiles where id = auth.uid()), false)
$$;
grant execute on function public.is_blocked() to authenticated;

-- A user can still edit their own name, but not their admin or blocked status.
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update using (id = auth.uid())
  with check (id = auth.uid()
    and is_admin = (select p.is_admin from public.profiles p where p.id = auth.uid())
    and blocked = (select p.blocked from public.profiles p where p.id = auth.uid())
    and block_message = (select p.block_message from public.profiles p where p.id = auth.uid()));

-- A blocked user's progress is frozen: they can't read or write it.
drop policy if exists "own progress" on public.progress;
create policy "own progress" on public.progress for all
  using (user_id = auth.uid() and not public.is_blocked())
  with check (user_id = auth.uid() and not public.is_blocked());

-- Heartbeat now also tells the page whether the account was blocked meanwhile.
drop function if exists public.heartbeat(bigint, integer);
create function public.heartbeat(p_session bigint, p_seconds integer) returns boolean
language plpgsql security definer set search_path = public as $$
declare add_s integer := greatest(0, least(coalesce(p_seconds, 0), 120));
begin
  if auth.uid() is null then return false; end if;
  if public.is_blocked() then return true; end if;
  update public.sessions set seconds = seconds + add_s, last_ping = now() where id = p_session and user_id = auth.uid();
  if found then update public.profiles set total_seconds = total_seconds + add_s, last_seen = now() where id = auth.uid(); end if;
  return false;
end $$;
grant execute on function public.heartbeat(bigint, integer) to authenticated;

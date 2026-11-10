-- Silas Academy: live status, location per visit (city / country) and refresh-safe visits for the admin panel.
-- Run once in Supabase → SQL Editor (after supabase-setup.sql and supabase-block.sql).

alter table public.sessions add column if not exists country text not null default '';
alter table public.sessions add column if not exists city text not null default '';
alter table public.sessions add column if not exists flag text not null default '';

-- The page reports where the visit comes from; it can only label its own session.
create or replace function public.set_session_geo(p_session bigint, p_country text, p_city text, p_flag text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  update public.sessions
     set country = left(coalesce(p_country, ''), 60), city = left(coalesce(p_city, ''), 60), flag = left(coalesce(p_flag, ''), 8)
   where id = p_session and user_id = auth.uid();
end $$;
grant execute on function public.set_session_geo(bigint, text, text, text) to authenticated;

-- Disconnect: the page reports when a visit ends (sign-out or closing the page), so "online now" is exact.
alter table public.sessions add column if not exists ended_at timestamptz;
create or replace function public.end_session(p_session bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  update public.sessions set ended_at = now(), last_ping = now() where id = p_session and user_id = auth.uid() and ended_at is null;
end $$;
grant execute on function public.end_session(bigint) to authenticated;

-- Refresh: reloading the page continues the same visit (within two minutes) instead of a disconnect and a new entry.
create or replace function public.resume_session(p_session bigint) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  update public.sessions set ended_at = null, last_ping = now()
   where id = p_session and user_id = auth.uid() and (ended_at is null or ended_at > now() - interval '2 minutes');
  return found;
end $$;
grant execute on function public.resume_session(bigint) to authenticated;

-- Silas Academy: sign-in / sign-up hardening.
-- Run in Supabase → SQL Editor → New query. It sends nothing and deletes nothing.
-- PART 1 is safe to run now. PART 2 only AFTER you have turned on two-step login for the admin account in the site
-- (החשבון שלי → אימות דו־שלבי), otherwise the admin panel stops opening until you do.

-- ======================= PART 1 (run now) =======================

-- 1) A name is a name: no links, no addresses, no markup, at most 30 characters.
--    Names go into the welcome email that is sent from support@, so a "name" must never be able to carry a link.
create or replace function public.clean_name(p text) returns text
language sql immutable set search_path = public as $$
  -- order: drop control characters → drop links and web addresses → markup/@ become spaces → collapse spaces → cut to 30
  select left(btrim(regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(
                 regexp_replace(coalesce(p, ''), '[[:cntrl:]]', '', 'g'),
               '(https?://|www\.)\S*', '', 'gi'),
             '\S+\.(com|net|org|io|co|il|ru|xyz|info|biz|me|link|app|site|online|top|click|ly|gl)\y\S*', '', 'gi'),
           '[<>@/\\{}\[\]]', ' ', 'g'),
         '\s+', ' ', 'g')), 30)
$$;
revoke all on function public.clean_name(text) from public, anon, authenticated;

-- 2) New accounts: the name is cleaned, and NOBODY becomes admin by registering with some email address.
--    (Before, whoever registered with the admin's address would have become admin if that account were ever deleted.)
--    The existing admin keeps the admin flag; this only affects new sign-ups.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, is_admin)
  values (new.id, public.clean_name(new.raw_user_meta_data->>'name'), coalesce(new.email, ''), false)
  on conflict (id) do nothing;
  return new;
end $$;

-- 3) The same rule for renames from the account page (checked by the database, not only by the page).
--    NOT VALID = existing names are left as they are; only new writes are checked.
alter table public.profiles drop constraint if exists profiles_name_safe;
alter table public.profiles add constraint profiles_name_safe
  check (char_length(name) <= 30 and name !~* '(https?://|www\.)' and name !~ '[<>@]') not valid;

-- 4) The welcome email goes out only once the address is CONFIRMED (not at sign-up),
--    so nobody can make support@ send email to a stranger's address by registering with it.
drop trigger if exists on_profile_created_welcome on public.profiles;
create or replace function public.on_user_confirmed_welcome() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.email_confirmed_at is not null and (tg_op = 'INSERT' or old.email_confirmed_at is null) then
    begin perform public.send_welcome(new.email, public.clean_name(new.raw_user_meta_data->>'name')); exception when others then null; end;
  end if;
  return new;
end $fn$;
revoke all on function public.on_user_confirmed_welcome() from public, anon, authenticated;
drop trigger if exists on_auth_user_confirmed_welcome on auth.users;
create trigger on_auth_user_confirmed_welcome after insert or update of email_confirmed_at on auth.users
  for each row execute function public.on_user_confirmed_welcome();

-- 5) A learner may change only their own NAME. Before this, a learner could rewrite other columns of their own
--    profile row (email, login counts, time on site) and the admin panel would show the fake values.
--    The site itself only ever updates the name; the server functions (heartbeat, set_block...) are not affected.
revoke update on public.profiles from anon, authenticated;
grant update (name) on public.profiles to authenticated;

-- Check: should list exactly one admin (you), and the two triggers on auth.users.
select email, is_admin from public.profiles where is_admin;
select tgname from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;


-- ======================= PART 2 (only after the admin turned on two-step login) =======================
-- Admin powers (seeing everyone, blocking, sending reminders) then need the 6-digit code too, enforced by the database:
-- a stolen admin password alone is no longer enough.
--
-- create or replace function public.is_admin() returns boolean
-- language sql stable security definer set search_path = public as $$
--   select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
--      and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
-- $$;
--
-- Undo PART 2 (e.g. if you lose the phone with the authenticator app):
-- create or replace function public.is_admin() returns boolean
-- language sql stable security definer set search_path = public as $$
--   select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
-- $$;

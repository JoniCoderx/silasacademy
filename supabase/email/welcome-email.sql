-- Silas Academy: welcome email for every new sign-up (free, through Brevo).
-- Run once in Supabase → SQL Editor, AFTER replacing the two values in the box below.

-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │ 1. BREVO_API_KEY_HERE  → your Brevo API key (starts with xkeysib-)         │
-- │ 2. SENDER_EMAIL_HERE   → the sender address you verified in Brevo          │
-- └───────────────────────────────────────────────────────────────────────────┘
-- The API key is stored encrypted in Supabase Vault. It is never in the website.

create extension if not exists pg_net with schema extensions;

delete from vault.secrets where name = 'brevo_api_key';
select vault.create_secret('BREVO_API_KEY_HERE', 'brevo_api_key', 'Brevo API key for welcome emails');

create table if not exists public.email_settings (id int primary key default 1, sender_email text not null, sender_name text not null default 'Silas Academy', site_url text not null);
alter table public.email_settings enable row level security;
insert into public.email_settings (id, sender_email, site_url) values (1, 'SENDER_EMAIL_HERE', 'https://silasacademy.com/')
  on conflict (id) do update set sender_email = excluded.sender_email, site_url = excluded.site_url;

-- Builds and sends the email. Used by the sign-up trigger and by the test below.
create or replace function public.send_welcome(p_email text, p_name text) returns void
language plpgsql security definer set search_path = public, extensions as $fn$
declare k text; st public.email_settings; nm text; em text; html text; txt text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'brevo_api_key' limit 1;
  select * into st from public.email_settings where id = 1;
  if k is null or st is null or coalesce(p_email, '') = '' then return; end if;
  nm := coalesce(nullif(trim(p_name), ''), 'שלום');
  nm := replace(replace(replace(nm, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  em := replace(replace(replace(p_email, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  html := replace(replace(replace($tpl$<!doctype html>
<html lang="he" dir="rtl" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>ברוכים הבאים לאקדמיית סיילס</title>
<style>
  body{margin:0;padding:0;background:#f3f5fa}
  a{color:#2337b4}
  @media (max-width:600px){.px{padding-left:20px!important;padding-right:20px!important}.h1{font-size:26px!important;line-height:34px!important}}
  @media (prefers-color-scheme:dark){
    body,.bg{background:#0a0e22!important}
    .card{background:#121834!important}
    .ink{color:#eceffa!important}
    .muted{color:#a0a7c6!important}
    .step{background:#0d1229!important}
    .tip{background:#2c2812!important}
    .tipt{color:#f5d547!important}
    .line{border-color:#232b52!important}
    .stepb{color:#a9b4ff!important}
  }
</style>
</head>
<body style="margin:0;padding:0;background:#f3f5fa;" class="bg">
<!-- preheader: the line inbox apps show next to the subject -->
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">{{name}}, החשבון שלכם מוכן. הנה איך מתחילים ללמוד.&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg" style="background:#f3f5fa;">
<tr><td align="center" style="padding:28px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
    <!-- brand -->
    <tr><td dir="ltr" style="padding:0 4px 18px;text-align:left;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" align="left" dir="ltr"><tr>
        <td style="padding-right:10px;vertical-align:middle;"><img src="{{site}}email/logo.png" width="40" height="40" alt="Silas Academy" style="display:block;border:0;border-radius:12px;"></td>
        <td style="vertical-align:middle;font-family:Rubik,'Segoe UI',Arial,sans-serif;font-size:20px;line-height:22px;color:#0f1430;" class="ink" dir="ltr"><b>silas</b> <span style="color:#5d6482;" class="muted">academy</span></td>
      </tr></table>
    </td></tr>
    <!-- hero -->
    <tr><td dir="rtl" class="px" style="background:#1a2580;background-image:linear-gradient(160deg,#2337b4,#0c1234);border-radius:22px 22px 0 0;padding:36px 36px 30px;text-align:right;">
      <p style="margin:0 0 10px;font-family:Arial,sans-serif;font-size:13px;color:#c9cff5;">ברוכים הבאים לאקדמיית סיילס</p>
      <h1 class="h1" style="margin:0;font-family:Rubik,'Segoe UI',Arial,sans-serif;font-size:30px;line-height:38px;font-weight:800;color:#ffffff;">{{name}}, נעים להכיר!</h1>
      <p style="margin:12px 0 0;font-family:Arial,sans-serif;font-size:17px;line-height:27px;color:#ffffff;">לומדים להבין, <span style="background:#f5d547;color:#1a1a05;padding:0 4px;border-radius:3px;">לא לשנן</span>.</p>
    </td></tr>
    <!-- body -->
    <tr><td dir="rtl" class="card px" style="background:#ffffff;border-radius:0 0 22px 22px;padding:30px 36px 34px;text-align:right;">
      <p class="ink" style="margin:0 0 22px;font-family:Arial,sans-serif;font-size:16px;line-height:27px;color:#0f1430;">תודה שהצטרפתם. החשבון שלכם מוכן, ואפשר להתחיל ללמוד כבר עכשיו. ההתקדמות, הטעויות והציונים נשמרים בחשבון, כך שתמיד ממשיכים בדיוק מאיפה שעצרתם.</p>
      <p class="ink" style="margin:0 0 12px;font-family:Rubik,'Segoe UI',Arial,sans-serif;font-size:15px;font-weight:700;color:#0f1430;">איך מתחילים:</p>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
        <tr><td class="step" style="background:#eceff7;border-radius:14px;padding:14px 16px;" dir="rtl">
          <p class="ink" style="margin:0;font-family:Arial,sans-serif;font-size:15px;line-height:24px;color:#0f1430;"><b class="stepb" style="color:#2337b4;">1. בוחרים קורס.</b> כל הקורסים מחכים בדף הבית, וההתקדמות נשמרת בכל אחד מהם.</p>
        </td></tr>
        <tr><td style="height:8px;line-height:8px;font-size:8px;">&nbsp;</td></tr>
        <tr><td class="step" style="background:#eceff7;border-radius:14px;padding:14px 16px;" dir="rtl">
          <p class="ink" style="margin:0;font-family:Arial,sans-serif;font-size:15px;line-height:24px;color:#0f1430;"><b class="stepb" style="color:#2337b4;">2. לומדים מאפס.</b> כל נושא מתחיל בהסבר פשוט, נוסחה ודוגמה פתורה.</p>
        </td></tr>
        <tr><td style="height:8px;line-height:8px;font-size:8px;">&nbsp;</td></tr>
        <tr><td class="step" style="background:#eceff7;border-radius:14px;padding:14px 16px;" dir="rtl">
          <p class="ink" style="margin:0;font-family:Arial,sans-serif;font-size:15px;line-height:24px;color:#0f1430;"><b class="stepb" style="color:#2337b4;">3. מתרגלים עם הסבר לכל טעות.</b> על כל תשובה שגויה מקבלים הסבר: מאיפה היא הגיעה, ואיך פותרים נכון. ובסוף, מבחנים לדוגמה.</p>
        </td></tr>
      </table>
      <!-- button (bulletproof: a padded link inside a table cell, works in Outlook too) -->
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" align="right" style="margin:26px 0 0;">
        <tr><td style="background:#2337b4;border-radius:12px;">
          <a href="{{site}}" target="_blank" style="display:inline-block;padding:15px 30px;font-family:Rubik,'Segoe UI',Arial,sans-serif;font-size:17px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:12px;">להתחיל ללמוד</a>
        </td></tr>
      </table>
      <div style="clear:both;line-height:0;font-size:0;">&nbsp;</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:26px;">
        <tr><td class="tip" style="background:#fdf3c8;border-radius:14px;padding:14px 16px;" dir="rtl">
          <p class="tipt" style="margin:0;font-family:Arial,sans-serif;font-size:14px;line-height:23px;color:#5c4700;"><b>טיפ:</b> 20 דקות ביום עדיפות על יום ארוך אחד בשבוע. נכנסים, פותרים כמה שאלות, וקוראים את ההסבר של כל טעות.</p>
        </td></tr>
      </table>
      <p class="muted" style="margin:24px 0 0;font-family:Arial,sans-serif;font-size:14px;line-height:23px;color:#5d6482;">בהצלחה,<br>צוות אקדמיית סיילס</p>
    </td></tr>
    <!-- footer -->
    <tr><td dir="rtl" style="padding:20px 8px 0;text-align:center;">
      <p class="muted" style="margin:0;font-family:Arial,sans-serif;font-size:12px;line-height:19px;color:#5d6482;">קיבלתם את המייל הזה כי נרשמתם לאקדמיית סיילס עם הכתובת {{email}}.<br>שאלות? כתבו לנו: <a href="mailto:support@silasacademy.com" style="color:#5d6482;" dir="ltr">support@silasacademy.com</a><br>© Silas Academy · אקדמיית סיילס</p>
    </td></tr>
  </table>
</td></tr>
</table>
</body>
</html>
$tpl$, '{{name}}', nm), '{{email}}', em), '{{site}}', st.site_url);
  txt := replace(replace(replace($txt${{name}}, נעים להכיר!

תודה שהצטרפתם לאקדמיית סיילס. החשבון שלכם מוכן, ואפשר להתחיל ללמוד כבר עכשיו.

איך מתחילים:
1. בוחרים קורס. כל הקורסים מחכים בדף הבית, וההתקדמות נשמרת בכל אחד מהם.
2. לומדים מאפס: הסבר פשוט, נוסחה ודוגמה פתורה.
3. מתרגלים עם הסבר לכל טעות, ובסוף מבחנים לדוגמה.

להתחיל ללמוד: {{site}}

טיפ: 20 דקות ביום עדיפות על יום ארוך אחד בשבוע.

בהצלחה,
צוות אקדמיית סיילס

קיבלתם את המייל כי נרשמתם לאקדמיית סיילס עם הכתובת {{email}}.$txt$, '{{name}}', coalesce(nullif(trim(p_name), ''), 'שלום')), '{{email}}', p_email), '{{site}}', st.site_url);
  perform net.http_post(
    url := 'https://api.brevo.com/v3/smtp/email',
    headers := jsonb_build_object('api-key', k, 'Content-Type', 'application/json', 'accept', 'application/json'),
    body := jsonb_build_object(
      'sender', jsonb_build_object('name', st.sender_name, 'email', st.sender_email),
      'to', jsonb_build_array(jsonb_build_object('email', p_email, 'name', coalesce(nullif(trim(p_name), ''), p_email))),
      'subject', coalesce(nullif(trim(p_name), ''), 'שלום') || ', ברוכים הבאים לאקדמיית סיילס',
      'htmlContent', html,
      'textContent', txt,
      'tags', jsonb_build_array('welcome')));
end $fn$;
revoke all on function public.send_welcome(text, text) from public, anon, authenticated;

-- Every new profile (= every new sign-up) gets the welcome email. An email problem never blocks a sign-up.
create or replace function public.on_profile_welcome() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  begin perform public.send_welcome(new.email, new.name); exception when others then null; end;
  return new;
end $fn$;
drop trigger if exists on_profile_created_welcome on public.profiles;
create trigger on_profile_created_welcome after insert on public.profiles for each row execute function public.on_profile_welcome();

-- Test: sends the welcome email to the sender address. Check the inbox (and the spam / promotions tab).
select public.send_welcome((select sender_email from public.email_settings where id = 1), 'Admin');

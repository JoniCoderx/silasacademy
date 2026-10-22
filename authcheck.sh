#!/bin/bash
# Outsider check of sign-in/sign-up, using only what anyone can see (the public page and the publishable key). Creates no accounts.
K=sb_publishable_lFPddHMR7XYQyNexNji-4g_eiftzZZ7; U=https://tsgbbmsqxxhggsmxjqpm.supabase.co; SITE=https://silasacademy.com/
r(){ printf '%-4s %s %s\n' "$1" "$2" "$3"; }
st=$(curl -s "$U/auth/v1/settings" -H "apikey: $K")
echo "$st" | grep -q '"mailer_autoconfirm":false' && r PASS "email must be confirmed before the account works" || r FAIL "email confirmation is OFF (anyone can register with someone else's address)"
echo "$st" | grep -q '"anonymous_users":false' && r PASS "anonymous sign-ins off" || r FAIL "anonymous sign-ins on"
min=$(curl -s -X POST "$U/auth/v1/signup" -H "apikey: $K" -H "Content-Type: application/json" -d '{"email":"probe@example.invalid","password":"1"}' | grep -o 'at least [0-9]*' | grep -o '[0-9]*')
[ "${min:-0}" -ge 8 ] && r PASS "server minimum password length" "$min" || r FAIL "server minimum password length is ${min:-?} (should be 8+)"
page=$(curl -s "$SITE"; curl -s "${SITE}corporate/")
echo "$page" | grep -qiE "adminEmail|adminUser|@gmail\.com" && r FAIL "an admin address is visible in the page" || r PASS "no admin address in the page"
echo "$page" | grep -q "mfaVerify" && r PASS "2-step login is in the site" || r FAIL "2-step login missing from the site"
for f in send_welcome clean_name on_user_confirmed_welcome; do c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$U/rest/v1/rpc/$f" -H "apikey: $K" -H "Content-Type: application/json" -d '{}'); [ "$c" != 200 ] && [ "$c" != 204 ] && r PASS "outsiders cannot run $f" "($c)" || r FAIL "outsiders can run $f"; done

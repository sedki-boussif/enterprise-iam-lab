#!/bin/bash
set -u
cd "$(dirname "$0")/.."
source .env

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }
c()  { docker compose exec -T linux-client "$@"; }
ad() { docker compose exec -T samba-ad "$@"; }
radius() { c radtest "$1" "$2" freeradius 0 "$RADIUS_SHARED_SECRET" 2>&1; }

# always leave carol enabled, even if the script is interrupted
trap 'ad samba-tool user enable carol >/dev/null 2>&1; c kdestroy >/dev/null 2>&1' EXIT
ad samba-tool user enable carol >/dev/null 2>&1

echo "== Kerberos =="
echo "$SEED_USER_PASSWORD" | c kinit alice@COMPANY.LOCAL >/dev/null 2>&1 \
  && pass 'T5 alice gets a TGT' || fail 'T5 alice gets a TGT'
c ldapsearch -Y GSSAPI -H ldap://dc1.company.local -b 'DC=company,DC=local' '(sAMAccountName=alice)' memberOf 2>/dev/null | grep -q 'GG-HR' \
  && pass 'T5 GSSAPI LDAP query without password' || fail 'T5 GSSAPI LDAP query without password'
c kdestroy >/dev/null 2>&1
echo wrong | c kinit alice@COMPANY.LOCAL >/dev/null 2>&1 \
  && fail 'T6 wrong password accepted' || pass 'T6 wrong password rejected'
echo "$SEED_USER_PASSWORD" | c kinit eve@COMPANY.LOCAL >/dev/null 2>&1 \
  && fail 'T6 disabled user accepted' || pass 'T6 disabled user rejected'

echo "== RADIUS =="
radius alice "$SEED_USER_PASSWORD" | grep -q Access-Accept \
  && pass 'T7 alice accepted' || fail 'T7 alice accepted'
radius alice "$SEED_USER_PASSWORD" | grep -q 'Tunnel-Private-Group-Id.*20' \
  && pass 'T7 HR user gets VLAN 20' || fail 'T7 HR user gets VLAN 20'
radius bob "$SEED_USER_PASSWORD" | grep -q 'Tunnel-Private-Group-Id' \
  && fail 'T7 non-HR user got a VLAN' || pass 'T7 non-HR user gets no VLAN'
radius alice wrong-password | grep -q Access-Reject \
  && pass 'T8 wrong password rejected' || fail 'T8 wrong password rejected'
radius eve "$SEED_USER_PASSWORD" | grep -q Access-Reject \
  && pass 'T8 disabled user rejected' || fail 'T8 disabled user rejected'

echo "== Identity lifecycle (carol) =="
radius carol "$SEED_USER_PASSWORD" | grep -q Access-Accept \
  && pass 'T10 carol accepted while enabled' || fail 'T10 carol accepted while enabled'
ad samba-tool user disable carol >/dev/null 2>&1
echo "$SEED_USER_PASSWORD" | c kinit carol@COMPANY.LOCAL >/dev/null 2>&1 \
  && fail 'T10 disabled carol got a ticket' || pass 'T10 disabled carol refused by Kerberos'
radius carol "$SEED_USER_PASSWORD" | grep -q Access-Reject \
  && pass 'T10 disabled carol refused by RADIUS' || fail 'T10 disabled carol refused by RADIUS'

echo
[ "$FAILED" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAILED

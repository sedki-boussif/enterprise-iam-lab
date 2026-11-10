#!/bin/bash
set -euo pipefail
BASE="DC=${DOMAIN//./,DC=}"

for ou in HR IT Development Admins Groups ServiceAccounts; do
  samba-tool ou create "OU=$ou,$BASE"
done

for g in GG-Employees GG-HR GG-IT GG-Dev GG-Admins; do
  samba-tool group add "$g" --groupou='OU=Groups'
done

mk() { samba-tool user create "$1" "$2" --given-name="$3" --surname="$4" --userou="OU=$5" --use-username-as-cn; }

mk alice "$SEED_USER_PASSWORD" Alice Hr HR
mk bob "$SEED_USER_PASSWORD" Bob Dev Development
mk carol "$SEED_USER_PASSWORD" Carol It IT
mk admin1 "$SEED_USER_PASSWORD" Admin One Admins
mk eve "$SEED_USER_PASSWORD" Eve Disabled Development
mk svc-keycloak "$SVC_KEYCLOAK_PASSWORD" Svc Keycloak ServiceAccounts
mk svc-radius "$SVC_RADIUS_PASSWORD" Svc Radius ServiceAccounts

samba-tool group addmembers GG-Employees alice,bob,carol,admin1,eve
samba-tool group addmembers GG-HR alice
samba-tool group addmembers GG-Dev bob
samba-tool group addmembers GG-IT carol,admin1
samba-tool group addmembers GG-Admins admin1
samba-tool user disable eve

# Lab only: keep demo passwords from expiring (Samba default max age is 42 days)
for u in Administrator alice bob carol admin1 eve svc-keycloak svc-radius; do
  samba-tool user setexpiry "$u" --noexpiry
done

# Lab only: deliberately vulnerable test account for the AS-REP roasting demo
samba-tool user create asrep-target "$SEED_USER_PASSWORD" --given-name=ASREP --surname=Target --userou="OU=Development" --use-username-as-cn
samba-tool user setexpiry asrep-target --noexpiry
ldapmodify -x -H ldap://127.0.0.1 -D "administrator@${DOMAIN}" -w "$ADMIN_PASSWORD" <<LDIF
dn: CN=asrep-target,OU=Development,DC=${DOMAIN//./,DC=}
changetype: modify
replace: userAccountControl
userAccountControl: 4194816
LDIF

# Lab only: deliberately weak service account with an SPN for the Kerberoasting demo
samba-tool user create svc-weak 'Dragon123' --given-name=Service --surname=Weak --userou="OU=ServiceAccounts" --use-username-as-cn
samba-tool user setexpiry svc-weak --noexpiry
samba-tool spn add HTTP/fileserver.company.local svc-weak

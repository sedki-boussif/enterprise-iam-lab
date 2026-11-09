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

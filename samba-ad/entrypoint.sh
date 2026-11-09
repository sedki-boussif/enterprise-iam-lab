#!/bin/bash
set -euo pipefail

if [ ! -f /var/lib/samba/private/sam.ldb ]; then
  rm -f /etc/samba/smb.conf
  samba-tool domain provision \
    --realm="$REALM" --domain="$NETBIOS" \
    --server-role=dc --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASSWORD" --use-rfc2307 \
    --option="dns forwarder=$DNS_FORWARDER" \
    --option='ldap server require strong auth=no'
fi

# Intentional lab weakness (fixed in the security phase): allow simple binds on plain LDAP
if ! grep -q 'ldap server require strong auth' /etc/samba/smb.conf; then
  sed -i '/^\[global\]/a\        ldap server require strong auth = no' /etc/samba/smb.conf
fi

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

samba --foreground --no-process-group &
SAMBA_PID=$!

until ldapsearch -x -H ldap://127.0.0.1 -s base -b '' namingContexts >/dev/null 2>&1; do sleep 2; done

if [ ! -f /var/lib/samba/.seeded ]; then
  /opt/seed.sh && touch /var/lib/samba/.seeded
fi

wait $SAMBA_PID

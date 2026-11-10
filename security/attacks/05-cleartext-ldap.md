# Scenario 5: Cleartext credentials on the wire

## Goal
Show that a simple LDAP bind on port 389 sends the password unencrypted, and that an attacker with visibility into the network segment can read it directly from the traffic.

## Setup
- Samba is configured with `ldap server require strong auth = no` (Phase 1), an intentional lab weakness that allows simple binds over plain LDAP.
- Capture point: the Docker bridge for the `iamnet` network, found with `docker network inspect enterprise-iam-lab_iamnet`.

## Attack
Capture command: `sudo tcpdump -i br-<id> -n -s0 -w ldap-cleartext.pcap 'tcp port 389'`

While the capture ran, a simple bind was performed as alice: `ldapsearch -x -H ldap://dc1.company.local -D 'alice@company.local' -w '<password>' -b 'DC=company,DC=local' '(sAMAccountName=alice)' dn`

## Evidence
Reading the capture with `tcpdump -r ldap-cleartext.pcap -A` shows the bind DN and password together in plain text inside the TCP payload: `alice@company.local..ChangeMe-User-1` (13 packets captured the full exchange).

## Detection
A packet capture is itself the evidence; there is no log-based detection for this one, since the server has no way to know the transport was unencrypted. The real control is prevention (below), not detection.

## Hardening
- Set `ldap server require strong auth = yes` in Samba, which refuses simple binds over plain LDAP.
- Move Keycloak's and FreeRADIUS's LDAP connections to LDAPS (port 636) with a certificate trusted by both.
- Re-test: repeat the capture during a bind attempt and confirm the bind is refused on 389, and that no readable credentials appear in a capture of port 636 (TLS).

## Re-test result
Not yet performed - tracked for when LDAPS is implemented.

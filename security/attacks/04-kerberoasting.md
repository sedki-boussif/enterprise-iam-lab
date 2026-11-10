# Scenario 4: Kerberoasting (enumeration succeeded; ticket extraction blocked by tooling interop)

## Goal
Request a Kerberos TGS ticket for a service account with an SPN, using only
an ordinary domain user's credentials, then crack the ticket offline to
recover the service account's password.

## Setup
- A dedicated service account, `svc-weak`, created with a deliberately weak
  password (`Dragon123`) and a registered SPN:
  `HTTP/fileserver.company.local`.
- Attacker credential used throughout: alice, an ordinary HR employee with
  no elevated rights.

## Attack — enumeration (succeeded)
    GetUserSPNs.py COMPANY.LOCAL/alice:<password> -dc-ip 172.28.0.10

This is a plain LDAP query filtered on `servicePrincipalName`, and alice's
ordinary credentials were sufficient to list `svc-weak` and its SPN, its
`PasswordLastSet` date, and that it has never logged on — exactly the kind
of account a real attacker would prioritize (unmonitored service account
with no activity history).

## Attack — ticket request (blocked by tooling interop, not a lab defense)
    GetUserSPNs.py COMPANY.LOCAL/alice:<password> -dc-ip 172.28.0.10 -request

Every attempt (with default options, with `-no-rc4` to force AES-only, and
via a separately-cached TGT obtained with `getTGT.py`) failed with:

    Kerberos SessionError: KRB_AP_ERR_INAPP_CKSUM (Inappropriate type of checksum in message)

This error means the KDC rejected the checksum type used in the TGS
request's authenticator for the negotiated session key. It is a known class
of Kerberos library interoperability issue between Impacket and non-Windows
KDC implementations, not a password or permissions problem — the request
got as far as being evaluated and rejected on a protocol-level detail,
which is a different failure mode than the "account doesn't support this"
response seen in the AS-REP roasting scenario.

## What this demonstrates regardless
- The core vulnerability condition is real and present: any ordinary user
  can discover `svc-weak` and know it is a Kerberoastable target. In a real
  Windows AD environment (or with a different/older Impacket build, or a
  tool such as Rubeus), the ticket request step would very likely succeed,
  since this is one of the most reliable and widely-used AD attacks.
- This is the second Phase 5 scenario (after AS-REP roasting) where Samba
  AD DC's Kerberos implementation diverges from Windows AD in a way that
  affects standard offensive tooling — worth calling out explicitly in the
  README's limitations section as a pattern, not a one-off.

## Detection and hardening (valid regardless of this tooling issue)
- Enforce long, random passwords (25+ characters) on all service accounts;
  a Kerberoast hash is only useful if the password is crackable.
- Monitor for TGS-REQ bursts requesting tickets for many different SPNs
  from a single account in a short window — the same pattern-based
  detection approach used in the password-spraying scenario, applied to
  `authDescription: "Kerberos TGS"` events instead of AS-REQ events.
- Use Group Managed Service Accounts (gMSA) where supported, which rotate
  passwords automatically and are effectively immune to offline cracking.
- Minimize SPN usage on accounts with interactive-logon-capable passwords.

## Re-test result
Not applicable — ticket extraction could not be completed due to a tooling
interoperability issue rather than a tested and fixed vulnerability.

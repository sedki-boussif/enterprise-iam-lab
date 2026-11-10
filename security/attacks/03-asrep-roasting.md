# Scenario 3: AS-REP roasting (attempted — blocked by a Samba AD DC limitation)

## Goal
Request an AS-REP for an account with Kerberos pre-authentication disabled
(`UF_DONT_REQUIRE_PREAUTH`), using Impacket's GetNPUsers.py, and crack the
resulting hash offline.

## Setup
- A dedicated test user, `asrep-target`, was created in `OU=Development`.
- `userAccountControl` was set to `4194816` (`UF_NORMAL_ACCOUNT` |
  `UF_DONT_REQUIRE_PREAUTH`), confirmed via `samba-tool user show`.
- `msDS-SupportedEncryptionTypes` was also set (value `28`, AES128+AES256+RC4)
  to rule out an encryption-type mismatch as the cause.
- A valid keytab with 3 Kerberos keys (KVNO 3) was exported for the account
  with `samba-tool domain exportkeytab`, confirming the account genuinely has
  usable Kerberos key material.

## Attack
    GetNPUsers.py COMPANY.LOCAL/asrep-target -no-pass -dc-ip 172.28.0.10 -format hashcat

## Result
Every attempt returned:

    [-] User asrep-target doesn't have UF_DONT_REQUIRE_PREAUTH set

This is Impacket's message for a live KDC response of
`KDC_ERR_PREAUTH_REQUIRED` — i.e. Samba's internal KDC demanded
pre-authentication regardless of the account's `userAccountControl` flag.

## Troubleshooting performed
- Confirmed the flag via `samba-tool user show` after every change (always
  correct: `4194816`).
- Reset the account's password twice to force key regeneration.
- Did a full `make reset && make up` (completely fresh domain provision) —
  same result on a cold start, ruling out a stale cache.
- Restarted the samba-ad container — same result.
- Checked Samba's authentication audit log (`log.samba`) at the time of the
  attack: no Kerberos KDC entry for `asrep-target` appears at all, while the
  same log clearly captures entries for other accounts (alice, carol) in the
  same session. This suggests Samba's KDC rejects the no-preauth AS-REQ before
  the request reaches the point where an auth attempt is logged.
- Checked and set `msDS-SupportedEncryptionTypes` directly, in case Samba's
  KDC requires it to be explicitly populated to honor the preauth-skip path —
  no change in outcome.

## Conclusion
Samba AD DC's internal (Heimdal-based) KDC does not appear to honor
`UF_DONT_REQUIRE_PREAUTH` the way a real Windows AD DC does, at least not via
a direct LDAP attribute modification as used here. This matches this
project's own documented substitution: Samba AD DC is an open-source,
largely AD-compatible stand-in for Windows Server AD, but it is not a
byte-for-byte reimplementation, and Kerberos pre-authentication enforcement
is one place the two diverge. (Notably, Samba's own lead developer has
publicly argued against disabling pre-authentication at all, which may
explain why this path is not fully supported.)

## Detection and hardening (for a real Windows AD environment)
Even though this could not be demonstrated end-to-end against Samba, the
controls are worth stating for completeness, since this is a real and common
attack against genuine Windows AD:
- Audit `userAccountControl` for the `DONT_REQ_PREAUTH` bit across all
  accounts; alert on any account that has it set outside of a documented,
  approved exception.
- Monitor for Kerberos `AS-REQ` events with no corresponding pre-auth success
  (Windows Event ID 4768 with no preceding 4771), which is the signature of
  this attack against a real Windows KDC.
- Avoid disabling pre-authentication for any account; where legacy clients
  require it, scope it as narrowly as possible and treat the account as
  high-risk.

## Re-test result
Not applicable — the attack could not be reproduced against this lab's
Samba AD DC. Documented as a platform limitation rather than a fixed
vulnerability.

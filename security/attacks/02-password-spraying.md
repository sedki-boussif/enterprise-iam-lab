# Scenario 2: Password spraying

## Goal
Show that trying one common password across many accounts stays under Samba's
per-user lockout threshold, and that it is still visible in the logs as a pattern:
many different usernames failing from one source in a short window.

## Setup
- Samba auth_audit logging enabled (`log level = 1 auth_audit:3 auth_json_audit:3`),
  emitting JSON authentication events to `/var/log/samba/log.samba`.
- Target users: the 7 seeded accounts plus 5 made-up usernames, to simulate an
  attacker guessing at the directory without prior knowledge of real accounts.

## Attack
A single password, `Summer2026!`, was tried via `kinit` against each username in
sequence from the linux-client container:

    while read -r user; do
      echo "$SPRAY_PASSWORD" | kinit "$user@COMPANY.LOCAL"
    done < userlist.txt

All 12 attempts failed, confirming no account used that password, and no lockout
was triggered by a handful of per-user attempts.

## Evidence
Samba's JSON audit log recorded each attempt. Real accounts returned
`NT_STATUS_WRONG_PASSWORD`; invented usernames returned `NT_STATUS_NO_SUCH_USER`,
which itself leaks which usernames are valid:

    {"clientAccount": "alice@COMPANY.LOCAL", "status": "NT_STATUS_WRONG_PASSWORD", ...}
    {"clientAccount": "jdoe@COMPANY.LOCAL", "status": "NT_STATUS_NO_SUCH_USER", ...}

## Detection
`security/detections/password-spray.py` reads the JSON audit log, groups failed
attempts by source IP within a 60-second window, and alerts when 5 or more
distinct accounts are tried from the same IP. Run against this attack's log it
produced:

    ALERT: possible password spray from 172.28.0.5
    window: 2026-11-10 14:16:55 -> 14:16:56 (5 distinct accounts)
    accounts tried: admin1, alice, bob, carol, eve

## Hardening
- Account lockout policy: `samba-tool domain passwordsettings set
  --account-lockout-threshold=5 --account-lockout-duration=30
  --reset-account-lockout-after=30`.
- Longer, higher-entropy passwords for all seeded accounts.
- Run the detection script continuously (or on a timer) rather than on demand.

## Re-test result
Not yet performed — tracked for after the lockout policy is applied.

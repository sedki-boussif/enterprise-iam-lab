# Scenario 1: LDAP enumeration

## Goal
Show that any authenticated user, even an ordinary employee with no special
rights, can read nearly the entire directory over a simple LDAP bind: every
account, group membership, disabled users and service accounts.

## Setup
- Samba's intentional lab weakness (`ldap server require strong auth = no`)
  allows simple binds with a username and password over plain LDAP.
- By default, authenticated users in AD have read access to most directory
  attributes. No special permissions were granted to alice for this test.

## Attack
All queries were run as alice, an HR employee, from the linux-client
container, using nothing but her own login password:

    ldapsearch -x -H ldap://dc1.company.local -D 'alice@company.local' \
      -w '<password>' -b 'DC=company,DC=local' '(objectClass=user)' sAMAccountName

The same bind was reused with different filters to enumerate members of the
`GG-Admins` group, disabled accounts, and the contents of the
`ServiceAccounts` OU.

## Evidence
A single query returned all 11 accounts in the domain, including the
built-in Administrator, the krbtgt account, and the domain controller's own
machine account (`DC1$`):

    sAMAccountName: Administrator
    sAMAccountName: carol
    sAMAccountName: bob
    sAMAccountName: admin1
    sAMAccountName: alice
    sAMAccountName: svc-radius
    sAMAccountName: eve
    sAMAccountName: svc-keycloak
    ... (11 total)

A filter on `cn=GG-Admins` revealed that `admin1` is the only member of the
privileged admin group, directly identifying the account to target for
privilege escalation:

    dn: CN=GG-Admins,OU=Groups,DC=company,DC=local
    member: CN=admin1,OU=Admins,DC=company,DC=local

A filter on the `userAccountControl` bitmask found every disabled account
(`eve`, plus the built-in `krbtgt` and `Guest`), and a scoped search of
`OU=ServiceAccounts` listed both service accounts by name, which are the
usual next targets for Kerberoasting.

## Detection
A single LDAP bind and search is indistinguishable from normal application
behavior (Keycloak and FreeRADIUS both do this routinely). What stands out
is volume and pattern: many searches, covering broad or sensitive filters
(`objectClass=user`, `cn=GG-Admins`, `userAccountControl` bitmasks), from one
account or source in a short window. Samba's `auth_audit` logging (enabled
in the password-spraying scenario) records each bind, but not the search
filters themselves; a full LDAP query audit would need `dsdb_json_audit`
or a network-level capture, which is listed below as a hardening follow-up
rather than implemented here.

## Hardening
- Disable anonymous LDAP binds (already the default in this lab; worth
  stating explicitly in the README as a control, not an assumption).
- Move to LDAPS and restrict which attributes and OUs an ordinary user's
  bind can read, rather than relying on AD's default broad read access.
- Enable `dsdb_json_audit` or equivalent to log search filters, not just
  binds, so a burst of enumeration-style queries is visible.
- Treat directory read access as a privilege to monitor, not a given:
  alert on an unusual volume of searches from a single account.

## Re-test result
Not yet performed — tracked for after LDAPS and search-level auditing are
implemented.

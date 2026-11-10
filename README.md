# Enterprise IAM Lab

A reproducible, Docker-based identity and access management lab for a fictional company (`company.local`). One directory (Samba Active Directory) is the single source of truth, and the same user identity is used for three different login paths:

- **Web** — OpenID Connect (OAuth 2.0) through Keycloak, with application roles taken from AD groups
- **Domain** — Kerberos single sign-on from a Linux client, including LDAP over GSSAPI
- **Network** — RADIUS authentication and group-based VLAN assignment through FreeRADIUS

Disable a user or change a group in AD once, and every path reacts.

![Architecture diagram](docs/architecture.png)

## Scope note (please read)

- **Samba AD DC stands in for Windows Active Directory.** Real AD needs Windows Server and cannot run in Docker. Samba provides AD-compatible LDAP, Kerberos and DNS.
- **RADIUS is tested with `radtest`**, because the lab has no access point or switch. 802.1X and EAP are not demonstrated end to end.
- **This is a lab, not a production design.** See [Known limitations](#known-limitations).

## Quick start

Requirements: Docker with Compose v2, Git, about 6 GB of RAM for Docker, and free ports 8080 and 5000.

```bash
git clone https://github.com/sedki-boussif/enterprise-iam-lab.git enterprise-iam-lab
cd enterprise-iam-lab
cp .env.example .env      # then change every ChangeMe-... value
make up
```

Keycloak needs about two minutes to start and import the realm. The web login only works after that. Then run the automated checks:

```bash
make test
```

Other targets: `make down` (stop), `make reset` (stop and delete all data, for a clean rebuild), `make logs`.

## Components

| Service | Image / build | Role |
|---|---|---|
| `samba-ad` | built from `samba-ad/` (Debian 12) | Domain controller: LDAP, Kerberos KDC and DNS for `company.local`. Seeds OUs, groups and users on first start. |
| `postgres` | `postgres:16` | Keycloak database |
| `keycloak` | `quay.io/keycloak/keycloak:26.8.2` | OIDC provider. Federates users and groups from AD over LDAP. The realm is imported from `keycloak/import/realm-company.json`. |
| `webapp` | built from `webapp/` (Flask + Authlib) | Demo app with role-based pages: `/profile`, `/hr`, `/admin` |
| `linux-client` | built from `linux-client/` (Debian 12) | Proves Kerberos (`kinit`, `klist`, `kvno`, `ldapsearch -Y GSSAPI`) and runs `radtest` |
| `freeradius` | `freeradius/freeradius-server:3.2.7` | Authenticates against AD with an LDAP bind and returns a VLAN for HR users |

Network: `iamnet`, subnet `172.28.0.0/24`, domain controller fixed at `172.28.0.10`. Containers that need domain names use the domain controller as their DNS server.

## Identity model

| AD group | Web role | Access |
|---|---|---|
| GG-Employees | Employee | `/profile` |
| GG-HR | HR | `/hr` |
| GG-Admins | Admin | `/admin` |

Users: `alice` (HR), `bob` (Development), `carol` (IT), `admin1` (Admins), `eve` (Development, **disabled**). Service accounts `svc-keycloak` and `svc-radius` are used only for read-only lookups.

## How the three login paths work

**Web (OIDC authorization code flow).** The browser is redirected to Keycloak, which verifies the password with an LDAP bind against Samba. Keycloak redirects back with a one-time code, the app exchanges it for tokens server to server, and the `groups` claim decides the role.

**Domain (Kerberos).** The client asks the Samba KDC for a ticket granting ticket (AS exchange), then for a service ticket such as `ldap/dc1.company.local` (TGS exchange). `ldapsearch -Y GSSAPI` then queries LDAP with no password prompt.

**Network (RADIUS).** FreeRADIUS receives a username and password, looks the user up in AD, verifies the password with an LDAP bind (PAP), and answers Accept or Reject. Members of `GG-HR` also receive `Tunnel-Private-Group-Id = 20`.

## Test results

Automated by `tests/smoke-test.sh` (run with `make test`):

```
== Kerberos ==
PASS  T5 alice gets a TGT
PASS  T5 GSSAPI LDAP query without password
PASS  T6 wrong password rejected
PASS  T6 disabled user rejected
== RADIUS ==
PASS  T7 alice accepted
PASS  T7 HR user gets VLAN 20
PASS  T7 non-HR user gets no VLAN
PASS  T8 wrong password rejected
PASS  T8 disabled user rejected
== Identity lifecycle (carol) ==
PASS  T10 carol accepted while enabled
PASS  T10 disabled carol refused by Kerberos
PASS  T10 disabled carol refused by RADIUS

ALL TESTS PASSED
```

Web tests need a browser and are run by hand:

| ID | Scenario | Expected | Result |
|---|---|---|---|
| T1 | alice logs in, opens `/hr` | Allowed | Pass (see `docs/screenshots/`) |
| T2 | bob logs in, opens `/hr` | 403 Forbidden | TODO: confirm and add screenshot |
| T3 | admin1 opens `/admin` | Allowed | TODO: confirm and add screenshot |
| T4 | eve (disabled) logs in | Refused | TODO: confirm and add screenshot |
| T9 | Remove alice from GG-HR, log in again | `/hr` returns 403 | TODO: confirm and add screenshot |
| T10 (web) | Disable carol in AD, log in | Refused with "Account is disabled, contact your administrator." | Pass |
| T11 / T12 | `make reset` then `make up` | Same working state, no manual steps | Pass on the build machine. TODO: repeat on a second machine |

## Security phase

Planned: LDAP enumeration, password spraying, AS-REP roasting, Kerberoasting, cleartext LDAP capture, OIDC misconfiguration, weak RADIUS secret, and privilege escalation by group change. Each scenario follows attack, detect, harden, re-test, with write-ups in `security/attacks/`. *(Update this section as the write-ups are completed.)*

## Troubleshooting and lessons learned

Real problems hit while building this lab:

- **`additional property ... is not allowed` or `did not find expected ',' or ']'` in `docker-compose.yml`.** A service block was placed outside `services:`, or `dns: [${DC_IP}]` was written as an inline list. Use the block form (`dns:` then `- ${DC_IP}`), and check placement with `docker compose config --services`.
- **`ldapsearch -Y GSSAPI` fails with "Server not found in Kerberos database".** OpenLDAP canonicalizes the server name through reverse DNS. Docker answers with the container name instead of `dc1.company.local`, so the client requests a ticket for the wrong service name. Fix: `ENV LDAPSASL_NOCANON=on` in `linux-client/Dockerfile`. Kerberos tickets are bound to exact service names.
- **FreeRADIUS rejects every user and logs "Operation unavailable without authentication".** The service-account bind succeeds, but AD returns referrals to other partitions and the module follows them without credentials. Fix: `chase_referrals = yes` and `rebind = yes` in the `ldap` module's `options` block.
- **Web app returns 500 right after `make up`.** Keycloak is still starting (about two minutes). Wait for `Profile dev activated` and reload.
- **A user re-enabled in AD is still "disabled" in Keycloak.** Keycloak cached the account. Fix: set the LDAP provider's cache policy to `NO_CACHE` (committed in the realm file) so AD changes apply immediately.
- **Scripts fail with `no such file or directory` on Windows.** CRLF line endings. `.gitattributes` forces LF for `*.sh` and Dockerfiles.
- **`LDAP error code 8 - Strong(er) authentication required`.** Samba refuses simple binds over plain LDAP. See the intentional weakness below.
- **Clock skew and DNS.** Kerberos needs clocks within about five minutes and correct DNS names. Containers share the host clock and use Samba for DNS.
- **FreeRADIUS logs a BlastRADIUS warning.** The client sends `Message-Authenticator` and the server enabled strict checking for it. This is expected. Consider requiring it explicitly in `clients.conf` as a hardening step.

Behavior worth knowing: disabling a user blocks *new* logins. A Kerberos ticket the user already holds stays valid until it expires, and an existing Keycloak session lasts until its own lifetime ends.

## Known limitations

- Samba is not Windows AD. Some features, such as full Group Policy behavior, differ.
- No access point, so 802.1X Wi-Fi is not shown end to end. RADIUS uses PAP over an LDAP bind. PEAP-MSCHAPv2 and EAP-TLS are not implemented.
- **Intentional lab weaknesses, to be fixed in the hardening phase:** `ldap server require strong auth = no` (simple binds over unencrypted LDAP, port 389), Keycloak in `start-dev` mode, plain HTTP, and lab passwords in `.env.example`.
- Browser Kerberos single sign-on (SPNEGO) is out of scope.

Stretch ideas: TOTP MFA, SSSD domain join in a VM, a Windows client joined to the Samba domain, Wazuh or Loki dashboards.

## Repository layout

```
docker-compose.yml   .env.example   Makefile
samba-ad/       Dockerfile, entrypoint.sh, seed.sh
keycloak/       import/realm-company.json
webapp/         Dockerfile, app.py, requirements.txt
linux-client/   Dockerfile, krb5.conf
freeradius/     clients.conf, mods-enabled/ldap, sites-enabled/default
tests/          smoke-test.sh
security/       attacks/, detections/, hardening/
docs/           architecture.png, screenshots/
```

## Secrets

All secrets live in `.env`, which is git-ignored. Only `.env.example` is committed, with placeholder values. The Keycloak realm export contains placeholders (`${SVC_KEYCLOAK_PASSWORD}`, `${WEBAPP_CLIENT_SECRET}`) that are filled from the environment at import time.

## License

See `LICENSE`.

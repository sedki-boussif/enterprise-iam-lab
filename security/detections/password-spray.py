#!/usr/bin/env python3
"""
Detects password spraying: many different usernames failing authentication
from the same source IP within a short time window.

Usage: docker compose exec samba-ad cat /var/log/samba/log.samba \
         | python3 security/detections/password-spray.py
"""
import sys
import json
import re
from collections import defaultdict
from datetime import datetime, timedelta

WINDOW_SECONDS = 60
THRESHOLD_USERS = 5

FAIL_STATUSES = {"NT_STATUS_WRONG_PASSWORD", "NT_STATUS_NO_SUCH_USER"}

events = []
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        rec = json.loads(line)
    except json.JSONDecodeError:
        continue
    auth = rec.get("Authentication", {})
    status = auth.get("status")
    if status not in FAIL_STATUSES:
        continue
    remote = auth.get("remoteAddress") or ""
    m = re.search(r"ipv4:([\d.]+):", remote)
    if not m:
        continue
    ip = m.group(1)
    user = auth.get("clientAccount") or "?"
    ts = datetime.fromisoformat(rec["timestamp"].replace("+0000", "+00:00"))
    events.append((ts, ip, user, status))

events.sort()

by_ip = defaultdict(list)
for ts, ip, user, status in events:
    by_ip[ip].append((ts, user, status))

alerts = []
for ip, recs in by_ip.items():
    window_start = 0
    for i in range(len(recs)):
        while recs[i][0] - recs[window_start][0] > timedelta(seconds=WINDOW_SECONDS):
            window_start += 1
        window = recs[window_start:i + 1]
        distinct_users = {u for _, u, _ in window}
        if len(distinct_users) >= THRESHOLD_USERS:
            alerts.append((ip, window[0][0], window[-1][0], distinct_users))
            break

if not alerts:
    print("No spray pattern detected.")
else:
    for ip, start, end, users in alerts:
        print(f"ALERT: possible password spray from {ip}")
        print(f"  window: {start} -> {end} ({len(users)} distinct accounts)")
        print(f"  accounts tried: {', '.join(sorted(users))}")

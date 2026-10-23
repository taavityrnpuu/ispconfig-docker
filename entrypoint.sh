#!/bin/bash
set -e
# journald persists to /var/log/journal only if the dir has the right
# ownership/setgid; the named-volume mount resets it, so set it at runtime.
mkdir -p /var/log/journal
chown root:systemd-journal /var/log/journal 2>/dev/null || true
chmod 2755 /var/log/journal 2>/dev/null || true
exec /lib/systemd/systemd

#!/bin/sh
# Open a remote shell over Wi-Fi so the host can work without USB round-trips.
# Runs first in runme.d so a later crash cannot cost us access.
#
# This file is deployed by tools/install_kindle.sh. It used to exist only on the
# device, which meant a reinstall silently dropped the only working remote
# channel.
#
# Hard-won notes for this device (Kindle PW3, fw 5.16.2.1.1):
#  - /mnt/us is a noexec FAT mount: copy binaries to tmpfs before executing.
#  - legacy dropbear is 0.53.1 (2009) and dispatches its applet on argv[0], so
#    the copy must literally be named "dropbear". It has NO -V flag: probing it
#    with -V prints "Unknown argument -V Dropbear sshd v0.53.1" and exits
#    non-zero, which once made a working server look broken. Do not probe it;
#    start it and check the listening socket.
#  - 0.53.1 speaks only ssh-rsa (SHA-1) and has no -a flag.
#  - telnetd is a proven fallback: the jailbreak itself uses it.
BASE=/mnt/us/extensions/kindlexiping261030
RUND=/var/tmp/kx-remote
LOG="$BASE/remote-access.log"

exec >>"$LOG" 2>&1
echo "===== remote access $(date '+%Y-%m-%d %H:%M:%S') ====="

PUB="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/1IhydOflYD+dx3SKKQ/SOPpxHrENhwkgF/E2aJECHFnCQerJjZ9S2m368ane7q3H+W1OhPzUP6UZrsDUQ9nSnuH5UWTDWdIFJpHjqEiY7iJ4wxqGFc3rybP7+PgTG2C5u/5wE5LvYO2S4L0gNJawFnQU9EajQtfPWXBvfh97BULqwYB6VPgwh/Ks56Abnc3Xj8Yn6CGv0MSsjngRon+lghFZJ3q7qcFwwc6QmS5MWCx/OKMlsqhhb7Z4VpvRKPRlzyUK8Jmh5c5sGQ8PoR7OnBhIZurS6pPQME4TjykjhqeuO9wNBKEHsNUsLK7gspLkAoOZzQRNZx9vfRIiN9j kindle-xiping"

mkdir -p "$RUND"

# The listening check reads /proc/net/tcp because netstat may be absent.
# Port 2222 = 08AE, port 2323 = 0913.
listening() {
    grep -qi ":$1 " /proc/net/tcp 2>/dev/null && return 0
    grep -qi ":$1 " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

# ---- keys -------------------------------------------------------------
# Dropbear reads ~/.ssh/authorized_keys for the login user. Cover every
# plausible home directory plus the paths older sessions used.
for d in "$RUND/.ssh" /root/.ssh /tmp/root/.ssh /mnt/us/usbnet/etc \
         /mnt/us/jobman/ssh/etc/dropbear; do
    mkdir -p "$d" 2>/dev/null || continue
    grep -qF "kindle-xiping" "$d/authorized_keys" 2>/dev/null || \
        printf '%s\n' "$PUB" >> "$d/authorized_keys" 2>/dev/null
    chmod 700 "$d" 2>/dev/null
    chmod 600 "$d/authorized_keys" 2>/dev/null
done
ROOT_HOME=$(sed -n 's/^root:[^:]*:[^:]*:[^:]*:\([^:]*\):.*/\1/p' /etc/passwd 2>/dev/null)
if [ -n "$ROOT_HOME" ] && [ "$ROOT_HOME" != "/root" ]; then
    mkdir -p "$ROOT_HOME/.ssh" 2>/dev/null
    grep -qF "kindle-xiping" "$ROOT_HOME/.ssh/authorized_keys" 2>/dev/null || \
        printf '%s\n' "$PUB" >> "$ROOT_HOME/.ssh/authorized_keys" 2>/dev/null
    chmod 600 "$ROOT_HOME/.ssh/authorized_keys" 2>/dev/null
fi
echo "keys staged (root home: ${ROOT_HOME:-unknown})"

# ---- dropbear ---------------------------------------------------------
cp /mnt/us/control/legacy-dropbearmulti "$RUND/dropbear" 2>/dev/null
chmod 755 "$RUND/dropbear" 2>/dev/null
cp /mnt/us/control/dropbear_rsa_host_key "$RUND/host_rsa" 2>/dev/null
chmod 600 "$RUND/host_rsa" 2>/dev/null

if [ -x "$RUND/dropbear" ] && [ -f "$RUND/host_rsa" ]; then
    if [ -f "$RUND/ssh.pid" ]; then
        kill "$(cat "$RUND/ssh.pid" 2>/dev/null)" 2>/dev/null
        sleep 1
    fi
    # No -a (absent in 0.53). -s disables password logins.
    "$RUND/dropbear" -r "$RUND/host_rsa" -P "$RUND/ssh.pid" -p 2222 -s
    sleep 2
    if listening 08AE; then
        echo "RESULT: ssh listening on 2222 (pid $(cat "$RUND/ssh.pid" 2>/dev/null))"
    else
        echo "RESULT: ssh did NOT listen on 2222"
    fi
else
    echo "RESULT: dropbear or host key missing, skipped"
fi

# ---- telnetd fallback -------------------------------------------------
# Unencrypted, but it is the same mechanism the jailbreak uses and it needs no
# key negotiation. Only started when SSH is unavailable.
if ! listening 08AE; then
    echo "falling back to telnetd"
    telnetd -l /bin/sh -p 2323 2>&1
    sleep 2
    if listening 0913; then
        echo "RESULT: telnet listening on 2323"
    else
        echo "RESULT: telnet failed to listen"
    fi
fi

echo "=== wlan0 ==="
ifconfig wlan0 2>/dev/null | grep 'inet addr'
echo "=== listening sockets ==="
grep -iE ':(08AE|0913) ' /proc/net/tcp 2>/dev/null
echo "===== done ====="

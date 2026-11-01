#!/bin/sh
# Installed to /mnt/us/emergency.sh, which the hotfix's /etc/upstart/kmc.conf
# executes on every `framework_ready` -- that is, on every boot and every time
# the framework restarts, including leaving USB storage mode.
#
# Why this exists: USB mass-storage mode turns the radio off, so the only way to
# work on the device without a USB unplug/replug cycle is for it to bring up an
# SSH server by itself once it is awake and off USB. Everything the host does
# after this lands (deploying files, running the daemon, capturing the panel)
# then goes over the LAN.
#
# Note this file is NOT in runme.d/: RUNME only fires when the user types
# `;log runme`, which is the manual step this replaces.
#
# Device facts this depends on (Kindle PW3, firmware 5.16.2.1.1, all verified
# on this unit):
#   - /mnt/us is FAT and mounted noexec: binaries must be copied to /var/tmp.
#   - legacy dropbear is 0.53.1 (2009): it dispatches its applet on argv[0], so
#     the copy must be named exactly "dropbear"; it has no -V and no -a flag.
#   - wlan0 can take a while to associate, so wait for an address rather than
#     assuming the network is up when the framework says it is ready.

LOG=/mnt/us/remote-autostart.log
RUND=/var/tmp/kx-remote
SSH_PORT=2222

# upstart runs this synchronously in pre-start, so waiting for Wi-Fi here would
# hold the boot UI back for minutes. Re-exec in the background and return at
# once; the hotfix treats a non-zero exit as a failure worth logging.
if [ "$1" != "--bg" ]; then
    ( /bin/sh "$0" --bg >/dev/null 2>&1 ) &
    exit 0
fi

exec >>"$LOG" 2>&1
echo "===== autostart $(date '+%Y-%m-%d %H:%M:%S') ====="

# Only the host's key is accepted; password logins stay disabled (-s below).
PUBKEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/1IhydOflYD+dx3SKKQ/SOPpxHrENhwkgF/E2aJECHFnCQerJjZ9S2m368ane7q3H+W1OhPzUP6UZrsDUQ9nSnuH5UWTDWdIFJpHjqEiY7iJ4wxqGFc3rybP7+PgTG2C5u/5wE5LvYO2S4L0gNJawFnQU9EajQtfPWXBvfh97BULqwYB6VPgwh/Ks56Abnc3Xj8Yn6CGv0MSsjngRon+lghFZJ3q7qcFwwc6QmS5MWCx/OKMlsqhhb7Z4VpvRKPRlzyUK8Jmh5c5sGQ8PoR7OnBhIZurS6pPQME4TjykjhqeuO9wNBKEHsNUsLK7gspLkAoOZzQRNZx9vfRIiN9j kindle-xiping'

mkdir -p "$RUND"

# /proc/net/tcp is used because netstat is not guaranteed to exist.
# 2222 = 08AE, 2323 = 0913.
listening() {
    grep -qi ":$1 " /proc/net/tcp 2>/dev/null && return 0
    grep -qi ":$1 " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

# ---- wait for Wi-Fi -------------------------------------------------
WAITED=0
while [ "$WAITED" -lt 180 ]; do
    if ifconfig wlan0 2>/dev/null | grep -q 'inet addr'; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done
echo "wlan0: $(ifconfig wlan0 2>/dev/null | grep 'inet addr' | tr -d '\n')"

# ---- keys -----------------------------------------------------------
# dropbear reads authorized_keys from the login user's home, and older tooling
# on this device looked in several places, so cover all of them.
for d in /root/.ssh /tmp/root/.ssh /mnt/us/usbnet/etc \
         /mnt/us/jobman/ssh/etc/dropbear "$RUND/.ssh"; do
    mkdir -p "$d" 2>/dev/null || continue
    grep -qF 'kindle-xiping' "$d/authorized_keys" 2>/dev/null || \
        printf '%s\n' "$PUBKEY" >> "$d/authorized_keys" 2>/dev/null
    chmod 700 "$d" 2>/dev/null
    chmod 600 "$d/authorized_keys" 2>/dev/null
done

# ---- dropbear -------------------------------------------------------
# Must be named "dropbear": 0.53.1 selects its applet from argv[0], so the
# copy cannot keep the "legacy-dropbearmulti" name, and "-V" does not exist.
cp /mnt/us/control/legacy-dropbearmulti "$RUND/dropbear" 2>/dev/null
cp /mnt/us/control/dropbear_rsa_host_key "$RUND/host_rsa" 2>/dev/null
chmod 755 "$RUND/dropbear" 2>/dev/null
chmod 600 "$RUND/host_rsa" 2>/dev/null

if listening 08AE; then
    echo "ssh already listening on $SSH_PORT"
elif [ -x "$RUND/dropbear" ] && [ -f "$RUND/host_rsa" ]; then
    [ -f "$RUND/ssh.pid" ] && kill "$(cat "$RUND/ssh.pid" 2>/dev/null)" 2>/dev/null
    # -s disables password auth. Do not probe with -V: 0.53.1 lacks that flag
    # and a non-zero exit would make a working server look broken.
    "$RUND/dropbear" -r "$RUND/host_rsa" -P "$RUND/ssh.pid" -p "$SSH_PORT" -s
    sleep 3
    if listening 08AE; then
        echo "RESULT: ssh listening on $SSH_PORT"
    else
        echo "RESULT: ssh did NOT listen on $SSH_PORT"
    fi
else
    echo "RESULT: dropbear or host key missing"
fi

# ---- telnetd fallback -----------------------------------------------
# Only when SSH is unavailable. Unencrypted, but it is the same mechanism the
# jailbreak itself uses and it needs no key exchange.
if ! listening 08AE; then
    telnetd -l /bin/sh -p 2323 2>&1
    sleep 2
    if listening 0913; then
        echo "RESULT: telnet listening on 2323"
    else
        echo "RESULT: telnet failed"
    fi
fi

echo "ip: $(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')"

# ---- reload the lockscreen daemon ------------------------------------
# The daemon reads its script once at startup and then keeps it in memory, so a
# deployed daemon.sh change has no effect on the running instance. Restarting it
# here means a boot (or a framework restart) is enough to pick up new code --
# without it, a fix can sit on disk forever while the old logic keeps running.
if [ -x /bin/sh ] && [ -f /mnt/us/extensions/kindlexiping261030/scripts/toggle.sh ]; then
    sh /mnt/us/extensions/kindlexiping261030/scripts/toggle.sh enable >/dev/null 2>&1
    echo "daemon: restarted via toggle.sh enable"
fi

echo "===== autostart done ====="

# ---- ride out transient drops ---------------------------------------
# Nothing supervises this process, and losing the channel costs a USB round-trip,
# so keep watching for ~10 minutes after boot instead of giving up at the first
# missed check.
N=0
while [ "$N" -lt 30 ]; do
    sleep 20
    if ! listening 08AE && ! listening 0913; then
        echo "$(date '+%H:%M:%S') channel dropped, restarting"
        if [ -x "$RUND/dropbear" ] && [ -f "$RUND/host_rsa" ]; then
            "$RUND/dropbear" -r "$RUND/host_rsa" -P "$RUND/ssh.pid" -p "$SSH_PORT" -s 2>/dev/null
            sleep 2
            listening 08AE && echo "restarted on $SSH_PORT"
        fi
    fi
    N=$((N + 1))
done
echo "===== watchdog done ====="

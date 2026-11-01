#!/bin/sh
# Deploy the extension to a Kindle over Wi-Fi. No USB, no `;log runme`.
#
# This is the counterpart to kindle/emergency.sh: that script brings up an SSH
# server by itself on every boot, and this one uses it. Together they remove the
# USB unplug/replug cycle that used to be required for every deploy and every
# verification, because USB mass-storage mode turns the device's radio off.
#
# Prerequisites, one time only:
#   1. emergency.sh is installed at /mnt/us/emergency.sh on the device
#      (tools/install_kindle.sh does this).
#   2. The device has booted at least once since then, so the hotfix's
#      /etc/upstart/kmc.conf has run it and dropbear is listening on 2222.
#
# Usage:
#   tools/deploy_over_wifi.sh                  # deploy, then restart the daemon
#   KINDLE_HOST=192.168.1.83 tools/deploy_over_wifi.sh
#   tools/deploy_over_wifi.sh --capture        # also pull the wake capture back
#
# Exit codes: 0 ok, 1 unreachable, 2 deploy failed.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOST="${KINDLE_HOST:-192.168.1.83}"
PORT="${KINDLE_PORT:-2222}"
USER_NAME="${KINDLE_USER:-root}"
KEY="${KINDLE_KEY:-$HOME/.ssh/kindle_xiping}"
BASE=/mnt/us/extensions/kindlexiping261030
CAPTURE=0

for arg in "$@"; do
    case "$arg" in
        --capture) CAPTURE=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Dropbear 0.53.1 speaks only ssh-rsa (SHA-1) and has no modern KEX, so the
# algorithms have to be opted into explicitly or the handshake fails outright.
SSH_OPTS="-p $PORT -i $KEY -o BatchMode=yes -o ConnectTimeout=8
 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa
 -o PubkeyAcceptedKeyTypes=+ssh-rsa
 -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
 -o LogLevel=ERROR"

remote() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$USER_NAME@$HOST" "$@"
}

# Retrying is worthwhile: the device may be waking up, or the watchdog in
# emergency.sh may be restarting dropbear after a transient drop.
echo "==> checking $HOST:$PORT"
ATTEMPT=1
while [ "$ATTEMPT" -le 5 ]; do
    if remote 'echo ok' >/dev/null 2>&1; then
        echo "    reachable"
        break
    fi
    [ "$ATTEMPT" -lt 5 ] && { echo "    attempt $ATTEMPT failed, retrying"; sleep 5; }
    ATTEMPT=$((ATTEMPT + 1))
done
if [ "$ATTEMPT" -gt 5 ]; then
    cat >&2 <<EOF
Cannot reach the Kindle at $HOST:$PORT.

The device is either asleep, off Wi-Fi, or still in USB mass-storage mode
(which turns the radio off). Wake it with the power button and make sure it is
not plugged into USB, then run this again.

If it stays unreachable while awake and unplugged, check on the device:
    /mnt/us/remote-autostart.log
That log is written by emergency.sh and says whether dropbear started.
EOF
    exit 1
fi

echo "==> staging files"
# tar over ssh rather than scp: /mnt/us is a FAT volume, and one stream avoids a
# round-trip per file.
STAGE=/tmp/kx-deploy.$$
tar -C "$ROOT/kindle" -cf - bin scripts emergency.sh 2>/dev/null \
    | remote "rm -rf $STAGE && mkdir -p $STAGE && tar -xf - -C $STAGE"

echo "==> installing"
remote "set -e
    BASE=$BASE
    mkdir -p \$BASE/bin \$BASE/scripts \$BASE/state \$BASE/runme.d
    cp \$STAGE/bin/* \$BASE/bin/
    cp \$STAGE/scripts/*.sh \$BASE/scripts/
    chmod 755 \$BASE/bin/* \$BASE/scripts/*.sh
    # Retired helpers would otherwise sit next to the live implementation.
    rm -f \$BASE/bin/xredraw \$BASE/bin/screensaver_shield \$BASE/bin/screensaver_draw
    cp \$STAGE/emergency.sh /mnt/us/emergency.sh
    chmod 755 /mnt/us/emergency.sh
    rm -rf \$STAGE
    echo '    files in place'"

echo "==> restarting the sleep daemon"
# toggle.sh restarts unconditionally on purpose: the daemon keeps its script in
# memory, so skipping the restart would leave an old daemon.sh running.
remote "sh $BASE/scripts/toggle.sh enable >/dev/null 2>&1 || true
    sleep 2
    if [ -f /tmp/custom_ss_daemon.pid ] && kill -0 \$(cat /tmp/custom_ss_daemon.pid) 2>/dev/null; then
        echo '    daemon running'
    else
        echo '    WARNING: daemon not running'
    fi
    tail -20 $BASE/custom_ss.log 2>/dev/null"

if [ "$CAPTURE" -eq 1 ]; then
    echo "==> pulling the post-wake capture"
    # The only honest way to know whether a wake repaint worked: look at what
    # the panel actually contained afterwards.
    if remote "test -f $BASE/screen-after-wake.raw"; then
        OUT="$ROOT/dist/screen-after-wake.raw"
        mkdir -p "$ROOT/dist"
        # shellcheck disable=SC2086
        scp $SSH_OPTS "$USER_NAME@$HOST:$BASE/screen-after-wake.raw" "$OUT"
        echo "    saved $OUT"
        echo "    decode with: python3 -c \"from PIL import Image;"
        echo "      Image.frombytes('L',(1088,1448),open('$OUT','rb').read()[:1088*1448])"
        echo "      .crop((0,0,1072,1448)).save('$ROOT/dist/screen-after-wake.png')\""
    else
        echo "    no capture yet; sleep and wake the device once, then rerun"
    fi
fi

echo "==> done"

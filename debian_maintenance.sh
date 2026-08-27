#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "Error: command failed on line $LINENO." >&2' ERR

# Check if run as root
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root." >&2
    exit 1
fi

before_space=$(df --output=avail / | awk 'NR==2 {print $1}')

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y full-upgrade
apt-get -y autoremove --purge
apt-get -y clean

dpkg -l | awk '/^rc/ {print $2}' | xargs -r apt-get -y -qq purge

if command -v snap >/dev/null 2>&1; then
    snap refresh || echo "Warning: Snap refresh encountered errors." >&2
fi

if command -v flatpak >/dev/null 2>&1; then
    flatpak update -y --noninteractive || \
    flatpak uninstall --unused -y --noninteractive || true
fi

if command -v docker >/dev/null 2>&1; then
    docker system prune -f >/dev/null 2>&1 || true
fi

if command -v podman >/dev/null 2>&1; then
    podman system prune --force >/dev/null 2>&1 || true
fi

journalctl --vacuum-size=200M || true
journalctl --vacuum-time=14d || true

find /tmp -type f -mtime +7 -delete 2>/dev/null || true

shopt -s nullglob

for home in /home/* /root; do
    [[ -d "$home" ]] || continue

    trash="$home/.local/share/Trash"

    if [[ -d "$trash" ]]; then
        rm -rf -- \
            "${trash:?}/files/"* \
            "${trash:?}/info/"* \
            2>/dev/null || true
    fi

    rm -rf -- "$home/.cache/thumbnails/"* 2>/dev/null || true
done

shopt -u nullglob

after_space=$(df --output=avail / | awk 'NR==2 {print $1}')
diff_mb=$(((after_space - before_space) / 1024))

echo "-----------------------------------------------------"

if (( diff_mb > 0 )); then
    echo "Success: Freed about ${diff_mb} MB."
elif (( diff_mb < 0 )); then
    echo "Disk usage increased by about $((-diff_mb)) MB."
else
    echo "No significant disk space change."
fi

if [[ -f /var/run/reboot-required ]]; then
    echo "NOTE: System reboot is required"
fi

exit 0

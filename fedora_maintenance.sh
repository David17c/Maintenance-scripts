#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

before_space=$(df --output=avail / | awk 'NR==2 {print $1}')

if command -v dnf5 >/dev/null 2>&1; then
    DNF=(dnf5)
elif command -v dnf >/dev/null 2>&1; then
    DNF=(dnf)
else
    echo "DNF not found." >&2
    exit 1
fi

"${DNF[@]}" -y upgrade --refresh
"${DNF[@]}" clean packages

if command -v flatpak >/dev/null 2>&1; then
    flatpak update -y --noninteractive
    flatpak uninstall --unused -y --noninteractive
fi

if command -v snap >/dev/null 2>&1; then
    snap refresh
fi

if command -v docker >/dev/null 2>&1; then
    docker system prune -f --filter "until=30d"
fi

if command -v podman >/dev/null 2>&1; then
    podman system prune --force --filter "until=30d"
fi

journalctl --vacuum-size=200M
journalctl --vacuum-time=14d

find /tmp -xdev -type f -mtime +7 -delete

shopt -s nullglob

for home in /home/* /root; do
    [[ -d "$home" ]] || continue

    trash="$home/.local/share/Trash"

    if [[ -d "$trash/files" ]]; then
        find "$trash/files" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf -- {} +
    fi

    if [[ -d "$trash/info" ]]; then
        find "$trash/info" -mindepth 1 -maxdepth 1 -mtime +30 -delete
    fi

    thumbnails="$home/.cache/thumbnails"

    if [[ -d "$thumbnails" ]]; then
        find "$thumbnails" -type f -mtime +30 -delete
    fi
done

shopt -u nullglob

after_space=$(df --output=avail / | awk 'NR==2 {print $1}')
diff_mib=$(((after_space - before_space) / 1024))

echo "Freed approximately ${diff_mib} MiB."

if command -v needs-restarting >/dev/null 2>&1 &&
   ! needs-restarting -r >/dev/null 2>&1; then
    echo "Reboot required."
fi

#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

before_space=$(df --output=avail / | awk 'NR==2 {print $1}')

# Check if dnf5 is available
if command -v dnf5 >/dev/null 2>&1; then
    DNF=(dnf5)
elif command -v dnf >/dev/null 2>&1; then
    DNF=(dnf)
else
    echo "DNF not found." >&2
    exit 1
fi

# Update Fedora and DNF packages
"${DNF[@]}" -y upgrade --refresh
"${DNF[@]}" clean packages

# update flatpak and remove unused packages
if command -v flatpak >/dev/null 2>&1; then
    flatpak update -y --noninteractive
    flatpak uninstall --unused -y --noninteractive
fi

# Update all Snaps and remove unused old revisions
if command -v snap >/dev/null 2>&1; then
    snap refresh

    snap list --all | awk '/disabled/{print $1, $3}' |
    while read -r snap revision; do
        snap remove "$snap" --revision="$revision"
    done
fi

# Remove unused Docker stuff older than 30 days
if command -v docker >/dev/null 2>&1; then
    docker system prune -f --filter "until=30d"
fi

# remove unused podman stuff older then 30 days
if command -v podman >/dev/null 2>&1; then
    podman system prune --force --filter "until=$(date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ')"
fi

# Remove journal logs until they are less 200 MiB and 14 days old
journalctl --vacuum-size=200M
journalctl --vacuum-time=14d

# Remove regular files in /tmp that have not been modified for more than 14 days
find /tmp -xdev -type f -mtime +30 -delete

for home in /home/* /root; do
    [[ -d "$home" ]] || continue

    # Empty everything in the trash older then 30 days
    trash="$home/.local/share/Trash"
    if [[ -d "$trash/files" ]]; then
        find "$trash/files" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf -- {} +
    fi

    # Remove old Trash metadata corresponding to deleted items
    if [[ -d "$trash/info" ]]; then
        find "$trash/info" -mindepth 1 -maxdepth 1 -type f -mtime +30 -delete
    fi

    thumbnails="$home/.cache/thumbnails"

    # Remove cached thumbnails that have not been used for 30 days
    if [[ -d "$thumbnails" ]]; then
        find "$thumbnails" -type f -mtime +30 -delete
    fi
done

# Calculate and show how much disk usage increased / decreased
after_space=$(df --output=avail / | awk 'NR==2 {print $1}')
diff_mb=$(((after_space - before_space) / 1024))

echo "-----------------------------------------------------"

if (( diff_mb > 0 )); then
    echo "Success: Freed approximately ${diff_mb} MB."
elif (( diff_mb < 0 )); then
    echo "Disk usage increased by approximately $((-diff_mb)) MB."
else
    echo "No significant disk space change."
fi

# Show if a reboot is needed
if "${DNF[@]}" needs-restarting -r >/dev/null 2>&1; then
    echo "NOTE: System reboot is required."
fi
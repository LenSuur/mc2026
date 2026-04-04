#!/bin/bash
set -e

BACKUP_DIR="/srv/mc/backups"
DATA_DIR="/srv/mc/mc-data"
DATE="$(date +%Y-%m-%d)"
FILE="$BACKUP_DIR/mc-backup-$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"
cd /srv/mc

echo "Warning players (60s)..."
docker compose exec mc rcon-cli say "[Server] Weekly backup will start in 60 seconds. Please finish what you are doing."

sleep 50

echo "Warning players (10s)..."
docker compose exec mc rcon-cli say "[Server] Backup starting in 10 seconds... server will pause briefly."

sleep 10

echo "Stopping Minecraft server..."
docker compose stop

echo "Creating backup: $FILE"
# Use -C so tar stores relative path and avoids the leading '/' warning
tar -czf "$FILE" -C /srv/mc mc-data

echo "Starting Minecraft server..."
docker compose start

echo "Cleaning up old backups (keeping latest 8)..."

cd "$BACKUP_DIR"

# List backups newest first, skip first 8, delete the rest
ls -1t mc-backup-*.tar.gz 2>/dev/null | sed -e '1,8d' | while read -r old; do
  [ -n "$old" ] && echo "Deleting old backup: $old" && rm -f -- "$old"
done

echo "Backup complete."


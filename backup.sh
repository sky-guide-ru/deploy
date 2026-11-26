#!/usr/bin/env bash
# Ежедневная копия того, что не лежит в git: data/ (аккаунты, история цен, рейтинг) и .env.
# Хранит последние 14 копий в /var/backups/skyblock. Запускается каждую ночь через cron (/etc/cron.d/skyblock-backup, ставит setup-vps.sh).
# Забрать копию на ПК (PowerShell): scp root@IP:/var/backups/skyblock/latest.tgz .
set -euo pipefail
APP=${APP:-/opt/skyblock-tracker}
DEST=${DEST:-/var/backups/skyblock}
KEEP=${KEEP:-14}
mkdir -p "$DEST"
chmod 700 "$DEST"
stamp=$(date +%Y-%m-%d_%H%M)
file="$DEST/skyblock-$stamp.tgz"
# Кэш (база NEU, иконки) не копируем: сайт скачает его заново
tar -czf "$file" -C "$APP" --ignore-failed-read --exclude=data/neu-repo.zip --exclude=data/icons data .env
ln -sfn "$file" "$DEST/latest.tgz"
ls -1t "$DEST"/skyblock-*.tgz | tail -n +$((KEEP + 1)) | xargs -r rm -f
echo "копия: $file ($(du -h "$file" | cut -f1))"

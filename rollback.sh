#!/usr/bin/env bash
# Вернуть прежний сайт после переключения. От root:
#   bash rollback.sh /opt/skyblock-tracker
# Данные, накопленные новой версией (входы, отзывы, история цен), копируются обратно в прежнюю папку:
# формат файлов тот же. Данные прежней папки до отката сохраняются архивом в /root.
set -euo pipefail
APP=${APP:-/opt/sky-guide}
OLD=${1:-}
die() { printf '\n\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "Запусти от root"
[ -n "$OLD" ] && [ -d "$OLD/data" ] || die "Укажи прежнюю папку: bash rollback.sh /opt/skyblock-tracker"
[ "${YES:-}" = 1 ] || { read -r -p "Вернуть прежний сайт из $OLD? Напиши да: " a; [ "$a" = да ] || die "Отменено"; }
cd "$APP"
docker compose stop
tar -czf "/root/old-data-before-rollback-$(date +%Y%m%d-%H%M).tgz" -C "$OLD" --ignore-failed-read --exclude=data/neu-repo.zip --exclude=data/icons data
tar -C "$APP" -cf - --exclude=data/neu-repo.zip --exclude=data/icons --exclude=data/hypixel-cache data | tar -C "$OLD" -xf -
chown -R 1000:1000 "$OLD/data"
(cd "$OLD" && docker compose start)
rm -f /etc/cron.d/sky-guide-backup
[ -f "$OLD/deploy/backup.sh" ] && echo "30 4 * * * root $OLD/deploy/backup.sh >> /var/log/skyblock-backup.log 2>&1" > /etc/cron.d/skyblock-backup
echo "Готово: работает прежний сайт из $OLD. Новая версия остановлена, её папка $APP цела."

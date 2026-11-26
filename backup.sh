#!/usr/bin/env bash
# Ночная копия того, чего нет в git: data/ (JSON-файлы: аккаунты, история цен, рейтинг, отзывы) и .env.
# Отдельной базы данных у сайта нет, поэтому копии папки достаточно.
# Хранит последние KEEP копий (по умолчанию 14) в /var/backups/sky-guide. Cron ставит setup-vps.sh: /etc/cron.d/sky-guide-backup.
# Забрать копию на ПК (PowerShell): scp root@IP:/var/backups/sky-guide/latest.tgz .
# Вернуть: bash import-data.sh /var/backups/sky-guide/latest.tgz
set -euo pipefail
APP=${APP:-/opt/sky-guide}
DEST=${DEST:-/var/backups/sky-guide}
KEEP=${KEEP:-14}
mkdir -p "$DEST"
chmod 700 "$DEST"
stamp=$(date +%Y-%m-%d_%H%M)
file="$DEST/sky-guide-$stamp.tgz"
# Кэш (база NEU, иконки, ответы Hypixel) не копируем: сайт скачает его заново
tar -czf "$file.part" -C "$APP" --ignore-failed-read \
  --exclude=data/neu-repo.zip --exclude=data/icons --exclude=data/hypixel-cache \
  data .env
# Битый архив не должен заменить последнюю хорошую копию
tar -tzf "$file.part" >/dev/null || { rm -f "$file.part"; echo "копия не прочиталась — оставляю прошлую" >&2; exit 1; }
mv "$file.part" "$file"
chmod 600 "$file"
ln -sfn "$file" "$DEST/latest.tgz"
ls -1t "$DEST"/sky-guide-*.tgz | tail -n +$((KEEP + 1)) | xargs -r rm -f
echo "копия: $file ($(du -h "$file" | cut -f1))"

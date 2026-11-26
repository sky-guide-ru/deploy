#!/usr/bin/env bash
# Скопировать данные из прежней папки сайта на этом же сервере (.env, data/, packs/, db/icons). Прежнюю папку только читает.
#   bash copy-data.sh /opt/skyblock-tracker          — для переключения (перед этим прежний сайт остановлен, DOCKER.md)
#   bash copy-data.sh /opt/skyblock-tracker --test   — для тестового запуска: копия без писем и без ИИ
set -euo pipefail
APP=${APP:-/opt/sky-guide}
OLD=${1:-}
MODE=${2:-}
[ -n "$OLD" ] && [ -d "$OLD/data" ] || { echo "Укажи прежнюю папку: bash copy-data.sh /opt/skyblock-tracker [--test]" >&2; exit 1; }
[ "$(realpath "$OLD")" != "$(realpath "$APP")" ] || { echo "Это та же папка" >&2; exit 1; }
cd "$APP"
mkdir -p data packs db/icons
# Серверные строки нового .env (порты, домен, автообновление) остаются, остальное — из прежнего .env
keep=$(grep -E '^(COMPOSE_PROFILES|SITE_DOMAIN|SITE_URL|APP_DIR|HTTP_PORT|HTTPS_PORT|DEPLOY_MERGERS|GITHUB_TOKEN)=' .env 2>/dev/null || true)
[ -f .env ] && cp .env "/root/sky-guide-env-before-copy-$(date +%Y%m%d-%H%M)"
cp "$OLD/.env" .env
sed -i 's/\r$//' .env
for k in $(printf '%s\n' "$keep" | cut -d= -f1); do sed -i "/^$k=/d" .env; done
[ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
[ -n "$keep" ] && printf '%s\n' "$keep" >> .env
if [ "$MODE" = --test ]; then
  # Тестовая копия не шлёт писем (сводки, тревоги, отзывы) и не тратит дневной бюджет ИИ живого сайта
  sed -i -E 's/^(SMTP_USER|SMTP_PASS|RESEND_API_KEY|MAIL_DOMAIN|MAIL_TO|INDEXNOW_KEY|ANTHROPIC_API_KEY)=.*/\1=/' .env
  echo "письма и ИИ в тестовой копии выключены"
fi
chmod 600 .env
# Кэш (база NEU, иконки, ответы Hypixel) не копируем: сайт скачает его заново
tar -C "$OLD" -cf - --exclude=data/neu-repo.zip --exclude=data/icons --exclude=data/hypixel-cache data \
  | tar -C "$APP" -xf -
cp -a "$OLD/packs/." packs/ 2>/dev/null || true
cp -a "$OLD/db/icons/." db/icons/ 2>/dev/null || true
chown -R 1000:1000 data
docker compose up -d --force-recreate api
echo "Готово: data $(du -sh data | cut -f1), паков $(ls packs/*.zip 2>/dev/null | wc -l), иконок $(ls db/icons 2>/dev/null | wc -l)"

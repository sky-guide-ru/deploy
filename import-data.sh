#!/usr/bin/env bash
# Разложить архив (.env, data/, db/icons, packs) по местам и перезапустить api. От root:
#   bash import-data.sh /root/move.tgz                      — архив с ПК (как собрать — DOCKER.md)
#   bash import-data.sh /var/backups/sky-guide/latest.tgz   — вернуть ночную копию
# Серверные строки .env (порты, домен, автообновление) остаются прежними.
set -euo pipefail
APP=${APP:-/opt/sky-guide}
arc=${1:-/root/move.tgz}
[ -f "$arc" ] || { echo "Нет файла $arc" >&2; exit 1; }
arc=$(realpath "$arc")
cd "$APP"
# Нынешнее на всякий случай сохраняем
[ -d data ] && tar -czf "/root/before-import-$(date +%Y%m%d-%H%M).tgz" --ignore-failed-read data .env 2>/dev/null || true
keep=$(grep -E '^(COMPOSE_PROFILES|SITE_DOMAIN|SITE_URL|APP_DIR|HTTP_PORT|HTTPS_PORT|DEPLOY_MERGERS|GITHUB_TOKEN)=' .env 2>/dev/null || true)
tar -xzf "$arc" -C "$APP"
sed -i 's/\r$//' .env
for line in $(printf '%s\n' "$keep" | cut -d= -f1); do sed -i "/^$line=/d" .env; done
[ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
[ -n "$keep" ] && printf '%s\n' "$keep" >> .env
chmod 600 .env
mkdir -p data packs db/icons
chown -R 1000:1000 data
docker compose up -d --force-recreate api
echo "Готово. Паки: $(ls packs/*.zip 2>/dev/null | wc -l), иконок: $(ls db/icons 2>/dev/null | wc -l)"

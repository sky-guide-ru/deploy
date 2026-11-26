#!/usr/bin/env bash
# Разложить архив с ПК (.env, data/, db/icons, packs) по местам и перезапустить сайт. От root:
#   bash import-data.sh /root/move.tgz
# Как собрать архив на ПК — в DOCKER.md, «Перенос данных с ПК».
set -euo pipefail
APP=/opt/skyblock-tracker
arc=${1:-/root/move.tgz}
[ -f "$arc" ] || { echo "Нет файла $arc" >&2; exit 1; }
cd "$APP"
# Старое на всякий случай сохраняем
[ -d data ] && tar -czf "/root/before-import-$(date +%Y%m%d-%H%M).tgz" --ignore-failed-read data .env 2>/dev/null || true
profiles=$(grep '^COMPOSE_PROFILES=.\+' .env 2>/dev/null || true)
domain=$(grep '^SITE_DOMAIN=' .env 2>/dev/null || true)
tar -xzf "$arc" -C "$APP"
# В архиве .env с ПК: возвращаем серверные строки
sed -i 's/\r$//' .env
# Последняя строка без перевода строки склеилась бы с тем, что допишем ниже
[ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
# На ПК строка обычно пустая — на сервере автообновление должно остаться включённым
if ! grep -q '^COMPOSE_PROFILES=.\+' .env; then
  sed -i '/^COMPOSE_PROFILES=/d' .env
  echo "${profiles:-COMPOSE_PROFILES=vps}" >> .env
fi
[ -n "$domain" ] && ! grep -q '^SITE_DOMAIN=.\+' .env && { sed -i '/^SITE_DOMAIN=/d' .env; echo "$domain" >> .env; }
chmod 600 .env
mkdir -p data packs db/icons
chown -R 1000:1000 data
docker compose up -d --force-recreate app
echo "Готово. Паки: $(ls packs/*.zip 2>/dev/null | wc -l), иконок: $(ls db/icons 2>/dev/null | wc -l)"

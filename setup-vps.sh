#!/usr/bin/env bash
# Подготовка VPS (Ubuntu 22.04/24.04 или Debian 12) и запуск Sky Guide в Docker. От root:
#   bash setup-vps.sh            — обычная установка: сайт на портах 80/443
#   TEST=1 bash setup-vps.sh     — тестовый запуск рядом с живым сайтом: порты 8080/8443, без автообновления
# Можно запускать повторно: сделанные шаги пропускаются. Подробно: DOCKER.md
set -euo pipefail

APP=${APP:-/opt/sky-guide}
ORG=${ORG:-https://github.com/sky-guide-ru}
TEST=${TEST:-0}

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "Запусти от root: sudo bash setup-vps.sh"
command -v apt-get >/dev/null || die "Нужен Ubuntu или Debian"
export DEBIAN_FRONTEND=noninteractive

say "Пакеты"
apt-get update -q
apt-get install -y -q curl ca-certificates git ufw cron iproute2

say "Docker"
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker >/dev/null 2>&1 || true
docker --version && docker compose version

say "Подкачка (swap), если памяти меньше 2 ГБ"
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$mem_mb" -lt 2000 ] && [ "$(swapon --show | wc -l)" -eq 0 ] && [ ! -f /swapfile ]; then
  # Сборка образов (npm + Vite) на 1 ГБ памяти без подкачки может упасть
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "добавлен swap 2 ГБ (памяти ${mem_mb} МБ)"
else
  echo "не нужно (памяти ${mem_mb} МБ)"
fi

say "Код: deploy в $APP, api и web в $APP/src"
# Репо открытые: ключи для чтения не нужны
[ -d "$APP/.git" ] || git clone --branch main "$ORG/deploy.git" "$APP"
mkdir -p "$APP/src"
for r in api web; do
  [ -d "$APP/src/$r/.git" ] || git clone --branch main "$ORG/$r.git" "$APP/src/$r"
done
cd "$APP"
mkdir -p data packs db/icons
chown -R 1000:1000 data
if [ ! -f .env ]; then
  cp .env.example .env
  echo "создан .env из примера: впиши ключи (nano $APP/.env) или перенеси свои (copy-data.sh, import-data.sh)"
fi
chmod 600 .env

set_env() { # set_env KEY VALUE — заменить строку или дописать
  [ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
  if grep -q "^$1=" .env; then sed -i "s#^$1=.*#$1=$2#" .env; else echo "$1=$2" >> .env; fi
}
set_env APP_DIR "$APP"

if [ "$TEST" = 1 ]; then
  say "Тестовый запуск: порты 8080 и 8443, автообновление выключено"
  set_env HTTP_PORT 8080
  set_env HTTPS_PORT 8443
  set_env SITE_DOMAIN ':80'
  set_env COMPOSE_PROFILES ''
  ufw allow 8080/tcp >/dev/null 2>&1 || true
else
  say "Файрвол: SSH, 80, 443"
  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443 >/dev/null
  ufw --force enable >/dev/null
  echo "включён"
  # Порты 80/443 держит другой сайт (например, прежняя версия) — не мешаем ему
  if ss -ltnH '( sport = :80 or sport = :443 )' | grep -q . && ! docker compose ps -q caddy 2>/dev/null | grep -q .; then
    die "Порты 80/443 уже заняты другим сайтом. Для проверки рядом с ним: TEST=1 bash setup-vps.sh. Переключение — DOCKER.md, «Переключение»"
  fi
  # На сервере включаем автообновление (контейнер updater)
  grep -q '^COMPOSE_PROFILES=.\+' .env || set_env COMPOSE_PROFILES vps
fi

say "Сборка и запуск (первый раз 5–10 минут)"
docker compose up -d --build

if [ "$TEST" != 1 ]; then
  say "Ночные копии данных"
  chmod +x ./*.sh
  echo "30 4 * * * root $APP/backup.sh >> /var/log/sky-guide-backup.log 2>&1" > /etc/cron.d/sky-guide-backup
  chmod 644 /etc/cron.d/sky-guide-backup
  echo "каждую ночь в 04:30 (время сервера) → /var/backups/sky-guide"
fi

say "Проверка"
port=$(grep -oP '^HTTP_PORT=\K[0-9]+' .env || echo 80)
ok=0
for _ in $(seq 1 60); do
  if curl -fsS -m 3 "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
ip=$(curl -fsS -m 5 -4 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
url="http://$ip"; [ "$port" = 80 ] || url="$url:$port"
if [ "$ok" = 1 ]; then
  echo; echo "  Готово! Сайт отвечает: $url"
else
  echo; echo "  Сайт пока не отвечает. Журнал: cd $APP && docker compose logs api --tail 50"
fi
cat <<MSG

  Дальше:
   • данные с прежней папки на этом сервере: bash $APP/copy-data.sh /opt/skyblock-tracker
   • данные архивом с ПК:                    bash $APP/import-data.sh /root/move.tgz
   • свой домен с HTTPS:                     bash $APP/set-domain.sh sky-guide.ru,www.sky-guide.ru
MSG

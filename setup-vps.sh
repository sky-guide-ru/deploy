#!/usr/bin/env bash
# Подготовка чистого VPS (Ubuntu 22.04/24.04 или Debian 12) и запуск сайта в Docker. От root:
#   bash setup-vps.sh
# Можно запускать повторно: сделанные шаги пропускаются. Подробно: DOCKER.md
set -euo pipefail

REPO=${REPO:-git@github.com:sky-guide-ru/sky-guide.git}
APP=/opt/skyblock-tracker   # путь зашит в docker-compose.yml (updater), не меняй
KEY=/root/.ssh/skyblock_deploy

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "Запусти от root: sudo bash setup-vps.sh"
command -v apt-get >/dev/null || die "Нужен Ubuntu или Debian"
export DEBIAN_FRONTEND=noninteractive

say "Пакеты"
apt-get update -q
apt-get install -y -q curl ca-certificates git ufw openssh-client cron

say "Docker"
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker >/dev/null 2>&1 || true
docker --version && docker compose version

say "Подкачка (swap), если памяти меньше 2 ГБ"
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$mem_mb" -lt 2000 ] && [ "$(swapon --show | wc -l)" -eq 0 ] && [ ! -f /swapfile ]; then
  # Сборка образа (npm + Vite) на 1 ГБ памяти без подкачки может упасть
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "добавлен swap 2 ГБ (памяти ${mem_mb} МБ)"
else
  echo "не нужно (памяти ${mem_mb} МБ)"
fi

say "Файрвол: SSH, 80, 443"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443 >/dev/null
ufw --force enable >/dev/null
echo "включён"

say "Доступ к приватному репозиторию (ключ только для чтения)"
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C "skyblock-vps" -f "$KEY"
if ! grep -q 'skyblock_deploy' /root/.ssh/config 2>/dev/null; then
  printf 'Host github.com\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$KEY" >> /root/.ssh/config
  chmod 600 /root/.ssh/config
fi
ssh-keyscan -t ed25519 github.com >> /root/.ssh/known_hosts 2>/dev/null
sort -u -o /root/.ssh/known_hosts /root/.ssh/known_hosts
if ! git ls-remote "$REPO" HEAD >/dev/null 2>&1; then
  cat <<MSG

  Серверу нужен доступ к репозиторию. Один раз:
  1) Открой https://github.com/sky-guide-ru/sky-guide/settings/keys/new
  2) Title: VPS. В поле Key вставь строку ниже. Галочку «Allow write access» НЕ ставь. Add key.

$(cat "$KEY.pub")

  3) Запусти ещё раз: bash setup-vps.sh
MSG
  exit 2
fi
echo "доступ есть"

say "Код сайта в $APP (ветка main)"
[ -d "$APP/.git" ] || git clone --branch main "$REPO" "$APP"
cd "$APP"
mkdir -p data packs db/icons
chown -R 1000:1000 data
if [ ! -f .env ]; then
  cp .env.example .env
  echo "создан .env из примера. Свой .env с ПК перенеси позже (DOCKER.md, «Перенос данных с ПК»)"
fi
chmod 600 .env
# Последняя строка без перевода строки склеилась бы с тем, что допишем ниже
[ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
# На сервере включаем автообновление (контейнер updater)
# (в .env.example строка уже есть, но пустая — её тоже заполняем)
if grep -q '^COMPOSE_PROFILES=.\+' .env; then :
elif grep -q '^COMPOSE_PROFILES=' .env; then sed -i 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=vps/' .env
else echo 'COMPOSE_PROFILES=vps' >> .env; fi

say "Сборка и запуск (первый раз 3–7 минут)"
docker compose up -d --build

say "Ночные копии данных"
chmod +x deploy/*.sh
echo "30 4 * * * root $APP/deploy/backup.sh >> /var/log/skyblock-backup.log 2>&1" > /etc/cron.d/skyblock-backup
chmod 644 /etc/cron.d/skyblock-backup
echo "каждую ночь в 04:30 (время сервера) → /var/backups/skyblock"

say "Проверка"
ok=0
for _ in $(seq 1 45); do
  if curl -fsS -m 3 http://127.0.0.1/healthz >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
ip=$(curl -fsS -m 5 -4 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
if [ "$ok" = 1 ]; then
  echo; echo "  Готово! Сайт открывается: http://$ip"
else
  echo; echo "  Сайт пока не отвечает. Посмотри журнал: cd $APP && docker compose logs app --tail 50"
fi
cat <<MSG

  Дальше:
   • перенеси данные с ПК: bash $APP/deploy/import-data.sh /root/move.tgz
   • адрес с SSL без покупки домена: bash $APP/deploy/set-domain.sh sslip
   • свой домен:                     bash $APP/deploy/set-domain.sh sb.example.ru
MSG

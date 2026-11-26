#!/usr/bin/env bash
# Переключение живого сайта с прежней папки на эту. Запускать только после проверки тестового запуска
# и только с согласия владельца. От root:
#   bash switch.sh /opt/skyblock-tracker
# Что делает: копия данных прежнего сайта → прежний сайт останавливается (его папка и данные остаются как есть) →
# свежие data/ и .env копируются сюда → сайт поднимается на 80/443 с прежними доменами → проверка.
# Не ответил за 3 минуты — сам возвращает прежний сайт. Вернуть вручную позже: bash rollback.sh /opt/skyblock-tracker
set -euo pipefail
APP=${APP:-/opt/sky-guide}
OLD=${1:-}
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "Запусти от root"
[ -n "$OLD" ] && [ -f "$OLD/.env" ] && [ -d "$OLD/data" ] || die "Укажи прежнюю папку: bash switch.sh /opt/skyblock-tracker"
cd "$APP"
[ -d src/api/.git ] && [ -d src/web/.git ] || die "Сначала bash setup-vps.sh"

old_env() { grep "^$1=" "$OLD/.env" | tail -1 | cut -d= -f2- || true; }
set_env() {
  [ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
  if grep -q "^$1=" .env; then sed -i "s#^$1=.*#$1=$2#" .env; else echo "$1=$2" >> .env; fi
}
domains=$(old_env SITE_DOMAIN); url=$(old_env SITE_URL)
echo "Прежний сайт: $OLD, домены: ${domains:-нет (http по IP)}"
[ "${YES:-}" = 1 ] || { read -r -p "Переключить живой сайт на $APP? Напиши да: " a; [ "$a" = да ] || die "Отменено"; }

say "Новая версия собрана заранее (пока работает прежний сайт)"
docker compose --profile vps build api web updater

say "Копия данных прежнего сайта"
snap="/root/before-switch-$(date +%Y%m%d-%H%M).tgz"
tar -czf "$snap" -C "$OLD" --ignore-failed-read --exclude=data/neu-repo.zip --exclude=data/icons data .env
echo "$snap"

say "Остановка прежнего сайта (папка и данные остаются)"
(cd "$OLD" && docker compose stop)

rollback() {
  say "Новая версия не ответила — возвращаю прежний сайт"
  docker compose stop || true
  (cd "$OLD" && docker compose start)
  die "Прежний сайт снова работает. Журнал новой версии: cd $APP && docker compose logs api caddy --tail 100"
}
trap rollback ERR

say "Свежие данные и настройки"
sed -i '/^HTTP_PORT=/d; /^HTTPS_PORT=/d' .env
bash ./copy-data.sh "$OLD" >/dev/null
set_env SITE_DOMAIN "$domains"
set_env SITE_URL "$url"
set_env COMPOSE_PROFILES vps
set_env APP_DIR "$APP"
docker compose up -d --remove-orphans

say "Проверка"
host=${domains%%,*}; host=${host// /}
ok=0
for _ in $(seq 1 90); do
  if [ -n "$host" ] && [ "$host" != ":80" ]; then curl -fsS -m 5 "https://$host/healthz" >/dev/null 2>&1 && { ok=1; break; }
  else curl -fsS -m 5 http://127.0.0.1/healthz >/dev/null 2>&1 && { ok=1; break; }; fi
  sleep 2
done
[ "$ok" = 1 ] || false
trap - ERR

say "Ночные копии и файрвол"
rm -f /etc/cron.d/skyblock-backup
echo "30 4 * * * root $APP/backup.sh >> /var/log/sky-guide-backup.log 2>&1" > /etc/cron.d/sky-guide-backup
chmod 644 /etc/cron.d/sky-guide-backup
ufw delete allow 8080/tcp >/dev/null 2>&1 || true
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
echo; echo "  Готово: сайт работает из $APP. Прежняя папка $OLD остановлена и цела. Вернуть: bash $APP/rollback.sh $OLD"

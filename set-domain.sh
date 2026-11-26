#!/usr/bin/env bash
# Подключить домен; SSL-сертификат Caddy получит и продлит сам. От root на сервере:
#   bash set-domain.sh sb.example.ru   — свой домен/поддомен (A-запись уже указывает на IP сервера)
#   bash set-domain.sh sslip           — без покупки: адрес вида 1-2-3-4.sslip.io
#   bash set-domain.sh off             — снова просто http://IP
set -euo pipefail
APP=/opt/skyblock-tracker
cd "$APP"
domain=${1:-}
[ -n "$domain" ] || { echo "Укажи домен: bash set-domain.sh sb.example.ru (или sslip, или off)" >&2; exit 1; }

set_env() { # set_env KEY VALUE
  [ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
  if grep -q "^$1=" .env; then sed -i "s#^$1=.*#$1=$2#" .env; else echo "$1=$2" >> .env; fi
}

if [ "$domain" = off ]; then
  set_env SITE_DOMAIN ''; set_env SITE_URL ''
  docker compose up -d
  echo "Готово: сайт снова по http://IP"; exit 0
fi

my_ip=$(curl -fsS -m 5 -4 https://api.ipify.org || true)
[ "$domain" = sslip ] && domain="${my_ip//./-}.sslip.io"
echo "домен: $domain"

# Let's Encrypt выдаст сертификат, только если домен уже указывает на этот сервер
dns_ip=$(getent ahostsv4 "$domain" | awk 'NR==1 {print $1}' || true)
if [ -n "$my_ip" ] && [ "$dns_ip" != "$my_ip" ]; then
  echo "Домен $domain указывает на '${dns_ip:-ничего}', а IP сервера $my_ip."
  echo "Создай у регистратора A-запись $domain → $my_ip и подожди 5–30 минут."
  echo "Если домен в Cloudflare — выключи оранжевое облако (режим «только DNS»): Cloudflare в РФ часто не открывается."
  exit 1
fi

set_env SITE_DOMAIN "$domain"
set_env SITE_URL "https://$domain"
docker compose up -d
echo "Готово: https://$domain (сертификат появится за минуту, первый заход может быть медленным)"

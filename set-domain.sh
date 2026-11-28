#!/usr/bin/env bash
# Подключить домен; HTTPS-сертификат Caddy получит и продлит сам. От root на сервере:
#   bash set-domain.sh sky-guide.ru,www.sky-guide.ru   — свои домены через запятую (A-записи уже указывают на IP сервера)
#   bash set-domain.sh sslip                           — без покупки: адрес вида 1-2-3-4.sslip.io
#   bash set-domain.sh off                             — снова просто http://IP
set -euo pipefail
APP=${APP:-/opt/sky-guide}
cd "$APP"
arg=${1:-}
[ -n "$arg" ] || { echo "Укажи домен: bash set-domain.sh sky-guide.ru,www.sky-guide.ru (или sslip, или off)" >&2; exit 1; }

set_env() { # set_env KEY VALUE
  [ -s .env ] && [ "$(tail -c1 .env)" != "" ] && echo >> .env
  if grep -q "^$1=" .env; then sed -i "s#^$1=.*#$1=$2#" .env; else echo "$1=$2" >> .env; fi
}

if [ "$arg" = off ]; then
  set_env SITE_DOMAIN ''; set_env SITE_URL ''
  docker compose up -d
  echo "Готово: сайт снова по http://IP"; exit 0
fi

my_ip=$(curl -fsS -m 5 -4 https://api.ipify.org || true)
[ "$arg" = sslip ] && arg="${my_ip//./-}.sslip.io"
IFS=',' read -ra domains <<< "${arg// /}"

# Let's Encrypt выдаст сертификат, только если каждый домен уже указывает на этот сервер
for d in "${domains[@]}"; do
  dns_ip=$(getent ahostsv4 "$d" | awk 'NR==1 {print $1}' || true)
  if [ -n "$my_ip" ] && [ "$dns_ip" != "$my_ip" ]; then
    echo "Домен $d указывает на '${dns_ip:-ничего}', а IP сервера $my_ip."
    echo "Создай у регистратора A-запись $d → $my_ip и подожди 5–30 минут."
    echo "Cloudflare-прокси (оранжевое облако) не включай: из России такие сайты часто не открываются."
    exit 1
  fi
done

list=$(IFS=','; echo "${domains[*]}" | sed 's/,/, /g')
set_env SITE_DOMAIN "$list"
set_env SITE_URL "https://${domains[0]}"
docker compose up -d
echo "Готово: https://${domains[0]} (сертификат появится за минуту, первый заход может быть медленным)"

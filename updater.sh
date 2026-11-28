#!/bin/sh
# Автообновление в Docker (то же, что scripts/supervisor.js на ПК): раз в минуту смотрит origin/main.
# Есть новые коммиты → git merge --ff-only → docker compose build app → перезапуск app.
# Не собралось или новая версия не отвечает → откат на прошлый коммит, этот коммит больше не ставим.
# Журнал пишет в data/deploy-log.json — его показывает панель «Сервер» владельца.
# Выключить: AUTO_UPDATE=0 в .env. Интервал: AUTO_UPDATE_SEC (по умолчанию 60).
set -u
cd "${APP_DIR:-/opt/skyblock-tracker}" || exit 1
git config --global --add safe.directory '*'
every=${AUTO_UPDATE_SEC:-60}
[ "$every" -lt 20 ] 2>/dev/null && every=20
bad=""

log() { echo "[автообновление $(date +%H:%M:%S)] $*"; }

record() { # record kind '{"from":"..."}'
  f=data/deploy-log.json
  now=$(($(date +%s) * 1000))
  ev=$(printf '%s' "${2:-{\}}" | jq -c --arg k "$1" --argjson at "$now" '{kind:$k, at:$at} + .')
  old=$(cat "$f" 2>/dev/null || echo '{}')
  printf '%s' "$old" | jq --argjson e "$ev" '{events: ([$e] + ((.events? // []) )) [:20]}' > "$f.tmp" 2>/dev/null \
    && mv "$f.tmp" "$f" && chown 1000:1000 "$f" 2>/dev/null
  return 0
}

healthy() { # ждём ответа нового сервера до 2 минут
  i=0
  while [ $i -lt 40 ]; do
    wget -q -T 3 -O /dev/null "${HEALTH_URL:-http://app:3000/healthz}" 2>/dev/null && return 0
    i=$((i + 1)); sleep 3
  done
  return 1
}

rebuild() { docker compose build app && docker compose up -d app; }

if [ "${AUTO_UPDATE:-1}" = 0 ]; then log "выключено (AUTO_UPDATE=0)"; else log "включено, проверка каждые ${every} с"; fi

cleanup # заодно убрать то, что накопилось до этой версии

while true; do
  sleep "$every"
  [ "${AUTO_UPDATE:-1}" = 0 ] && continue
  git fetch --quiet origin main 2>/dev/null || continue
  head=$(git rev-parse HEAD)
  remote=$(git rev-parse origin/main)
  [ -z "$remote" ] || [ "$head" = "$remote" ] || [ "$remote" = "$bad" ] && continue
  if ! git merge-base --is-ancestor "$head" "$remote"; then log "локальная ветка разошлась с origin/main — пропускаю"; continue; fi
  changed=$(git diff --name-only "$head" "$remote")
  n=$(printf '%s\n' "$changed" | grep -c .)
  log "новые изменения ($n файлов), обновляюсь до $(echo "$remote" | cut -c1-7)"
  if ! git merge --ff-only --quiet "$remote"; then log "git merge не удался"; continue; fi
  h7=$(echo "$head" | cut -c1-7); r7=$(echo "$remote" | cut -c1-7)
  why=""
  if ! rebuild; then why="сборка не удалась"
  elif ! healthy; then why="новая версия $r7 не отвечает"
  fi
  if [ -n "$why" ]; then
    log "$why — возвращаю $h7 и жду исправления в main"
    bad=$remote
    git reset --keep "$head" || log "откат не удался: есть свои правки в тех же файлах"
    rebuild || log "старая версия тоже не собралась — нужна ручная проверка: docker compose logs app"
    record rollback "{\"why\":\"$why\",\"from\":\"$r7\",\"to\":\"$h7\"}"
    continue
  fi
  log "сайт обновлён"
  record update "{\"from\":\"$h7\",\"to\":\"$r7\",\"files\":$n}"
  # Поменялись сами настройки Docker — применяем их (caddy, updater пересоздадутся; updater перезапустится с новым скриптом)
  if printf '%s\n' "$changed" | grep -qE '^(docker-compose\.yml|deploy/)'; then
    log "изменились настройки Docker — применяю"
    # Себя этим же контейнером пересоздать нельзя: Docker убьёт updater посреди команды, и новый
    # останется в «Created». Поэтому app и caddy обновляем сами, а updater — отдельным коротким контейнером
    docker compose up -d --build --remove-orphans app caddy
    # Новый Caddyfile сам caddy не увидит: git заменяет файл целиком, а в контейнере остаётся старый.
    # Сначала проверяем его отдельным контейнером, и только если он верный — пересоздаём caddy (пауза ~1 с)
    if printf '%s\n' "$changed" | grep -qx 'deploy/Caddyfile'; then
      if docker compose run --rm --no-deps -T caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
        docker compose up -d --force-recreate --no-deps caddy && log "Caddyfile применён"
      else
        log "новый Caddyfile не прошёл проверку — caddy оставлен со старым"
      fi
    fi
    docker compose build updater
    app_dir=$(pwd)
    docker rm -f skyblock-selfupdate >/dev/null 2>&1
    docker run -d --rm --name skyblock-selfupdate \
      -v /var/run/docker.sock:/var/run/docker.sock -v "$app_dir:$app_dir" -w "$app_dir" \
      skyblock-updater:local sh -c 'sleep 5; docker compose up -d --force-recreate --no-deps updater' >/dev/null \
      || log "не смог запустить перезапуск updater — нужна ручная команда: docker compose up -d updater"
    sleep 60
  fi
done

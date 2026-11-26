#!/bin/sh
# Автообновление на сервере: раз в минуту смотрит ветку main трёх репо и пересобирает только то, что изменилось.
#   deploy (эта папка) — настройки Docker и Caddy: применяет их, а updater пересоздаёт себя
#   api    (src/api)   — пересобирает api, ждёт ответа /healthz
#   web    (src/web)   — пересобирает сайт, ждёт, пока новая сборка ляжет в общий том
# Не собралось или не отвечает → возвращает прошлый коммит этого репо и этот коммит больше не ставит (ждёт исправления).
# DEPLOY_MERGERS в .env — ставить только то, что слили в main эти логины GitHub (через запятую). Пусто — ставить всё из main.
# Журнал — data/deploy-log.json, его показывает панель «Сервер» владельца.
# Выключить: AUTO_UPDATE=0 в .env. Интервал: AUTO_UPDATE_SEC (по умолчанию 60, не меньше 20).
set -u
cd "${APP_DIR:-/opt/sky-guide}" || exit 1
git config --global --add safe.directory '*'
every=${AUTO_UPDATE_SEC:-60}
[ "$every" -lt 20 ] 2>/dev/null && every=20
state=${STATE_DIR:-/tmp/sky-updater}
API_URL=${API_URL:-http://api:3000} # api изнутри сети Docker
mkdir -p "$state"

log() { echo "[автообновление $(date +%H:%M:%S)] $*"; }

record() { # record kind '{"repo":"api",...}'
  f=data/deploy-log.json
  now=$(($(date +%s) * 1000))
  ev=$(printf '%s' "$2" | jq -c --arg k "$1" --argjson at "$now" '{kind:$k, at:$at} + .') || return 0
  old=$(cat "$f" 2>/dev/null || echo '{}')
  printf '%s' "$old" | jq --argjson e "$ev" '{events: ([$e] + ((.events? // []))) [:30]}' > "$f.tmp" 2>/dev/null \
    && mv "$f.tmp" "$f" && chown 1000:1000 "$f" 2>/dev/null
  return 0
}

short() { echo "$1" | cut -c1-7; }

# --- Кто слил: только PR, которые слил человек из DEPLOY_MERGERS ---
gh() { # gh путь → JSON из GitHub API (GITHUB_TOKEN необязателен: репо открытые, без него 60 запросов в час)
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsS -m 15 -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/$1"
  else
    curl -fsS -m 15 -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"
  fi
}

refused="" # почему коммит не пропущен — для журнала
approved() { # approved папка старый новый → 0 да, 1 нет, 2 GitHub не ответил (проверим в следующий раз)
  allow=$(echo "${DEPLOY_MERGERS:-}" | tr -d ' ' | tr 'A-Z' 'a-z')
  [ -z "$allow" ] && return 0
  slug=$(git -C "$1" remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')
  # Каждый коммит, который main получил с прошлого раза (по первой линии: слияния и squash), должен быть слиянием PR
  for c in $(git -C "$1" rev-list --first-parent "$2..$3"); do
    j=$(gh "repos/$slug/commits/$c/pulls") || return 2
    pr=$(printf '%s' "$j" | jq -r --arg c "$c" '[.[] | select(.merge_commit_sha == $c and .merged_at != null)][0].number // empty')
    [ -n "$pr" ] || { refused="коммит $(short "$c") попал в main не через PR"; return 1; }
    j=$(gh "repos/$slug/pulls/$pr") || return 2
    who=$(printf '%s' "$j" | jq -r '.merged_by.login // empty' | tr 'A-Z' 'a-z')
    case ",$allow," in *",$who,"*) ;; *) refused="PR #$pr слил не тот, кто указан в DEPLOY_MERGERS"; return 1 ;; esac
  done
  return 0
}

# --- Проверки готовности ---
api_ok() { # до 2 минут ждём ответа нового api
  i=0
  while [ $i -lt 40 ]; do
    wget -q -T 3 -O /dev/null "$API_URL/healthz" 2>/dev/null && return 0
    i=$((i + 1)); sleep 3
  done
  return 1
}

build_id() { wget -q -T 3 -O - "$API_URL/api/version" 2>/dev/null | jq -r '.build // empty' 2>/dev/null; }

web_ok() { # web скопировал сборку в том: контейнер работает без перезапусков, api видит сборку (новую или через 30 с — ту же)
  before=$1
  i=0
  while [ $i -lt 40 ]; do
    sleep 3; i=$((i + 1))
    id=$(docker compose ps -q web)
    st=$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' "$id" 2>/dev/null || echo "false 0")
    [ "${st%% *}" = true ] || continue
    [ "${st##* }" = 0 ] || return 1
    b=$(build_id)
    [ -n "$b" ] && [ "$b" != dev ] || continue
    [ "$b" != "$before" ] && return 0
    [ $i -ge 10 ] && return 0 # поменялись не скрипты (например, картинка в public/) — имя сборки то же
  done
  return 1
}

caddy_reload() { # новый Caddyfile caddy сам не увидит; сначала проверяем его отдельным контейнером
  if docker compose run --rm --no-deps -T caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
    docker compose up -d --force-recreate --no-deps caddy && log "Caddyfile применён"
  else
    log "новый Caddyfile не прошёл проверку — caddy оставлен со старым"
    return 1
  fi
}

# --- Как применять изменения каждого репо ---
apply() { # apply имя изменённые_файлы → 0 удачно
  case $1 in
    api)
      docker compose build api && docker compose up -d api && api_ok ;;
    web)
      before=$(build_id)
      docker compose build web && docker compose up -d web && web_ok "$before" ;;
    deploy)
      # Поменялись только тексты и проверки — на сервере применять нечего
      printf '%s\n' "$2" | grep -qvE '(\.md$|^docs/|^test/|^e2e/|^\.github/|^LICENSE$|^package\.json$)' || return 0
      docker compose up -d --build --remove-orphans api web caddy || return 1
      if printf '%s\n' "$2" | grep -qx 'Caddyfile'; then caddy_reload || return 1; fi
      api_ok ;;
  esac
}

selfupdate() { # себя этим же контейнером пересоздать нельзя: Docker убьёт updater посреди команды
  docker compose build updater || { log "updater не собрался — работаю со старым"; return; }
  docker rm -f sky-guide-selfupdate >/dev/null 2>&1
  docker run -d --rm --name sky-guide-selfupdate \
    -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" \
    sky-guide-updater:local sh -c 'sleep 5; docker compose up -d --force-recreate --no-deps updater' >/dev/null \
    || log "не смог перезапустить updater — нужна ручная команда: docker compose up -d updater"
  sleep 60
}

check() { # check имя папка
  name=$1; dir=$2
  [ -d "$dir/.git" ] || { [ -f "$state/missing-$name" ] || { log "$name: нет клона в $dir (bash setup-vps.sh)"; touch "$state/missing-$name"; }; return 0; }
  git -C "$dir" fetch --quiet origin main 2>/dev/null || return 0
  head=$(git -C "$dir" rev-parse HEAD)
  remote=$(git -C "$dir" rev-parse origin/main 2>/dev/null || true)
  [ -z "$remote" ] || [ "$head" = "$remote" ] && return 0
  [ "$remote" = "$(cat "$state/skip-$name" 2>/dev/null)" ] && return 0
  h7=$(short "$head"); r7=$(short "$remote")
  if ! git -C "$dir" merge-base --is-ancestor "$head" "$remote"; then
    log "$name: локальная ветка разошлась с origin/main — пропускаю"; echo "$remote" > "$state/skip-$name"; return 0
  fi
  approved "$dir" "$head" "$remote"; a=$?
  if [ $a = 2 ]; then log "$name: GitHub не ответил, кто слил $r7 — проверю позже"; return 0; fi
  if [ $a = 1 ]; then
    log "$name: $r7 не ставлю — $refused"; echo "$remote" > "$state/skip-$name"
    record skipped "{\"repo\":\"$name\",\"why\":\"$refused\",\"to\":\"$r7\"}"; return 0
  fi
  changed=$(git -C "$dir" diff --name-only "$head" "$remote")
  n=$(printf '%s\n' "$changed" | grep -c .)
  log "$name: новые изменения ($n файлов), обновляюсь до $r7"
  git -C "$dir" merge --ff-only --quiet "$remote" || { log "$name: git merge не удался"; return 0; }
  if ! apply "$name" "$changed"; then
    why="$name $r7 не собрался или не отвечает"
    log "$why — возвращаю $h7 и жду исправления в main"
    echo "$remote" > "$state/skip-$name"
    git -C "$dir" reset --keep "$head" || log "$name: откат не удался — есть свои правки в тех же файлах"
    apply "$name" "$changed" || log "$name: старая версия тоже не поднялась — нужна ручная проверка: docker compose logs"
    record rollback "{\"repo\":\"$name\",\"why\":\"$why\",\"from\":\"$r7\",\"to\":\"$h7\"}"
    return 0
  fi
  log "$name: обновлено"
  record update "{\"repo\":\"$name\",\"from\":\"$h7\",\"to\":\"$r7\",\"files\":$n}"
  if [ "$name" = deploy ] && printf '%s\n' "$changed" | grep -qE '^(updater\.sh|updater\.Dockerfile|docker-compose\.yml)$'; then
    log "изменился сам updater — перезапускаю его"
    selfupdate
  fi
}

if [ "${AUTO_UPDATE:-1}" = 0 ]; then log "выключено (AUTO_UPDATE=0)"
else log "включено, проверка каждые ${every} с${DEPLOY_MERGERS:+, ставлю только слитое через PR}"; fi

while true; do
  sleep "$every"
  [ "${AUTO_UPDATE:-1}" = 0 ] && continue
  # Сначала deploy: новая схема Docker может понадобиться для новых api и web
  check deploy .
  check api src/api
  check web src/web
done

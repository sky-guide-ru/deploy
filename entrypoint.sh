#!/bin/sh
# Папка data приходит с хоста и может принадлежать root. Отдаём её пользователю node и запускаем сайт уже от него.
set -e
if [ "$(id -u)" = 0 ]; then
  if [ "$(stat -c %u /app/data)" != "$(id -u node)" ]; then chown -R node:node /app/data; fi
  exec setpriv --reuid=node --regid=node --init-groups "$@"
fi
exec "$@"

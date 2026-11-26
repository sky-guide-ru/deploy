# Образ автообновления: docker compose + git, curl и jq (проверка «кто слил» через GitHub API)
FROM docker:cli
RUN apk add --no-cache git curl jq

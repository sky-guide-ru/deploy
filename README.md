# Sky Guide · deploy

Запуск сайта [sky-guide.ru](https://sky-guide.ru) на сервере: Docker (api + web + Caddy + автообновление), HTTPS, ночные бэкапы `data/`, браузерный прогон e2e.

## Что внутри

| Файл | Что там |
|---|---|
| `docker-compose.yml` | контейнеры `api`, `web`, `caddy`, `updater`, лимиты памяти |
| `Caddyfile` | домен, HTTPS, файлы сборки из тома, остальное в api, журнал без IP |
| `updater.sh` | автообновление из `main` трёх репо (deploy, api, web) с откатом |
| `setup-vps.sh`, `set-domain.sh` | первая настройка VPS, домен и HTTPS |
| `backup.sh`, `import-data.sh`, `copy-data.sh` | ночные копии `data/`, возврат копии, перенос данных |
| `switch.sh`, `rollback.sh` | переключение с прежней сборки и откат |
| `.env.example` | все настройки сайта с пояснениями, значения пустые |
| `e2e/smoke.mjs` | прогон сайта в браузере: `npm run e2e` (рядом `api` и `web`, или `E2E_URL`) |
| `docs/` | почта сайта, мониторинг |

Как запустить на сервере, переехать и откатиться — [DOCKER.md](DOCKER.md).

## Репо проекта

| Репо | Что там |
|---|---|
| [core](https://github.com/sky-guide-ru/core) | расчёты без HTTP: разбор профиля, план «Что делать», рынок, гайды, русская база предметов, переводы. Пакет `@sky-guide/core` |
| [api](https://github.com/sky-guide-ru/api) | сервер: адреса `/api/*`, вход и аккаунты, SEO-страницы, OpenAPI и Swagger |
| [web](https://github.com/sky-guide-ru/web) | сайт [sky-guide.ru](https://sky-guide.ru) на React + Vite, данные берёт только у api |
| [deploy](https://github.com/sky-guide-ru/deploy) | запуск на сервере: Docker, Caddy, автообновление, бэкапы, браузерный e2e |

Как запустить у себя и прислать правку — [CONTRIBUTING.md](CONTRIBUTING.md). Лицензия — [AGPL-3.0](LICENSE).

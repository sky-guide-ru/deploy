# Sky Guide · deploy

Запуск сайта [sky-guide.ru](https://sky-guide.ru) на сервере: Docker, Caddy с HTTPS, автообновление из `main`, ночные бэкапы `data/`, браузерный прогон e2e.

## Что внутри

| Файл | Что там |
|---|---|
| `docker-compose.yml`, `DOCKER.md` | контейнеры и пошаговая инструкция |
| `Caddyfile` | домен, HTTPS, журнал без IP |
| `updater.sh`, `setup-vps.sh`, `backup.sh` | автообновление, первая настройка VPS, бэкапы |
| `.env.example` | все настройки сайта с пояснениями |
| `e2e/smoke.mjs` | прогон сайта в браузере: `npm run e2e` (рядом нужны `api` и `web`) |
| `docs/` | почта сайта, мониторинг |

> Сейчас compose — от прежней сборки в один контейнер. Переход на `api` + `web` + Caddy + updater для трёх репо — в работе.

## Репо проекта

| Репо | Что там |
|---|---|
| [core](https://github.com/sky-guide-ru/core) | расчёты без HTTP: разбор профиля, план «Что делать», рынок, гайды, русская база предметов, переводы. Пакет `@sky-guide/core` |
| [api](https://github.com/sky-guide-ru/api) | сервер: адреса `/api/*`, вход и аккаунты, SEO-страницы, OpenAPI и Swagger |
| [web](https://github.com/sky-guide-ru/web) | сайт [sky-guide.ru](https://sky-guide.ru) на React + Vite, данные берёт только у api |
| [deploy](https://github.com/sky-guide-ru/deploy) | запуск на сервере: Docker, Caddy, автообновление, бэкапы, браузерный e2e |

Как запустить у себя и прислать правку — [CONTRIBUTING.md](CONTRIBUTING.md). Лицензия — [AGPL-3.0](LICENSE).

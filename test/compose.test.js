// Схема сервера: api + web + caddy + updater, лимиты памяти, общий том со сборкой сайта, пустой .env.example
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');
const compose = read('docker-compose.yml');
// Блок одного сервиса: от «  имя:» до следующего сервиса того же отступа
const service = name => {
  const m = new RegExp(`^  ${name}:\\n([\\s\\S]*?)(?=^  \\w[\\w-]*:\\n|^\\S)`, 'm').exec(compose);
  assert.ok(m, `нет сервиса ${name}`);
  return m[1];
};

test('compose: четыре сервиса, updater только с профилем vps', () => {
  for (const s of ['api', 'web', 'caddy', 'updater']) service(s);
  assert.doesNotMatch(compose, /^  app:/m, 'старый общий контейнер app');
  assert.match(service('updater'), /profiles: \["vps"\]/);
});

test('compose: api — лимит 1,5 ГБ и потолок кучи Node 1 ГБ', () => {
  const api = service('api');
  assert.match(api, /mem_limit: 1536m/);
  assert.match(api, /NODE_OPTIONS: "--max-old-space-size=1024"/);
  assert.match(api, /\.\/data:\/app\/data/);
  assert.match(api, /web_dist:\/app\/web:ro/);
  assert.match(api, /WEB_DIST: \/app\/web/);
  assert.doesNotMatch(api, /ports:/, 'api наружу не открыт');
});

test('compose: у каждого сервиса свой лимит памяти, data/ подключена только к api', () => {
  for (const s of ['web', 'caddy', 'updater']) {
    assert.match(service(s), /mem_limit: \d+m/, s);
    assert.doesNotMatch(service(s), /\.\/data:/, `${s} не должен видеть data/`);
  }
  assert.match(service('web'), /web_dist:\/out/);
  assert.match(service('caddy'), /web_dist:\/srv\/web:ro/);
});

test('Caddyfile: /assets/* из тома, остальное в api', () => {
  const c = read('Caddyfile').replace(/#.*$/gm, '');
  assert.match(c, /handle \/assets\/\* \{[\s\S]*?root \* \/srv\/web[\s\S]*?file_server/);
  assert.match(c, /reverse_proxy api:3000/);
  assert.doesNotMatch(c, /app:3000/);
});

test('.env.example: все значения пустые', () => {
  const filled = read('.env.example').split('\n').filter(l => /^[A-Z_]+=./.test(l));
  assert.deepEqual(filled, []);
  // и в нём есть всё, что спрашивают скрипты
  for (const k of ['APP_DIR', 'SITE_DOMAIN', 'COMPOSE_PROFILES', 'DEPLOY_MERGERS', 'HYPIXEL_API_KEY']) assert.match(read('.env.example'), new RegExp(`^${k}=`, 'm'), k);
});

test('скрипты: без синтаксических ошибок и без старой папки', () => {
  for (const f of fs.readdirSync(root).filter(f => f.endsWith('.sh'))) {
    const sh = read(f);
    execFileSync(sh.startsWith('#!/bin/sh') ? 'sh' : 'bash', ['-n', path.join(root, f)]);
    assert.doesNotMatch(sh, /^\s*APP=.*skyblock-tracker/m, `${f}: работает в папке прежнего сайта`);
  }
});

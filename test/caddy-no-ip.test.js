// IP посетителей не попадает в журналы (решение владельца, 25.11.2026): ни в console.* сервера, ни в журнал Caddy
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');


test('Caddy: журнала запросов нет, из ошибок вырезаны IP и заголовки', () => {
  const c = fs.readFileSync(path.join(root, 'Caddyfile'), 'utf8').replace(/#.*$/gm, '');
  for (const f of ['request>remote_ip', 'request>client_ip', 'request>headers', 'remote_ip', 'client_ip']) {
    assert.match(c, new RegExp(`\\s${f.replace('>', '\\>')} delete`), f);
  }
  // `log` внутри блока сайта включил бы журнал всех запросов с IP
  const site = c.slice(c.indexOf('{$SITE_DOMAIN}'));
  assert.doesNotMatch(site, /^\s*log\b/m);
});

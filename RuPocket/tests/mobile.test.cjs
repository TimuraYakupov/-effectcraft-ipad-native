const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../RuPocket/Web/mobile.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, '../RuPocket/Web/mobile.css'), 'utf8');

function page(html, location = 'https://rutracker.org/forum/tracker.php') {
  const dom = new JSDOM(`<!doctype html><html><head><title>Тест :: RuTracker.org</title></head><body>${html}</body></html>`, { url: location, runScripts: 'outside-only' });
  const messages = [];
  dom.window.webkit = { messageHandlers: { rupocket: { postMessage: data => messages.push(data) } } };
  dom.window.eval(source);
  return { dom, window: dom.window, document: dom.window.document, messages };
}

test('Search rows become cards without replacing links, original controls, or event handlers', () => {
  const p = page('<table><tbody><tr id="trs-tr-21"><td><a data-topic_id="21" href="viewtopic.php?t=21">Фильм</a></td><td><b class="seedmed">35</b></td><td><b class="leechmed">4</b></td></tr></tbody></table>');
  const link = p.document.querySelector('a');
  let clicks = 0;
  link.addEventListener('click', event => { event.preventDefault(); clicks++; });
  p.window.RuPocket.refresh();
  assert.ok(p.document.querySelector('tr').classList.contains('rp-topic-row'));
  assert.equal(p.document.querySelector('a'), link);
  link.click();
  assert.equal(clicks, 1);
  assert.equal(p.document.querySelector('.seedmed').parentElement.dataset.rpLabel, 'Сиды');
  p.window.close();
});

test('Login form and password fields stay intact', () => {
  const p = page('<form action="login.php" method="post"><input name="login_username"><input name="login_password" type="password"><input type="hidden" name="token" value="xyz"><input type="submit" value="Вход"></form>', 'https://rutracker.org/forum/login.php');
  assert.equal(p.document.querySelector('[name=login_password]').type, 'password');
  assert.equal(p.document.querySelector('[name=token]').value, 'xyz');
  assert.equal(p.document.querySelector('form').method, 'post');
  assert.equal(p.window.RuPocket.search('тест', 10), false);
  p.window.close();
});

test('Cyrillic search uses the original form and keeps its hidden token', () => {
  const p = page('<form method="post" action="tracker.php"><input name="nm"><input name="token" type="hidden" value="original"><select name="o"><option value="1">Дата</option><option value="10">Сиды</option></select><input name="s" value="1"><button type="submit">Поиск</button></form>');
  let submissions = 0;
  const form = p.document.querySelector('form');
  form.requestSubmit = () => submissions++;
  assert.equal(p.window.RuPocket.search('Планета Земля', 10), true);
  assert.equal(form.elements.nm.value, 'Планета Земля');
  assert.equal(form.elements.o.value, '10');
  assert.equal(form.elements.s.value, '2');
  assert.equal(form.elements.token.value, 'original');
  assert.equal(submissions, 1);
  p.window.close();
});

test('Missing or external search forms are rejected', () => {
  const missing = page('<p>Войдите в аккаунт</p>');
  assert.equal(missing.window.RuPocket.search('query', 10), false);
  missing.window.close();
  const external = page('<form action="https://example.org/forum/tracker.php"><input name="nm"></form>');
  assert.equal(external.window.RuPocket.search('query', 10), false);
  external.window.close();
});

test('Torrent action must match the current topic and an HTTPS RuTracker origin', () => {
  const p = page('<h1 id="topic-title">Пример</h1><a href="dl.php?t=99">Wrong topic</a><a href="https://rutracker.org.evil.example/forum/dl.php?t=42">Wrong host</a><a href="http://rutracker.org/forum/dl.php?t=42">HTTP</a><a href="dl.php?t=42">Download</a><a href="magnet:?xt=urn:btih:0123456789012345678901234567890123456789">magnet</a>', 'https://rutracker.org/forum/viewtopic.php?t=42');
  const state = p.messages.at(-1);
  assert.equal(state.torrentURL, 'https://rutracker.org/forum/dl.php?t=42');
  assert.equal(state.title, 'Пример');
  assert.match(state.magnet, /^magnet:\?xt=urn:btih:/);
  p.window.close();
});

test('Non-topic pages do not expose a misleading download action', () => {
  const p = page('<a href="dl.php?t=42">Download</a>');
  assert.equal(p.messages.at(-1).torrentURL, null);
  p.window.close();
});

test('Repeated refresh is idempotent and original viewport is restored', () => {
  const p = page('<form><input name="nm"></form>');
  p.window.RuPocket.refresh();
  p.window.RuPocket.refresh();
  assert.equal(p.document.querySelectorAll('meta[name=viewport]').length, 1);
  assert.equal(p.messages.length, 1);
  p.window.RuPocket.setEnabled(false);
  assert.equal(p.document.documentElement.classList.contains('rp-mobile'), false);
  p.window.RuPocket.setEnabled(true);
  assert.equal(p.document.documentElement.classList.contains('rp-mobile'), true);
  assert.match(p.document.querySelector('meta[name=viewport]').content, /width=device-width/);
  p.window.close();
});

test('Dynamic search results are adapted', async () => {
  const p = page('<div id="results"></div>');
  p.document.getElementById('results').innerHTML = '<table><tr><td><a data-topic_id="71" href="viewtopic.php?t=71">Новая раздача</a></td></tr></table>';
  await new Promise(resolve => setTimeout(resolve, 260));
  assert.ok(p.document.querySelector('tr').classList.contains('rp-topic-row'));
  p.window.close();
});

test('Links inside a description do not turn its table into search result cards', () => {
  const p = page('<div class="post_body"><table><tr><td><a class="tLink" href="viewtopic.php?t=42">Ссылка</a></td></tr></table></div>');
  assert.equal(p.document.querySelectorAll('.rp-topic-row').length, 0);
  p.window.close();
});

test('CSS parses and every selector is scoped to the mobile layout', () => {
  const p = page('<p>Текст</p>');
  const style = p.document.createElement('style');
  style.textContent = css;
  p.document.head.appendChild(style);
  const rules = Array.from(style.sheet.cssRules);
  assert.ok(rules.length > 25);
  for (const rule of rules) {
    if (rule.selectorText) {
      for (const selector of rule.selectorText.split(',')) assert.match(selector.trim(), /^(html)?\.rp-mobile/);
    }
  }
  p.window.close();
});

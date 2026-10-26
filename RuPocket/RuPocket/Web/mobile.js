/* Render a phone-sized surface from real site links; keep original forms and nodes. */
(() => {
  'use strict';
  if (window.RuPocket) { window.RuPocket.refresh(); return; }
  const pageURL = () => new URL(location.href === 'about:blank' ? document.baseURI : location.href);
  const trusted = u => u.protocol === 'https:' && !u.username && !u.password && (!u.port || u.port === '443') &&
    (u.hostname === 'rutracker.org' || u.hostname.endsWith('.rutracker.org'));
  const absolute = value => { try { const u = new URL(value, document.baseURI); return trusted(u) ? u : null; } catch (_) { return null; } };
  const clean = text => String(text || '').replace(/\s+/g, ' ').trim();
  const original = selector => Array.from(document.querySelectorAll(selector)).filter(n => !n.closest('#rp-app'));
  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text) n.textContent = text; return n; };
  let enabled = true, root = null, observer = null, timer = null, lastRender = '', previousState = '';
  const moved = new Map();
  const post = data => {
    const serialized = JSON.stringify(data);
    if (serialized === previousState) return;
    previousState = serialized;
    window.webkit?.messageHandlers?.rupocket?.postMessage(data);
  };
  const requestSearch = () => window.webkit?.messageHandlers?.rupocket?.postMessage({type: 'search'});
  const restore = () => {
    for (const [node, placeholder] of moved) { if (placeholder.parentNode) placeholder.replaceWith(node); }
    moved.clear();
  };
  const move = (node, parent) => {
    if (!moved.has(node)) { const mark = document.createComment('RuPocket original position'); node.before(mark); moved.set(node, mark); }
    parent.appendChild(node);
  };
  const viewport = () => {
    let meta = document.querySelector('meta[name="viewport"]');
    if (!meta) { meta = document.createElement('meta'); meta.name = 'viewport'; document.head.appendChild(meta); }
    if (!meta.hasAttribute('data-rp-original')) meta.setAttribute('data-rp-original', meta.content || '');
    meta.content = enabled ? 'width=device-width, initial-scale=1, viewport-fit=cover' : (meta.getAttribute('data-rp-original') || 'width=1024');
  };
  const pageTitle = () => clean(original('#topic-title, h1.maintitle, h1')[0]?.textContent || document.title).replace(/\s*::\s*RuTracker\.org\s*$/i, '');
  const forums = () => {
    const seen = new Set(), result = [];
    for (const link of original('a[href]')) {
      const u = absolute(link.href), title = clean(link.textContent);
      if (!u || title.length < 2) continue;
      const isForum = /\/viewforum\.php$/.test(u.pathname) && /^\d+$/.test(u.searchParams.get('f') || '');
      const isCategory = /\/index\.php$/.test(u.pathname) && /^\d+$/.test(u.searchParams.get('c') || '');
      if (!isForum && !isCategory) continue;
      const key = (isForum ? 'f' : 'c') + u.searchParams.get(isForum ? 'f' : 'c');
      if (seen.has(key)) continue;
      seen.add(key); result.push({title, url: u.href, kind: isForum ? 'Раздел' : 'Категория'});
    }
    return result;
  };
  const topics = () => {
    const seen = new Set(), result = [];
    for (const link of original('a[data-topic_id], a.tLink, a.torTopic, a.tt-text, a.topictitle, a[href*="viewtopic.php?t="]')) {
      const u = absolute(link.href), title = clean(link.textContent), row = link.closest('tr');
      if (!u || !/\/viewtopic\.php$/.test(u.pathname) || !/^\d+$/.test(u.searchParams.get('t') || '') || !row || link.closest('.post_body, .postbody')) continue;
      if (title.length < 5 || u.hash || /^(последнее|последний|перейти|новые сообщения)/i.test(title)) continue;
      const id = u.searchParams.get('t'); if (seen.has(id)) continue;
      seen.add(id);
      row.classList.add('rp-topic-row'); row.closest('table')?.classList.add('rp-topic-table');
      link.classList.add('rp-topic-link'); link.closest('td')?.classList.add('rp-title-cell');
      const seed = row.querySelector('.seedmed'), leech = row.querySelector('.leechmed');
      if (seed) seed.closest('td')?.setAttribute('data-rp-label', 'Сиды');
      if (leech) leech.closest('td')?.setAttribute('data-rp-label', 'Пиры');
      const size = row.querySelector('.tor-size, td[data-ts_text].row4, .tor-size a');
      result.push({title, url: u.href, seed: clean(seed?.textContent), leech: clean(leech?.textContent), size: clean(size?.textContent)});
    }
    return result;
  };
  const pagination = () => {
    const seen = new Set(), result = [], current = pageURL();
    for (const link of original('a.pg, a[href*="start="]')) {
      const u = absolute(link.href), text = clean(link.textContent);
      if (!u || u.pathname !== current.pathname || !text || text.length > 25 || seen.has(u.href)) continue;
      if (!/^(\d+|след|пред|дальше|назад|[«»<>])/i.test(text)) continue;
      seen.add(u.href); result.push({title: text, url: u.href});
    }
    return result;
  };
  const icon = title => /кино|фильм|сериал|видео/i.test(title) ? '🎬' : /музык|джаз|рок|аудио/i.test(title) ? '🎵' : /игр/i.test(title) ? '🎮' : /книг|литератур|учеб/i.test(title) ? '📚' : /программ|софт|windows|linux|apple/i.test(title) ? '💻' : '📂';
  const action = (title, handler) => { const b = el('button', 'rp-search-action', title); b.type = 'button'; b.addEventListener('click', handler); return b; };
  const card = (item, isTopic) => {
    const a = el('a', isTopic ? 'rp-card rp-result' : 'rp-card rp-forum-card'); a.href = item.url;
    if (!isTopic) a.appendChild(el('span', 'rp-icon', icon(item.title)));
    const text = el('span', 'rp-card-content'); text.appendChild(el('span', 'rp-card-title', item.title));
    const meta = el('span', 'rp-card-meta');
    if (isTopic) {
      if (item.size) meta.appendChild(el('span', 'rp-chip', item.size));
      if (item.seed) meta.appendChild(el('span', 'rp-chip rp-seeds', '↑ ' + item.seed + ' сидов'));
      if (item.leech) meta.appendChild(el('span', 'rp-chip', '↓ ' + item.leech + ' пиров'));
    } else meta.textContent = item.kind;
    if (meta.childNodes.length) text.appendChild(meta);
    a.appendChild(text); if (!isTopic) a.appendChild(el('span', 'rp-chevron', '›'));
    return a;
  };
  const model = () => {
    const path = pageURL().pathname;
    const login = document.querySelector('input[name="login_password"]')?.form;
    const search = document.querySelector('input[name="nm"]')?.form;
    const bodies = Array.from(document.querySelectorAll('.post_body, .postbody')).filter(n => !n.parentElement?.closest('.post_body, .postbody'));
    if (login && /\/login\.php$/.test(path)) return {type: 'login', title: 'Вход в RuTracker', form: login};
    if (/\/viewtopic\.php$/.test(path) && bodies.length) return {type: 'topic', title: pageTitle(), bodies, pages: pagination()};
    const list = /\/(tracker|viewforum|search)\.php$/.test(path) ? topics() : [];
    const sections = forums();
    if (list.length) return {type: 'results', title: /tracker|search/.test(path) ? 'Результаты поиска' : pageTitle(), topics: list, pages: pagination()};
    if (sections.length) return {type: 'forums', title: /\/index\.php$/.test(path) && !pageURL().searchParams.has('c') ? 'Разделы RuTracker' : pageTitle(), forums: sections};
    if (search && /\/tracker\.php$/.test(path)) return {type: 'search', title: 'Поиск по RuTracker', form: search};
    if (login) return {type: 'login', title: 'Вход в RuTracker', form: login};
    return null;
  };
  const signature = m => JSON.stringify({type: m.type, title: m.title, forums: m.forums, topics: m.topics, pages: m.pages, body: m.bodies?.map(n => clean(n.textContent)), form: m.form?.getAttribute('action')});
  const render = m => {
    const stamp = signature(m);
    if (root && stamp === lastRender) return;
    lastRender = stamp;
    restore(); root?.remove(); root = el('main', 'rp-surface'); root.id = 'rp-app';
    const heading = el('header', 'rp-heading');
    heading.appendChild(el('p', 'rp-eyebrow', m.type === 'forums' ? 'КАТАЛОГ' : m.type === 'topic' ? 'РАЗДАЧА' : 'RUTRACKER'));
    heading.appendChild(el('h1', 'rp-page-title', m.title)); root.appendChild(heading);
    if (m.type === 'forums' || m.type === 'results') root.appendChild(action('⌕  Найти раздачу', requestSearch));
    if (m.forums) {
      const filter = el('input', 'rp-section-filter'); filter.type = 'search'; filter.placeholder = 'Фильтр разделов'; filter.setAttribute('aria-label', 'Фильтр разделов'); root.appendChild(filter);
      const list = el('section', 'rp-cards'); list.setAttribute('aria-label', 'Разделы');
      for (const item of m.forums) list.appendChild(card(item, false));
      filter.addEventListener('input', () => { const q = clean(filter.value).toLocaleLowerCase('ru'); for (const c of list.children) c.hidden = !c.textContent.toLocaleLowerCase('ru').includes(q); });
      root.appendChild(list);
    }
    if (m.topics) {
      root.appendChild(el('p', 'rp-count', 'Раздач на странице: ' + m.topics.length));
      const list = el('section', 'rp-cards'); list.setAttribute('aria-label', 'Раздачи');
      for (const item of m.topics) list.appendChild(card(item, true)); root.appendChild(list);
    }
    if (m.form) { const panel = el('section', 'rp-form'); move(m.form, panel); root.appendChild(panel); }
    if (m.bodies) {
      m.bodies.forEach((node, index) => {
        const panel = el(index === 0 ? 'article' : 'section', index === 0 ? 'rp-description' : 'rp-comment');
        if (index) panel.appendChild(el('p', 'rp-comment-label', 'Комментарий ' + index));
        move(node, panel); root.appendChild(panel);
      });
    }
    if (m.pages?.length) {
      const nav = el('nav', 'rp-pagination'); nav.setAttribute('aria-label', 'Страницы');
      for (const item of m.pages) { const a = el('a', '', item.title); a.href = item.url; nav.appendChild(a); }
      root.appendChild(nav);
    }
    document.body.appendChild(root); document.documentElement.classList.add('rp-rendered');
  };
  const state = () => {
    let torrentURL = null, magnet = null;
    if (/\/viewtopic\.php$/.test(pageURL().pathname)) {
      const topic = pageURL().searchParams.get('t');
      for (const link of document.querySelectorAll('a[href]')) {
        const raw = link.getAttribute('href') || '', u = absolute(link.href);
        if (!magnet && raw.startsWith('magnet:?') && /[?&]xt=urn:btih:/i.test(raw)) magnet = raw;
        if (!torrentURL && u?.pathname.endsWith('/dl.php') && u.searchParams.get('t') === topic && topic) torrentURL = u.href;
      }
    }
    post({type: 'page', title: pageTitle(), torrentURL, magnet});
  };
  const refresh = () => {
    observer?.disconnect();
    try {
      document.documentElement.classList.toggle('rp-mobile', enabled); viewport();
      if (enabled) {
        const m = model();
        if (m) render(m);
        else { restore(); root?.remove(); root = null; lastRender = ''; document.documentElement.classList.remove('rp-rendered'); }
      } else { restore(); root?.remove(); root = null; lastRender = ''; document.documentElement.classList.remove('rp-rendered'); }
      state();
    } finally { if (document.body) observer?.observe(document.body, {childList: true, subtree: true}); }
  };
  window.RuPocket = {
    refresh,
    setEnabled(value) { enabled = !!value; refresh(); },
    search(query, order) {
      if (!trusted(pageURL()) || !pageURL().pathname.endsWith('/tracker.php')) return false;
      const input = document.querySelector('input[name="nm"]'), form = input?.form, target = form && absolute(form.action);
      if (!input || !form || !target?.pathname.endsWith('/tracker.php')) return false;
      input.value = String(query);
      const sort = form.querySelector('[name="o"]'); if (sort) sort.value = String(order);
      const direction = form.querySelector('[name="s"]'); if (direction) direction.value = '2';
      const submit = form.querySelector('input[type="submit"], button[type="submit"]');
      if (typeof form.requestSubmit === 'function') form.requestSubmit(submit || undefined);
      else if (submit) submit.click(); else HTMLFormElement.prototype.submit.call(form);
      return true;
    }
  };
  const start = () => {
    observer = new MutationObserver(mutations => {
      if (mutations.every(m => root && root.contains(m.target))) return;
      clearTimeout(timer); timer = setTimeout(refresh, 120);
    });
    refresh();
  };
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start, {once: true});
})();

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
  const navigation = 'nav, .nav, .breadcrumbs, .breadcrumb, #breadcrumbs, #page_header, #page_footer, .last-post, .lastpost';
  const forumTitle = 'a.forumlink, .forumlink a, a.forumlink-new, a.forum-title, .forum-title a, .f-name a, a.f-name';
  const topicTitle = 'a[data-topic_id], a.tLink, a.torTopic, a.tt-text, .tt-text a, a.topictitle, a.topic-title, .topic-title a';
  const withSource = (data, link) => { Object.defineProperty(data, 'source', {value: link}); return data; };
  const forums = () => {
    const seen = new Map(), current = pageURL(), inside = !/\/index\.php$/.test(current.pathname) || current.searchParams.has('c');
    const candidates = original('a[href]').filter(link => {
      const u = absolute(link.href);
      if (!u || clean(link.textContent).length < 2) return false;
      const isForum = /\/viewforum\.php$/.test(u.pathname) && /^\d+$/.test(u.searchParams.get('f') || '');
      const isCategory = /\/index\.php$/.test(u.pathname) && /^\d+$/.test(u.searchParams.get('c') || '');
      return isForum || isCategory;
    });
    const mainLinks = inside ? candidates.filter(link => !link.closest(navigation + ', #sidebar, #sidebar1, #sidebar2, .sidebar') &&
      (link.matches(forumTitle) || link.closest('.forumline, #forums, #forum-list, #forums_list, .forum-list, .forum-listing'))) : [];
    const pool = mainLinks.length ? mainLinks : candidates;
    for (const link of pool) {
      const u = absolute(link.href), category = /\/index\.php$/.test(u.pathname), id = u.searchParams.get(category ? 'c' : 'f');
      if (inside && link.closest(navigation)) continue;
      if (inside && category) continue;
      if (u.pathname === current.pathname && id === current.searchParams.get(category ? 'c' : 'f')) continue;
      const key = (category ? 'c:' : 'f:') + id;
      const score = (link.matches(forumTitle) ? 10 : 0) + (link.closest('.forumline, .forum-list') ? 3 : 0);
      if (seen.has(key) && seen.get(key).score >= score) continue;
      seen.set(key, withSource({key, id, title: clean(link.textContent), url: u.href, kind: category ? 'Категория' : 'Раздел', category, score}, link));
    }
    return Array.from(seen.values());
  };
  const groupForums = items => {
    const markers = original('.cat_title, .cat-title, .catTitle, .catHead, .category-title, .category-header')
      .map(node => ({node, title: clean(node.textContent).replace(/^[+−–\-\s]+/, '')}))
      .filter(m => m.title && m.title.length < 100 && !m.node.querySelector('input, select'));
    const groups = new Map();
    const fallback = title => /игр|консол|playstation|xbox|nintendo|sega/i.test(title) ? 'Игры' :
      /кино|фильм|сериал|мульт|видео|аниме/i.test(title) ? 'Кино, видео и ТВ' :
      /музык|аудио|рок|джаз|flac|mp3|классич|саундтрек/i.test(title) ? 'Музыка и аудио' :
      /книг|литератур|обуч|учеб|язык|журнал/i.test(title) ? 'Книги и обучение' :
      /программ|софт|windows|linux|macos|apple|дизайн/i.test(title) ? 'Программы' :
      /спорт|футбол|хоккей/i.test(title) ? 'Спорт' : 'Остальные разделы';
    for (const item of items.filter(i => !i.category)) {
      let heading = null;
      for (const marker of markers) {
        if (marker.node.contains(item.source)) { heading = marker.title; break; }
        if (marker.node.compareDocumentPosition(item.source) & Node.DOCUMENT_POSITION_FOLLOWING) heading = marker.title;
      }
      const title = heading || fallback(item.title);
      if (!groups.has(title)) groups.set(title, {title, items: []});
      groups.get(title).items.push(item);
    }
    return Array.from(groups.values());
  };
  const topics = () => {
    const seen = new Map();
    for (const link of original(topicTitle + ', a[href*="viewtopic.php?t="]')) {
      const u = absolute(link.href), title = clean(link.textContent), preferred = link.matches(topicTitle);
      const row = link.closest('tr') || link.closest('.topic-row, .topic, .tor-row, .topic-card');
      if (!u || !/\/viewtopic\.php$/.test(u.pathname) || !/^\d+$/.test(u.searchParams.get('t') || '') || link.closest('.post_body, .postbody, ' + navigation)) continue;
      if ((!row && !preferred) || title.length < 2 || (!preferred && u.hash) || /^(последнее|последний|перейти|новые сообщения|[«»<>])/i.test(title)) continue;
      if (!preferred && row?.querySelector(forumTitle)) continue; // last-post previews inside subforum rows
      const id = u.searchParams.get('t'), score = preferred ? 10 : 0;
      if (seen.has(id) && seen.get(id).score >= score) continue;
      u.hash = '';
      row?.classList.add('rp-topic-row'); row?.closest('table')?.classList.add('rp-topic-table');
      link.classList.add('rp-topic-link'); link.closest('td')?.classList.add('rp-title-cell');
      const seed = row?.querySelector('.seedmed'), leech = row?.querySelector('.leechmed');
      if (seed) seed.closest('td')?.setAttribute('data-rp-label', 'Сиды');
      if (leech) leech.closest('td')?.setAttribute('data-rp-label', 'Пиры');
      const size = row?.querySelector('.tor-size, td[data-ts_text].row4, .tor-size a');
      seen.set(id, {title, url: u.href, seed: clean(seed?.textContent), leech: clean(leech?.textContent), size: clean(size?.textContent), score});
    }
    return Array.from(seen.values());
  };
  const pagination = () => {
    const seen = new Set(), result = [], current = pageURL();
    for (const link of original('a.pg, a[href*="start="]')) {
      const u = absolute(link.href), text = clean(link.textContent);
      if (!u || u.pathname !== current.pathname || (current.searchParams.has('f') && u.searchParams.get('f') !== current.searchParams.get('f')) || (current.searchParams.has('t') && u.searchParams.get('t') !== current.searchParams.get('t')) || !text || text.length > 25 || seen.has(u.href)) continue;
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
    const sections = /\/(tracker|search)\.php$/.test(path) ? [] : forums();
    const globalIndex = /\/index\.php$/.test(path) && (!pageURL().searchParams.has('c') || pageURL().searchParams.get('c') === '0');
    if (globalIndex && sections.length) {
      const categories = sections.filter(i => i.category && i.id !== '0');
      if (categories.length) return {type: 'catalogue', title: 'Разделы RuTracker', forums: categories};
      return {type: 'catalogue', title: 'Разделы RuTracker', groups: groupForums(sections)};
    }
    // A forum can contain announcements, subforums and torrents at the same time.
    if (sections.length || list.length) return {
      type: /tracker|search/.test(path) ? 'results' : 'section',
      title: /tracker|search/.test(path) ? 'Результаты поиска' : pageTitle(),
      forums: sections, topics: list, pages: pagination()
    };
    if (search && /\/tracker\.php$/.test(path)) return {type: 'search', title: 'Поиск по RuTracker', form: search};
    if (login) return {type: 'login', title: 'Вход в RuTracker', form: login};
    return null;
  };
  const signature = m => JSON.stringify({type: m.type, title: m.title, forums: m.forums, groups: m.groups, topics: m.topics, pages: m.pages, body: m.bodies?.map(n => clean(n.textContent)), form: m.form?.getAttribute('action')});
  const render = m => {
    const stamp = signature(m);
    if (root && stamp === lastRender) return;
    lastRender = stamp;
    restore(); root?.remove(); root = el('main', 'rp-surface'); root.id = 'rp-app';
    const heading = el('header', 'rp-heading');
    heading.appendChild(el('p', 'rp-eyebrow', ['catalogue', 'section'].includes(m.type) ? 'КАТАЛОГ' : m.type === 'topic' ? 'РАЗДАЧА' : 'RUTRACKER'));
    heading.appendChild(el('h1', 'rp-page-title', m.title)); root.appendChild(heading);
    if (['catalogue', 'section', 'results'].includes(m.type)) root.appendChild(action('⌕  Найти раздачу', requestSearch));
    const sectionCards = [];
    const groupNodes = [];
    if (m.forums?.length || m.groups?.length) {
      if (m.type === 'section') root.appendChild(el('h2', 'rp-section-heading', 'Подразделы'));
      const filter = el('input', 'rp-section-filter'); filter.type = 'search'; filter.placeholder = 'Фильтр разделов'; filter.setAttribute('aria-label', 'Фильтр разделов'); root.appendChild(filter);
      if (m.forums?.length) {
        const list = el('section', 'rp-cards'); list.setAttribute('aria-label', 'Разделы');
        for (const item of m.forums) { const c = card(item, false); sectionCards.push(c); list.appendChild(c); }
        root.appendChild(list);
      }
      if (m.groups) {
        const list = el('section', 'rp-groups'); list.setAttribute('aria-label', 'Категории');
        for (const group of m.groups) {
          const details = el('details', 'rp-category-group'), summary = el('summary', 'rp-category-toggle');
          summary.appendChild(el('span', 'rp-icon', icon(group.title)));
          const label = el('span', 'rp-card-content'); label.appendChild(el('span', 'rp-card-title', group.title));
          label.appendChild(el('span', 'rp-card-meta', 'Разделов: ' + group.items.length)); summary.appendChild(label);
          summary.appendChild(el('span', 'rp-chevron', '›')); details.appendChild(summary);
          const children = el('section', 'rp-cards rp-category-children');
          for (const item of group.items) { const c = card(item, false); sectionCards.push(c); children.appendChild(c); }
          details.appendChild(children); list.appendChild(details); groupNodes.push(details);
        }
        root.appendChild(list);
      }
      filter.addEventListener('input', () => {
        const q = clean(filter.value).toLocaleLowerCase('ru');
        for (const c of sectionCards) c.hidden = !c.textContent.toLocaleLowerCase('ru').includes(q);
        for (const group of groupNodes) {
          const titleMatch = group.querySelector('summary').textContent.toLocaleLowerCase('ru').includes(q);
          if (titleMatch) for (const c of group.querySelectorAll('.rp-card')) c.hidden = false;
          group.hidden = !titleMatch && !group.querySelector('.rp-card:not([hidden])');
          group.open = !!q && !group.hidden;
        }
      });
    }
    if (m.topics?.length) {
      if (m.forums?.length) root.appendChild(el('h2', 'rp-section-heading', 'Темы и раздачи'));
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

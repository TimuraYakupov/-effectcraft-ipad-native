/* RuPocket: enhance the original document without rebuilding forms or login. */
(() => {
  'use strict';
  if (window.RuPocket) return;
  const trusted = url => url.protocol === 'https:' && !url.username && !url.password &&
    (!url.port || url.port === '443') &&
    (url.hostname === 'rutracker.org' || url.hostname.endsWith('.rutracker.org'));
  const absolute = value => {
    try { const url = new URL(value, document.baseURI); return trusted(url) ? url : null; }
    catch (_) { return null; }
  };
  let enabled = true;
  let timer;
  let previousState = '';
  const post = data => {
    const serialized = JSON.stringify(data);
    if (serialized === previousState) return;
    previousState = serialized;
    window.webkit?.messageHandlers?.rupocket?.postMessage(data);
  };
  const refresh = () => {
    document.documentElement.classList.toggle('rp-mobile', enabled);
    let viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) {
      viewport = document.createElement('meta');
      viewport.name = 'viewport';
      viewport.dataset.rpCreated = 'true';
      document.head.appendChild(viewport);
    }
    if (!viewport.dataset.rpOriginal) {
      viewport.dataset.rpOriginal = viewport.content || '__empty__';
    }
    viewport.content = enabled ? 'width=device-width, initial-scale=1, viewport-fit=cover' :
      (viewport.dataset.rpOriginal === '__empty__' ? 'width=1024' : viewport.dataset.rpOriginal);

    document.querySelectorAll('a[data-topic_id], a.tLink, a.torTopic, a.tt-text, a.topictitle').forEach(link => {
      const url = absolute(link.href);
      if (!url || !url.pathname.endsWith('/viewtopic.php')) return;
      const row = link.closest('tr');
      const table = row?.closest('table');
      if (!row || !table || row.closest('.post_body, .postbody')) return;
      row.classList.add('rp-topic-row');
      table.classList.add('rp-topic-table');
      link.classList.add('rp-topic-link');
      link.closest('td')?.classList.add('rp-title-cell');
    });
    document.querySelectorAll('a.forumlink, a.forumlink-new').forEach(link => {
      const row = link.closest('tr');
      if (!row) return;
      row.classList.add('rp-forum-row');
      link.closest('td')?.classList.add('rp-forum-cell');
    });
    document.querySelectorAll('.seedmed, .leechmed, .tor-size, .row4.small').forEach(node => {
      const cell = node.closest('td');
      if (node.matches('.seedmed')) cell?.setAttribute('data-rp-label', 'Сиды');
      if (node.matches('.leechmed')) cell?.setAttribute('data-rp-label', 'Пиры');
      if (node.matches('.tor-size')) cell?.setAttribute('data-rp-label', 'Размер');
    });
    document.querySelectorAll('.post_body img, .postbody img').forEach(img => {
      img.loading = 'lazy';
    });

    let torrentURL = null;
    let magnet = null;
    if (location.pathname.endsWith('/viewtopic.php')) {
      const topic = new URL(location.href).searchParams.get('t');
      for (const link of document.querySelectorAll('a[href]')) {
        const raw = link.getAttribute('href') || '';
        if (!magnet && raw.startsWith('magnet:?') && /[?&]xt=urn:btih:/i.test(raw)) magnet = raw;
        const url = absolute(link.href);
        if (!torrentURL && url?.pathname.endsWith('/dl.php') && url.searchParams.get('t') === topic && topic) {
          torrentURL = url.href;
        }
      }
    }
    const title = (document.querySelector('#topic-title, h1.maintitle, h1')?.textContent || document.title)
      .replace(/\s*::\s*RuTracker\.org\s*$/i, '').trim();
    post({type: 'page', title, torrentURL, magnet});
  };

  window.RuPocket = {
    refresh,
    setEnabled(value) { enabled = !!value; refresh(); },
    search(query, order) {
      if (!trusted(new URL(location.href)) || !location.pathname.endsWith('/tracker.php')) return false;
      // Use the site's form and its document encoding, including Windows-1251.
      const input = document.querySelector('input[name="nm"]');
      const form = input?.form;
      const action = form && absolute(form.action);
      if (!input || !form || !action || !action.pathname.endsWith('/tracker.php')) return false;
      input.value = String(query);
      const sort = form.querySelector('[name="o"]');
      if (sort) sort.value = String(order);
      const direction = form.querySelector('[name="s"]');
      if (direction) direction.value = '2';
      const submit = form.querySelector('input[type="submit"], button[type="submit"]');
      if (typeof form.requestSubmit === 'function') form.requestSubmit(submit || undefined);
      else if (submit) submit.click();
      else HTMLFormElement.prototype.submit.call(form);
      return true;
    }
  };
  const start = () => {
    refresh();
    new MutationObserver(() => {
      clearTimeout(timer);
      timer = setTimeout(refresh, 180);
    }).observe(document.body, {childList: true, subtree: true});
  };
  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start, {once: true});
})();

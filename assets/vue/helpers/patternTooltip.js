const patternMeta = new Map();
const patternMetaPromises = new Map();
let activePersistentTooltip = null;

export function patternIdsFromInfo(info) {
  if (!info) return [];
  if (Array.isArray(info.pids)) return info.pids.map(id => String(id)).filter(Boolean);
  if (info.pid != null) return [String(info.pid)];
  return [];
}

export async function fetchPatternMeta(id) {
  if (patternMeta.has(id)) return patternMeta.get(id);
  if (patternMetaPromises.has(id)) return patternMetaPromises.get(id);
  const promise = (async () => {
    const res = await fetch(`/licenses/pattern/${id}.json`);
    if (!res.ok) return null;
    const meta = await res.json();
    patternMeta.set(id, meta);
    return meta;
  })();
  patternMetaPromises.set(id, promise);
  return promise;
}

export async function renderPatternTooltip(dom, ids, options = {}) {
  dom.innerHTML =
    '<div class="cavil-pattern-tip-loading"><i class="fa-solid fa-spinner fa-pulse"></i> Loading...</div>';
  try {
    const metas = await Promise.all(ids.map(id => fetchPatternMeta(id)));
    const valid = metas.filter(m => m);
    if (valid.length === 0) {
      dom.innerHTML = '<div class="cavil-pattern-tip-error">No pattern info available.</div>';
      return;
    }
    dom.innerHTML = '';
    for (const meta of valid) dom.appendChild(buildPatternTooltipCard(meta, options));
  } catch (e) {
    dom.innerHTML = '<div class="cavil-pattern-tip-error">Failed to load pattern info.</div>';
  }
}

export function buildPatternTooltipCard(meta, options = {}) {
  const card = document.createElement('div');
  card.className = 'cavil-pattern-tip-card';

  const header = document.createElement('div');
  header.className = 'cavil-pattern-tip-header';
  const title = document.createElement('span');
  title.className = 'cavil-pattern-tip-title';
  title.textContent = meta.license && meta.license !== '' ? meta.license : 'Keyword pattern';
  header.appendChild(title);
  const risk = document.createElement('span');
  risk.className = `cavil-pattern-tip-risk risk-${meta.risk ?? 0}`;
  risk.textContent = `risk ${meta.risk ?? '?'}`;
  header.appendChild(risk);
  card.appendChild(header);

  const preview = document.createElement('pre');
  preview.className = 'cavil-pattern-tip-preview';
  const allLines = (meta.pattern ?? '').split('\n');
  const shown = allLines.slice(0, 6).join('\n');
  preview.textContent = shown + (allLines.length > 6 ? '\n...' : '');
  card.appendChild(preview);

  if (options.link !== false) {
    const footer = document.createElement('div');
    footer.className = 'cavil-pattern-tip-footer';
    const link = document.createElement('a');
    link.href = `/licenses/edit_pattern/${meta.id}`;
    link.target = '_blank';
    link.rel = 'noopener';
    link.textContent = 'Open pattern';
    footer.appendChild(link);
    card.appendChild(footer);
  }

  return card;
}

export function showPatternTooltip(anchor, ids, options = {}) {
  if (!ids.length) return null;
  const persistent = options.persistent ?? false;
  const interactive = options.interactive ?? true;
  const hideDelay = options.hideDelay ?? 800;
  if (persistent && activePersistentTooltip) activePersistentTooltip.destroy();
  const dom = document.createElement('div');
  dom.className = 'cavil-pattern-tip cavil-pattern-tip-floating';
  if (!interactive) {
    dom.style.pointerEvents = 'none';
  }
  document.body.appendChild(dom);
  let destroyTimer = null;
  let destroyed = false;
  let watchingDocument = false;
  let watchingScroll = false;

  const place = () => {
    if (destroyed) return;
    const rect = anchor.getBoundingClientRect();
    const offsetLeft = options.offsetLeft ?? 96;
    const maxTop = window.innerHeight - dom.offsetHeight - 8;
    let top;
    if (options.placement === 'source-row') {
      const below = rect.bottom + 6;
      const above = rect.top - dom.offsetHeight - 6;
      top = below + dom.offsetHeight <= window.innerHeight - 8 || above < 8 ? below : above;
    } else {
      top = rect.top - 4;
    }
    top = Math.min(Math.max(8, top), Math.max(8, maxTop));
    const maxLeft = window.innerWidth - dom.offsetWidth - 8;
    const left = Math.min(Math.max(8, rect.left + offsetLeft), Math.max(8, maxLeft));
    dom.style.top = `${top}px`;
    dom.style.left = `${left}px`;
  };

  const cancelDestroy = () => {
    if (destroyTimer) clearTimeout(destroyTimer);
    destroyTimer = null;
  };

  const destroy = () => {
    if (destroyed) return;
    cancelDestroy();
    stopWatchingDocument();
    stopWatchingScroll();
    destroyed = true;
    dom.remove();
    if (activePersistentTooltip?.destroy === destroy) activePersistentTooltip = null;
    if (options.onDestroy) options.onDestroy();
  };

  const scheduleDestroy = () => {
    cancelDestroy();
    destroyTimer = setTimeout(destroy, hideDelay);
  };

  const onDocumentPointerDown = event => {
    if (dom.contains(event.target) || anchor.contains(event.target)) return;
    destroy();
  };

  const onDocumentKeyDown = event => {
    if (event.key === 'Escape') destroy();
  };

  const onScroll = () => destroy();

  function startWatchingDocument() {
    if (watchingDocument) return;
    watchingDocument = true;
    document.addEventListener('mousedown', onDocumentPointerDown, true);
    document.addEventListener('keydown', onDocumentKeyDown, true);
  }

  function stopWatchingDocument() {
    if (!watchingDocument) return;
    watchingDocument = false;
    document.removeEventListener('mousedown', onDocumentPointerDown, true);
    document.removeEventListener('keydown', onDocumentKeyDown, true);
  }

  function startWatchingScroll() {
    if (watchingScroll) return;
    watchingScroll = true;
    window.addEventListener('scroll', onScroll, true);
  }

  function stopWatchingScroll() {
    if (!watchingScroll) return;
    watchingScroll = false;
    window.removeEventListener('scroll', onScroll, true);
  }

  dom.style.visibility = 'hidden';
  if (!persistent && interactive) {
    dom.addEventListener('mouseenter', cancelDestroy);
    dom.addEventListener('mouseleave', scheduleDestroy);
    dom.addEventListener('focusin', cancelDestroy);
    dom.addEventListener('focusout', scheduleDestroy);
  }
  if (!persistent) startWatchingScroll();
  const rendered = renderPatternTooltip(dom, ids, options);

  requestAnimationFrame(() => {
    place();
    dom.style.visibility = 'visible';
  });
  rendered.then(place);

  const tooltip = {
    destroy,
    scheduleDestroy,
    cancelDestroy
  };
  if (persistent) {
    activePersistentTooltip = tooltip;
    setTimeout(startWatchingDocument, 0);
  }
  return tooltip;
}

import {showFloatingTooltip} from './floatingTooltip.js';

const patternMeta = new Map();
const patternMetaPromises = new Map();

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
    if (valid.length > 1) {
      const summary = document.createElement('div');
      summary.className = 'cavil-pattern-tip-summary';
      summary.textContent = `${valid.length} matching patterns`;
      dom.appendChild(summary);
    }
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
  const title = document.createElement('strong');
  title.className = 'cavil-pattern-tip-title';
  title.textContent = meta.license && meta.license !== '' ? meta.license : 'Keyword pattern';
  header.appendChild(title);

  const actions = document.createElement('div');
  actions.className = 'cavil-pattern-tip-actions';

  if (options.link !== false) {
    const link = document.createElement('a');
    link.className = 'cavil-pattern-tip-open';
    link.href = `/licenses/edit_pattern/${meta.id}`;
    link.target = '_blank';
    link.rel = 'noopener';
    link.title = 'Open pattern';
    link.setAttribute('aria-label', 'Open pattern');
    link.innerHTML = '<i class="fa-solid fa-arrow-up-right-from-square"></i>';
    actions.appendChild(link);
  }

  const risk = document.createElement('span');
  risk.className = `cavil-pattern-tip-risk risk-${meta.risk ?? 0}`;
  risk.textContent = `risk ${meta.risk ?? '?'}`;
  actions.appendChild(risk);

  header.appendChild(actions);
  card.appendChild(header);

  const preview = document.createElement('pre');
  preview.className = 'cavil-pattern-tip-preview';
  const allLines = (meta.pattern ?? '').split('\n');
  const shown = allLines.slice(0, 6).join('\n');
  preview.textContent = shown + (allLines.length > 6 ? '\n...' : '');
  const previewWrap = document.createElement('div');
  previewWrap.className = 'cavil-pattern-tip-preview-wrap';
  if (allLines.length > 6) previewWrap.classList.add('is-truncated');
  previewWrap.appendChild(preview);
  card.appendChild(previewWrap);

  return card;
}

export function showPatternTooltip(anchor, ids, options = {}) {
  if (!ids.length) return null;
  return showFloatingTooltip(anchor, {...options, render: dom => renderPatternTooltip(dom, ids, options)});
}

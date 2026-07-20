import {showFloatingTooltip} from './floatingTooltip.js';

// Hover tooltip that explains *how* a snippet was automatically resolved, shown on the derived
// (folded/cleared/covered) rows of the file browser. It reuses the shared .cavil-pattern-tip box + title
// header, but its body is deliberately a labelled explanation (lead sentence + metric rows), not the
// monospace pattern preview, so the two are never mistaken for each other. It reads the detail the
// backend put on line[1] (Cavil::Model::Snippets::file_line_info).

// Each resolution kind describes itself as a title, an optional risk chip, one short lead sentence, and a
// set of labelled metric rows. The metric rows are formatted identically across kinds - the license the
// snippet relates to is always a row (never inline), so fold and boilerplate read consistently. Absent
// fields (e.g. no classifier confidence, or an overlap-clear with no similarity) simply drop their rows.
function describe(info) {
  const licenseValue = info.closestSpdx || info.spdx || info.closest || info.name;
  const similarity = info.similarity ? {label: 'Similarity', value: `${info.similarity}%`} : null;
  const confidence = info.confidence ? {label: 'Confidence', value: `${info.confidence}%`} : null;
  const resembles = info.closest ? {label: 'Resembles', value: licenseValue, mono: true} : null;

  if (info.folded) {
    return {
      title: 'Automatically folded',
      icon: 'fa-circle-check',
      risk: info.risk,
      lead: 'Treated as a real match for this license.',
      metrics: [{label: 'Counted as', value: licenseValue, mono: true}, similarity, confidence]
    };
  }
  if (info.cleared && info.clearReason === 'overlap') {
    return {
      title: 'Cleared as redundant',
      icon: 'fa-circle-minus',
      lead: 'Repeats a license already matched on these lines.',
      metrics: []
    };
  }
  if (info.cleared) {
    return {
      title: 'Cleared as license boilerplate',
      icon: 'fa-circle-xmark',
      lead: 'Generic license wording that names no single license.',
      metrics: [resembles, similarity, confidence]
    };
  }
  if (info.covered) {
    return {
      title: 'Covered by an existing match',
      icon: 'fa-circle-dot',
      lead: 'A license already established here covers it.',
      metrics: [resembles, similarity, confidence]
    };
  }
  return null;
}

function render(dom, info) {
  const spec = describe(info);
  if (!spec) {
    dom.innerHTML = '<div class="cavil-pattern-tip-error">No resolution info available.</div>';
    return;
  }

  const card = document.createElement('div');
  card.className = 'cavil-pattern-tip-card cavil-resolution-tip';

  // Shared box header (title + optional risk chip) - identical to the pattern tooltip on purpose.
  const header = document.createElement('div');
  header.className = 'cavil-pattern-tip-header';
  const title = document.createElement('strong');
  title.className = 'cavil-pattern-tip-title';
  if (spec.icon) {
    const icon = document.createElement('i');
    icon.className = `fa-solid ${spec.icon} cavil-resolution-tip-icon`;
    icon.setAttribute('aria-hidden', 'true');
    title.appendChild(icon);
  }
  title.appendChild(document.createTextNode(spec.title));
  header.appendChild(title);
  if (spec.risk != null) {
    const actions = document.createElement('div');
    actions.className = 'cavil-pattern-tip-actions';
    const risk = document.createElement('span');
    risk.className = `cavil-pattern-tip-risk risk-${spec.risk}`;
    risk.textContent = `risk ${spec.risk}`;
    actions.appendChild(risk);
    header.appendChild(actions);
  }
  card.appendChild(header);

  // Distinct body: one short lead sentence + a small definition-list of metrics.
  const body = document.createElement('div');
  body.className = 'cavil-resolution-tip-body';
  const lead = document.createElement('div');
  lead.className = 'cavil-resolution-tip-lead';
  lead.textContent = spec.lead;
  body.appendChild(lead);

  const metrics = spec.metrics.filter(Boolean);
  if (metrics.length > 0) {
    const dl = document.createElement('dl');
    dl.className = 'cavil-resolution-tip-metrics';
    for (const m of metrics) {
      const dt = document.createElement('dt');
      dt.className = 'cavil-resolution-tip-metric-label';
      dt.textContent = m.label;
      const dd = document.createElement('dd');
      dd.className = 'cavil-resolution-tip-metric-value' + (m.mono ? ' mono' : '');
      dd.textContent = m.value;
      dl.appendChild(dt);
      dl.appendChild(dd);
    }
    body.appendChild(dl);
  }
  card.appendChild(body);

  const hint = document.createElement('div');
  hint.className = 'cavil-resolution-tip-hint';
  hint.textContent = 'Automatic decision — fix it from the row menu.';
  card.appendChild(hint);

  dom.appendChild(card);
}

export function showResolutionTooltip(anchor, info, options = {}) {
  return showFloatingTooltip(anchor, {
    ...options,
    interactive: false,
    hideDelay: options.hideDelay ?? 1000,
    placement: 'cursor',
    render: dom => render(dom, info)
  });
}

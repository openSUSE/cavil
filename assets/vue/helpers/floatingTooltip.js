// Generic floating tooltip: positioning, show/hide lifecycle, scroll/click/Escape dismissal, and the
// single-active-tooltip bookkeeping shared by the pattern tooltip and the resolution tooltip. Callers
// supply a `render(dom)` that fills the tooltip body (sync or async); everything else is handled here so
// the two tooltips never reimplement the same placement and teardown logic.
let activePersistentTooltip = null;
let activeTransientTooltip = null;

export function showFloatingTooltip(anchor, options = {}) {
  const render = options.render;
  if (typeof render !== 'function') return null;
  const persistent = options.persistent ?? false;
  const interactive = options.interactive ?? true;
  const hideDelay = options.hideDelay ?? 800;
  if (persistent && activePersistentTooltip) activePersistentTooltip.destroy();
  if (!persistent && activeTransientTooltip) activeTransientTooltip.destroy();

  const dom = document.createElement('div');
  dom.className = 'cavil-pattern-tip cavil-pattern-tip-floating';
  if (!interactive) dom.style.pointerEvents = 'none';
  document.body.appendChild(dom);

  let destroyTimer = null;
  let destroyed = false;
  let watchingDocument = false;
  let watchingScroll = false;
  let watchingCursor = false;
  // Last known pointer position, for the 'cursor' placement mode. Seeded from the triggering event so the
  // tooltip is placed correctly even before the first mousemove.
  let cursor = options.origin ? {x: options.origin.x, y: options.origin.y} : null;

  // Cursor-relative placement: sit just off the pointer (down-right by default) and flip to the other
  // side of the cursor near a viewport edge, so the tooltip stays fully readable but never covers the
  // line the pointer is on - the reader's eye is already at the cursor. Used for the resolution tooltip.
  const placeAtCursor = () => {
    const gap = 16;
    const w = dom.offsetWidth;
    const h = dom.offsetHeight;
    let left = cursor.x + gap;
    if (left + w > window.innerWidth - 8) left = cursor.x - gap - w;
    left = Math.min(Math.max(8, left), Math.max(8, window.innerWidth - w - 8));
    let top = cursor.y + gap;
    if (top + h > window.innerHeight - 8) top = cursor.y - gap - h;
    top = Math.min(Math.max(8, top), Math.max(8, window.innerHeight - h - 8));
    dom.style.top = `${top}px`;
    dom.style.left = `${left}px`;
  };

  // Corner placement: pin to the top-right of the anchor (e.g. the editor container), clamped to the
  // viewport. Used for the editor's persistent pattern tooltip so it stays put off to the side rather
  // than covering the line being edited.
  const placeAtCorner = () => {
    const rect = anchor.getBoundingClientRect();
    const margin = 8;
    const w = dom.offsetWidth;
    const h = dom.offsetHeight;
    let left = rect.right - w - margin;
    left = Math.min(Math.max(8, left), Math.max(8, window.innerWidth - w - 8));
    let top = rect.top + margin;
    top = Math.min(Math.max(8, top), Math.max(8, window.innerHeight - h - 8));
    dom.style.top = `${top}px`;
    dom.style.left = `${left}px`;
  };

  const place = () => {
    if (destroyed) return;
    if (options.placement === 'cursor' && cursor) return placeAtCursor();
    if (options.placement === 'anchor-corner') return placeAtCorner();
    const rect = anchor.getBoundingClientRect();
    const offsetLeft = options.offsetLeft ?? 96;
    const maxTop = window.innerHeight - dom.offsetHeight - 8;
    let top;
    if (options.placement === 'source-row' || options.placement === 'cursor') {
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
    stopWatchingCursor();
    destroyed = true;
    dom.remove();
    if (activePersistentTooltip?.destroy === destroy) activePersistentTooltip = null;
    if (activeTransientTooltip?.destroy === destroy) activeTransientTooltip = null;
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

  const onCursorMove = event => {
    cursor = {x: event.clientX, y: event.clientY};
    place();
  };

  function startWatchingCursor() {
    if (watchingCursor) return;
    watchingCursor = true;
    window.addEventListener('mousemove', onCursorMove, true);
  }

  function stopWatchingCursor() {
    if (!watchingCursor) return;
    watchingCursor = false;
    window.removeEventListener('mousemove', onCursorMove, true);
  }

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
  if (!persistent && options.placement === 'cursor') startWatchingCursor();

  const rendered = Promise.resolve(render(dom));
  requestAnimationFrame(() => {
    place();
    dom.style.visibility = 'visible';
  });
  rendered.then(place);

  // A closable tooltip gets a small pin bar with a close button, inserted at the top after the content
  // renders (the render step owns dom's innerHTML). Used for the editor's persistent pattern tooltip, so
  // it can be dismissed without clicking elsewhere.
  if (options.closable) {
    rendered.then(() => {
      if (destroyed) return;
      const bar = document.createElement('div');
      bar.className = 'cavil-pattern-tip-pinbar';
      if (options.closeLabel) {
        const label = document.createElement('span');
        label.className = 'cavil-pattern-tip-pinbar-label';
        label.textContent = options.closeLabel;
        bar.appendChild(label);
      }
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'cavil-pattern-tip-close';
      btn.setAttribute('aria-label', 'Close');
      btn.innerHTML = '<i class="fa-solid fa-xmark" aria-hidden="true"></i>';
      btn.addEventListener('click', event => {
        event.stopPropagation();
        destroy();
      });
      bar.appendChild(btn);
      dom.insertBefore(bar, dom.firstChild);
      place();
    });
  }

  const tooltip = {destroy, scheduleDestroy, cancelDestroy};
  if (persistent) {
    activePersistentTooltip = tooltip;
    setTimeout(startWatchingDocument, 0);
  } else {
    activeTransientTooltip = tooltip;
  }
  return tooltip;
}

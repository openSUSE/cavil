import {Popover} from 'bootstrap';

const tooltip = `
<a
  data-bs-html="true"
  data-bs-toggle="popover"
  data-bs-trigger="hover focus"
  data-bs-title="Error"
  data-bs-content="Error during report generation, please contact an administrator."
>
  <i class="fa-solid fa-circle-exclamation"></i>
</a>
`;

export function encodePath(path) {
  return path
    .split('/')
    .filter(part => part.length > 0)
    .map(part => encodeURIComponent(part))
    .join('/');
}

export function fileViewUrl(pkgId, path) {
  return `/reviews/file_view/${pkgId}/${encodePath(path)}`;
}

export function licenseLink(license) {
  let name = license.license;
  if (name === '') name = '*Pattern without license*';
  return `<a href='/licenses/${name}'>${name}</a>`;
}

export function packageLink(review) {
  const name = review.name;
  return `<a href='/search?q=${name}'>${name}</a>`;
}

// In-page navigation by default (the product listing); the report metadata opens a new tab so a reviewer
// keeps their place, matching the other report links, by passing {blank: true}
export function productLink(product, {blank = false} = {}) {
  const name = product.name;
  const attrs = blank ? " target='_blank' rel='noopener'" : '';
  return `<a href='/products/${encodeURIComponent(name)}'${attrs}>${name}</a>`;
}

export function reportLink(review) {
  const id = review.id;
  if (!review.imported_epoch) return progressLink(review, 'not yet imported');
  if (!review.unpacked_epoch) return progressLink(review, 'not yet unpacked');
  if (!review.indexed_epoch) return progressLink(review, 'not yet indexed');
  if (review.checksum) {
    return linkWithContext(
      `<a class="report-${id}" href="/reviews/details/${review.id}">${review.checksum}</a>`,
      review
    );
  }
  return progressLink(review, 'unpacked');
}

export function setupPopover() {
  const popoverTriggerList = document.querySelectorAll('[data-bs-toggle="popover"]');
  [...popoverTriggerList].map(popoverTriggerEl => new Popover(popoverTriggerEl));
}

export function setupPopoverDelayed() {
  setTimeout(setupPopover, 1);
}

// Lawyers triage by "has a review been written yet, and by whom", so one element swaps its glyph
// through three states. Deliberately no check mark anywhere: a review note carries findings, not a
// verdict, and the accept/reject decision is one click away.
const NOTE_STATES = {
  ai_review: ['fa-solid fa-robot', 'An AI-assisted review note applies to this report'],
  review: ['fa-solid fa-note-sticky', 'A review note applies to this report'],
  note: ['fa-regular fa-note-sticky', 'A note applies to this report, but no review note yet']
};

function notesLink(review) {
  const state = NOTE_STATES[review.relevant_note];
  if (!state) return '';
  const [icon, label] = state;
  const muted = review.relevant_note === 'note' ? '' : ' is-review';
  // No whitespace around the link: the gap is CSS, so the cell's text stays exactly the report name
  return `<a class="cavil-list-notes${muted}" href="/reviews/details/${review.id}#notes"
    title="${label}" aria-label="${label}"><i class="${icon}"></i></a>`;
}

function linkWithContext(html, review) {
  html = `${html}${notesLink(review)}`;

  const unresolved = review.unresolved_matches;
  if (unresolved !== 0) html = `${html} <div class="badge cavil-risk-unknown-badge">${unresolved}</div>`;

  const activeJobs = review.active_jobs ?? 0;
  const failedJobs = review.failed_jobs ?? 0;

  if (activeJobs === 0 && failedJobs === 0) return html;

  if (failedJobs > 0) {
    return `${html} ${tooltip}`;
  } else {
    return `${html} <i class="fa-solid fa-rotate fa-spin"></i>`;
  }
}

function progressLink(review, state) {
  return linkWithContext(`<a class="report-${review.id}" href="/reviews/details/${review.id}">${state}</a>`, review);
}

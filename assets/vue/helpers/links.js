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

export function productLink(product) {
  let name = product.name;
  return `<a href='/products/${name}' target='_blank' rel='noopener'>${name}</a>`;
}

export function spdxLicenseUrl(name) {
  return `https://spdx.org/licenses/${encodeURIComponent(name)}.html`;
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

function linkWithContext(html, review) {
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

import {Popover} from 'bootstrap';

const tooltip = `
<a
  data-bs-html="true"
  data-bs-toggle="popover"
  data-bs-trigger="hover focus"
  data-bs-title="Error"
  data-bs-content="Error during report generation, please constact an administrator."
>
  <i class="fas fa-exclamation-circle"></i>
</a>
`;

export function externalLink(review) {
  const link = review.external_link;

  if (link.substr(0, 4) === 'obs#') {
    return `<a href='https://build.opensuse.org/request/show/${link.substr(4)}' target='_blank'>${link}</a>`;
  }
  if (link.substr(0, 4) === 'ibs#') {
    return `<a href='https://build.suse.de/request/show/${link.substr(4)}' target='_blank'>${link}</a>`;
  }
  const sooMatch = link.match(/soo#([^!]+)!(\d+)/);
  if (sooMatch !== null) {
    return `<a href='https://src.opensuse.org/${sooMatch[1]}/pulls/${sooMatch[2]}' target='_blank'>${sooMatch[0]}</a>`;
  }
  const ssdMatch = link.match(/ssd#([^!]+)!(\d+)/);
  if (ssdMatch !== null) {
    return `<a href='https://src.suse.de/${ssdMatch[1]}/pulls/${ssdMatch[2]}' target='_blank'>${ssdMatch[0]}</a>`;
  }

  return link;
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
  return `<a href='/products/${name}'>${name}</a>`;
}

export function reportLink(review) {
  const id = review.id;
  if (!review.imported_epoch) return linkWithContext(`<i class="report-${id}">not yet imported</i>`, review);
  if (!review.unpacked_epoch) return linkWithContext(`<iclass="report-${id}">not yet unpacked</i>`, review);
  if (!review.indexed_epoch) return linkWithContext(`<i class="report-${id}">not yet indexed</i>`, review);
  if (review.checksum) {
    return linkWithContext(
      `<a class="report-${id}" href="/reviews/details/${review.id}">${review.checksum}</a>`,
      review
    );
  }
  return linkWithContext(`<a class="report-${id}" href="/reviews/details/${review.id}">unpacked</a>`, review);
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
  if (unresolved !== 0) html = `${html} <div class="badge text-bg-dark">${unresolved}</div>`;

  const activeJobs = review.active_jobs ?? 0;
  const failedJobs = review.failed_jobs ?? 0;

  if (activeJobs === 0 && failedJobs === 0) return html;

  if (failedJobs > 0) {
    return `${html} ${tooltip}`;
  } else {
    return `${html} <i class="fas fa-sync fa-spin"></i>`;
  }
}

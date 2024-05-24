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
  if (!review.imported_epoch) return linkWithContext('<i>not yet imported</i>', review);
  if (!review.unpacked_epoch) return linkWithContext('<i>not yet unpacked</i>', review);
  if (!review.indexed_epoch) return linkWithContext('<i>not yet indexed</i>', review);
  if (review.checksum) {
    return linkWithContext(`<a href='/reviews/details/${review.id}'/>${review.checksum}</a>`, review);
  }
  return linkWithContext(`<a href='/reviews/details/${review.id}'/>unpacked</a>`, review);
}

export function setupPopover() {
  const popoverTriggerList = document.querySelectorAll('[data-bs-toggle="popover"]');
  [...popoverTriggerList].map(popoverTriggerEl => new Popover(popoverTriggerEl));
}

function linkWithContext(html, review) {
  const activeJobs = review.active_jobs ?? 0;
  const failedJobs = review.failed_jobs ?? 0;

  if (activeJobs === 0 && failedJobs === 0) return html;

  if (failedJobs > 0) {
    return `${html} ${tooltip}`;
  } else {
    return `${html} <i class="fas fa-sync fa-spin"></i>`;
  }
}

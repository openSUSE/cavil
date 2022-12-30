export function externalLink(review) {
  const link = review.external_link;
  const prio = `(${review.priority})`;

  if (link.substr(0, 4) === 'obs#') {
    return `${prio} <a href='https://build.opensuse.org/request/show/${link.substr(4)}' target='_blank'>${link}</a>`;
  }
  if (link.substr(0, 4) === 'ibs#') {
    return `${prio} <a href='https://build.suse.de/request/show/${link.substr(4)}' target='_blank'>${link}</a>`;
  }

  return `${prio} ${link}`;
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
  if (!review.imported_epoch) return '<i>not yet imported</i>';
  if (!review.unpacked_epoch) return '<i>not yet unpacked</i>';
  if (!review.indexed_epoch) return '<i>not yet indexed</i>';
  if (review.checksum) return `<a href='/reviews/details/${review.id}'/>${review.checksum}</a>`;
  return `<a href='/reviews/details/${review.id}'/>unpacked</a>`;
}

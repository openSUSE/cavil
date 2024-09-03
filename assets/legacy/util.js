export function formatLink(row) {
  const link = row.external_link;
  const prio = `(${row.priority}) `;
  if (link.substr(0, 4) == 'obs#') {
    return `${prio}<a href='https://build.opensuse.org/request/show/${link.substr(4)}' target='_blank'>${link}</a>`;
  }
  if (link.substr(0, 4) == 'ibs#') {
    return `${prio}<a href='https://build.suse.de/request/show/${link.substr(4)}' target='_blank'>${link}</a>`;
  }
  return prio + link;
}

export function moveSelector() {
  $('.current-selector').removeClass('current-selector');
  let cs;
  window.cavil.fireIndex++;
  $.each(window.cavil.fires, function (index) {
    if (index == window.cavil.fireIndex) {
      if ($(this).hasClass('fa-fire')) {
        cs = $(this).parent('a');
      } else {
        window.cavil.fireIndex++;
      }
    }
  });
  if (!cs) {
    return;
  }
  cs.addClass('current-selector');
  const offset = cs.offset();
  offset.top -= 50;
  $('html, body').animate({
    scrollTop: offset.top
  });
}

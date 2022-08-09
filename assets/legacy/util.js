export function createLicense() {
  const name = $('#name').val();
  $.ajax({
    type: 'POST',
    url: '/licenses',
    data: {name},
    success(data) {
      window.location = data;
    }
  });
  return false;
}

export function ignoreLine(link) {
  const hash = link.data('hash');
  $.post(`/reviews/add_ignore?hash=${hash}&package=${link.data('packname')}`);
  $(`.hash-${hash}`).removeClass('risk-9');
  const cs = $(`.hash-${hash} .fa-fire`);
  if (link.hasClass('current-selector')) {
    moveSelector();
  }
  cs.removeClass('fa-fire');
  return false;
}

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

export function snippetNonLicense(link) {
  const hash = link.data('hash');
  const id = link.data('snippet-id');
  $.post(`/snippet/decision/${id}?mark-non-license=1`);
  $(`.hash-${hash}`).removeClass('risk-9');
  const cs = $(`.hash-${hash} .fa-fire`);
  if (link.hasClass('current-selector')) {
    moveSelector();
  }
  cs.removeClass('fa-fire');
  return false;
}

export function snippetSwitcher() {
  $('.license').click(function () {
    if ($(this).hasClass('license-1')) {
      $(this).removeClass('license-1').addClass('license-0');
    } else {
      $(this).removeClass('license-0').addClass('license-1');
    }
    const name = `#good_${$(this).data('snippet')}`;
    const elem = $(name);
    elem.val(1 - elem.val());
  });
}

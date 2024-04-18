import {ignoreLine, moveSelector} from './util.js';
import Chart from 'chart.js';

export function setupReviewDetails(url) {
  $('#reindex_button').prop('disabled', false);

  getUntilSuccess(url, data => {
    $('#details').html(data);

    drawLicenseChart();

    /*
     * Make sure not to bind the event on every element - large
     * packages have a lot of them and the performance goes down hill
     */
    $('#details').on('click', '.expand-pre', expandSources);
    $('#details').on('click', '.collapse-pre', collapseSources);

    $('#details').on('click', '.file-link', function () {
      let target = $(this).data('file');
      target = $(`#expand-link-${target}`);
      target.parents('.file-container').removeClass('d-none');
      fetchSource(target);
      return true;
    });

    window.cavil.fires = $('.fa-fire');
    window.cavil.fireIndex = -1;

    $('.fa-fire').click(function () {
      const link = $(this).parents('a');
      ignoreLine(link);
      return false;
    });

    $('#details').on('click', '.add-to-glob', function () {
      $('#glob-to-add').val($(this).data('name'));
      $('#globModal').modal({focus: true, keyboard: true, show: true});
      return false;
    });

    $('#details').on('click', '.extend-action', extendMatch);

    $('#globAddButton').click(() => {
      const glob = $('#glob-to-add').val();
      const data = {glob, package: $('#globModal').data('package')};
      $.post($('#globModal').data('url'), data, () => {
        $('#globModal').hide();
        location.reload();
      });
    });

    $('.dropdown').hover(
      function () {
        $(this).find('.dropdown-menu').stop(true, true).delay(200).fadeIn(100);
      },
      function () {
        $(this).find('.dropdown-menu').stop(true, true).delay(200).fadeOut(100);
      }
    );
  });

  $('#create-pattern-and-continue').click(createPatternAndContinue);
  $('#create-pattern-and-reindex').click(createPatternAndReindex);

  $('#reindex_button').click(e => {
    e.preventDefault();
    $('#reindex_button').prop('disabled', true);
    triggerReindex();
  });

  $('#only-match-local').change(() => {
    $('input[name=packname]').prop('disabled', !$('#only-match-local').prop('checked'));
  });
}

function collapseSources() {
  $(this).parents('.file-container').find('.source').hide();
  $(this).addClass('expand-pre').removeClass('collapse-pre');
  return false;
}

function createPattern(success) {
  const dia = $('#new-license-pattern');
  const data = {license: dia.find('select[name=license]').val()};
  data.pattern = dia.find('textarea').val();
  $.each(['patent', 'trademark'], (i, val) => {
    if (dia.find(`input[name=${val}]`).prop('checked')) {
      data[val] = 1;
    }
  });

  if (dia.find('#only-match-local').prop('checked')) {
    data.packname = dia.find('input[name=packname]').val();
  }

  $.ajax({
    type: 'POST',
    url: dia.data('create-url'),
    data,
    success,
    error(jqXHR, exception) {
      alert(formatAjaxError(jqXHR, exception));
    }
  });
}

function createPatternAndContinue(e) {
  $('#new-license-pattern').modal('hide');
  const link = $('.current-selector');
  const hash = link.data('hash');
  e.preventDefault();
  createPattern(() => {
    $(`.hash-${hash}`).removeClass('risk-9');
    const cs = $(`.hash-${hash} .fa-fire`);
    if (link.hasClass('current-selector')) {
      moveSelector();
    }
    cs.removeClass('fa-fire');
  });
}

function createPatternAndReindex(e) {
  e.preventDefault();
  createPattern(triggerReindex);
}

function drawLicenseChart() {
  const ctx = document.getElementById('license-chart');
  new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: $('#chart-data').data('licenses'),
      datasets: [
        {
          label: '# of Files',
          data: $('#chart-data').data('num-files'),
          backgroundColor: $('#chart-data').data('colours')
        }
      ]
    },
    options: {
      legend: {position: 'right'}
    }
  });
}

function extendMatch() {
  const actions = $(this).parents('.actions');
  const target = $(this).parents('.file-container');
  const source = target.find('.source');
  let start = Number(actions.data('start'));
  let end = actions.data('end');
  if ($(this).hasClass('extend-one-line-above')) {
    start -= 1;
  } else if ($(this).hasClass('extend-one-line-below')) {
    end += 1;
  } else if ($(this).hasClass('extend-top')) {
    start = 1;
  } else if ($(this).hasClass('extend-bottom')) {
    // This is faking
    end += 3000;
  } else if ($(this).hasClass('extend-match-above')) {
    start = actions.data('prev-match');
  } else if ($(this).hasClass('extend-match-below')) {
    end = actions.data('next-match');
  }
  $.get(
    `/reviews/fetch_source/${source.data('file-id')}`,
    {
      start,
      end
    },
    data => {
      source.html(data);
      source.show();
    }
  );
  return false;
}

function expandSources() {
  fetchSource($(this));
  $(this).removeClass('expand-pre').addClass('collapse-pre');
  return false;
}

function fetchSource(target) {
  const source = target.parents('.file-container').find('.source');
  $.get(`/reviews/fetch_source/${source.data('file-id')}`, {}, data => {
    source.html(data);
    source.show();
  });
}

function formatAjaxError(jqXHR, exception) {
  if (jqXHR.status === 0) {
    return 'Not connected. Please check your network connection.';
  } else if (jqXHR.status == 404) {
    return 'Page not found (404).';
  } else if (jqXHR.status == 500) {
    return 'Server error (500).';
  } else if (exception === 'parsererror') {
    return 'Could not parse response.';
  } else if (exception === 'timeout') {
    return 'Timeout error.';
  } else if (exception === 'abort') {
    return 'Ajax request aborted.';
  }
  return `Error: ${jqXHR.responseText}`;
}

function getUntilSuccess(url, cb) {
  $.ajax({
    type: 'GET',
    url,
    success: cb,
    error() {
      setTimeout(() => {
        getUntilSuccess(url, cb);
      }, 2000);
    }
  });
}

function triggerReindex() {
  $.ajax({
    type: 'POST',
    url: $('form#reindex-form').data('url'),
    cache: false,
    success() {
      $('#reindex_button').addClass('btn-success');
      window.location.reload();
    },
    error() {
      $('#reindex_button').addClass('btn-danger');
    }
  });
}

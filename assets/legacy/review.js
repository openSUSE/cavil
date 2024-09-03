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

    $('#details').on('click', '.extend-action', extendMatch);

    $('.dropdown').hover(
      function () {
        $(this).find('.dropdown-menu').stop(true, true).delay(200).fadeIn(100);
      },
      function () {
        $(this).find('.dropdown-menu').stop(true, true).delay(200).fadeOut(100);
      }
    );
  });

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

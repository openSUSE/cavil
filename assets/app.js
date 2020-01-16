
var myCodeMirror;
var fires;
var fire_index;

function formatLink (row) {
  var link = row['external_link'];
  var prio = "(" + row['priority'] + ") ";
  if (link.substr(0, 4) == 'obs#') {
    return prio + "<a href='https://build.opensuse.org/request/show/" + link.substr(4) + "' target='_blank'>" + link + '</a>';
  }
  if (link.substr(0, 4) == 'ibs#') {
    return prio + "<a href='https://build.suse.de/request/show/" + link.substr(4) + "' target='_blank'>" + link + '</a>';
  }
  return prio + link;
}

function backToTop () {
  $(document).ready(function () {
    $(window).scroll(function () {
      if ($(this).scrollTop() > 50) {
        $('#back-to-top').fadeIn();
      } else {
        $('#back-to-top').fadeOut();
      }
    });
    $('#back-to-top').click(function () {
      $('#back-to-top').tooltip('hide');
      $('body, html').animate({scrollTop: 0}, 800);
      return false;
    });
    $('#back-to-top').tooltip('show');
  });
}

function setupProductTable() {
  var dt = $('#reviews').DataTable({
    processing: true,
    serverSide: false,
    ajax: $('#reviews').data('script'),
    columns: [
      {data: 'name'},
      {data: 'state'},
      {data: 'checksum'}
    ],
    columnDefs: [
      {
        targets: "package",
        render: function (data, type, row) {
          if (type === 'display') {
            return "<a href='/search?q=" + data + "' target='_blank'>" + data + '</a>';
          }
          else {
            return data;
          }
        }
      },
      {
        targets: "report",
        render: function (data, type, row) {
          if (row['checksum']) {
            return "<a href='/reviews/details/" + row['id'] + "' target='_blank'>" + row['checksum'] + "</a>";
          }
          else {
            return "<a href='/reviews/details/" + row['id'] + "' target='_blank'>not available</a>";
          }
        }
      }
    ],
    order: [[0, 'asc']]
  });
}

function setupRecentTable() {
    var dt = $('#reviews').DataTable({
      processing: true,
      serverSide: false,
      ajax: $('#reviews').data('script'),
      columns: [
        {data: 'external_link'},
        {data: 'created_epoch'},
        {data: 'reviewed_epoch'},
        {data: 'name'},
        {data: 'state'},
        {data: 'result'},
        {data: 'login'},
        {data: 'checksum'}
      ],
      columnDefs: [
        {
          targets: "link",
          render: function (data, type, row) {
            return formatLink(row);
          }
        },
        {
          targets: "created",
          render: function (data, type, row) {
            if (type === 'display') {
        	    return '<span title="' + row['created'] + '">' + jQuery.timeago(new Date(data * 1000)) + '</span>';
            }
            else {
              return data;
            }
          }
        },
        {
          targets: "reviewed",
          render: function (data, type, row) {
            if (type === 'display') {
              return '<span title="' + row['reviewed'] + '">' + jQuery.timeago(new Date(data * 1000)) + '</span>';
            }
            else {
              return data;
            }
          }
        },
        {
          targets: "package",
          render: function (data, type, row) {
            if (type === 'display') {
              return "<a href='/search?q=" + data + "'>" + data + '</a>';
            }
            else {
              return data;
            }
          }
        },
        {
          targets: "report",
          render: function (data, type, row) {
            if (!row['imported']) {
              return "<i>not yet imported</i>";
            }
            else if (!row['unpacked']) {
              return "<i>not yet unpacked</i>";
            }
  	        else if (!row['indexed']) {
              return "<i>not yet indexed</i>";
            }
  	        else if (row['checksum']) {
  	          return "<a href='/reviews/details/" + row['id'] + "'/>" + row['checksum'] + "</a>";
            }
  	        else {
  	          return "<a href='/reviews/details/" + row['id'] + "'/>unpacked</a>";
            }
          }
        }
      ],
      order: [[2, 'desc']]
    });
}

function setupReviewTable(is_admin) {

  var columns = [];
  if ($('table#reviews thead th.link').length) {
    columns.push({
      data: "external_link",
      class: "middle-align"
    });
  }

  columns.push({
    data: "created_epoch",
    class: "middle-align"
  });
  if ($('table#reviews thead th.package').length) {
    columns.push({
      data: "name",
      class: "middle-align"
    });
  }
  var order = [0, 'asc'];

  if ($('table#reviews thead th.state').length) {
    columns.push({ data: "state" });
    order = [0, 'desc'];
  }

  if ($('table#reviews thead th.result').length) {
    columns.push({ data: "result" });
  }

  if ($('table#reviews thead th.login').length) {
    columns.push({ data: "login" });
  }

  if ($('table#reviews thead th.products').length) {
    columns.push({
      data: "products",
      class: "middle-align"
    });
  }

  columns.push({
    data: "checksum",
    class: "middle-align"
  });

  var dt = $('#reviews').DataTable( {
    processing: true,
    serverSide: false,
    ajax: $('#reviews').data('script'),
    columns: columns,
    columnDefs: [
      {
        targets: "link",
        render: function (data, type, row) {
          if (type === 'display' && data) {
            return formatLink(row);
          }
          else {
            return (10 - row['priority']) + data;
          }
        }
      },
      {
        targets: "created",
        render: function (data, type, row) {
          if (type === 'display') {
	          return '<span title="' + row['created'] + '">' + jQuery.timeago(new Date(data * 1000)) + '</span>';
          }
          else {
            return data;
          }
        }
      },
      {
        targets: "package",
        render: function (data, type, row) {
          if (type === 'display') {
            return "<a href='/search?q=" + data + "'>" + data + '</a>';
          }
          else {
            return data;
          }
        }
      },
      {
        targets: "state",
        render: function (data, type, row) {
          return data;
        }
      },
      {
        targets: "result",
        render: function (data, type, row) {
          return data;
        }
      },
      {
        targets: "report",
        render: function (data, type, row) {
          if (!row['imported']) {
            return "<i>not yet imported</i>";
          }
          else if (!row['unpacked']) {
            return "<i>not yet unpacked</i>";
          }
	        else if (!row['indexed']) {
            return "<i>not yet indexed</i>";
          }
	        else if (row['checksum']) {
	          return "<a href='/reviews/details/" + row['id'] + "'/>" + row['checksum'] + "</a>";
          }
	        else {
	          return "<a href='/reviews/details/" + row['id'] + "'/>unpacked</a>";
          }
        }
      }
    ],
    "order": [order]
  } );

  // Array to track the ids of the details displayed rows
  var detailRows = [];

  var reportUrl = $('#reviews').data('report-url');

  $('#reviews tbody').on( 'click', 'tr td span.details-control', function () {
    var tr = $(this).closest('tr');
    var row = dt.row( tr );
    var idx = $.inArray( tr.attr('id'), detailRows );

    if ( row.child.isShown() ) {
      tr.removeClass( 'details' );
      $(this).removeClass('fa-minus-square').addClass('fa-plus-square');

      row.child.hide();

      // Remove from the 'open' array
      detailRows.splice( idx, 1 );
    }
    else {
      tr.addClass( 'details' );
      $(this).addClass('fa-minus-square').removeClass('fa-plus-square');

      $.ajax({url: reportUrl,
	      data: { id: row.data().id },
	      success: function(data) { row.child( data ).show(); }
	     });

      // Add to the 'open' array
      if ( idx === -1 ) {
        detailRows.push( tr.attr('id') );
      }
    }
  } );

  // On each draw, loop over the `detailRows` array and show any child rows
  dt.on( 'draw', function () {
    $.each(detailRows, function ( i, id ) {
      $('#'+id+' td.details-control').trigger( 'click' );
    });
  });

  dt.on('draw',function () {
    $('.dataTables_empty').html('<i class="fas fa-check-circle" '
      + 'style="color:Green"></i> All reviews are done!');
  });
}

function ignoreLine(link) {
  var hash = link.data('hash');
  $.post('/reviews/add_ignore?hash=' + hash + '&package=' + link.data('packname'));
  $('.hash-' + hash).removeClass('risk-9');
  var cs = $('.hash-' + hash + ' .fa-fire');
  if (link.hasClass('current-selector')) {
    moveSelector();
  }
  cs.removeClass('fa-fire');
  return false;
}

function snippetNonLicense(link) {
  var hash = link.data('hash');
  var id = link.data('snippet-id');
  $.post('/snippet/decision/' + id +'?mark-non-license=1');
  $('.hash-' + hash).removeClass('risk-9');
  var cs = $('.hash-' + hash + ' .fa-fire');
  if (link.hasClass('current-selector')) {
    moveSelector();
  }
  cs.removeClass('fa-fire');
  return false;
}

function createPatternDialog() {
  var link = $('.current-selector');
  var current_snippet = link.parents('tr').find('.code').data('snippet');
  var div = link.parents('.source');
  var text = '';
  $.each(div.find('.code'), function(index, element) {
    element = $(element);
    if (element.data('snippet') == current_snippet) {
      text += element.text();
      text += "\n";
    }
  });
  $('#only-match-local').prop('checked', false);
  $('input[name=packname]').prop('disabled', true);

  var dia = $('#new-license-pattern');
  dia.find('textarea').val(text);
  dia.modal();
}

function formatAjaxError(jqXHR, exception) {
  if (jqXHR.status === 0) {
      return ('Not connected. Please check your network connection.');
  } else if (jqXHR.status == 404) {
      return ('Page not found (404).');
  } else if (jqXHR.status == 500) {
      return ('Server error (500).');
  } else if (exception === 'parsererror') {
      return ('Could not parse response.');
  } else if (exception === 'timeout') {
      return ('Timeout error.');
  } else if (exception === 'abort') {
      return ('Ajax request aborted.');
  } else {
      return ('Error: ' + jqXHR.responseText);
  }
}

function createPattern(success) {
  var dia = $('#new-license-pattern');
  var data = { license: dia.find("select[name=license]").val() };
  data['pattern'] = dia.find('textarea').val();
  $.each(['opinion', 'patent', 'trademark'], function(i, val) {
    if (dia.find('input[name=' + val + ']').prop('checked')) {
      data[val] = 1;
    }
  });

  if (dia.find('#only-match-local').prop('checked')) {
    data['packname'] = dia.find('input[name=packname]').val();
  }

  $.ajax({
    type:    'POST',
    url:     dia.data('create-url'),
    data:    data,
    success: success,
    error:   function (jqXHR, exception) {
      alert(formatAjaxError(jqXHR, exception));
    }
  });
}

function createPatternAndReindex(e) {
  e.preventDefault();
  createPattern(triggerReindex);
}

function createPatternAndContinue(e) {
  $('#new-license-pattern').modal('hide');
  var link = $('.current-selector');
  var hash = link.data('hash');
  e.preventDefault();
  createPattern(function() {
    $('.hash-' + hash).removeClass('risk-9');
    var cs = $('.hash-' + hash + ' .fa-fire');
    if (link.hasClass('current-selector')) {
      moveSelector();
    }
    cs.removeClass('fa-fire');
  });
}

function getUntilSuccess(url, cb) {
  $.ajax({
    type: 'GET',
    url: url,
    success: cb,
    error: function() {
      setTimeout(function () {
        getUntilSuccess(url, cb);
      }, 2000);
    }
  });
}

function drawLicenseChart() {
  var ctx = document.getElementById("license-chart");
  var myChart = new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: $('#chart-data').data('licenses'),
      datasets: [{
        label: '# of Files',
        data: $('#chart-data').data('num-files'),
        backgroundColor: $('#chart-data').data('colours')
      }]
    },
    options: {
      legend: { position: 'right' }
    }
  });
}

function fetchSource(target) {
  var source = target.parents(".file-container").find('.source');
  $.get('/reviews/fetch_source/' + target.data('file-id'), {},
	   function(data) {
       source.html(data);
       source.show();
     });
}

function expandSources() {
  fetchSource($(this));
  $(this).removeClass('expand-pre').addClass('collapse-pre');
  return false;
}

function collapseSources() {
  $(this).parents(".file-container").find('.source').hide();
  $(this).addClass('expand-pre').removeClass('collapse-pre');
  return false;
}

function extendOneLineAbove() {
  console.log($(this));
  console.log($(this).parents('.actions').data());
  return false;
}

function setupReviewDetails(url) {

  $('#reindex_button').prop('disabled', false);
  Mousetrap.bind('?', function() { $('#help').modal('show') });
  Mousetrap.bind('R', function() { $('#reindex_button').click() });
  Mousetrap.bind('F', function() {
    window.location.href = $('#full_report').attr('href');
  });

  getUntilSuccess(url, function(data) {
    $('#details').html(data);
    document.title = $('h1').text();

    drawLicenseChart();

    // make sure not to bind the event on every element - large
    // packages have a lot of them and the performance goes down hill
    $('#details').on('click', '.expand-pre', expandSources);
    $('#details').on('click', '.collapse-pre', collapseSources);

    $('#details').on('click', '.file-link', function() {
      var target = $(this).data('file');
      target = $('#expand-link-' + target);
      target.parents('.file-container').removeClass('d-none');
      fetchSource(target);
      return true;
    });

    fires = $('.fa-fire');
    fire_index = -1;

    $('.fa-fire').click(function() {
      var link = $(this).parents('a');
      ignoreLine(link);
      return false;
    });

    Mousetrap.bind('n', moveSelector);
    Mousetrap.bind('i', function() { ignoreLine($('.current-selector')); });
    Mousetrap.bind('c', createPatternDialog);

    $('#details').on('click', '.add-to-glob', function() {
      $('#glob-to-add').val($(this).data('name'));
      $('#globModal').modal({'focus': true, 'keyboard': true, 'show': true});
      return false;
    });

    $('#details').on('click', '.extend-one-line-above', extendOneLineAbove);
    $('#details').on('click', '.extend-match-above', function() { return false});
    $('#details').on('click', '.extend-top', function() { return false});
    $('#details').on('click', '.extend-match-below', function() { return false});
    $('#details').on('click', '.extend-bottom', function() { return false});
    $('#details').on('click', '.extend-one-line-below', function() { return false});

    $('#globAddButton').click(function() {
      var glob = $('#glob-to-add').val();
      var data = { 'glob': glob,
                   'package': $('#globModal').data('package')
                 };
      $.post($('#globModal').data('url'), data, function() {
        $('#globModal').hide();
        location.reload();
      });
    });

    $('.dropdown').hover(
      function() {
        $(this).find('.dropdown-menu').stop(true, true).delay(200).fadeIn(100);
      }, function() {
        $(this).find('.dropdown-menu').stop(true, true).delay(200).fadeOut(100);
      });
  });

  $('#create-pattern-and-continue').click(createPatternAndContinue);
  $('#create-pattern-and-reindex').click(createPatternAndReindex);

  $('#reindex_button').click(function(e) {
    e.preventDefault();
    $('#reindex_button').prop('disabled', true);
    triggerReindex();
  });

  $('#only-match-local').change(function() {
    $('input[name=packname]').prop('disabled', !$('#only-match-local').prop('checked'));
  });

}

function triggerReindex() {
  $.ajax({
    type:    'POST',
    url:     $('form#reindex-form').data('url'),
    cache:   false,
    success: function() {
      $('#reindex_button').addClass('btn-success');
      window.location.reload();
    },
    error:   function() { $('#reindex_button').addClass('btn-danger'); }
  });
}

function moveSelector() {
  $('.current-selector').removeClass('current-selector');
  var cs;
  fire_index++;
  $.each(fires, function(index, element) {
    if (index == fire_index) {
      if ($(this).hasClass('fa-fire')) {
	      cs = $(this).parent('a');
	      return;
      } else {
	      fire_index++;
      }
    }
  });
  if (!cs) {
    return;
  }
  cs.addClass('current-selector');
  var offset = cs.offset();
  offset.top -= 50;
  $('html, body').animate({
    scrollTop: offset.top
  });
}

function setupCodeMirror() {
  myCodeMirror = CodeMirror.fromTextArea(document.getElementById("file"), { theme: 'neo' });
}

function setupCreatePattern() {
  $('#create-pattern').on('click', function(e) {
    e.preventDefault();
    var text = "";
    if (myCodeMirror) {
      text = myCodeMirror.getSelection();
      if (!text.length) {
	      text = myCodeMirror.getValue();
      }
    } else if (window.getSelection) {
      $('.linenumber').hide();
      text = window.getSelection().toString();
    } else if (document.selection && document.selection.type != "Control") {
      text = document.selection.createRange().text;
    }
    var url = $(this).attr('href');
    var csrfToken = $('meta[name=csrf-token]').attr('content');
    var csrfParam =  $('meta[name=csrf-param]').attr('content');
    var form = $('<form method="post" action="' + url + '"></form>');
    var metadataInput = '<input name="' + csrfParam + '" value="' + csrfToken + '" type="hidden" />';
    metadataInput += '<input name="packname" value="' + $(this).data('packname') + '"/>';
    metadataInput += '<input name="license-name" value="' + $(this).data('license-name') + '"/>';
    var textarea = $('<textarea name="pattern"/>');
    textarea.val(text);
    form.hide().append(metadataInput).append(textarea).appendTo('body');
    form.submit();
    return false;
  });
}

function createLicense() {
  var name = $('#name').val();
  $.ajax({
    type: "POST",
    url: '/licenses',
    data: { name: name },
    success: function(data) { window.location = data; }
  });
  return false;
}

function fromNow() {
  $('.from-now').each(function () {
    var date = $(this);
    date.text(jQuery.timeago(new Date(date.text() * 1000)));
  });
 }

function snippetSwitcher() {
  $('.license').click(function() {
    if ($(this).hasClass('license-1')) {
      $(this).removeClass('license-1').addClass('license-0');
    } else {
      $(this).removeClass('license-0').addClass('license-1');
    }
    var name = '#good_' + $(this).data('snippet');
    var elem = $(name);
    elem.val(1 - elem.val());
  });
}

export function setupReindex() {
  $('#reindex_button').prop('disabled', false);

  $('#reindex_button').click(e => {
    e.preventDefault();
    $('#reindex_button').prop('disabled', true);
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
  });
}

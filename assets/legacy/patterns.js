export function setupCreatePattern() {
  $('#create-pattern').on('click', function (e) {
    e.preventDefault();
    let text = '';
    if (window.legacy.myCodeMirror) {
      text = window.legacy.myCodeMirror.getSelection();
      if (!text.length) {
        text = window.legacy.myCodeMirror.getValue();
      }
    } else if (window.getSelection) {
      $('.linenumber').hide();
      text = window.getSelection().toString();
    } else if (document.selection && document.selection.type != 'Control') {
      text = document.selection.createRange().text;
    }
    const url = $(this).attr('href');
    const csrfToken = $('meta[name=csrf-token]').attr('content');
    const csrfParam = $('meta[name=csrf-param]').attr('content');
    const form = $(`<form method="post" action="${url}"></form>`);
    let metadataInput = `<input name="${csrfParam}" value="${csrfToken}" type="hidden" />`;
    metadataInput += `<input name="packname" value="${$(this).data('packname')}"/>`;
    metadataInput += `<input name="license-name" value="${$(this).data('license-name')}"/>`;
    const textarea = $('<textarea name="pattern"/>');
    textarea.val(text);
    form.hide().append(metadataInput).append(textarea).appendTo('body');
    form.submit();
    return false;
  });
}

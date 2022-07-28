export function fromNow() {
  $('.from-now').each(function () {
    const date = $(this);
    date.text($.timeago(new Date(date.text() * 1000)));
  });
}

export function backToTop() {
  $(document).ready(() => {
    $(window).scroll(function () {
      if ($(this).scrollTop() > 50) {
        $('#back-to-top').fadeIn();
      } else {
        $('#back-to-top').fadeOut();
      }
    });
    $('#back-to-top').click(() => {
      $('body, html').animate({scrollTop: 0}, 800);
      return false;
    });
  });
}

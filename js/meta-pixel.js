/* XOXO Pastry — Meta (Facebook/Instagram) Pixel.
   Meta's standard base code, moved out of an inline <script> because the CSP
   forbids inline scripts. It loads fbevents.js async from connect.facebook.net
   and reports a PageView on every page that includes this file. */
(function () {
  'use strict';

  var PIXEL_ID = '1485503546755774';

  // Only the live site reports; local previews (localhost, file://) stay out of the stats.
  if (!/(^|\.)xoxopastry\.com$/.test(location.hostname)) return;

  !function (f, b, e, v, n, t, s) {
    if (f.fbq) return; n = f.fbq = function () {
      n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments);
    };
    if (!f._fbq) f._fbq = n; n.push = n; n.loaded = !0; n.version = '2.0';
    n.queue = []; t = b.createElement(e); t.async = !0;
    t.src = v; s = b.getElementsByTagName(e)[0];
    s.parentNode.insertBefore(t, s);
  }(window, document, 'script', 'https://connect.facebook.net/en_US/fbevents.js');

  fbq('init', PIXEL_ID);
  fbq('track', 'PageView');
})();

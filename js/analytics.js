/* XOXO Pastry — Google tag (GA4 + Google Ads).
   The usual inline snippet, kept in its own file; gtag.js itself is loaded
   async from googletagmanager.com right before this file.
   The Google Ads purchase conversion is a URL rule on /thank-you (page load),
   so nothing here has to fire it — this only configures the tag and reports
   contact clicks (WhatsApp / SMS / Instagram) as GA4 events. */
window.dataLayer = window.dataLayer || [];
function gtag() { window.dataLayer.push(arguments); }

(function () {
  'use strict';

  var TAG_ID = 'G-3TVH94LNMW';

  // Only the live site reports; local previews (localhost, file://) stay out of the stats.
  if (!/(^|\.)xoxopastry\.com$/.test(location.hostname)) return;

  gtag('js', new Date());
  gtag('config', TAG_ID);

  function contactMethod(href) {
    if (href.indexOf('https://wa.me/') === 0) return 'whatsapp';
    if (href.indexOf('sms:') === 0 || href.indexOf('tel:') === 0) return 'sms';
    if (href.indexOf('instagram.com') !== -1) return 'instagram';
    return null;
  }

  document.addEventListener('click', function (event) {
    var link = event.target.closest && event.target.closest('a[href]');
    if (!link) return;
    var method = contactMethod(link.getAttribute('href'));
    if (method) gtag('event', 'contact', { method: method });
  });
})();

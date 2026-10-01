/* XOXO Pastry — /thank-you page.
   order-form.js stores {order_number, deposit_due} in sessionStorage right
   before redirecting here. Without it (storage blocked, page opened directly)
   the generic copy already in the HTML stays as-is. */
(function () {
  'use strict';

  var WHATSAPP_URL = 'https://wa.me/19167799058';

  function money(n) {
    return n % 1 === 0 ? String(n) : n.toFixed(2);
  }

  var order = null;
  try {
    order = JSON.parse(sessionStorage.getItem('xoxo_last_order') || 'null');
  } catch (e) { order = null; }
  if (!order || !order.order_number) return;

  var num = String(order.order_number);
  var deposit = Number(order.deposit_due) || 0;
  var dep = '$' + money(deposit);

  document.getElementById('ty-title').textContent = 'Order #' + num + ' received!';
  document.getElementById('ty-amount').textContent = dep;
  document.getElementById('ty-amount-line').hidden = false;
  document.getElementById('ty-num').textContent = num;

  var msg = 'Hi! Order #' + num + ' — sending the ' + dep +
    ' deposit now. Here is my payment screenshot:';
  document.getElementById('ty-wa').href = WHATSAPP_URL + '?text=' + encodeURIComponent(msg);

  // GA4 purchase, once per order (a reload of this page must not count twice).
  if (typeof gtag === 'function' && !order.reported) {
    gtag('event', 'purchase', {
      transaction_id: 'xoxo-' + num,
      value: Math.round(deposit / 0.2 * 100) / 100,
      currency: 'USD'
    });
    order.reported = true;
    try { sessionStorage.setItem('xoxo_last_order', JSON.stringify(order)); } catch (e) { /* ignore */ }
  }
})();

/* XOXO Pastry — public order form.
   Fetches the catalog from Supabase, renders the items repeater,
   validates client-side and submits through the place_order RPC.
   Prices shown here are estimates; the server resolves real prices. */
(function () {
  'use strict';

  const WHATSAPP_URL = 'https://wa.me/19167799058';
  const MAX_ROWS = 10;
  const PHONE_RE = /^[0-9+() .\-]{7,24}$/;
  const NETWORK_MSG = 'We could not send your order. Please try again, or';
  const RATE_MSG = 'Looks like several orders came from this number today.' +
    ' To be safe,';
  const MENU_CHANGED_MSG = 'Our menu just changed — please reload the page and try again.';

  const els = {};
  let products = [];
  let rowSeq = 0;
  let sending = false;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  /* ---------- bootstrap ---------- */

  function init() {
    const card = document.querySelector('.oform');
    if (!card) return;

    els.loading = document.getElementById('oform-loading');
    els.fallback = document.getElementById('oform-fallback');
    els.success = document.getElementById('oform-success');
    els.successTitle = document.getElementById('oform-success-title');
    els.successText = document.getElementById('oform-success-text');
    els.form = document.getElementById('order-form');
    els.rows = document.getElementById('oform-rows');
    els.add = document.getElementById('oform-add');
    els.rowTemplate = document.getElementById('oform-row-template');
    els.date = document.getElementById('oform-date');
    els.addressWrap = document.getElementById('oform-address-wrap');
    els.address = document.getElementById('oform-address');
    els.name = document.getElementById('oform-name');
    els.phone = document.getElementById('oform-phone');
    els.instagram = document.getElementById('oform-instagram');
    els.notes = document.getElementById('oform-notes');
    els.honeypot = document.getElementById('oform-website');
    els.total = document.getElementById('oform-total');
    els.formError = document.getElementById('oform-form-error');
    els.submit = document.getElementById('oform-submit');

    const cfg = window.XOXO_CONFIG || {};
    if (!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) return; // keep fallback visible

    els.fallback.hidden = true;
    els.loading.hidden = false;
    els.date.min = hawaiiTomorrow();

    wireEvents();
    loadCatalog(cfg);
  }

  function wireEvents() {
    els.add.addEventListener('click', () => addRow());
    els.form.addEventListener('submit', onSubmit);
    const radios = els.form.querySelectorAll('input[name="fulfillment"]');
    radios.forEach((radio) => radio.addEventListener('change', syncFulfillment));
  }

  function syncFulfillment() {
    const delivery = els.form.elements.fulfillment.value === 'delivery';
    els.addressWrap.hidden = !delivery;
    els.address.required = delivery;
  }

  function loadCatalog(cfg) {
    const url = cfg.SUPABASE_URL +
      '/rest/v1/products?select=id,name,unit,base_price,min_qty,note,sort,' +
      'product_flavors(name,price_override,sort)&active=is.true&order=sort';
    fetch(url, {
      headers: {
        apikey: cfg.SUPABASE_ANON_KEY,
        Authorization: 'Bearer ' + cfg.SUPABASE_ANON_KEY
      }
    })
      .then((res) => {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      })
      .then((data) => {
        if (!Array.isArray(data) || data.length === 0) throw new Error('empty catalog');
        products = data.map(normalizeProduct);
        showForm();
      })
      .catch(showFallback);
  }

  function normalizeProduct(raw) {
    const flavors = (raw.product_flavors || [])
      .slice()
      .sort((a, b) => (a.sort || 0) - (b.sort || 0))
      .map((f) => ({
        name: f.name,
        price: f.price_override == null ? Number(raw.base_price) : Number(f.price_override)
      }));
    return {
      id: raw.id,
      name: raw.name,
      basePrice: Number(raw.base_price),
      minQty: Math.max(1, parseInt(raw.min_qty, 10) || 1),
      flavors
    };
  }

  /* ---------- view switches ---------- */

  function showFallback() {
    els.loading.hidden = true;
    els.form.hidden = true;
    els.fallback.hidden = false;
  }

  function showForm() {
    els.loading.hidden = true;
    els.form.hidden = false;
    addRow();
    syncFulfillment();
  }

  function showSuccess(result) {
    els.form.hidden = true;
    els.successTitle.textContent = 'Order #' + result.order_number + ' received!';
    els.successText.textContent =
      'We will text you shortly to confirm the details and the 20% deposit ($' +
      money(Number(result.deposit_due) || 0) + ').';
    els.success.hidden = false;
    els.successTitle.focus();
  }

  /* ---------- item rows ---------- */

  function rowList() {
    return Array.from(els.rows.querySelectorAll('.oform-row'));
  }

  function addRow() {
    if (rowList().length >= MAX_ROWS) return;

    const frag = els.rowTemplate.content.cloneNode(true);
    const row = frag.querySelector('.oform-row');
    rowSeq += 1;
    const idBase = 'oform-r' + rowSeq;

    labelField(row, '.oform-row__product', idBase + '-product');
    labelField(row, '.oform-row__flavor', idBase + '-flavor');
    labelField(row, '.oform-row__qty', idBase + '-qty');
    row.querySelector('.oform-row__error').id = idBase + '-error';

    const productSelect = rowProduct(row);
    products.forEach((p) => {
      productSelect.appendChild(option(p.id, productOptionLabel(p)));
    });

    productSelect.addEventListener('change', () => syncRowProduct(row));
    rowFlavor(row).addEventListener('change', () => refreshRowPrice(row));
    rowQty(row).addEventListener('input', () => refreshRowPrice(row));
    row.querySelector('.oform-row__remove').addEventListener('click', () => {
      row.remove();
      syncRowChrome();
      updateSummary();
    });

    els.rows.appendChild(frag);
    syncRowProduct(row);
    syncRowChrome();
  }

  function labelField(row, selector, id) {
    const field = row.querySelector(selector);
    const control = field.querySelector('select, input');
    control.id = id;
    field.querySelector('label').htmlFor = id;
  }

  function option(value, text) {
    const opt = document.createElement('option');
    opt.value = value;
    opt.textContent = text;
    return opt;
  }

  function rowProduct(row) { return row.querySelector('.oform-row__product select'); }
  function rowFlavor(row) { return row.querySelector('.oform-row__flavor select'); }
  function rowQty(row) { return row.querySelector('.oform-row__qty input'); }

  function productById(id) {
    return products.find((p) => p.id === id) || null;
  }

  function productOptionLabel(p) {
    if (!p.flavors.length) return p.name + ' — $' + money(p.basePrice);
    const lowest = p.flavors.reduce((min, f) => Math.min(min, f.price), Infinity);
    return p.name + ' — from $' + money(lowest);
  }

  function flavorOptionLabel(p, flavor) {
    if (flavor.price !== p.basePrice) return flavor.name + ' — $' + money(flavor.price);
    return flavor.name;
  }

  function syncRowProduct(row) {
    const p = productById(rowProduct(row).value);
    if (!p) return;

    const flavorSelect = rowFlavor(row);
    flavorSelect.textContent = '';
    p.flavors.forEach((f) => flavorSelect.appendChild(option(f.name, flavorOptionLabel(p, f))));
    const hasFlavors = p.flavors.length > 0;
    row.classList.toggle('oform-row--noflavor', !hasFlavors);
    flavorSelect.disabled = !hasFlavors;
    flavorSelect.required = hasFlavors;

    const qty = rowQty(row);
    qty.min = String(p.minQty);
    qty.value = String(p.minQty);

    refreshRowPrice(row);
  }

  function rowUnitPrice(row) {
    const p = productById(rowProduct(row).value);
    if (!p) return 0;
    if (!p.flavors.length) return p.basePrice;
    const chosen = p.flavors.find((f) => f.name === rowFlavor(row).value);
    return chosen ? chosen.price : p.basePrice;
  }

  function rowLineTotal(row) {
    const qty = parseInt(rowQty(row).value, 10);
    return rowUnitPrice(row) * (qty > 0 ? qty : 0);
  }

  function refreshRowPrice(row) {
    row.querySelector('.oform-row__price').textContent = '$' + money(rowLineTotal(row));
    updateSummary();
  }

  function syncRowChrome() {
    const rows = rowList();
    rows.forEach((row) => {
      row.querySelector('.oform-row__remove').hidden = rows.length === 1;
    });
    els.add.hidden = rows.length >= MAX_ROWS;
  }

  /* ---------- summary ---------- */

  function currentTotal() {
    return round2(rowList().reduce((sum, row) => sum + rowLineTotal(row), 0));
  }

  function updateSummary() {
    const total = currentTotal();
    els.total.textContent = 'Estimated total $' + money(total) +
      ' · 20% deposit $' + money(round2(total * 0.2)) + ' confirms your order';
  }

  /* ---------- helpers ---------- */

  function hawaiiTomorrow() {
    const todayHawaii = new Intl.DateTimeFormat('en-CA', { timeZone: 'Pacific/Honolulu' })
      .format(new Date()); // "YYYY-MM-DD"
    const d = new Date(todayHawaii + 'T00:00:00Z');
    d.setUTCDate(d.getUTCDate() + 1);
    return d.toISOString().slice(0, 10);
  }

  function money(n) {
    return Number.isInteger(n) ? String(n) : n.toFixed(2);
  }

  function round2(n) {
    return Math.round(n * 100) / 100;
  }

  /* ---------- errors ---------- */

  function clearErrors() {
    els.form.querySelectorAll('.oform__error').forEach((el) => {
      el.hidden = true;
      el.textContent = '';
    });
    els.form.querySelectorAll('[aria-invalid]').forEach((el) => {
      el.removeAttribute('aria-invalid');
    });
  }

  function fieldError(input, errorEl, message) {
    errorEl.textContent = message;
    errorEl.hidden = false;
    input.setAttribute('aria-invalid', 'true');
    return input;
  }

  function rowError(row, message) {
    const qty = rowQty(row);
    const errorEl = row.querySelector('.oform-row__error');
    return fieldError(qty, errorEl, message);
  }

  function formError(message, withWhatsApp) {
    els.formError.textContent = message;
    if (withWhatsApp) {
      els.formError.appendChild(document.createTextNode(' '));
      const link = document.createElement('a');
      link.href = WHATSAPP_URL;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.textContent = 'message us on WhatsApp';
      els.formError.appendChild(link);
      els.formError.appendChild(document.createTextNode('.'));
    }
    els.formError.hidden = false;
    return null;
  }

  /* ---------- submit ---------- */

  function onSubmit(event) {
    event.preventDefault();
    if (sending) return;
    clearErrors();

    if (els.honeypot.value.trim() !== '') {
      // Bot filled the trap: pretend everything went fine, send nothing.
      showSuccess({
        order_number: 100 + Math.floor(Math.random() * 900),
        deposit_due: round2(currentTotal() * 0.2)
      });
      return;
    }

    const payload = collectPayload();
    const firstInvalid = validate(payload);
    if (firstInvalid) {
      firstInvalid.focus();
      return;
    }
    send(payload);
  }

  function collectPayload() {
    const fulfillment = els.form.elements.fulfillment.value;
    const payload = {
      customer_name: els.name.value.trim(),
      customer_phone: els.phone.value.trim(),
      fulfillment,
      needed_date: els.date.value,
      items: rowList().map((row) => {
        const item = {
          product_id: rowProduct(row).value,
          quantity: parseInt(rowQty(row).value, 10) || 0
        };
        if (!rowFlavor(row).disabled) item.flavor = rowFlavor(row).value;
        return item;
      })
    };
    const contact = els.instagram.value.trim();
    if (contact) payload.customer_contact = contact;
    if (fulfillment === 'delivery') payload.delivery_address = els.address.value.trim();
    const notes = els.notes.value.trim();
    if (notes) payload.notes = notes;
    return payload;
  }

  // Returns the first invalid control (to focus), or null when all good.
  function validate(payload) {
    let firstInvalid = null;
    const mark = (control) => { firstInvalid = firstInvalid || control; };

    rowList().forEach((row) => {
      const p = productById(rowProduct(row).value);
      const qty = parseInt(rowQty(row).value, 10);
      if (!p) return;
      if (!Number.isInteger(qty) || qty < p.minQty) {
        mark(rowError(row, 'Minimum ' + p.minQty + ' for ' + p.name + '.'));
      } else if (qty > 200) {
        mark(rowError(row, 'Maximum 200 for ' + p.name + ' — for bigger orders, message us on WhatsApp.'));
      }
    });

    if (!payload.needed_date) {
      mark(fieldError(els.date, document.getElementById('oform-date-error'), 'Please pick a date.'));
    } else if (payload.needed_date < els.date.min) {
      mark(fieldError(els.date, document.getElementById('oform-date-error'),
        'We need at least 1 day notice (Hawaii time).'));
    }

    if (payload.fulfillment === 'delivery' && !payload.delivery_address) {
      mark(fieldError(els.address, document.getElementById('oform-address-error'),
        'Please add a delivery address.'));
    }

    if (!payload.customer_name) {
      mark(fieldError(els.name, document.getElementById('oform-name-error'),
        'Please tell us your name.'));
    }
    if (!PHONE_RE.test(payload.customer_phone)) {
      mark(fieldError(els.phone, document.getElementById('oform-phone-error'),
        'Please enter a valid phone number.'));
    }

    return firstInvalid;
  }

  function send(payload) {
    const cfg = window.XOXO_CONFIG;
    sending = true;
    els.submit.disabled = true;
    els.submit.textContent = 'Sending…';

    fetch(cfg.SUPABASE_URL + '/rest/v1/rpc/place_order', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: cfg.SUPABASE_ANON_KEY,
        Authorization: 'Bearer ' + cfg.SUPABASE_ANON_KEY
      },
      body: JSON.stringify({ payload })
    })
      .then((res) => res.json().then((body) => ({ ok: res.ok, body })))
      .then((result) => {
        if (result.ok && result.body && result.body.ok) {
          showSuccess(result.body);
        } else {
          handleRpcError(result.body || {});
        }
      })
      .catch(() => formError(NETWORK_MSG, true))
      .finally(() => {
        sending = false;
        els.submit.disabled = false;
        els.submit.textContent = 'Place order';
      });
  }

  function handleRpcError(body) {
    const code = body.message || '';
    switch (code) {
      case 'BAD_NAME':
        focusError(fieldError(els.name, document.getElementById('oform-name-error'),
          'Please tell us your name.'));
        break;
      case 'BAD_PHONE':
        focusError(fieldError(els.phone, document.getElementById('oform-phone-error'),
          'Please enter a valid phone number.'));
        break;
      case 'DELIVERY_NEEDS_ADDRESS':
        els.addressWrap.hidden = false;
        focusError(fieldError(els.address, document.getElementById('oform-address-error'),
          'Please add a delivery address.'));
        break;
      case 'BAD_DATE':
        focusError(fieldError(els.date, document.getElementById('oform-date-error'),
          'Please pick a valid date.'));
        break;
      case 'DATE_TOO_SOON':
        focusError(fieldError(els.date, document.getElementById('oform-date-error'),
          'We need at least 1 day notice (Hawaii time).'));
        break;
      case 'DATE_TOO_FAR':
        focusError(fieldError(els.date, document.getElementById('oform-date-error'),
          'Please pick a date within the next year.'));
        break;
      case 'BAD_QTY':
        handleBadQty(body.hint);
        break;
      case 'NO_ITEMS':
        formError('Please add at least one dessert.', false);
        break;
      case 'TOO_MANY_ITEMS':
        formError('That is quite a celebration! For large orders, please', true);
        break;
      case 'UNKNOWN_PRODUCT':
      case 'FLAVOR_REQUIRED':
      case 'BAD_FLAVOR':
        formError(MENU_CHANGED_MSG, false);
        break;
      case 'BAD_TEXT':
        formError('One of the fields is a little too long — please shorten it and try again.', false);
        break;
      case 'RATE_LIMITED':
        formError(RATE_MSG, true);
        break;
      default:
        formError(NETWORK_MSG, true);
    }
  }

  function handleBadQty(productId) {
    const row = rowList().find((r) => rowProduct(r).value === productId);
    const p = productById(productId);
    if (row && p) {
      focusError(rowError(row, 'Minimum ' + p.minQty + ' for ' + p.name + '.'));
    } else {
      formError('Please check the quantities and try again.', false);
    }
  }

  function focusError(control) {
    if (control) control.focus();
  }
})();

/* XOXO Pastry — custom, brand-styled date picker.
   Replaces the native date popup with a cream/rose calendar. It writes the
   chosen day (YYYY-MM-DD) into the hidden #oform-date that order-form.js reads,
   so the existing validation/submit path is untouched. No dependencies; works
   under the page CSP (script-src 'self'). Bounds match the server: earliest is
   tomorrow in Hawaii, latest is one year out. */
(function () {
  'use strict';

  var btn = document.getElementById('oform-date-btn');
  var text = document.getElementById('oform-date-text');
  var hidden = document.getElementById('oform-date');
  var cal = document.getElementById('oform-cal');
  var errorEl = document.getElementById('oform-date-error');
  if (!btn || !text || !hidden || !cal) return;

  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
                'July', 'August', 'September', 'October', 'November', 'December'];
  var WEEK = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']; // Monday-first

  var DAY = 86400000;
  var minTime, maxTime;   // inclusive UTC-midnight bounds (ms)
  var viewY, viewM;       // month on screen
  var activeTime = null;  // day holding roving focus (ms)
  var selTime = null;     // chosen day (ms) or null
  var isOpen = false;

  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function utc(y, m, d) { return Date.UTC(y, m, d); }
  function isoOf(ms) {
    var d = new Date(ms);
    return d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-' + pad(d.getUTCDate());
  }
  function fmt(ms, opts) {
    opts.timeZone = 'UTC';
    return new Intl.DateTimeFormat('en-US', opts).format(new Date(ms));
  }
  function pretty(ms) { return fmt(ms, { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' }); }
  function longLabel(ms) { return fmt(ms, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' }); }

  function computeBounds() {
    var todayStr = new Intl.DateTimeFormat('en-CA', { timeZone: 'Pacific/Honolulu' }).format(new Date());
    var p = todayStr.split('-');
    var todayMs = utc(+p[0], +p[1] - 1, +p[2]);
    minTime = todayMs + DAY;          // tomorrow, Hawaii time
    maxTime = todayMs + 365 * DAY;    // one year out
  }

  function ymOf(ms) { var d = new Date(ms); return d.getUTCFullYear() * 12 + d.getUTCMonth(); }
  function clampTime(t) { return t < minTime ? minTime : (t > maxTime ? maxTime : t); }

  function el(tag, cls, txt) {
    var n = document.createElement(tag);
    if (cls) { n.className = cls; }
    if (txt != null) { n.textContent = txt; }
    return n;
  }

  function render() {
    cal.textContent = '';
    var viewYM = viewY * 12 + viewM;

    /* header: prev — Month YYYY — next */
    var head = el('div', 'oform__cal-head');
    var prev = el('button', 'oform__cal-nav'); prev.type = 'button';
    prev.setAttribute('aria-label', 'Previous month'); prev.innerHTML = '‹';
    prev.disabled = viewYM <= ymOf(minTime);
    prev.addEventListener('click', function () { shiftMonth(-1); });
    var title = el('div', 'oform__cal-title', MONTHS[viewM] + ' ' + viewY);
    title.id = 'oform-cal-title';
    var next = el('button', 'oform__cal-nav'); next.type = 'button';
    next.setAttribute('aria-label', 'Next month'); next.innerHTML = '›';
    next.disabled = viewYM >= ymOf(maxTime);
    next.addEventListener('click', function () { shiftMonth(1); });
    head.appendChild(prev); head.appendChild(title); head.appendChild(next);
    cal.appendChild(head);
    cal.setAttribute('aria-labelledby', 'oform-cal-title');

    /* weekday row */
    var wk = el('div', 'oform__cal-week');
    WEEK.forEach(function (w) {
      var c = el('span', 'oform__cal-wd', w);
      c.setAttribute('aria-hidden', 'true');
      wk.appendChild(c);
    });
    cal.appendChild(wk);

    /* day grid (Monday-first) */
    var grid = el('div', 'oform__cal-grid');
    grid.setAttribute('role', 'grid');
    var firstDow = new Date(utc(viewY, viewM, 1)).getUTCDay(); // 0=Sun
    var lead = (firstDow + 6) % 7;
    var daysInMonth = new Date(utc(viewY, viewM + 1, 0)).getUTCDate();
    var i;
    for (i = 0; i < lead; i++) { grid.appendChild(el('span', 'oform__cal-pad')); }
    for (var day = 1; day <= daysInMonth; day++) {
      var ms = utc(viewY, viewM, day);
      var b = el('button', 'oform__cal-day', String(day));
      b.type = 'button';
      b.setAttribute('role', 'gridcell');
      if (ms < minTime || ms > maxTime) {
        b.disabled = true;
      } else {
        b.dataset.ms = String(ms);
        b.setAttribute('aria-label', longLabel(ms));
        if (selTime === ms) { b.classList.add('is-selected'); b.setAttribute('aria-current', 'date'); }
        b.tabIndex = (ms === activeTime) ? 0 : -1;
        b.addEventListener('click', function (ev) { choose(Number(ev.currentTarget.dataset.ms)); });
      }
      grid.appendChild(b);
    }
    grid.addEventListener('keydown', onGridKey);
    cal.appendChild(grid);
  }

  function focusActive() {
    var node = cal.querySelector('.oform__cal-day[tabindex="0"]');
    if (node) { node.focus(); }
  }

  function setActive(t) {
    activeTime = clampTime(t);
    var d = new Date(activeTime);
    viewY = d.getUTCFullYear();
    viewM = d.getUTCMonth();
    render();
    focusActive();
  }

  function shiftMonth(delta) {
    var ym = viewY * 12 + viewM + delta;
    viewY = Math.floor(ym / 12);
    viewM = ((ym % 12) + 12) % 12;
    var dim = new Date(utc(viewY, viewM + 1, 0)).getUTCDate();
    var dom = Math.min(new Date(activeTime).getUTCDate(), dim);
    setActive(utc(viewY, viewM, dom));
  }

  function onGridKey(e) {
    var k = e.key;
    var dow = (new Date(activeTime).getUTCDay() + 6) % 7; // Mon=0
    if (k === 'ArrowLeft') { e.preventDefault(); setActive(activeTime - DAY); }
    else if (k === 'ArrowRight') { e.preventDefault(); setActive(activeTime + DAY); }
    else if (k === 'ArrowUp') { e.preventDefault(); setActive(activeTime - 7 * DAY); }
    else if (k === 'ArrowDown') { e.preventDefault(); setActive(activeTime + 7 * DAY); }
    else if (k === 'Home') { e.preventDefault(); setActive(activeTime - dow * DAY); }
    else if (k === 'End') { e.preventDefault(); setActive(activeTime + (6 - dow) * DAY); }
    else if (k === 'PageUp') { e.preventDefault(); shiftMonth(-1); }
    else if (k === 'PageDown') { e.preventDefault(); shiftMonth(1); }
    else if (k === 'Enter' || k === ' ') { e.preventDefault(); choose(activeTime); }
  }

  function choose(ms) {
    selTime = ms;
    hidden.value = isoOf(ms);
    text.textContent = pretty(ms);
    text.classList.remove('oform__datebtn-text--empty');
    btn.removeAttribute('aria-invalid');
    if (errorEl) { errorEl.hidden = true; errorEl.textContent = ''; }
    close(true);
  }

  function open() {
    if (isOpen) { return; }
    computeBounds();
    if (selTime != null) { setView(selTime); activeTime = selTime; }
    else { setView(minTime); activeTime = minTime; }
    cal.hidden = false;
    isOpen = true;
    btn.setAttribute('aria-expanded', 'true');
    render();
    focusActive();
    document.addEventListener('mousedown', onDocDown, true);
    document.addEventListener('keydown', onDocKey, true);
  }
  function setView(ms) { var d = new Date(ms); viewY = d.getUTCFullYear(); viewM = d.getUTCMonth(); }

  function close(returnFocus) {
    if (!isOpen) { return; }
    cal.hidden = true;
    isOpen = false;
    btn.setAttribute('aria-expanded', 'false');
    document.removeEventListener('mousedown', onDocDown, true);
    document.removeEventListener('keydown', onDocKey, true);
    if (returnFocus) { btn.focus(); }
  }

  function onDocDown(e) {
    if (cal.contains(e.target) || btn.contains(e.target)) { return; }
    close(false);
  }
  function onDocKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); close(true); }
  }

  btn.addEventListener('click', function () { isOpen ? close(true) : open(); });
  btn.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowDown' && !isOpen) { e.preventDefault(); open(); }
  });
})();

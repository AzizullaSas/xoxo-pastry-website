/* XOXO Pastry — admin orders dashboard.
   Supabase email+password auth; data visible only to emails in
   admin_users (enforced by RLS server-side). All untrusted text
   (names, notes, addresses) is rendered via textContent. */
(function () {
  'use strict';

  /* ---------- constants ---------- */

  var STATUSES = ['new', 'confirmed', 'in_progress', 'ready', 'completed', 'cancelled'];
  var STATUS_LABELS = {
    new: 'New',
    confirmed: 'Confirmed',
    in_progress: 'In progress',
    ready: 'Ready',
    completed: 'Completed',
    cancelled: 'Cancelled'
  };
  var ACTIVE_SET = { new: true, confirmed: true, in_progress: true, ready: true };

  var FILTERS = [
    { id: 'active',    label: 'Active',    test: function (s) { return ACTIVE_SET[s] === true; } },
    { id: 'new',       label: 'New',       test: function (s) { return s === 'new'; } },
    { id: 'completed', label: 'Completed', test: function (s) { return s === 'completed'; } },
    { id: 'cancelled', label: 'Cancelled', test: function (s) { return s === 'cancelled'; } },
    { id: 'all',       label: 'All',       test: function () { return true; } }
  ];

  var EMPTY_MSG = {
    active: 'No active orders — time to bake something beautiful.',
    new: 'No new orders right now.',
    completed: 'No completed orders yet.',
    cancelled: 'No cancelled orders.',
    all: 'No orders yet.'
  };

  var CONNECT_MSG = 'Can’t reach the order service right now. Check the connection and try again.';

  /* ---------- dom ---------- */

  function $(id) { return document.getElementById(id); }

  var views = {
    loading: $('view-loading'),
    login: $('view-login'),
    denied: $('view-denied'),
    error: $('view-error'),
    dash: $('view-dash')
  };

  var loadingMsg = $('loading-msg');
  var loginForm = $('login-form');
  var loginEmail = $('login-email');
  var loginPassword = $('login-password');
  var loginMsg = $('login-msg');
  var btnSignin = $('btn-signin');
  var btnSignup = $('btn-signup');
  var btnDeniedSignout = $('btn-denied-signout');
  var btnErrorRetry = $('btn-error-retry');
  var btnErrorSignout = $('btn-error-signout');
  var btnRefresh = $('btn-refresh');
  var btnSignout = $('btn-signout');
  var btnRetry = $('btn-retry');
  var searchInput = $('search');
  var chipsEl = $('chips');
  var dashStatusEl = $('dash-status');
  var dashLoadingEl = $('dash-loading');
  var dashErrorEl = $('dash-error');
  var dashErrorMsgEl = $('dash-error-msg');
  var dashEmptyEl = $('dash-empty');
  var listEl = $('orders-list');
  var toastsEl = $('toasts');

  /* ---------- state ---------- */

  var sb = null;
  var state = {
    userId: null,
    accessChecked: false,
    orders: [],
    filter: 'active',
    query: '',
    loading: false,
    loadError: null
  };

  /* ---------- date helpers (Hawaii time) ---------- */

  function hawaiiTodayStr() {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'Pacific/Honolulu' })
      .format(new Date());
  }

  function dayDiff(fromStr, toStr) {
    var a = String(fromStr).split('-');
    var b = String(toStr).split('-');
    var from = Date.UTC(+a[0], +a[1] - 1, +a[2]);
    var to = Date.UTC(+b[0], +b[1] - 1, +b[2]);
    return Math.round((to - from) / 86400000);
  }

  function formatNeededDate(dateStr) {
    var p = String(dateStr).split('-');
    if (p.length !== 3) { return String(dateStr); }
    var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2]));
    return new Intl.DateTimeFormat('en-US', {
      weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC'
    }).format(d);
  }

  function relativeNeeded(dateStr) {
    var diff = dayDiff(hawaiiTodayStr(), dateStr);
    if (isNaN(diff)) { return ''; }
    if (diff === 0) { return 'today'; }
    if (diff === 1) { return 'tomorrow'; }
    if (diff === -1) { return 'yesterday'; }
    if (diff > 1) { return 'in ' + diff + ' days'; }
    return Math.abs(diff) + ' days ago';
  }

  function formatCreatedAt(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) { return ''; }
    return new Intl.DateTimeFormat('en-US', {
      timeZone: 'Pacific/Honolulu',
      month: 'short', day: 'numeric', year: 'numeric',
      hour: 'numeric', minute: '2-digit'
    }).format(d) + ' HST';
  }

  /* ---------- misc helpers ---------- */

  function money(value) {
    var n = Number(value);
    if (!isFinite(n)) { return '$—'; }
    return '$' + (n % 1 === 0 ? String(n) : n.toFixed(2));
  }

  function phoneDigits(phone) {
    var d = String(phone || '').replace(/\D/g, '');
    if (d.length === 10) { d = '1' + d; }
    return d;
  }

  function capitalize(s) {
    s = String(s || '');
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = text; }
    return node;
  }

  function svgIcon(symbolId) {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    var use = document.createElementNS(ns, 'use');
    use.setAttribute('href', symbolId);
    svg.appendChild(use);
    return svg;
  }

  function toast(message) {
    var t = el('div', 'toast', message);
    toastsEl.appendChild(t);
    window.setTimeout(function () {
      if (t.parentNode) { t.parentNode.removeChild(t); }
    }, 5000);
  }

  function friendlyAuthError(err) {
    var msg = (err && err.message) ? String(err.message) : '';
    if (/invalid api key|failed to fetch|network|load failed|fetch/i.test(msg)) { return CONNECT_MSG; }
    if (/invalid login credentials/i.test(msg)) { return 'Wrong email or password.'; }
    if (/email not confirmed/i.test(msg)) { return 'Please confirm your email first — check your inbox for the link.'; }
    if (/already registered/i.test(msg)) { return 'This email is already registered — try signing in.'; }
    return msg || CONNECT_MSG;
  }

  /* ---------- views ---------- */

  function showView(name) {
    Object.keys(views).forEach(function (key) {
      views[key].hidden = (key !== name);
    });
  }

  function setLoginMsg(message, kind) {
    loginMsg.textContent = message;
    loginMsg.className = 'auth-msg' +
      (kind === 'error' ? ' auth-msg--error' : '') +
      (kind === 'ok' ? ' auth-msg--ok' : '');
  }

  function setAuthBusy(busy) {
    btnSignin.disabled = busy;
    btnSignup.disabled = busy;
  }

  /* ---------- auth flow ---------- */

  function handleAuthChange(session) {
    if (!session || !session.user) {
      state.userId = null;
      state.accessChecked = false;
      state.orders = [];
      showView('login');
      return;
    }
    if (state.userId === session.user.id && state.accessChecked) {
      return; /* token refresh — nothing to do */
    }
    state.userId = session.user.id;
    checkAccess();
  }

  function checkAccess() {
    loadingMsg.textContent = 'Checking access…';
    showView('loading');
    sb.rpc('is_admin').then(function (res) {
      if (res.error) {
        state.accessChecked = false;
        showView('error');
        return;
      }
      state.accessChecked = true;
      if (res.data !== true) {
        showView('denied');
        return;
      }
      showView('dash');
      loadOrders();
    }, function () {
      state.accessChecked = false;
      showView('error');
    });
  }

  function signIn(event) {
    event.preventDefault();
    if (!sb) { return; }
    var email = loginEmail.value.trim();
    var password = loginPassword.value;
    if (!email || !password) {
      setLoginMsg('Enter your email and password.', 'error');
      return;
    }
    setAuthBusy(true);
    setLoginMsg('Signing in…');
    sb.auth.signInWithPassword({ email: email, password: password }).then(function (res) {
      setAuthBusy(false);
      if (res.error) {
        setLoginMsg(friendlyAuthError(res.error), 'error');
        return;
      }
      setLoginMsg('');
      /* onAuthStateChange takes it from here */
    }, function () {
      setAuthBusy(false);
      setLoginMsg(CONNECT_MSG, 'error');
    });
  }

  function signUp() {
    if (!sb) { return; }
    var email = loginEmail.value.trim();
    var password = loginPassword.value;
    if (!email || !password) {
      setLoginMsg('Fill in email and password, then press Create account.', 'error');
      return;
    }
    if (password.length < 6) {
      setLoginMsg('Password must be at least 6 characters.', 'error');
      return;
    }
    setAuthBusy(true);
    setLoginMsg('Creating account…');
    sb.auth.signUp({ email: email, password: password }).then(function (res) {
      setAuthBusy(false);
      if (res.error) {
        setLoginMsg(friendlyAuthError(res.error), 'error');
        return;
      }
      if (res.data && res.data.session) {
        setLoginMsg('');
        return; /* confirmations disabled — signed in already */
      }
      setLoginMsg('Account created. Check your email for a confirmation link, then sign in here.', 'ok');
    }, function () {
      setAuthBusy(false);
      setLoginMsg(CONNECT_MSG, 'error');
    });
  }

  function signOut() {
    state.orders = [];
    state.accessChecked = false;
    if (!sb) { showView('login'); return; }
    sb.auth.signOut().then(function () {
      showView('login');
    }, function () {
      showView('login');
    });
  }

  /* ---------- data ---------- */

  function loadOrders() {
    state.loading = true;
    state.loadError = null;
    renderDashboard();
    sb.from('orders')
      .select('*, order_items(*)')
      .order('needed_date', { ascending: true })
      .limit(500)
      .then(function (res) {
        state.loading = false;
        if (res.error) {
          state.loadError = CONNECT_MSG;
        } else {
          state.orders = res.data || [];
        }
        renderDashboard();
      }, function () {
        state.loading = false;
        state.loadError = CONNECT_MSG;
        renderDashboard();
      });
  }

  function applyPatch(order, patch, revert, what) {
    Object.keys(patch).forEach(function (k) { order[k] = patch[k]; });
    renderDashboard();
    sb.from('orders')
      .update(patch)
      .eq('id', order.id)
      .select('id')
      .then(function (res) {
        if (res.error || !res.data || res.data.length === 0) {
          Object.keys(revert).forEach(function (k) { order[k] = revert[k]; });
          renderDashboard();
          toast(what + ' for #' + order.order_number + ' was not saved. Please try again.');
        }
      }, function () {
        Object.keys(revert).forEach(function (k) { order[k] = revert[k]; });
        renderDashboard();
        toast(what + ' for #' + order.order_number + ' was not saved. Please try again.');
      });
  }

  /* ---------- filtering ---------- */

  function filterDef() {
    for (var i = 0; i < FILTERS.length; i++) {
      if (FILTERS[i].id === state.filter) { return FILTERS[i]; }
    }
    return FILTERS[0];
  }

  function matchesQuery(order, raw) {
    var q = String(raw || '').trim().toLowerCase();
    if (!q) { return true; }
    if (q.charAt(0) === '#') { q = q.slice(1); }
    if (!q) { return true; }
    if (String(order.order_number).indexOf(q) !== -1) { return true; }
    if (String(order.customer_name || '').toLowerCase().indexOf(q) !== -1) { return true; }
    var qDigits = q.replace(/\D/g, '');
    if (qDigits && String(order.customer_phone || '').replace(/\D/g, '').indexOf(qDigits) !== -1) {
      return true;
    }
    return false;
  }

  function visibleOrders() {
    var def = filterDef();
    return state.orders.filter(function (o) {
      return def.test(o.status) && matchesQuery(o, state.query);
    });
  }

  /* ---------- rendering ---------- */

  function buildChips() {
    FILTERS.forEach(function (f) {
      var chip = el('button', 'chip');
      chip.type = 'button';
      chip.setAttribute('data-filter', f.id);
      chip.setAttribute('aria-pressed', String(f.id === state.filter));
      chip.appendChild(el('span', 'chip__label', f.label));
      chip.appendChild(el('span', 'chip__count', '0'));
      chip.addEventListener('click', function () {
        state.filter = f.id;
        renderDashboard();
      });
      chipsEl.appendChild(chip);
    });
  }

  function renderChips() {
    var counts = {};
    FILTERS.forEach(function (f) { counts[f.id] = 0; });
    state.orders.forEach(function (o) {
      FILTERS.forEach(function (f) {
        if (f.test(o.status)) { counts[f.id] += 1; }
      });
    });
    var chips = chipsEl.querySelectorAll('.chip');
    for (var i = 0; i < chips.length; i++) {
      var id = chips[i].getAttribute('data-filter');
      chips[i].setAttribute('aria-pressed', String(id === state.filter));
      chips[i].querySelector('.chip__count').textContent = String(counts[id] || 0);
    }
  }

  function buildCard(order) {
    var card = el('li', 'ocard');

    /* top row: number, status pill, channel badge */
    var top = el('div', 'ocard__top');
    top.appendChild(el('span', 'ocard__num', '#' + order.order_number));
    var statusKey = STATUSES.indexOf(order.status) !== -1 ? order.status : 'new';
    top.appendChild(el('span', 'pill pill--' + statusKey, STATUS_LABELS[statusKey] || capitalize(order.status)));
    top.appendChild(el('span', 'badge', capitalize(order.channel || 'website')));
    card.appendChild(top);

    /* needed date */
    var dateLine = el('p', 'ocard__date', formatNeededDate(order.needed_date));
    var rel = relativeNeeded(order.needed_date);
    if (rel) { dateLine.appendChild(el('span', 'ocard__rel', '· ' + rel)); }
    card.appendChild(dateLine);

    /* customer */
    card.appendChild(el('p', 'ocard__name', order.customer_name || ''));

    var contacts = el('p', 'ocard__contacts');
    var telLink = el('a', null);
    telLink.href = 'tel:' + String(order.customer_phone || '').replace(/[^+\d]/g, '');
    telLink.appendChild(svgIcon('#icon-phone'));
    telLink.appendChild(document.createTextNode(order.customer_phone || ''));
    contacts.appendChild(telLink);
    var digits = phoneDigits(order.customer_phone);
    if (digits) {
      var waLink = el('a', null);
      waLink.href = 'https://wa.me/' + digits;
      waLink.target = '_blank';
      waLink.rel = 'noopener noreferrer';
      waLink.appendChild(svgIcon('#icon-whatsapp'));
      waLink.appendChild(document.createTextNode('WhatsApp'));
      contacts.appendChild(waLink);
    }
    card.appendChild(contacts);

    if (order.customer_contact) {
      card.appendChild(el('p', 'ocard__contact-extra', 'Contact: ' + order.customer_contact));
    }

    /* fulfillment */
    var fulfill = el('p', 'ocard__fulfill');
    fulfill.appendChild(el('span', 'badge', order.fulfillment === 'delivery' ? 'Delivery' : 'Pickup'));
    if (order.fulfillment === 'delivery' && order.delivery_address) {
      fulfill.appendChild(el('span', 'ocard__address', order.delivery_address));
    }
    card.appendChild(fulfill);

    /* items */
    var items = order.order_items || [];
    if (items.length) {
      var list = el('ul', 'ocard__items');
      items.forEach(function (item) {
        var li = el('li');
        var label = item.quantity + ' × ' + item.product_name +
          (item.flavor ? ' (' + item.flavor + ')' : '');
        li.appendChild(el('span', null, label));
        li.appendChild(el('span', 'ocard__item-price', money(item.line_total)));
        list.appendChild(li);
      });
      card.appendChild(list);
    }

    /* money + deposit */
    var moneyRow = el('div', 'ocard__money');
    var sums = el('p', 'ocard__sums');
    sums.appendChild(document.createTextNode('Subtotal '));
    sums.appendChild(el('strong', null, money(order.subtotal_estimate)));
    sums.appendChild(document.createTextNode(' · deposit '));
    sums.appendChild(el('strong', null, money(order.deposit_due)));
    moneyRow.appendChild(sums);

    var checkLabel = el('label', 'check');
    var checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = order.deposit_paid === true;
    checkbox.setAttribute('data-fkey', 'deposit-' + order.id);
    checkbox.addEventListener('change', function () {
      var next = checkbox.checked;
      applyPatch(order, { deposit_paid: next }, { deposit_paid: !next }, 'Deposit');
    });
    checkLabel.appendChild(checkbox);
    checkLabel.appendChild(document.createTextNode('Deposit paid'));
    moneyRow.appendChild(checkLabel);
    card.appendChild(moneyRow);

    /* notes */
    if (order.notes) {
      card.appendChild(el('p', 'ocard__notes', order.notes));
    }

    /* created */
    var created = formatCreatedAt(order.created_at);
    if (created) {
      card.appendChild(el('p', 'ocard__meta', 'Placed ' + created));
    }

    /* status action */
    var actions = el('div', 'ocard__actions');
    var selectId = 'status-' + order.id;
    var selectLabel = el('label', 'visually-hidden', 'Status for order #' + order.order_number);
    selectLabel.htmlFor = selectId;
    var select = document.createElement('select');
    select.className = 'status-select';
    select.id = selectId;
    select.setAttribute('data-fkey', 'status-' + order.id);
    STATUSES.forEach(function (s) {
      var opt = document.createElement('option');
      opt.value = s;
      opt.textContent = STATUS_LABELS[s];
      select.appendChild(opt);
    });
    select.value = statusKey;
    select.addEventListener('change', function () {
      var prev = order.status;
      var next = select.value;
      if (next === prev) { return; }
      applyPatch(order, { status: next }, { status: prev }, 'Status');
    });
    actions.appendChild(selectLabel);
    actions.appendChild(select);
    card.appendChild(actions);

    return card;
  }

  function renderList() {
    var focusKey = null;
    if (document.activeElement && document.activeElement.getAttribute) {
      focusKey = document.activeElement.getAttribute('data-fkey');
    }

    listEl.textContent = '';
    dashLoadingEl.hidden = !state.loading;
    dashErrorEl.hidden = !(!state.loading && state.loadError);
    if (state.loadError) { dashErrorMsgEl.textContent = state.loadError; }

    if (state.loading || state.loadError) {
      dashEmptyEl.hidden = true;
      dashStatusEl.textContent = state.loading ? 'Loading orders' : state.loadError;
      return;
    }

    var visible = visibleOrders();
    if (visible.length === 0) {
      dashEmptyEl.hidden = false;
      dashEmptyEl.textContent = state.query.trim()
        ? 'Nothing matches your search.'
        : (EMPTY_MSG[state.filter] || EMPTY_MSG.all);
      dashStatusEl.textContent = dashEmptyEl.textContent;
      return;
    }

    dashEmptyEl.hidden = true;
    var frag = document.createDocumentFragment();
    visible.forEach(function (order) {
      frag.appendChild(buildCard(order));
    });
    listEl.appendChild(frag);
    dashStatusEl.textContent = visible.length + (visible.length === 1 ? ' order shown' : ' orders shown');

    if (focusKey) {
      var target = listEl.querySelector('[data-fkey="' + focusKey + '"]');
      if (target) { target.focus(); }
    }
  }

  function renderDashboard() {
    renderChips();
    renderList();
  }

  /* ---------- init ---------- */

  function init() {
    var cfg = window.XOXO_CONFIG || {};
    var lib = window.supabase;

    buildChips();

    loginForm.addEventListener('submit', signIn);
    btnSignup.addEventListener('click', signUp);
    btnDeniedSignout.addEventListener('click', signOut);
    btnErrorSignout.addEventListener('click', signOut);
    btnSignout.addEventListener('click', signOut);
    btnErrorRetry.addEventListener('click', checkAccess);
    btnRefresh.addEventListener('click', loadOrders);
    btnRetry.addEventListener('click', loadOrders);
    searchInput.addEventListener('input', function () {
      state.query = searchInput.value;
      renderList();
    });

    if (!lib || typeof lib.createClient !== 'function' || !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
      showView('login');
      setLoginMsg('The dashboard is not configured — Supabase settings are missing.', 'error');
      setAuthBusy(true);
      document.body.setAttribute('data-admin-ready', 'no-config');
      return;
    }

    sb = lib.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);

    sb.auth.onAuthStateChange(function (event, session) {
      /* defer: never call other supabase methods inside the callback */
      window.setTimeout(function () { handleAuthChange(session); }, 0);
    });

    document.body.setAttribute('data-admin-ready', '1');
  }

  init();
}());

/* XOXO Pastry — admin "Menu" tab.
   Sections and cards of the public menu (menu_sections / menu_items), the Sold out switch,
   photos (Storage bucket menu-photos) and the order-form catalog (products /
   product_flavors). Every write is gated by RLS (is_admin()); see
   db/migrations/0027_menu_admin_and_sold_out.sql.

   - A card's `sells` lists the order-form rows it stands for: [{p: productId, f: flavor}]
     for one flavor, [{p: productId}] for a whole product. products.sold_out /
     product_flavors.sold_out are derived from the cards by the database — never written here.
   - All text from the database is rendered with textContent / .value (never innerHTML). */
(function () {
  'use strict';

  var BUCKET = 'menu-photos';
  var PHOTO_MAX = 1000;          // px, longest side — same as scripts/build-menu.py
  var CONNECT_MSG = 'Can’t reach the menu right now. Check the connection and try again.';

  function $(id) { return document.getElementById(id); }

  var tabOrders = $('tab-orders');
  var tabMenu = $('tab-menu');
  var panelOrders = $('panel-orders');
  var panelMenu = $('panel-menu');
  if (!tabMenu || !panelMenu) { return; }

  var sectionsEl = $('m-sections');
  var productsEl = $('m-products');
  var loadingEl = $('m-loading');
  var errorEl = $('m-error');
  var errorMsgEl = $('m-error-msg');
  var statusEl = $('m-status');
  var dialog = $('m-dialog');
  var dialogForm = $('m-dialog-form');
  var dialogTitle = $('m-dialog-title');
  var dialogBody = $('m-dialog-body');
  var dialogMsg = $('m-dialog-msg');
  var dialogActions = $('m-dialog-actions');

  var state = {
    sections: [],   // [{ id, title, subtitle, sort, visible, items: [...] }]
    products: [],   // [{ id, name, unit, base_price, min_qty, note, sort, active, sold_out, flavors: [...] }]
    loaded: false,
    busy: false
  };

  /* ---------- shared helpers ---------- */

  function api() { return window.XOXOAdmin || {}; }
  function sb() { return api().sb; }
  function toast(msg) { if (api().toast) { api().toast(msg); } }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null && text !== '') { node.textContent = text; }
    return node;
  }

  function button(text, className, onClick, label) {
    var b = el('button', className || 'btn btn--ghost btn--sm', text);
    b.type = 'button';
    if (label) { b.setAttribute('aria-label', label); }
    if (onClick) { b.addEventListener('click', onClick); }
    return b;
  }

  function money(n) {
    n = Number(n);
    if (!isFinite(n)) { return '$—'; }
    return '$' + (n % 1 === 0 ? String(n) : n.toFixed(2));
  }

  function bySort(a, b) { return (a.sort || 0) - (b.sort || 0); }

  function trimOrNull(v) {
    v = String(v == null ? '' : v).trim();
    return v === '' ? null : v;
  }

  function slugify(s) {
    return String(s || '').toLowerCase()
      .normalize('NFKD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);
  }

  function randomTag() {
    return Math.random().toString(36).slice(2, 6);
  }

  function productById(id) {
    for (var i = 0; i < state.products.length; i++) {
      if (state.products[i].id === id) { return state.products[i]; }
    }
    return null;
  }

  function flavorOf(p, name) {
    if (!p) { return null; }
    for (var i = 0; i < p.flavors.length; i++) {
      if (p.flavors[i].name === name) { return p.flavors[i]; }
    }
    return null;
  }

  function flavorPrice(p, f) {
    return f && f.price_override != null ? Number(f.price_override) : Number(p.base_price);
  }

  // "Signature Cheesecake · 7 inch" → "7 inch"; used for short labels.
  function shortProductName(p) {
    var parts = String(p.name).split(' · ');
    return parts.length > 1 ? parts.slice(1).join(' · ') : p.name;
  }

  function linkText(link) {
    var p = productById(link.p);
    if (!p) { return link.p + (link.f ? ' · ' + link.f : '') + ' (missing)'; }
    if (!link.f) { return p.name; }
    return p.name + ' — ' + link.f + (flavorOf(p, link.f) ? '' : ' (missing)');
  }

  function setStatus(msg) { statusEl.textContent = msg; }

  function resultError(res) {
    if (!res) { return CONNECT_MSG; }
    var e = res.error;
    if (!e) { return null; }
    var m = String(e.message || '');
    if (/duplicate key|already exists/i.test(m)) { return 'That name is already used here — pick another.'; }
    if (/foreign key|violates foreign/i.test(m)) { return 'This is still in use, so it can’t be removed.'; }
    if (/row-level security|permission denied/i.test(m)) { return 'This account can’t change the menu.'; }
    if (/check constraint/i.test(m)) { return 'One of the values isn’t allowed (too long, or a bad photo address).'; }
    if (/fetch|network|load failed/i.test(m)) { return CONNECT_MSG; }
    return m || CONNECT_MSG;
  }

  // Run a supabase query builder; resolves to the result, rejects with a friendly message.
  function run(query) {
    return Promise.resolve(query).then(function (res) {
      var msg = resultError(res);
      if (msg) { throw new Error(msg); }
      return res;
    }, function () { throw new Error(CONNECT_MSG); });
  }

  /* ---------- tabs ---------- */

  function selectTab(which) {
    var menu = which === 'menu';
    tabOrders.setAttribute('aria-selected', String(!menu));
    tabMenu.setAttribute('aria-selected', String(menu));
    tabOrders.tabIndex = menu ? -1 : 0;
    tabMenu.tabIndex = menu ? 0 : -1;
    panelOrders.hidden = menu;
    panelMenu.hidden = !menu;
    if (menu) { load(); }
  }

  tabOrders.addEventListener('click', function () { selectTab('orders'); });
  tabMenu.addEventListener('click', function () { selectTab('menu'); });
  [tabOrders, tabMenu].forEach(function (t) {
    t.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        var other = t === tabOrders ? tabMenu : tabOrders;
        other.focus();
        other.click();
      }
    });
  });

  document.addEventListener('xoxo:signout', function () {
    state.sections = [];
    state.products = [];
    state.loaded = false;
    sectionsEl.textContent = '';
    productsEl.textContent = '';
    if (dialog.open) { dialog.close(); }
    selectTab('orders');
  });

  $('m-refresh').addEventListener('click', function () { load(); });
  $('m-retry').addEventListener('click', function () { load(); });
  $('m-add-section').addEventListener('click', function () { editSection(null); });
  $('m-add-product').addEventListener('click', function () { editProduct(null); });

  /* ---------- data ---------- */

  function fetchProducts() {
    return run(sb().from('products')
      .select('id,name,unit,base_price,min_qty,note,sort,active,sold_out,product_flavors(name,price_override,sort,sold_out)')
      .order('sort', { ascending: true }))
      .then(function (res) {
        state.products = (res.data || []).map(function (p) {
          p.flavors = (p.product_flavors || []).slice().sort(bySort);
          delete p.product_flavors;
          return p;
        });
      });
  }

  function fetchSections() {
    return run(sb().from('menu_sections')
      .select('id,title,subtitle,sort,visible,menu_items(id,section_id,name,emoji,description,note,price_label,image_url,image_w,image_h,sort,visible,sold_out,sells)')
      .order('sort', { ascending: true }))
      .then(function (res) {
        state.sections = (res.data || []).map(function (s) {
          s.items = (s.menu_items || []).slice().sort(bySort);
          s.items.forEach(function (it) { if (!Array.isArray(it.sells)) { it.sells = []; } });
          delete s.menu_items;
          return s;
        });
      });
  }

  function load() {
    if (!sb()) { return; }
    loadingEl.hidden = state.loaded;
    errorEl.hidden = true;
    setStatus('Loading the menu');
    return Promise.all([fetchSections(), fetchProducts()]).then(function () {
      state.loaded = true;
      loadingEl.hidden = true;
      render();
      setStatus('Menu loaded');
    }, function (err) {
      loadingEl.hidden = true;
      if (!state.loaded) {
        errorMsgEl.textContent = err.message || CONNECT_MSG;
        errorEl.hidden = false;
      } else {
        toast(err.message || CONNECT_MSG);
      }
    });
  }

  // After a write: refresh quietly (the database recomputes sold-out flags).
  function reload() {
    return Promise.all([fetchSections(), fetchProducts()]).then(render, function (err) {
      toast(err.message || CONNECT_MSG);
    });
  }

  function sectionById(id) {
    for (var i = 0; i < state.sections.length; i++) {
      if (state.sections[i].id === id) { return state.sections[i]; }
    }
    return null;
  }

  // Give a list sort = 10, 20, 30… and save only the rows whose sort changed.
  function saveOrder(table, rows) {
    var writes = [];
    rows.forEach(function (row, i) {
      var want = (i + 1) * 10;
      if (row.sort !== want) {
        row.sort = want;
        writes.push(run(sb().from(table).update({ sort: want }).eq('id', row.id)));
      }
    });
    return Promise.all(writes);
  }

  function move(list, index, delta) {
    var to = index + delta;
    if (to < 0 || to >= list.length) { return false; }
    var tmp = list[index];
    list[index] = list[to];
    list[to] = tmp;
    return true;
  }

  /* ---------- rendering: sections and cards ---------- */

  function render() {
    renderSections();
    renderProducts();
  }

  function renderSections() {
    sectionsEl.textContent = '';
    if (!state.sections.length) {
      sectionsEl.appendChild(el('p', 'dash-empty', 'No sections yet — press “+ Section” to start the menu.'));
      return;
    }
    state.sections.forEach(function (s, si) {
      var box = el('section', 'm-sec' + (s.visible ? '' : ' m-sec--hidden'));
      box.setAttribute('aria-label', s.title);

      var head = el('header', 'm-sec__head');
      var titles = el('div', 'm-sec__titles');
      var h = el('h2', 'm-sec__title', s.title);
      if (!s.visible) { h.appendChild(el('span', 'm-tag m-tag--muted', 'Hidden')); }
      titles.appendChild(h);
      if (s.subtitle) { titles.appendChild(el('p', 'm-sec__sub', s.subtitle)); }
      head.appendChild(titles);

      var tools = el('div', 'm-tools');
      var up = button('↑', 'm-icon', function () { moveSection(si, -1); }, 'Move section “' + s.title + '” up');
      up.disabled = si === 0;
      var down = button('↓', 'm-icon', function () { moveSection(si, 1); }, 'Move section “' + s.title + '” down');
      down.disabled = si === state.sections.length - 1;
      tools.appendChild(up);
      tools.appendChild(down);
      tools.appendChild(button('Edit', 'btn btn--ghost btn--sm', function () { editSection(s); }, 'Edit section “' + s.title + '”'));
      head.appendChild(tools);
      box.appendChild(head);

      var list = el('ul', 'm-items');
      s.items.forEach(function (it, ii) { list.appendChild(itemRow(s, it, ii)); });
      if (!s.items.length) { list.appendChild(el('li', 'm-items__empty', 'No cards in this section yet.')); }
      box.appendChild(list);

      box.appendChild(button('+ Add card', 'btn-subtle m-add', function () { editItem(null, s); }));
      sectionsEl.appendChild(box);
    });
  }

  function itemRow(section, it, index) {
    var li = el('li', 'm-item' + (it.sold_out ? ' m-item--soldout' : '') + (it.visible ? '' : ' m-item--hidden'));

    var thumb = el('div', 'm-item__thumb');
    if (it.image_url) {
      var img = document.createElement('img');
      img.src = it.image_url;
      img.alt = '';
      img.loading = 'lazy';
      thumb.appendChild(img);
    }
    li.appendChild(thumb);

    var main = el('div', 'm-item__main');
    var name = el('p', 'm-item__name', it.name + (it.emoji ? ' ' + it.emoji : ''));
    main.appendChild(name);
    var meta = el('p', 'm-item__meta');
    if (it.price_label) { meta.appendChild(el('span', 'm-item__price', it.price_label)); }
    if (!it.visible) { meta.appendChild(el('span', 'm-tag m-tag--muted', 'Hidden')); }
    if (!it.sells.length) { meta.appendChild(el('span', 'm-tag m-tag--warn', 'Not in order form')); }
    main.appendChild(meta);
    li.appendChild(main);

    var tools = el('div', 'm-tools');
    var sw = el('label', 'm-switch');
    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = it.sold_out === true;
    cb.setAttribute('aria-label', 'Sold out: ' + it.name);
    cb.addEventListener('change', function () { setSoldOut(it, cb.checked, cb); });
    sw.appendChild(cb);
    sw.appendChild(el('span', 'm-switch__label', 'Sold out'));
    tools.appendChild(sw);

    var up = button('↑', 'm-icon', function () { moveItem(section, index, -1); }, 'Move “' + it.name + '” up');
    up.disabled = index === 0;
    var down = button('↓', 'm-icon', function () { moveItem(section, index, 1); }, 'Move “' + it.name + '” down');
    down.disabled = index === section.items.length - 1;
    tools.appendChild(up);
    tools.appendChild(down);
    tools.appendChild(button('Edit', 'btn btn--ghost btn--sm', function () { editItem(it, section); }, 'Edit “' + it.name + '”'));
    li.appendChild(tools);
    return li;
  }

  function setSoldOut(it, value, cb) {
    cb.disabled = true;
    run(sb().from('menu_items').update({ sold_out: value }).eq('id', it.id).select('id'))
      .then(function (res) {
        if (!res.data || !res.data.length) { throw new Error('Not saved — this account can’t change the menu.'); }
        it.sold_out = value;
        toast(it.name + (value ? ' is sold out — hidden from the order form.' : ' is back on sale.'));
        return reload();
      })
      .catch(function (err) {
        cb.checked = !value;
        cb.disabled = false;
        toast(err.message);
      });
  }

  function moveSection(index, delta) {
    if (!move(state.sections, index, delta)) { return; }
    renderSections();
    saveOrder('menu_sections', state.sections).catch(function (err) { toast(err.message); reload(); });
  }

  function moveItem(section, index, delta) {
    if (!move(section.items, index, delta)) { return; }
    renderSections();
    saveOrder('menu_items', section.items).catch(function (err) { toast(err.message); reload(); });
  }

  /* ---------- rendering: order-form products ---------- */

  function renderProducts() {
    productsEl.textContent = '';
    state.products.forEach(function (p) {
      var li = el('li', 'm-prod' + (p.active ? '' : ' m-prod--off'));
      var main = el('div', 'm-prod__main');
      main.appendChild(el('p', 'm-prod__name', p.name));
      var meta = el('p', 'm-item__meta');
      var prices = p.flavors.length
        ? p.flavors.map(function (f) { return flavorPrice(p, f); })
        : [Number(p.base_price)];
      var lo = Math.min.apply(null, prices);
      var hi = Math.max.apply(null, prices);
      meta.appendChild(el('span', 'm-item__price', lo === hi ? money(lo) : money(lo) + '–' + money(hi)));
      if (p.min_qty > 1) { meta.appendChild(el('span', 'm-tag', 'min ' + p.min_qty)); }
      if (p.flavors.length) {
        var out = p.flavors.filter(function (f) { return f.sold_out; }).length;
        meta.appendChild(el('span', 'm-tag', p.flavors.length + ' flavors' + (out ? ' · ' + out + ' sold out' : '')));
      }
      if (!p.active) { meta.appendChild(el('span', 'm-tag m-tag--muted', 'Off')); }
      else if (p.sold_out) { meta.appendChild(el('span', 'm-tag m-tag--warn', 'Sold out')); }
      main.appendChild(meta);
      li.appendChild(main);
      li.appendChild(button('Edit', 'btn btn--ghost btn--sm', function () { editProduct(p); }, 'Edit product “' + p.name + '”'));
      productsEl.appendChild(li);
    });
  }

  /* ---------- dialog plumbing ---------- */

  var dialogSubmit = null;

  function openDialog(title, buildBody, actions, onSubmit) {
    dialogTitle.textContent = title;
    dialogBody.textContent = '';
    dialogActions.textContent = '';
    dialogMsg.textContent = '';
    buildBody(dialogBody);
    actions.forEach(function (a) { dialogActions.appendChild(a); });
    dialogSubmit = onSubmit;
    if (!dialog.open) { dialog.showModal(); }
    var first = dialogBody.querySelector('input:not([type=checkbox]):not([type=file]), textarea, select');
    if (first) { first.focus(); }
  }

  function closeDialog() {
    dialogSubmit = null;
    if (dialog.open) { dialog.close(); }
  }

  dialogForm.addEventListener('submit', function (e) {
    e.preventDefault();
    if (dialogSubmit && !state.busy) { dialogSubmit(); }
  });
  dialog.addEventListener('cancel', function (e) {
    if (state.busy) { e.preventDefault(); }
  });

  function primary(text) {
    var b = el('button', 'btn btn--primary btn--sm', text);
    b.type = 'submit';
    return b;
  }

  function cancelBtn() {
    return button('Cancel', 'btn btn--ghost btn--sm', function () { if (!state.busy) { closeDialog(); } });
  }

  function dangerBtn(text, onClick) {
    return button(text, 'btn-subtle m-danger', onClick);
  }

  function busy(on) {
    state.busy = on;
    dialogActions.querySelectorAll('button').forEach(function (b) { b.disabled = on; });
  }

  function fail(err) {
    busy(false);
    dialogMsg.textContent = (err && err.message) || CONNECT_MSG;
  }

  var fieldSeq = 0;
  function field(parent, label, input, hint) {
    fieldSeq += 1;
    var wrap = el('div', 'field');
    input.id = 'mf-' + fieldSeq;
    var lab = el('label', null, label);
    lab.htmlFor = input.id;
    wrap.appendChild(lab);
    wrap.appendChild(input);
    if (hint) { wrap.appendChild(el('p', 'm-field-hint', hint)); }
    parent.appendChild(wrap);
    return input;
  }

  function textInput(value, maxLength, attrs) {
    var i = document.createElement('input');
    i.type = 'text';
    i.value = value == null ? '' : String(value);
    if (maxLength) { i.maxLength = maxLength; }
    Object.keys(attrs || {}).forEach(function (k) { i.setAttribute(k, attrs[k]); });
    return i;
  }

  function numberInput(value, min, step) {
    var i = document.createElement('input');
    i.type = 'number';
    i.inputMode = 'decimal';
    i.min = String(min);
    i.step = step || 'any';
    i.value = value == null ? '' : String(value);
    return i;
  }

  function textArea(value, maxLength) {
    var t = document.createElement('textarea');
    t.rows = 3;
    t.value = value == null ? '' : String(value);
    if (maxLength) { t.maxLength = maxLength; }
    return t;
  }

  function checkbox(parent, label, checked) {
    var wrap = el('label', 'check');
    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = !!checked;
    wrap.appendChild(cb);
    wrap.appendChild(document.createTextNode(label));
    parent.appendChild(wrap);
    return cb;
  }

  function confirmThen(question, yesText, action) {
    openDialog('Are you sure?', function (body) {
      body.appendChild(el('p', 'm-confirm', question));
    }, [dangerBtn(yesText, function () {
      busy(true);
      action().then(function () { busy(false); closeDialog(); }, fail);
    }), cancelBtn()], null);
  }

  function parsePrice(input, label) {
    var raw = String(input.value).trim();
    var n = Number(raw);
    if (raw === '' || !isFinite(n) || n < 0 || n > 100000) {
      throw new Error(label + ': enter a price in dollars, e.g. 45 or 9.50.');
    }
    return Math.round(n * 100) / 100;
  }

  /* ---------- section editor ---------- */

  function editSection(s) {
    var f = {};
    openDialog(s ? 'Edit section' : 'New section', function (body) {
      f.title = field(body, 'Title', textInput(s ? s.title : '', 120, { required: 'required' }));
      f.sub = field(body, 'Line under the title (optional)', textArea(s ? s.subtitle : '', 600),
        'E.g. “Gluten-free · 7″ · serves 8–10”.');
      f.visible = checkbox(body, 'Show this section on the menu', s ? s.visible : true);
    }, [primary(s ? 'Save' : 'Add section'), cancelBtn()].concat(s ? [dangerBtn('Delete section', function () {
      if (s.items.length) {
        dialogMsg.textContent = 'Move or delete its ' + s.items.length + ' card(s) first — or just untick “Show this section”.';
        return;
      }
      confirmThen('Delete the empty section “' + s.title + '”?', 'Delete', function () {
        return run(sb().from('menu_sections').delete().eq('id', s.id)).then(reload);
      });
    })] : []), function () {
      var title = trimOrNull(f.title.value);
      if (!title) { dialogMsg.textContent = 'Please give the section a title.'; f.title.focus(); return; }
      var row = { title: title, subtitle: trimOrNull(f.sub.value), visible: f.visible.checked };
      busy(true);
      var q;
      if (s) {
        q = sb().from('menu_sections').update(row).eq('id', s.id).select('id');
      } else {
        var last = state.sections.length ? state.sections[state.sections.length - 1].sort : 0;
        row.sort = (last || 0) + 10;
        q = sb().from('menu_sections').insert(row).select('id');
      }
      run(q).then(function (res) {
        if (!res.data || !res.data.length) { throw new Error('Not saved — this account can’t change the menu.'); }
        busy(false);
        closeDialog();
        toast(s ? 'Section saved.' : 'Section “' + title + '” added.');
        return reload();
      }).catch(fail);
    });
  }

  /* ---------- photo: resize in the browser, upload to Storage ---------- */

  function resizePhoto(file) {
    return new Promise(function (resolve, reject) {
      if (!/^image\//.test(file.type)) { reject(new Error('Please choose a photo (JPEG, PNG or WebP).')); return; }
      var url = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () {
        var w = img.naturalWidth;
        var h = img.naturalHeight;
        var k = Math.min(1, PHOTO_MAX / Math.max(w, h));
        w = Math.max(1, Math.round(w * k));
        h = Math.max(1, Math.round(h * k));
        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        canvas.getContext('2d').drawImage(img, 0, 0, w, h);
        URL.revokeObjectURL(url);
        canvas.toBlob(function (blob) {
          if (!blob) { reject(new Error('This photo could not be read. Try another one.')); return; }
          resolve({ blob: blob, w: w, h: h });
        }, 'image/jpeg', 0.84);
      };
      img.onerror = function () {
        URL.revokeObjectURL(url);
        reject(new Error('This photo could not be read. Try a JPEG or PNG.'));
      };
      img.src = url;
    });
  }

  function uploadPhoto(photo) {
    var path = 'items/' + Date.now() + '-' + randomTag() + '.jpg';
    return run(sb().storage.from(BUCKET).upload(path, photo.blob, {
      contentType: 'image/jpeg', cacheControl: '31536000', upsert: false
    })).then(function () {
      var pub = sb().storage.from(BUCKET).getPublicUrl(path);
      return { url: pub.data.publicUrl, w: photo.w, h: photo.h };
    });
  }

  function storagePath(url) {
    var marker = '/storage/v1/object/public/' + BUCKET + '/';
    var i = String(url || '').indexOf(marker);
    return i === -1 ? null : url.slice(i + marker.length);
  }

  function removeStoredPhoto(url) {
    var path = storagePath(url);
    if (!path) { return Promise.resolve(); } // photos under images/ ship with the site
    return Promise.resolve(sb().storage.from(BUCKET).remove([path])).catch(function () {});
  }

  /* ---------- card editor ---------- */

  function editItem(it, section) {
    var f = {};
    var photo = { url: it ? it.image_url : null, w: it ? it.image_w : null, h: it ? it.image_h : null, file: null, preview: null };
    var links = it ? it.sells.map(function (l) { return l.f ? { p: l.p, f: l.f } : { p: l.p }; }) : [];
    var linkBoxes = []; // { cb, link }

    openDialog(it ? 'Edit card' : 'New card in “' + section.title + '”', function (body) {
      var sel = document.createElement('select');
      state.sections.forEach(function (s) {
        var o = document.createElement('option');
        o.value = s.id;
        o.textContent = s.title;
        sel.appendChild(o);
      });
      sel.value = section.id;
      f.section = field(body, 'Section', sel);

      f.name = field(body, 'Name', textInput(it ? it.name : '', 120, { required: 'required' }));
      f.emoji = field(body, 'Emoji (optional)', textInput(it ? it.emoji : '', 16));
      f.desc = field(body, 'Description (optional)', textArea(it ? it.description : '', 600));
      f.note = field(body, 'Highlighted note (optional)', textInput(it ? it.note : '', 200),
        'Shown as a small rose label, e.g. “Not gluten free”.');
      f.price = field(body, 'Price as shown on the menu', textInput(it ? it.price_label : '', 120),
        'Free text, e.g. “$65” or “6″ $45 · 7″ $70”. Real prices come from the order form options below.');
      var fill = button('Fill from order prices', 'btn-subtle', function () {
        var label = priceFromLinks(currentLinks());
        if (label) { f.price.value = label; } else { dialogMsg.textContent = 'Tick what this card sells first.'; }
      });
      f.price.parentNode.appendChild(fill);

      // photo
      var pWrap = el('div', 'field');
      pWrap.appendChild(el('span', 'm-label', 'Photo'));
      var pRow = el('div', 'm-photo');
      var pImg = document.createElement('img');
      pImg.alt = '';
      pImg.className = 'm-photo__img';
      var pNone = el('span', 'm-photo__none', 'No photo');
      function showPhoto() {
        var src = photo.preview || photo.url;
        pImg.hidden = !src;
        pNone.hidden = !!src;
        if (src) { pImg.src = src; }
      }
      pRow.appendChild(pImg);
      pRow.appendChild(pNone);
      var pBtns = el('div', 'm-photo__btns');
      var file = document.createElement('input');
      file.type = 'file';
      file.accept = 'image/jpeg,image/png,image/webp';
      file.id = 'mf-photo-' + (++fieldSeq);
      file.className = 'visually-hidden';
      var pick = el('label', 'btn btn--ghost btn--sm', 'Choose photo');
      pick.htmlFor = file.id;
      pick.tabIndex = 0;
      pick.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); file.click(); } });
      file.addEventListener('change', function () {
        var chosen = file.files && file.files[0];
        if (!chosen) { return; }
        if (photo.preview) { URL.revokeObjectURL(photo.preview); }
        photo.file = chosen;
        photo.preview = URL.createObjectURL(chosen);
        showPhoto();
      });
      var clear = button('Remove photo', 'btn-subtle', function () {
        if (photo.preview) { URL.revokeObjectURL(photo.preview); }
        photo.file = null;
        photo.preview = null;
        photo.url = null;
        file.value = '';
        showPhoto();
      });
      pBtns.appendChild(file);
      pBtns.appendChild(pick);
      pBtns.appendChild(clear);
      pRow.appendChild(pBtns);
      pWrap.appendChild(pRow);
      body.appendChild(pWrap);
      showPhoto();

      f.visible = checkbox(body, 'Show on the menu', it ? it.visible : true);
      f.soldOut = checkbox(body, 'Sold out', it ? it.sold_out : false);

      // what the card sells
      var box = el('fieldset', 'm-sells');
      box.appendChild(el('legend', null, 'In the order form, this card is…'));
      box.appendChild(el('p', 'm-field-hint',
        'Tick the rows customers order for this card. “Sold out” or hiding the card takes exactly these out of the order form.'));
      state.products.forEach(function (p) {
        var det = el('details', 'm-sells__prod');
        var sum = el('summary', null, p.name + (p.active ? '' : ' (off)'));
        det.appendChild(sum);
        var whole = { p: p.id };
        linkBoxes.push({ cb: checkbox(det, p.flavors.length ? 'The whole product (customer picks the flavor)' : p.name + ' — ' + money(p.base_price), hasLink(links, whole)), link: whole });
        p.flavors.forEach(function (fl) {
          var one = { p: p.id, f: fl.name };
          linkBoxes.push({ cb: checkbox(det, fl.name + ' — ' + money(flavorPrice(p, fl)), hasLink(links, one)), link: one });
        });
        if (linkBoxes.some(function (x) { return x.link.p === p.id && x.cb.checked; })) { det.open = true; }
        box.appendChild(det);
      });
      // links to rows that no longer exist stay visible (and kept) until unticked
      links.forEach(function (l) {
        var p = productById(l.p);
        if (p && (!l.f || flavorOf(p, l.f))) { return; }
        linkBoxes.push({ cb: checkbox(box, linkText(l), true), link: l });
      });
      body.appendChild(box);

      // create a new order-form row for this card
      var nw = el('fieldset', 'm-sells');
      nw.appendChild(el('legend', null, 'Add a new order option for this card (optional)'));
      var mode = document.createElement('select');
      [['', 'No — nothing new'], ['product', 'A new product in the order form'], ['flavor', 'A new flavor of an existing product']]
        .forEach(function (o) { var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1]; mode.appendChild(op); });
      f.newMode = field(nw, 'Create', mode);
      var prodSel = document.createElement('select');
      state.products.forEach(function (p) {
        if (!p.flavors.length) { return; }
        var op = document.createElement('option');
        op.value = p.id;
        op.textContent = p.name;
        prodSel.appendChild(op);
      });
      f.newProduct = field(nw, 'Flavor of', prodSel);
      f.newPrice = field(nw, 'Price, $', numberInput('', 0));
      f.newMin = field(nw, 'Minimum per order', numberInput(1, 1, '1'));
      function syncMode() {
        var m = mode.value;
        f.newProduct.parentNode.hidden = m !== 'flavor';
        f.newPrice.parentNode.hidden = m === '';
        f.newMin.parentNode.hidden = m !== 'product';
      }
      mode.addEventListener('change', syncMode);
      syncMode();
      body.appendChild(nw);
    }, [primary(it ? 'Save' : 'Add card'), cancelBtn()].concat(it ? [dangerBtn('Delete card', function () {
      confirmThen('Delete the card “' + it.name + '”? The order form options it points at stay.', 'Delete', function () {
        return run(sb().from('menu_items').delete().eq('id', it.id))
          .then(function () { removeStoredPhoto(it.image_url); toast('Card deleted.'); return reload(); });
      });
    })] : []), function () { saveItem(it, section, f, photo, currentLinks()); });

    function currentLinks() {
      return linkBoxes.filter(function (x) { return x.cb.checked; }).map(function (x) { return x.link; });
    }
  }

  function hasLink(links, l) {
    return links.some(function (x) { return x.p === l.p && (x.f || null) === (l.f || null); });
  }

  // "$65" / "from $8" / "6 inch (Baby) $45 · 7 inch $70" from the ticked rows.
  function priceFromLinks(links) {
    var byProduct = [];
    links.forEach(function (l) {
      var p = productById(l.p);
      if (!p) { return; }
      var prices;
      if (l.f) {
        var fl = flavorOf(p, l.f);
        if (!fl) { return; }
        prices = [flavorPrice(p, fl)];
      } else {
        prices = p.flavors.length ? p.flavors.map(function (x) { return flavorPrice(p, x); }) : [Number(p.base_price)];
      }
      byProduct.push({ p: p, lo: Math.min.apply(null, prices), hi: Math.max.apply(null, prices) });
    });
    if (!byProduct.length) { return ''; }
    function one(x) { return (x.lo === x.hi ? '' : 'from ') + money(x.lo); }
    var same = byProduct.every(function (x) { return x.lo === byProduct[0].lo && x.hi === byProduct[0].hi; });
    if (byProduct.length === 1 || same) { return one(byProduct[0]); }
    return byProduct.map(function (x) { return shortProductName(x.p) + ' ' + one(x); }).join(' · ');
  }

  function saveItem(it, section, f, photo, links) {
    var name = trimOrNull(f.name.value);
    if (!name) { dialogMsg.textContent = 'Please give the card a name.'; f.name.focus(); return; }
    var targetSection = sectionById(f.section.value) || section;
    var mode = f.newMode.value;
    var newPrice = null;
    try {
      if (mode) { newPrice = parsePrice(f.newPrice, 'New option'); }
    } catch (e) { dialogMsg.textContent = e.message; f.newPrice.focus(); return; }
    var newMin = Math.max(1, parseInt(f.newMin.value, 10) || 1);

    busy(true);
    dialogMsg.textContent = '';
    var oldPhoto = it ? it.image_url : null;

    // 1. photo
    var step = photo.file
      ? resizePhoto(photo.file).then(uploadPhoto)
      : Promise.resolve(photo.url ? { url: photo.url, w: photo.w, h: photo.h } : null);

    step.then(function (ph) {
      // 2. new order-form row, if asked for
      return createOption(mode, name, targetSection, f.newProduct.value, newPrice, newMin).then(function (link) {
        if (link && !hasLink(links, link)) { links = links.concat([link]); }
        return ph;
      });
    }).then(function (ph) {
      // 3. the card
      var row = {
        section_id: targetSection.id,
        name: name,
        emoji: trimOrNull(f.emoji.value),
        description: trimOrNull(f.desc.value),
        note: trimOrNull(f.note.value),
        // a new option with no price text yet: show its price on the menu
        price_label: trimOrNull(f.price.value) || (mode ? money(newPrice) : null),
        image_url: ph ? ph.url : null,
        image_w: ph ? ph.w : null,
        image_h: ph ? ph.h : null,
        visible: f.visible.checked,
        sold_out: f.soldOut.checked,
        sells: links
      };
      if (!it || it.section_id !== targetSection.id) {
        var last = targetSection.items.length ? targetSection.items[targetSection.items.length - 1].sort : 0;
        row.sort = (last || 0) + 10;
      }
      var q = it
        ? sb().from('menu_items').update(row).eq('id', it.id).select('id')
        : sb().from('menu_items').insert(row).select('id');
      return run(q).then(function (res) {
        if (!res.data || !res.data.length) { throw new Error('Not saved — this account can’t change the menu.'); }
        if (oldPhoto && oldPhoto !== row.image_url) { removeStoredPhoto(oldPhoto); }
        if (photo.preview) { URL.revokeObjectURL(photo.preview); }
        busy(false);
        closeDialog();
        toast(it ? '“' + name + '” saved.' : '“' + name + '” added to the menu.');
        return reload();
      });
    }).catch(fail);
  }

  // Creates the product / flavor the card asked for; resolves to its link (or null).
  function createOption(mode, name, section, productId, price, minQty) {
    if (mode === 'flavor') {
      var p = productById(productId);
      if (!p) { return Promise.reject(new Error('Choose which product gets the new flavor.')); }
      if (flavorOf(p, name)) { return Promise.resolve({ p: p.id, f: name }); }
      var sort = p.flavors.reduce(function (m, x) { return Math.max(m, x.sort || 0); }, 0) + 1;
      return run(sb().from('product_flavors').insert({
        product_id: p.id, name: name, price_override: price, sort: sort
      }).select('name')).then(function () { return { p: p.id, f: name }; });
    }
    if (mode === 'product') {
      var id = (slugify(section.title + ' ' + name) || 'item') + '-' + randomTag();
      var sortP = nextProductSort(section);
      // "Tiramisu · Classic Cup" reads better in the dropdown than "Classic Cup",
      // but "Hawaiian Honey Cake · Hawaiian Honey Cake" does not.
      var a = name.toLowerCase();
      var b = section.title.toLowerCase();
      var label = (a.indexOf(b) !== -1 || b.indexOf(a) !== -1) ? name : section.title + ' · ' + name;
      return run(sb().from('products').insert({
        id: id, name: label.slice(0, 120), unit: minQty > 1 ? 'piece' : 'item', base_price: price,
        min_qty: minQty, note: null, sort: sortP, active: true
      }).select('id')).then(function () { return { p: id }; });
    }
    return Promise.resolve(null);
  }

  // A new product lands in the order-form dropdown right after the products this
  // section's cards already sell (or at the end).
  function nextProductSort(section) {
    var max = 0;
    var mine = 0;
    state.products.forEach(function (p) { max = Math.max(max, p.sort || 0); });
    section.items.forEach(function (it) {
      it.sells.forEach(function (l) { var p = productById(l.p); if (p) { mine = Math.max(mine, p.sort || 0); } });
    });
    return mine ? mine + 1 : max + 10;
  }

  /* ---------- product editor (order form options) ---------- */

  function editProduct(p) {
    var f = {};
    var rows = []; // { orig: flavor|null, name, price, removed }
    openDialog(p ? 'Edit order form option' : 'New order form option', function (body) {
      f.name = field(body, 'Name in the order form', textInput(p ? p.name : '', 120, { required: 'required' }),
        'E.g. “Basque Cheesecake · 7 inch”.');
      f.note = field(body, 'Small note under it (optional)', textInput(p ? p.note : '', 300));
      f.price = field(body, 'Price, $', numberInput(p ? p.base_price : '', 0),
        'Used when there are no flavors, or for a flavor with an empty price.');
      f.min = field(body, 'Minimum per order', numberInput(p ? p.min_qty : 1, 1, '1'));
      f.active = checkbox(body, 'Offered in the order form', p ? p.active : true);
      if (p && p.sold_out) {
        body.appendChild(el('p', 'm-field-hint', 'Now sold out — switch “Sold out” off on its menu card to bring it back.'));
      }

      var fs = el('fieldset', 'm-sells');
      fs.appendChild(el('legend', null, 'Flavors (optional)'));
      fs.appendChild(el('p', 'm-field-hint', 'With flavors, the customer must pick one. Leave a price empty to use the price above.'));
      var list = el('div', 'm-flavors');
      fs.appendChild(list);
      function addRow(fl) {
        var r = { orig: fl, removed: false };
        var line = el('div', 'm-flavor');
        r.name = textInput(fl ? fl.name : '', 120, { 'aria-label': 'Flavor name', placeholder: 'Flavor' });
        r.price = numberInput(fl && fl.price_override != null ? fl.price_override : '', 0);
        r.price.setAttribute('aria-label', 'Flavor price, $');
        r.price.placeholder = '$';
        line.appendChild(r.name);
        line.appendChild(r.price);
        if (fl && fl.sold_out) { line.appendChild(el('span', 'm-tag m-tag--warn', 'Sold out')); }
        line.appendChild(button('Remove', 'btn-subtle m-danger', function () {
          r.removed = true;
          line.remove();
        }, 'Remove flavor'));
        list.appendChild(line);
        rows.push(r);
        return r;
      }
      (p ? p.flavors : []).forEach(addRow);
      fs.appendChild(button('+ Flavor', 'btn-subtle', function () { addRow(null).name.focus(); }));
      body.appendChild(fs);
      if (!p) {
        body.appendChild(el('p', 'm-field-hint', 'Then point a menu card at it (Edit card → “In the order form, this card is…”), so Sold out works for it.'));
      }
    }, [primary(p ? 'Save' : 'Add'), cancelBtn()], function () {
      var name = trimOrNull(f.name.value);
      if (!name) { dialogMsg.textContent = 'Please enter a name.'; f.name.focus(); return; }
      var base;
      try { base = parsePrice(f.price, 'Price'); } catch (e) { dialogMsg.textContent = e.message; f.price.focus(); return; }
      var min = Math.max(1, parseInt(f.min.value, 10) || 1);

      var live = rows.filter(function (r) { return !r.removed; });
      var seen = {};
      var flavorRows = [];
      for (var i = 0; i < live.length; i++) {
        var fname = trimOrNull(live[i].name.value);
        if (!fname) {
          if (!live[i].orig && String(live[i].price.value).trim() === '') { continue; } // empty new line
          dialogMsg.textContent = 'Every flavor needs a name.'; live[i].name.focus(); return;
        }
        if (seen[fname.toLowerCase()]) { dialogMsg.textContent = 'The flavor “' + fname + '” is listed twice.'; live[i].name.focus(); return; }
        seen[fname.toLowerCase()] = true;
        var fp = null;
        if (String(live[i].price.value).trim() !== '') {
          try { fp = parsePrice(live[i].price, fname); } catch (e2) { dialogMsg.textContent = e2.message; live[i].price.focus(); return; }
        }
        flavorRows.push({ r: live[i], name: fname, price: fp, sort: flavorRows.length + 1 });
      }
      var removed = rows.filter(function (r) { return r.removed && r.orig; });

      busy(true);
      dialogMsg.textContent = '';
      var id = p ? p.id : (slugify(name) || 'item') + '-' + randomTag();
      var prodRow = { name: name, note: trimOrNull(f.note.value), base_price: base, min_qty: min, active: f.active.checked };
      var first;
      if (p) {
        first = run(sb().from('products').update(prodRow).eq('id', p.id).select('id'));
      } else {
        prodRow.id = id;
        prodRow.unit = min > 1 ? 'piece' : 'item';
        prodRow.sort = state.products.reduce(function (m, x) { return Math.max(m, x.sort || 0); }, 0) + 10;
        first = run(sb().from('products').insert(prodRow).select('id'));
      }
      first.then(function (res) {
        if (!res.data || !res.data.length) { throw new Error('Not saved — this account can’t change the order form.'); }
        // deletes first, then renames/updates, then inserts — so names can be swapped around
        return Promise.all(removed.map(function (r) {
          return run(sb().from('product_flavors').delete().eq('product_id', id).eq('name', r.orig.name));
        }));
      }).then(function () {
        return flavorRows.reduce(function (chain, x) {
          return chain.then(function () {
            var o = x.r.orig;
            if (o) {
              var oldPrice = o.price_override == null ? null : Number(o.price_override);
              if (o.name === x.name && oldPrice === x.price && o.sort === x.sort) { return null; }
              return run(sb().from('product_flavors')
                .update({ name: x.name, price_override: x.price, sort: x.sort })
                .eq('product_id', id).eq('name', o.name));
            }
            return run(sb().from('product_flavors')
              .insert({ product_id: id, name: x.name, price_override: x.price, sort: x.sort }));
          });
        }, Promise.resolve());
      }).then(function () {
        busy(false);
        closeDialog();
        toast(p ? 'Order form option saved.' : '“' + name + '” added to the order form.');
        return reload();
      }).catch(function (err) {
        fail(err);
        reload(); // part of it may have been saved
      });
    });
  }
}());

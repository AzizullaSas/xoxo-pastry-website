/* XOXO Pastry — the #menu section, drawn from the database (menu_sections / menu_items,
   managed in admin.html → Menu). The cards already in index.html are the fallback: if
   the fetch fails or comes back empty they stay as they are, so the page never shows an
   empty menu. Everything is built with DOM APIs / textContent (no innerHTML). */
(function () {
  'use strict';

  var cfg = window.XOXO_CONFIG || {};
  var root = document.querySelector('#menu .menu-cats');
  if (!root || !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) return;

  var url = cfg.SUPABASE_URL + '/rest/v1/menu_sections' +
    '?select=id,title,subtitle,sort,' +
    'menu_items(id,name,emoji,description,note,price_label,image_url,image_w,image_h,sort,sold_out)' +
    '&order=sort';

  fetch(url, { headers: { apikey: cfg.SUPABASE_ANON_KEY, Authorization: 'Bearer ' + cfg.SUPABASE_ANON_KEY } })
    .then(function (res) { if (!res.ok) throw new Error('HTTP ' + res.status); return res.json(); })
    .then(function (sections) {
      if (!Array.isArray(sections)) return;
      var filled = sections.filter(function (s) { return s.menu_items && s.menu_items.length; });
      if (!filled.length) return; // keep the static menu
      render(filled);
    })
    .catch(function () { /* keep the static menu */ });

  function el(tag, className, text) {
    var n = document.createElement(tag);
    if (className) n.className = className;
    if (text != null && text !== '') n.textContent = text;
    return n;
  }

  function bySort(a, b) { return (a.sort || 0) - (b.sort || 0); }

  function card(item, sectionTitle) {
    var li = el('li', 'fcard reveal' + (item.image_url ? '' : ' fcard--nophoto') +
      (item.sold_out ? ' fcard--soldout' : ''));
    if (item.image_url) {
      var media = el('div', 'fcard__media');
      var img = document.createElement('img');
      img.src = item.image_url;
      img.alt = 'XOXO Pastry ' + item.name + ' ' + sectionTitle.replace(/s$/, '');
      if (item.image_w && item.image_h) { img.width = item.image_w; img.height = item.image_h; }
      img.loading = 'lazy';
      img.decoding = 'async';
      media.appendChild(img);
      li.appendChild(media);
    }
    var body = el('div', 'fcard__body');
    var name = el('h4', 'fcard__name', item.name);
    if (item.emoji) {
      name.appendChild(document.createTextNode(' '));
      name.appendChild(el('span', 'fcard__emoji', item.emoji));
    }
    body.appendChild(name);
    if (item.description) body.appendChild(el('p', 'fcard__desc', item.description));
    if (item.note) body.appendChild(el('p', 'fcard__note fcard__note--warn', item.note));
    var price = el('p', 'fcard__price', item.price_label);
    if (item.sold_out) {
      price.appendChild(el('span', 'fcard__soldout-tag', 'Sold out'));
    }
    if (item.price_label || item.sold_out) body.appendChild(price);
    li.appendChild(body);
    return li;
  }

  function render(sections) {
    var frag = document.createDocumentFragment();
    sections.slice().sort(bySort).forEach(function (s) {
      var box = el('div', 'menu-cat reveal');
      var head = el('header', 'menu-cat__head');
      head.appendChild(el('h3', 'menu-cat__title', s.title));
      if (s.subtitle) head.appendChild(el('p', 'menu-cat__sub', s.subtitle));
      box.appendChild(head);
      var list = el('ul', 'fcard-list');
      s.menu_items.slice().sort(bySort).forEach(function (item) {
        list.appendChild(card(item, s.title));
      });
      box.appendChild(list);
      frag.appendChild(box);
    });
    root.textContent = '';
    root.appendChild(frag);
    reveal(root.querySelectorAll('.reveal'));
  }

  // The page's reveal-on-scroll (script.js) only sees elements present at load,
  // so the new cards get the same one-shot observer here.
  function reveal(nodes) {
    var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced || !('IntersectionObserver' in window)) {
      nodes.forEach(function (n) { n.classList.add('is-visible'); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('is-visible'); io.unobserve(e.target); }
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });
    nodes.forEach(function (n) { io.observe(n); });
  }
})();

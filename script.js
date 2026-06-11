(() => {
  'use strict';

  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ----------------------------------------------------------
     Sticky nav: toggle .is-scrolled past a small threshold.
     ---------------------------------------------------------- */
  const nav = document.querySelector('.nav');
  if (nav) {
    let ticking = false;
    const onScroll = () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        nav.classList.toggle('is-scrolled', window.scrollY > 24);
        ticking = false;
      });
    };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  /* ----------------------------------------------------------
     Reveal-on-scroll. One observer, one-shot per element.
     Honours prefers-reduced-motion (no observer at all).
     ---------------------------------------------------------- */
  const reveals = document.querySelectorAll('.reveal');

  if (prefersReducedMotion || !('IntersectionObserver' in window)) {
    reveals.forEach((el) => el.classList.add('is-visible'));
    return;
  }

  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        io.unobserve(entry.target);
      }
    }
  }, {
    threshold: 0.15,
    rootMargin: '0px 0px -8% 0px'
  });

  reveals.forEach((el) => io.observe(el));
})();

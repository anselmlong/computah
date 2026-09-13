// Progressive enhancement: without JavaScript every workflow stage stays visible.
function initializeWorkflow() {
  const tablist = document.querySelector('.workflow-tabs');
  if (!tablist) return;
  const tabs = [...tablist.querySelectorAll('button')];
  const panels = tabs.map(tab => document.getElementById(tab.dataset.panel));
  if (!tabs.length || !panels.every(Boolean)) return;

  function activate(index, focus = false) {
    tabs.forEach((tab, i) => {
      tab.setAttribute('aria-selected', String(i === index));
      tab.tabIndex = i === index ? 0 : -1;
      panels[i].hidden = i !== index;
    });
    if (focus) tabs[index].focus();
  }

  tablist.setAttribute('role', 'tablist');
  tabs.forEach((tab, index) => {
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-controls', panels[index].id);
    panels[index].setAttribute('role', 'tabpanel');
    panels[index].setAttribute('aria-labelledby', tab.id);
    panels[index].tabIndex = 0;
    tab.addEventListener('click', () => activate(index));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) {
        event.preventDefault();
        activate(next, true);
      }
    });
  });

  function activateHash() {
    const index = panels.findIndex(panel => `#${panel.id}` === location.hash);
    if (index >= 0) activate(index);
  }
  activate(0);
  activateHash();
  window.addEventListener('hashchange', activateHash);
  tablist.hidden = false;
}

initializeWorkflow();

function initializeCompanion() {
  const faces = [...document.querySelectorAll('.brand-face')];
  if (!faces.length) return;
  const controls = [...document.querySelectorAll('.motion-toggle')];
  let paused = false;
  controls.forEach(control => control.addEventListener('click', () => {
    paused = !paused;
    document.body.classList.toggle('motion-paused', paused);
    controls.forEach(button => {
      button.setAttribute('aria-pressed', String(paused));
      button.textContent = paused ? 'Resume animation' : 'Pause animation';
    });
  }));

  function updateVisibility() {
    document.body.classList.toggle('document-hidden', document.hidden);
  }
  document.addEventListener('visibilitychange', updateVisibility);
  updateVisibility();
  if ('IntersectionObserver' in window) {
    const visibility = new IntersectionObserver(entries => {
      entries.forEach(entry => entry.target.classList.toggle('motion-offscreen', !entry.isIntersecting));
    });
    faces.forEach(face => visibility.observe(face));
  }

  const hello = document.querySelector('.hello-companion');
  const caption = document.querySelector('.companion-caption');
  if (!hello || !caption) return;
  let reset;
  let greetings = 0;
  hello.addEventListener('click', () => {
    clearTimeout(reset);
    hello.dataset.mood = 'hello';
    caption.textContent = greetings++ % 2 === 0
      ? 'Oh, hello. Big plans? I’m all ears.'
      : 'A little company for your next big step.';
    reset = setTimeout(() => { delete hello.dataset.mood; }, 1400);
  });
}

initializeCompanion();

function initializeTypewriter() {
  const text = document.querySelector('.typed-request');
  if (!text) return;
  const title = text.parentElement;
  const phrases = [...title.querySelectorAll('.title-measure')].map(node => node.textContent);
  if (!phrases.length) return;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let index = 0;
  let length = Array.from(phrases[0]).length;
  let deleting = true;
  let paused = false;
  let visible = true;
  let timer;

  function schedule(delay = 1200) {
    clearTimeout(timer);
    if (!paused && visible && !document.hidden && !reducedMotion.matches) {
      timer = setTimeout(step, delay);
    }
  }
  function step() {
    const letters = Array.from(phrases[index]);
    length += deleting ? -1 : 1;
    text.textContent = letters.slice(0, length).join('');
    let delay = deleting ? 38 : 75;
    if (deleting && length === 0) {
      index = (index + 1) % phrases.length;
      deleting = false;
      delay = 350;
    } else if (!deleting && length === letters.length) {
      deleting = true;
      delay = 2200;
    }
    schedule(delay);
  }
  document.querySelectorAll('.motion-toggle').forEach(control => {
    control.addEventListener('click', () => {
      // Companion controls update their accessible state before this listener runs.
      paused = control.getAttribute('aria-pressed') === 'true';
      schedule();
    });
  });
  document.addEventListener('visibilitychange', () => schedule());
  reducedMotion.addEventListener('change', () => {
    if (reducedMotion.matches) {
      index = 0;
      length = Array.from(phrases[0]).length;
      deleting = true;
      text.textContent = phrases[0];
    }
    schedule();
  });
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      visible = entries[0].isIntersecting;
      title.classList.toggle('motion-offscreen', !visible);
      schedule();
    });
    observer.observe(title);
  }
  schedule(2200);
}

initializeTypewriter();

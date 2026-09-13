const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../website/site.js'), 'utf8');

function fixture({ missingTablist = false, missingPanel = false, hash = '' } = {}) {
  function element(id) {
    return { id, attrs: {}, handlers: {}, hidden: false,
      setAttribute(name, value) { this.attrs[name] = value; },
      addEventListener(name, handler) { this.handlers[name] = handler; },
      focus() { this.focused = true; } };
  }
  const panels = ['research', 'prepare', 'review'].map(element);
  const tabs = panels.map(panel => Object.assign(element(`tab-${panel.id}`), { dataset: { panel: panel.id } }));
  const tablist = Object.assign(element('tabs'), { hidden: true, querySelectorAll: () => tabs });
  const window = element('window');
  const location = { hash };
  const document = {
    querySelector: selector => selector === '.workflow-tabs' && !missingTablist ? tablist : null,
    querySelectorAll: () => [],
    getElementById: id => missingPanel && id === 'review' ? null : panels.find(panel => panel.id === id)
  };
  vm.runInNewContext(source, { document, window, location });
  return { panels, tabs, tablist, window, location };
}

test('pages without a complete workflow keep fallback content available', () => {
  assert.doesNotThrow(() => fixture({ missingTablist: true }));
  const page = fixture({ missingPanel: true });
  assert.equal(page.tablist.hidden, true);
  assert.ok(page.panels.every(panel => !panel.hidden));
});

test('deep links select their panel initially and when the hash changes', () => {
  const page = fixture({ hash: '#review' });
  assert.deepEqual(page.panels.map(panel => panel.hidden), [true, true, false]);
  page.location.hash = '#prepare';
  page.window.handlers.hashchange();
  assert.equal(page.tabs[1].attrs['aria-selected'], 'true');
  assert.equal(page.panels[1].hidden, false);
  page.location.hash = '#installation';
  page.window.handlers.hashchange();
  assert.equal(page.panels[1].hidden, false);
});

test('keyboard navigation wraps with roving focus and click switches panels', () => {
  const page = fixture();
  let prevented = false;
  page.tabs[0].handlers.keydown({ key: 'ArrowLeft', preventDefault() { prevented = true; } });
  assert.ok(prevented);
  assert.ok(page.tabs[2].focused);
  assert.deepEqual(page.tabs.map(tab => tab.tabIndex), [-1, -1, 0]);
  page.tabs[2].handlers.keydown({ key: 'Home', preventDefault() {} });
  assert.equal(page.tabs[0].attrs['aria-selected'], 'true');
  page.tabs[1].handlers.click();
  assert.deepEqual(page.panels.map(panel => panel.hidden), [true, false, true]);
});

function companionFixture() {
  function element() {
    const classes = new Set();
    return { dataset: {}, handlers: {}, attrs: {}, textContent: '', classes,
      classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); } },
      setAttribute(name, value) { this.attrs[name] = value; },
      addEventListener(name, handler) { this.handlers[name] = handler; } };
  }
  const face = element(), control = element(), hello = element(), caption = element(), body = element();
  let visibilityCallback, timeoutCallback;
  const document = Object.assign(element(), {
    hidden: false, body,
    querySelectorAll: selector => selector === '.brand-face' ? [face] : [control],
    querySelector: selector => ({ '.hello-companion': hello, '.companion-caption': caption })[selector] || null
  });
  class Observer {
    constructor(callback) { visibilityCallback = callback; }
    observe() {}
  }
  vm.runInNewContext(source, {
    document, window: { IntersectionObserver: Observer }, IntersectionObserver: Observer,
    clearTimeout() {}, setTimeout(callback) { timeoutCallback = callback; return 1; }
  });
  return { face, control, hello, caption, body, document,
    intersect: visible => visibilityCallback([{ target: face, isIntersecting: visible }]),
    reset: () => timeoutCallback() };
}

test('animation controls pause and resume with accessible state', () => {
  const page = companionFixture();
  page.control.handlers.click();
  assert.ok(page.body.classes.has('motion-paused'));
  assert.equal(page.control.attrs['aria-pressed'], 'true');
  assert.equal(page.control.textContent, 'Resume animation');
  page.control.handlers.click();
  assert.ok(!page.body.classes.has('motion-paused'));
  assert.equal(page.control.attrs['aria-pressed'], 'false');
});

test('companion stops offscreen and in background, and responds to a greeting', () => {
  const page = companionFixture();
  page.intersect(false);
  assert.ok(page.face.classes.has('motion-offscreen'));
  page.intersect(true);
  assert.ok(!page.face.classes.has('motion-offscreen'));
  page.document.hidden = true;
  page.document.handlers.visibilitychange();
  assert.ok(page.body.classes.has('document-hidden'));
  page.hello.handlers.click();
  assert.equal(page.hello.dataset.mood, 'hello');
  assert.match(page.caption.textContent, /hello/);
  page.reset();
  assert.equal(page.hello.dataset.mood, undefined);
});

test('typewriter deletes, types all requests, and stops for motion preferences', () => {
  const phrases = ['apply for my master’s.', 'book me a flight ticket.', 'fill in a survey.', 'check my emails.'];
  const title = { querySelectorAll: () => phrases.map(textContent => ({ textContent })) };
  const text = { textContent: phrases[0], parentElement: title };
  const preference = { matches: false, addEventListener(name, handler) { this.change = handler; } };
  const timers = new Map();
  let nextID = 0;
  const listeners = {};
  const control = { paused: false, getAttribute() { return String(this.paused); }, addEventListener(name, handler) { this.click = handler; } };
  const document = {
    hidden: false,
    querySelector: selector => selector === '.typed-request' ? text : null,
    querySelectorAll: selector => selector === '.motion-toggle' ? [control] : [],
    addEventListener(name, handler) { listeners[name] = handler; }
  };
  vm.runInNewContext(source, {
    document, window: { matchMedia: () => preference },
    setTimeout(handler) { timers.set(++nextID, handler); return nextID; },
    clearTimeout(id) { timers.delete(id); }
  });
  const seen = new Set([text.textContent]);
  for (let i = 0; i < 200; i++) {
    const [id, handler] = timers.entries().next().value;
    timers.delete(id); handler(); seen.add(text.textContent);
  }
  assert.ok(seen.has(''));
  phrases.forEach(phrase => assert.ok(seen.has(phrase), phrase));
  control.paused = true; control.click();
  assert.equal(timers.size, 0);
  control.paused = false; control.click();
  assert.equal(timers.size, 1);
  document.hidden = true; listeners.visibilitychange();
  assert.equal(timers.size, 0);
  document.hidden = false; listeners.visibilitychange();
  assert.equal(timers.size, 1);
  preference.matches = true; preference.change();
  assert.equal(timers.size, 0);
  assert.equal(text.textContent, phrases[0]);
});

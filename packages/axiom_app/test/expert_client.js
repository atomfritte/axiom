/* Ein Wegwerf-Browser fuer `assets/expert/index.html`.

   Warum das hier steht: Die Weboberflaeche des Expertenmodus ist die
   einzige Flaeche des Projekts, durch die kein Dart-Werkzeug greift.
   `expert_i18n_test.dart` liest ihren Quelltext — was die Seite beim Klick
   TUT, hat bisher niemand nachgesehen. Genau dort sassen zehn bestaetigte
   Fehler, und die meisten davon lagen daran, dass ein abgelehnter Aufruf
   ueberhaupt keinen Weg an die Oberflaeche hatte: Der Knopf war von kaputt
   nicht zu unterscheiden.

   Der Nachbau ist absichtlich klein: gerade so viel DOM, wie die Seite
   anfasst. Er ersetzt keinen Browser. Er reicht, um Knoepfe zu druecken und
   zu lesen, was danach dasteht. Aufgerufen wird er aus
   `expert_client_test.dart` mit einem Szenarionamen; heraus kommt genau
   eine Zeile JSON.

   Zwei Stellen bilden das Verhalten des Browsers bewusst nach, weil an
   ihnen die Befunde haengen:
   - Ein `onclick`, der eine abgelehnte Zusage zurueckgibt, loest
     `unhandledrejection` aus. Ohne das waere jeder fehlende Fehlerpfad
     unsichtbar — also genau der Zustand, den die Tests messen sollen.
   - Ein Knopf mit `disabled` nimmt keinen Klick mehr an.
*/
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

// ── Das kleine DOM ────────────────────────────────────────────────────
class Text {
  constructor(t) { this.nodeType = 3; this._text = String(t); }
  get textContent() { return this._text; }
}

class Node {
  constructor(tag) {
    this.tag = tag; this.nodeType = 1; this.children = []; this.attrs = {};
    this._class = ''; this.dataset = {}; this.style = {}; this.handlers = {};
    this.value = ''; this._text = null; this.open = false; this.parent = null;
    this.disabled = false;
  }
  get className() { return this._class; }
  set className(v) { this._class = String(v); }
  get classList() {
    const self = this;
    const list = () => self._class.split(/\s+/).filter(Boolean);
    return {
      add: (...c) => { const l = list(); for (const x of c) if (!l.includes(x)) l.push(x); self._class = l.join(' '); },
      remove: (...c) => { self._class = list().filter(x => !c.includes(x)).join(' '); },
      toggle: (c, on) => {
        const has = list().includes(c); const want = on === undefined ? !has : !!on;
        if (want && !has) self._class = list().concat([c]).join(' ');
        if (!want && has) self._class = list().filter(x => x !== c).join(' ');
      },
      contains: c => list().includes(c),
    };
  }
  setAttribute(k, v) {
    this.attrs[k] = String(v);
    if (k.startsWith('data-')) this.dataset[k.slice(5)] = String(v);
    // Ein <input value="x"> traegt den Wert auch als Eigenschaft — sonst
    // laese `input.value` leer, was der Seite Schritte ohne Titel vortaeuscht.
    if (k === 'value') this.value = v;
    if (k === 'disabled') this.disabled = true;
  }
  getAttribute(k) { return this.attrs[k] === undefined ? null : this.attrs[k]; }
  removeAttribute(k) { delete this.attrs[k]; }
  addEventListener(type, fn) { (this.handlers[type] = this.handlers[type] || []).push(fn); }
  removeEventListener() {}
  /* Steigt auf wie im Browser: Der Reiterstreifen hoert stellvertretend fuer
     seine Knoepfe zu, und ohne Aufstieg fiele genau dieser Weg durch.
     Zurueck kommt, was die Handler zurueckgeben — der Treiber braucht die
     Zusagen, um `unhandledrejection` nachzubilden. */
  dispatch(type, ev = {}) {
    if (this.disabled) return [];
    const event = Object.assign({ target: this, preventDefault() {}, stopPropagation() {} }, ev);
    const out = [];
    let n = this;
    while (n) {
      for (const fn of n.handlers[type] || []) out.push(fn(Object.assign(event, { currentTarget: n })));
      n = n.parent;
    }
    return out;
  }
  click() { return this.dispatch('click'); }
  append(...kids) {
    for (const k of kids.flat(Infinity)) {
      if (k === null || k === undefined || k === false) continue;
      if (k instanceof Fragment) { for (const c of k.children) { c.parent = this; this.children.push(c); } continue; }
      k.parent = this;
      this.children.push(k);
    }
  }
  replaceChildren(...kids) { this.children = []; this.append(...kids); }
  get textContent() {
    return this._text !== null ? this._text
      : this.children.map(c => c.textContent === undefined ? String(c) : c.textContent).join('');
  }
  set textContent(v) { this._text = String(v); this.children = []; }
  set innerHTML(v) { this._text = String(v); this.children = []; }
  querySelector(sel) { return this.findAll(sel)[0] || null; }
  querySelectorAll(sel) { return this.findAll(sel); }
  findAll(sel) {
    const out = [];
    const walk = n => {
      for (const c of n.children || []) {
        if (c instanceof Node) { if (c.matches(sel)) out.push(c); walk(c); }
      }
    };
    walk(this);
    return out;
  }
  matches(sel) {
    return String(sel).split(',').map(s => s.trim()).some(s => {
      if (s === ':hover') return false;
      if (s.startsWith('.')) return this.classList.contains(s.slice(1));
      if (s.startsWith('#')) return this.attrs.id === s.slice(1);
      if (s.startsWith('[')) return this._attrMatch(s);
      const m = /^([a-z0-9]+)(\[[^\]]+\])?$/i.exec(s);
      if (!m || this.tag !== m[1]) return false;
      return m[2] ? this._attrMatch(m[2]) : true;
    });
  }
  _attrMatch(s) {
    const m = /^\[([^\]=]+)(?:=([^\]]+))?\]$/.exec(s);
    if (!m) return false;
    const key = m[1];
    const want = m[2] && m[2].replace(/^["']|["']$/g, '');
    return this.attrs[key] !== undefined && (want === undefined || this.attrs[key] === want);
  }
  closest(sel) { let n = this; while (n) { if (n.matches && n.matches(sel)) return n; n = n.parent; } return null; }
  showModal() { this.open = true; }
  close() { this.open = false; this.dispatch('close'); }
  focus() { doc.activeElement = this; }
  scrollIntoView() {}
}

class Fragment {
  constructor() { this.children = []; this.nodeType = 11; }
  append(...kids) {
    for (const k of kids.flat(Infinity)) {
      if (k === null || k === undefined || k === false) continue;
      if (k instanceof Fragment) { this.children.push(...k.children); continue; }
      this.children.push(k);
    }
  }
  get textContent() { return this.children.map(c => c.textContent).join(''); }
}

const named = new Map();
function stub(sel) {
  if (!named.has(sel)) {
    const n = new Node(sel.startsWith('#') ? 'div' : 'span');
    if (sel.startsWith('#')) n.attrs.id = sel.slice(1);
    named.set(sel, n);
  }
  return named.get(sel);
}

const doc = {
  createElement: t => new Node(t),
  createDocumentFragment: () => new Fragment(),
  createTextNode: t => new Text(t),
  documentElement: new Node('html'),
  body: new Node('body'),
  activeElement: null,
  addEventListener: () => {},
  /* Die Seite fragt beides, um zu entscheiden, ob gerade jemand hinsieht
     (G4). Szenarien stellen sie ueber `h.sandbox.document` um. */
  visibilityState: 'visible',
  _focused: true,
  hasFocus() { return doc._focused; },
  querySelector(sel) {
    if (/^#[A-Za-z0-9_-]+$/.test(sel)) return stub(sel);
    return doc.querySelectorAll(sel)[0] || null;
  },
  querySelectorAll(sel) {
    const parts = String(sel).trim().split(/\s+/);
    const last = parts[parts.length - 1];
    const roots = parts.length > 1 && /^#[A-Za-z0-9_-]+$/.test(parts[0])
      ? [stub(parts[0])] : [...named.values()];
    const out = [];
    for (const r of roots) for (const n of r.findAll(last)) if (!out.includes(n)) out.push(n);
    return out;
  },
};

// Der Teil des Markups, den das Skript beim Laden anfasst. Mehr braucht es
// nicht — was die Seite selbst zeichnet, entsteht durch el().
function buildMarkup(tabs) {
  stub('#app').className = 'hide';
  stub('#gate').className = '';
  const bar = stub('#tabs');
  for (const name of tabs) {
    const b = new Node('button');
    b.setAttribute('role', 'tab');
    b.setAttribute('data-tab', name);
    b.setAttribute('aria-selected', name === 'board' ? 'true' : 'false');
    bar.append(b);
  }
}

// ── Der Lauf ──────────────────────────────────────────────────────────
const SOURCE = path.join(__dirname, '..', 'assets', 'expert', 'index.html');

/* Eine Zusage, die niemand annimmt, beendet unter Node den Prozess — im
   Browser loest sie `unhandledrejection` aus. Hier wird daraus dasselbe
   Ereignis, sonst maesse der Test die Regel von Node statt die der Seite. */
let raiseToPage = null;
process.on('unhandledRejection', reason => { if (raiseToPage) raiseToPage(reason); });

function boot(options) {
  const html = fs.readFileSync(SOURCE, 'utf8');
  const code = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
  buildMarkup(['board', 'tasks', 'inbox', 'state', 'rules', 'review', 'events', 'help']);

  const calls = [];
  const store = Object.assign({}, options.storage || {});
  const sandbox = {
    document: doc, console,
    navigator: { language: options.browserLanguage || 'de-DE' },
    location: { protocol: 'http:', host: 'axiom.local:8787' },
    localStorage: {
      getItem: k => (store[k] === undefined ? null : store[k]),
      setItem: (k, v) => { store[k] = String(v); },
      removeItem: k => { delete store[k]; },
    },
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    // Zeitgeber laufen nicht: Der Takt der Seite ist hier nur Rauschen, und
    // ein wartender Zeitgeber liesse den Prozess haengen.
    setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0, clearInterval() {},
    confirm: () => true,
    WebSocket: class { constructor() { this.readyState = 0; } close() {} },
    fetch: async (url, opts) => {
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      calls.push({ url, method: (opts && opts.method) || 'GET', body,
        headers: (opts && opts.headers) || {} });
      const answer = options.server(url, opts, body) || { status: 200, body: {} };
      return {
        ok: answer.status < 400,
        status: answer.status,
        json: async () => answer.body || {},
      };
    },
    /* Eine steuerbare Uhr, wenn das Szenario eine will. `new Date(x)` bleibt
       echt — nur `Date.now()` folgt dem Szenario. Ohne das waere die
       Leerlaufgrenze der Seite nur mit fuenf Minuten Wartezeit pruefbar. */
    Date: options.clock
      ? class extends Date { static now() { return options.clock(); } }
      : Date,
    Math, JSON, Map, Set, Promise, String, Number, Boolean, Array, Object,
    Error, TypeError, RegExp, encodeURIComponent, decodeURIComponent, isNaN, parseInt, parseFloat,
  };
  const windowHandlers = {};
  sandbox.addEventListener = (type, fn) => { (windowHandlers[type] = windowHandlers[type] || []).push(fn); };
  sandbox.removeEventListener = () => {};
  sandbox.globalThis = sandbox;
  sandbox.window = sandbox;
  sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: 'expert.js' });

  const flush = async () => { for (let i = 0; i < 12; i++) await new Promise(r => setImmediate(r)); };

  /* Ein Klick wie im Browser: Gibt der Handler eine Zusage zurueck und wird
     die abgelehnt, kommt sie als `unhandledrejection` am Fenster an. */
  const fire = async (node, type = 'click', ev = {}) => {
    const results = node.dispatch(type, ev);
    for (const r of results) {
      if (r && typeof r.then === 'function') {
        try { await r; } catch (reason) { raise(reason); }
      }
    }
    await flush();
  };
  const raise = reason => {
    const listeners = windowHandlers.unhandledrejection || [];
    for (const fn of listeners) fn({ reason, preventDefault() {} });
  };
  raiseToPage = raise;
  const key = async k => {
    const listeners = windowHandlers.keydown || [];
    const errors = [];
    for (const fn of listeners) {
      try { fn({ key: k, target: doc.body, preventDefault() {} }); } catch (e) { errors.push(String(e && e.message || e)); }
    }
    await flush();
    return errors;
  };

  return { sandbox, calls, store, flush, fire, key, raise, windowHandlers };
}

/* Die englischen Fassungen, direkt aus der Seite gelesen — dieselbe Tabelle,
   die `expert_i18n_test.dart` auswertet. Sie ist hier der Massstab: Steht in
   der englischen Oberflaeche ein Text, der als SCHLUESSEL in dieser Tabelle
   vorkommt, dann ist er die deutsche Fassung eines Satzes, dessen englische
   es gibt — also nicht durch tr() gegangen oder zu frueh uebersetzt. */
function englishTable() {
  const html = fs.readFileSync(SOURCE, 'utf8');
  const start = html.indexOf('const EN={');
  const body = html.slice(start + 'const EN={'.length);
  const end = body.indexOf('\n};');
  const table = new Map();
  const entry = /"((?:[^"\\]|\\.)*)":"((?:[^"\\]|\\.)*)",/g;
  let m;
  while ((m = entry.exec(body.slice(0, end)))) table.set(unescape(m[1]), unescape(m[2]));
  return table;
}
function unescape(v) {
  return v.replace(/\\"/g, '"').replace(/\\'/g, "'").replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
}

// Jeder sichtbare Text eines Baumes, einzeln — Beschriftungen von
// Bedienelementen eingeschlossen, denn ein aria-label liest jemand vor.
function visibleText(node, out = []) {
  if (!node) return out;
  if (node instanceof Text) { out.push(node._text); return out; }
  if (node instanceof Node) {
    for (const key of ['aria-label', 'placeholder', 'title']) {
      if (node.attrs[key]) out.push(node.attrs[key]);
    }
    if (node._text !== null) out.push(node._text);
  }
  for (const c of node.children || []) visibleText(c, out);
  return out;
}

// Knopf mit dieser Aufschrift, egal wie tief.
function button(root, label) {
  const hit = root.findAll('button').find(b => b.textContent.trim() === label);
  return hit || null;
}
function texts(root, selector) {
  return root.findAll(selector).map(n => n.textContent.trim());
}

// ── Die Szenarien ─────────────────────────────────────────────────────
const STATE = {
  language: 'de',
  values: { capacity: { label: 'Kapazität', value: 60 }, load_index: { label: 'Last', value: 20 } },
  loadLevel: 'L0', focus: null, running: [], startable: [], atomize: [], decision: null,
  inboxCount: 0, metaMinutesToday: 3, metaBudgetMinutes: 12,
  configLocked: false, weightsCalibrated: true,
};

function stateWith(extra) { return Object.assign({}, STATE, extra); }

const scenarios = {
  /* B15 — Fokus beenden ohne Notiz. Das Feld ist ausdruecklich optional; der
     Server lehnt einen Leerstring ab. Geprueft wird beides: dass die Seite
     „nicht angegeben" sendet, und dass eine Ablehnung sichtbar wird. */
  'focus-end-empty': async () => {
    const answers = { fail: false };
    const h = boot({
      server: (url, opts, body) => {
        if (url === '/api/state') return { status: 200, body: stateWith({ focus: { startedAt: new Date().toISOString(), plannedMinutes: 25, elapsedMinutes: 5 } }) };
        if (url === '/api/tasks') return { status: 200, body: { tasks: [] } };
        if (url === '/api/inbox') return { status: 200, body: { notes: [], tasks: [] } };
        if (url === '/api/focus' && answers.fail) return { status: 400, body: { error: 'Feld "breadcrumb" ist leer' } };
        return { status: 200, body: {} };
      },
    });
    await h.flush();
    h.sandbox.endFocusDialog();
    const dlg = stub('#dlg');
    await h.fire(button(dlg, 'Beenden'));
    const sent = h.calls.filter(c => c.url === '/api/focus');

    // Zweiter Durchgang: Der Server lehnt ab — sagt die Seite etwas?
    answers.fail = true;
    h.sandbox.endFocusDialog();
    await h.fire(button(stub('#dlg'), 'Beenden'));
    return {
      breadcrumb: sent.length ? sent[0].body.breadcrumb : 'nicht gesendet',
      method: sent.length ? sent[0].method : null,
      toast: stub('#toast').textContent,
      dialogOffen: stub('#dlg').open,
    };
  },

  /* B15, Gegenstueck — Fokus starten ohne laufende Aufgabe. */
  'focus-start-empty': async () => {
    const h = boot({
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({}) };
        if (url === '/api/tasks') return { status: 200, body: { tasks: [] } };
        if (url === '/api/inbox') return { status: 200, body: { notes: [], tasks: [] } };
        return { status: 200, body: {} };
      },
    });
    await h.flush();
    h.sandbox.focusDialog();
    await h.fire(button(stub('#dlg'), 'Starten'));
    const sent = h.calls.filter(c => c.url === '/api/focus');
    return { title: sent.length ? sent[0].body.title : 'nicht gesendet' };
  },

  /* B36 — Eine lange Notiz uebernehmen. Der Server nimmt ueber /api/capture
     4000 Zeichen an und ueber /api/tasks nur 500; ohne Kappung ist der Knopf
     tot. Der Server hier bildet genau diese Grenze nach. */
  'adopt-long-note': async () => {
    const long = 'Artikel: ' + 'x'.repeat(900);
    const h = boot({
      storage: { 'axiom.tab': 'inbox' },
      server: (url, opts, body) => {
        if (url === '/api/state') return { status: 200, body: stateWith({}) };
        if (url === '/api/inbox') return { status: 200, body: { notes: [{ id: 'C-1', at: new Date().toISOString(), text: long, via: 'share' }], tasks: [] } };
        if (url === '/api/tasks' && body && String(body.title).length > 500) {
          return { status: 400, body: { error: 'Feld "title" ist zu lang: ' + body.title.length + ' Zeichen, erlaubt sind 500' } };
        }
        return { status: 200, body: { tasks: [] } };
      },
    });
    await h.flush();
    const knopf = button(stub('#surface'), 'Als Aufgabe');
    await h.fire(knopf);
    const posts = h.calls.filter(c => c.url === '/api/tasks' && c.method === 'POST');
    return {
      gesendet: posts.length,
      laenge: posts.length ? String(posts[0].body.title).length : 0,
      volltextErhalten: posts.length ? long.startsWith(String(posts[0].body.title).replace(/ …$/, '')) : false,
      toast: stub('#toast').textContent,
    };
  },

  /* B37 — Der Zaehler am Reiter „Eingang". Der Server meldet in /api/state
     `inboxCount: 0` (Aufgaben im Zustand inbox — eine Menge, die auf keinem
     Weg entsteht), waehrend drei Notizen zu sortieren sind. */
  /* Was als Zeit im System zaehlt (G4). Ein Reiter im Hintergrund fragt
     weiter — der Server bucht den Abstand zwischen zwei Anfragen, und ein
     Tag ohne einen einzigen Blick buchte sich damit voll. Geprueft wird der
     Kopf, den die Seite mitschickt, weil an ihm die Buchung haengt. */
  'meta-attention': async () => {
    let jetzt = 1000000;
    const h = boot({
      clock: () => jetzt,
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({}) };
        if (url === '/api/inbox') return { status: 200, body: { notes: [], tasks: [] } };
        return { status: 200, body: { tasks: [] } };
      },
    });
    await h.flush();

    const kopf = () => {
      const last = h.calls[h.calls.length - 1];
      return (last.headers || {})['X-Axiom-Attended'];
    };
    /* Genau der Weg, um den es geht: der eigene Takt der Seite. Nicht
       `key('r')` — ein Tastendruck ist selbst eine Regung und setzte die
       Leerlaufuhr zurueck, die hier gemessen werden soll. */
    const laden = async () => { await h.sandbox.sync(); await h.flush(); };

    const antwort = {};

    // Sichtbar, im Vordergrund, gerade erst geladen.
    await laden();
    antwort.davor = kopf();

    // Reiter in den Hintergrund.
    h.sandbox.document.visibilityState = 'hidden';
    await laden();
    antwort.hintergrund = kopf();

    // Wieder sichtbar, aber ein anderes Fenster hat den Fokus — der Fall
    // „Uebersicht auf dem zweiten Bildschirm, gearbeitet wird woanders".
    h.sandbox.document.visibilityState = 'visible';
    h.sandbox.document._focused = false;
    await laden();
    antwort.danebengeklickt = kopf();

    // Zurueck, aber seit sechs Minuten keine Regung.
    h.sandbox.document._focused = true;
    jetzt += 6 * 60 * 1000;
    await laden();
    antwort.leerlauf = kopf();

    // Eine Mausbewegung genuegt, um wieder mitzuzaehlen.
    const bewegen = h.windowHandlers.pointermove || [];
    for (const fn of bewegen) fn({});
    await laden();
    antwort.wiederda = kopf();
    antwort.hatMelder = bewegen.length > 0;

    return antwort;
  },

  'inbox-badge': async () => {
    const notes = [1, 2, 3].map(i => ({ id: 'C-' + i, at: new Date().toISOString(), text: 'Notiz ' + i, via: 'quick' }));
    const h = boot({
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({ inboxCount: 0 }) };
        if (url === '/api/inbox') return { status: 200, body: { notes, tasks: [] } };
        return { status: 200, body: { tasks: [] } };
      },
    });
    await h.flush();
    return { badge: stub('#c-inbox').textContent, notizen: notes.length };
  },

  /* B38 — Der Browser steht auf Deutsch, die App auf Englisch. Die
     Gruppenbeschriftung wurde beim Laden uebersetzt, also bevor die Sprache
     vom Telefon da war. */
  'group-labels': async () => {
    const h = boot({
      browserLanguage: 'de-DE',
      storage: { 'axiom.tab': 'board' },
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({ language: 'en' }) };
        if (url === '/api/tasks') return { status: 200, body: { tasks: [{ id: 'T-1', title: 'Tax papers', state: 'ready', activationEnergy: 3, salience: 5, stakes: 5 }] } };
        if (url === '/api/inbox') return { status: 200, body: { notes: [], tasks: [] } };
        return { status: 200, body: {} };
      },
    });
    await h.flush();
    return {
      sprache: h.sandbox.LANG === undefined ? 'unbekannt' : h.sandbox.LANG,
      baender: texts(stub('#surface'), '.gname'),
      ariaLabels: stub('#surface').findAll('.group').map(g => g.getAttribute('aria-label')),
    };
  },

  /* B38/B39 — Dieselbe Frage fuer die Vergleichsliste im Regeleditor. */
  'operator-labels': async () => {
    const h = boot({
      browserLanguage: 'de-DE',
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({ language: 'en' }) };
        return { status: 200, body: { tasks: [] } };
      },
    });
    await h.flush();
    return { labels: h.sandbox.opItems(false).map(o => o.l) };
  },

  /* B40 — Zweimal auf „Als Aufgabe", solange die erste Anfrage laeuft. */
  'double-adopt': async () => {
    const h = boot({
      storage: { 'axiom.tab': 'inbox' },
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({}) };
        if (url === '/api/inbox') return { status: 200, body: { notes: [{ id: 'C-1', at: new Date().toISOString(), text: 'Steuerunterlagen sortieren', via: 'quick' }], tasks: [] } };
        return { status: 200, body: { tasks: [] } };
      },
    });
    await h.flush();
    const knopf = button(stub('#surface'), 'Als Aufgabe');
    // Beide Klicks fallen in dasselbe Zeitfenster: Der zweite kommt, bevor
    // die Antwort auf den ersten da ist.
    const erster = knopf.dispatch('click');
    const zwischenstand = knopf.disabled;
    const zweiter = knopf.dispatch('click');
    for (const r of [...erster, ...zweiter]) if (r && r.then) { try { await r; } catch (e) { h.raise(e); } }
    await h.flush();
    return {
      posts: h.calls.filter(c => c.url === '/api/tasks' && c.method === 'POST').length,
      gesperrtWaehrendAnfrage: zwischenstand,
    };
  },

  /* B59 — Zerlegen mit mehr Schritten, als der Kern annimmt. */
  'atomize-limit': async () => {
    const h = boot({
      server: (url, opts, body) => {
        if (url === '/api/state') return { status: 200, body: stateWith({}) };
        if (String(url).endsWith('/atomize')) {
          if (body.steps.length > 20) return { status: 400, body: { error: 'Höchstens 20 Schritte je Zerlegung, angefragt: ' + body.steps.length } };
          return { status: 200, body: { ok: true } };
        }
        return { status: 200, body: { tasks: [] } };
      },
    });
    await h.flush();
    h.sandbox.atomizeDialog({ taskId: 'T-1', title: 'Steuererklärung' });
    const dlg = stub('#dlg');
    const plus = button(dlg, '+ Schritt');
    for (let i = 0; i < 30; i++) await h.fire(plus);
    const felder = dlg.findAll('.field');
    for (const f of felder) f.querySelector('input[type=text]').value = 'Schritt';
    await h.fire(button(dlg, 'Übernehmen'));
    const sent = h.calls.filter(c => String(c.url).endsWith('/atomize'));
    return {
      zeilen: felder.length,
      plusGesperrt: plus.disabled === true,
      geschickt: sent.length ? sent[0].body.steps.length : 0,
      toast: stub('#toast').textContent,
    };
  },

  /* B60 — Kuerzel auf der Anmeldeseite. Ohne Sitzung ist nichts fokussiert,
     also greift jedes Kuerzel. */
  'keys-on-gate': async () => {
    const h = boot({
      server: url => {
        if (url === '/api/auth/request') return { status: 200, body: { id: 'A-1', number: '42' } };
        return { status: 401, body: { error: 'Nicht angemeldet' } };
      },
    });
    await h.flush();
    const fehler = [];
    const blaetter = [];
    let aufrufe = 0;
    // Jede Taste einzeln: Ein offenes Blatt sperrt die naechste Taste, und
    // dann pruefte man nur noch die Sperre.
    for (const k of ['f', 'c', 'a', 'n', 'r', '1', '3', '7']) {
      const vorher = h.calls.length;
      fehler.push(...await h.key(k));
      if (stub('#dlg').open) { blaetter.push(k); stub('#dlg').close(); }
      aufrufe += h.calls.length - vorher;
    }
    return {
      gateSichtbar: !stub('#gate').classList.contains('hide'),
      fehler,
      blaetter,
      aufrufe,
      fokusImVerstecktenFeld: doc.activeElement !== null,
      gespeicherterReiter: h.store['axiom.tab'] || null,
    };
  },

  /* B61 — Reiterwechsel, waehrend der Server nicht antwortet. */
  'tab-load-fails': async () => {
    const kaputt = { on: false };
    const h = boot({
      storage: { 'axiom.tab': 'board' },
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({}) };
        if (url.startsWith('/api/events')) {
          return kaputt.on ? { status: 503, body: { error: 'Der Server antwortet nicht.' } } : { status: 200, body: { events: [] } };
        }
        if (url === '/api/inbox') return { status: 200, body: { notes: [], tasks: [] } };
        return { status: 200, body: { tasks: [{ id: 'T-1', title: 'Steuerunterlagen', state: 'ready', activationEnergy: 3, salience: 5, stakes: 5 }] } };
      },
    });
    await h.flush();
    kaputt.on = true;
    const reiter = stub('#tabs').findAll('button').find(b => b.dataset.tab === 'events');
    await h.fire(reiter);
    const markiert = stub('#tabs').findAll('button')
      .filter(b => b.getAttribute('aria-selected') === 'true').map(b => b.dataset.tab);
    return {
      markiert,
      gespeichert: h.store['axiom.tab'],
      flaeche: stub('#surface').textContent.includes('Steuerunterlagen') ? 'board' : 'anderes',
      toast: stub('#toast').textContent,
    };
  },

  /* B63 — Die Hilfe oeffnet in der Sprache der Oberflaeche, solange niemand
     dort ausdruecklich gewaehlt hat. */
  'help-language': async () => {
    const h = boot({
      browserLanguage: 'de-DE',
      storage: { 'axiom.tab': 'help' },
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({ language: 'en' }) };
        if (url.startsWith('/api/help/')) return { status: 200, body: { id: '01', title: 'What this is', markdown: '# What this is' } };
        if (url.startsWith('/api/help')) return { status: 200, body: { chapters: [{ id: '01', title: 'What this is' }] } };
        return { status: 200, body: { tasks: [], notes: [] } };
      },
    });
    await h.flush();
    const gefragt = h.calls.filter(c => c.url.startsWith('/api/help')).map(c => c.url);
    return { gefragt };
  },

  /* B38/B39 als Ganzes — der Waechter, den es vorher nicht gab.

     Die Seite laeuft auf Englisch, alles vom Server ist englisch. Danach
     wird jede Flaeche und jedes Blatt gezeichnet und der sichtbare Text
     gegen die Schluessel der EN-Tabelle gehalten: Jeder Treffer ist ein
     deutscher Satz, dessen englische Fassung es gibt — also entweder nicht
     durch tr() gegangen oder zu frueh uebersetzt. Der Quelltextwaechter in
     `expert_i18n_test.dart` sah nur Umlaute und liess „leer", „voll",
     „sofort", „von", „bis", „mindestens" und „genau" durch. */
  'german-leak': async () => {
    const h = boot({
      browserLanguage: 'de-DE',
      storage: { 'axiom.tab': 'board', 'axiom.tasks.done': '1' },
      server: url => {
        if (url === '/api/state') {
          return { status: 200, body: stateWith({
            language: 'en',
            values: { capacity: { label: 'Capacity', value: 60 }, load_index: { label: 'Load', value: 20 } },
            breakdown: { load_index: [{ label: 'Sleep debt', contribution: 4 }] },
            startable: [{ id: 'T-1', title: 'Tax papers', state: 'ready', activationEnergy: 3, salience: 5, stakes: 5 }],
          }) };
        }
        if (url === '/api/tasks') return { status: 200, body: { tasks: [{ id: 'T-1', title: 'Tax papers', state: 'ready', activationEnergy: 3, salience: 5, stakes: 5 }] } };
        if (url === '/api/inbox') return { status: 200, body: { notes: [{ id: 'C-1', at: new Date().toISOString(), text: 'Read something', via: 'quick' }], tasks: [] } };
        if (url === '/api/rules') return { status: 200, body: { rules: [{ id: 'R-010', title: 'Config lock', severity: 'nudge', deficit: 'D3', yaml: '- id: R-010\n' }], issues: [] } };
        if (url.startsWith('/api/review')) return { status: 200, body: { scope: 'day', values: [], events: [] } };
        if (url.startsWith('/api/events')) return { status: 200, body: { events: [{ at: new Date().toISOString(), type: 'capture', payload: {} }] } };
        if (url.startsWith('/api/help/')) return { status: 200, body: { id: '01', title: 'What this is', markdown: '# What this is' } };
        if (url.startsWith('/api/help')) return { status: 200, body: { chapters: [{ id: '01', title: 'What this is' }] } };
        if (url === '/api/vocabulary') {
          return { status: 200, body: {
            numerics: [{ id: 'capacity', label: 'Capacity', min: 0, max: 100 }],
            symbolics: [{ id: 'load_level', label: 'Load level', values: { L0: 'L0', L2: 'L2' } }],
            events: [{ id: 'checkin', label: 'Check-in' }],
            actions: [{ type: 'nudge', label: 'Nudge', params: {} }],
            severities: [{ id: 'log_only', label: 'log only' }],
            deficits: [{ id: 'D3', label: 'Meta work' }],
            operators: { numeric: ['lt', 'lte', 'gte', 'gt'], symbolic: ['eq', 'ne'] },
            operatorLabels: {},
          } };
        }
        return { status: 200, body: {} };
      },
    });
    await h.flush();
    const table = englishTable();
    const seen = [];
    const collect = node => {
      for (const raw of visibleText(node)) {
        const text = String(raw).trim();
        if (!text) continue;
        if (table.has(text) && table.get(text) !== text && !seen.includes(text)) seen.push(text);
      }
    };
    collect(stub('#hchips'));
    collect(stub('#act'));
    collect(stub('#cap-note'));
    for (const name of ['board', 'tasks', 'inbox', 'state', 'rules', 'review', 'events', 'help']) {
      const b = stub('#tabs').findAll('button').find(x => x.dataset.tab === name);
      await h.fire(b);
      collect(stub('#surface'));
    }
    for (const open of ['checkinDialog', 'taskDialog', 'focusDialog', 'endFocusDialog', 'keysDialog']) {
      h.sandbox[open]();
      collect(stub('#dlg'));
      stub('#dlg').close();
    }
    h.sandbox.atomizeDialog({ taskId: 'T-1', title: 'Tax papers' });
    collect(stub('#dlg'));
    stub('#dlg').close();
    // Der Regeleditor ist die groesste deutsche Flaeche der Seite. Jede Art
    // von Bedingung zeichnet andere Felder — „von/bis" und „Minuten" stehen
    // nur in zweien davon.
    const rulesTab = stub('#tabs').findAll('button').find(x => x.dataset.tab === 'rules');
    await h.fire(rulesTab);
    await h.sandbox.openEditor(null);
    await h.flush();
    collect(stub('#surface'));
    for (const kind of ['time', 'since', 'count', 'choice']) {
      const picker = stub('#surface').findAll('select')
        .find(s => s.findAll('option').some(o => o.attrs.value === 'time'));
      if (!picker) continue;
      picker.dispatch('change', { target: { value: kind } });
      await h.flush();
      collect(stub('#surface'));
    }
    return { deutschInEnglisch: seen };
  },

  /* B63, Gegenprobe — eine getroffene Wahl gewinnt weiterhin. */
  'help-language-chosen': async () => {
    const h = boot({
      storage: { 'axiom.tab': 'help', 'axiom.help.lang': 'de' },
      server: url => {
        if (url === '/api/state') return { status: 200, body: stateWith({ language: 'en' }) };
        if (url.startsWith('/api/help/')) return { status: 200, body: { id: '01', title: 'Was das ist', markdown: '# Was das ist' } };
        if (url.startsWith('/api/help')) return { status: 200, body: { chapters: [{ id: '01', title: 'Was das ist' }] } };
        return { status: 200, body: { tasks: [], notes: [] } };
      },
    });
    await h.flush();
    return { gefragt: h.calls.filter(c => c.url.startsWith('/api/help')).map(c => c.url) };
  },
};

const name = process.argv[2];
if (!scenarios[name]) {
  console.log(JSON.stringify({ error: 'Unbekanntes Szenario: ' + name, bekannt: Object.keys(scenarios) }));
  process.exit(2);
}
scenarios[name]()
  .then(r => { console.log(JSON.stringify(r)); })
  .catch(e => { console.log(JSON.stringify({ error: String(e && e.stack || e) })); process.exit(3); });

/* ── Kliner's window ─────────────────────────────────────────────────────

   This page is the window. It draws; it never decides what runs. Every
   request it makes names a page by number, and the Swift side looks the
   command up in its own list, asks you with a real macOS dialog before
   anything changes, and only then runs nimo. There is no way from here to
   hand nimo an argument, open a URL, or reach the network.              */

/* ── talking to the app ───────────────────────────────────────────────── */

const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.kliner;
let serial = 0;
const owed = new Map();

/** Ask the app for something and wait for its answer. */
function ask(op, args) {
    return new Promise(resolve => {
        if (!native) { resolve({ ok: false, text: '', missing: true }); return; }
        const id = ++serial;
        owed.set(id, resolve);
        native.postMessage(Object.assign({}, args || {}, { id, op }));
    });
}

/** Tell the app something that needs no answer. */
function tell(op, args) {
    if (native) native.postMessage(Object.assign({}, args || {}, { id: 0, op }));
}

/* ── what the window knows ────────────────────────────────────────────── */

const K = {
    meta: null,
    page: -1,
    behind: [],
    ahead: [],
    kept: {},           // page → what it last said
    wallOn: 0,          // the one put on from this window
    walls: null,        // the wallpapers, read once
    wallPics: null,     // and small pictures of them, drawn by the Mac
    busy: false,
    walked: [],         // how far into a folder you have clicked
    walkedFrom: -1,
    preview: false,
    wide: false,
    jobs: [],           // what Kliner has done since it opened
    unread: false,
    lastRead: 0,
    sighted: true,
    welcome: null,
    home: null,         // the figures Home read, for the rail and ⌘K
};

const $ = sel => document.querySelector(sel);
const pages = () => (K.meta ? K.meta.pages : []);
const SETTINGS = () => pages().length;
const HELP = () => pages().length + 1;
const ACTIVITY = () => pages().length + 2;
const isAction = i => i >= 0 && i < pages().length;
const kind = i => (isAction(i) ? pages()[i].kind : i === SETTINGS() ? 'settings' : i === ACTIVITY() ? 'activity' : 'help');

function titleOf(i) {
    if (isAction(i)) return pages()[i].title;
    return i === SETTINGS() ? 'Settings' : i === ACTIVITY() ? 'Activity' : 'Help';
}
function placeOf(i) {
    return (K.meta.places || []).find(p => p.holds.includes(i)) || null;
}

/* ── the frame ────────────────────────────────────────────────────────── */

function drawFrame() {
    const app = $('#app');
    app.replaceChildren();
    app.className = 'app' + (K.wide ? ' wide' : '');

    // the rail: every place, then Settings and Help at the foot
    const places = h('div', { class: 'places' });
    for (const place of K.meta.places) {
        const first = place.holds[0];
        const spot = h('button', {
            class: 'spot', 'data-page': first, 'data-tip': place.title,
            onclick: () => show(first),
        }, icon(place.symbol), h('span', { class: 'label' }, place.title));
        places.append(spot);
        if (place.holds.length > 1) {
            const kids = h('div', { class: 'kids' });
            for (const i of place.holds) {
                kids.append(h('button', { class: 'kid', 'data-kid': i, onclick: () => show(i) }, titleOf(i)));
            }
            places.append(kids);
        }
    }
    const foot = h('div', { class: 'foot' },
        h('button', { class: 'spot', 'data-page': HELP(), 'data-tip': 'Help', onclick: () => show(HELP()) },
          icon('help'), h('span', { class: 'label' }, 'Help')),
        h('button', { class: 'spot', 'data-page': SETTINGS(), 'data-tip': 'Settings', 'data-keys': '⌘,',
                      onclick: () => show(SETTINGS()) },
          icon('gear'), h('span', { class: 'label' }, 'Settings')));
    const rail = h('nav', { class: 'rail' }, h('i', { class: 'mark', id: 'railmark' }),
                   h('div', { class: 'logo', 'data-tip': 'Kliner' }, eyesMark()), places, foot);

    // the bar along the top
    const bar = h('header', { class: 'bar' },
        h('div', { class: 'nav' },
            h('button', { class: 'sq', id: 'fold', 'data-hole': '', 'data-tip': 'Show names', 'data-keys': '⌘B', onclick: fold }, icon('sidebar')),
            h('button', { class: 'sq', id: 'back', 'data-hole': '', 'data-tip': 'Back', 'data-keys': '⌘[', onclick: back }, icon('left')),
            h('button', { class: 'sq', id: 'fwd', 'data-hole': '', 'data-tip': 'Forward', 'data-keys': '⌘]', onclick: forward }, icon('right'))),
        h('div', { class: 'where', id: 'where' }),
        h('div', { class: 'right' },
            h('button', { class: 'age', id: 'age', 'data-hole': '', 'data-tip': 'Read it again',
                          onclick: () => { delete K.kept[K.page]; look(K.page); } },
              h('i', { class: 'live' }), h('span', { id: 'ageSaid' })),
            h('button', { class: 'mode', id: 'mode', 'data-hole': '', onclick: flipPreview,
                          'data-tip': 'Show what would happen, change nothing' },
              icon('eye'), h('span', null, 'Preview')),
            h('button', { class: 'sq', 'data-hole': '', 'data-tip': 'Search', 'data-keys': '⌘K', onclick: () => tell('quick') },
              icon('search')),
            h('button', { class: 'bell', id: 'bell', 'data-hole': '', 'data-tip': 'History', onclick: toggleActivity },
              icon('bell'))));

    const scroll = h('div', { class: 'scroll', id: 'scroll' }, h('div', { class: 'page', id: 'page' }));
    app.append(rail, h('main', { class: 'main' }, bar, scroll));

    wireTips(app);
    setFrame();
    reportChrome();
}

/** Everything in the frame that depends on where you are. */
function setFrame() {
    const i = K.page;
    for (const spot of document.querySelectorAll('.spot')) {
        const n = parseInt(spot.dataset.page, 10);
        const place = placeOf(i);
        spot.classList.toggle('on', place ? place.holds[0] === n : n === i);
    }
    for (const kid of document.querySelectorAll('.kid')) {
        kid.classList.toggle('on', parseInt(kid.dataset.kid, 10) === i);
    }
    const mark = $('#railmark'), onSpot = document.querySelector('.spot.on');
    if (mark && onSpot) {
        mark.style.opacity = 1;
        mark.style.transform = `translateY(${onSpot.offsetTop + onSpot.offsetHeight / 2 - 10}px)`;
    } else if (mark) mark.style.opacity = 0;

    const where = $('#where');
    if (where) {
        where.replaceChildren();
        const place = placeOf(i);
        const symbol = place ? place.symbol : (i === SETTINGS() ? 'gear' : 'help');
        where.append(icon(symbol));
        if (i === 0) {
            where.append(h('span', { class: 'name' }, 'Overview'));
        } else if (place && place.holds.length > 1) {
            where.append(h('span', { class: 'group' }, place.title));
            // No pill sliding between them. It measured, waited a frame and
            // moved on every single draw, which is a strip that never sits
            // still. The one that is on is simply the one that is on.
            const tabs = h('div', { class: 'tabs', 'data-hole': '' });
            for (const n of place.holds) {
                tabs.append(h('button', { class: 'tab' + (n === i ? ' on' : ''), onclick: () => show(n) }, titleOf(n)));
            }
            where.append(tabs);
        } else {
            where.append(h('span', { class: 'name' }, titleOf(i)));
        }
        const reveal = isAction(i) ? pages()[i].reveal : '';
        const trail = K.walked.length && K.walked[0] === reveal ? K.walked.slice(1) : K.walked;
        if (trail.length) {
            where.append(h('span', { class: 'slash' }, '/'),
                         h('span', { class: 'group' }, trail.join(' / ')));
        }
    }

    const backBtn = $('#back'), fwdBtn = $('#fwd');
    if (backBtn) backBtn.disabled = !K.behind.length && !K.walked.length;
    if (fwdBtn) fwdBtn.disabled = !K.ahead.length;
    const mode = $('#mode');
    if (mode) mode.classList.toggle('on', K.preview);
    const bell = $('#bell');
    if (bell) {
        const dot = bell.querySelector('.dot');
        if (K.unread && !dot) bell.append(h('span', { class: 'dot' }));
        if (!K.unread && dot) dot.remove();
    }
    tally();
    sayAge();
    reportChrome();
}

/** The count on a place: how many things are waiting there. */
function tally() {
    const f = K.home;
    for (const spot of document.querySelectorAll('.spot')) {
        spot.querySelector('.count')?.remove();
        if (!f) continue;
        const n = parseInt(spot.dataset.page, 10);
        const place = (K.meta.places || []).find(p => p.holds[0] === n);
        if (!place) continue;
        let many = 0;
        if (place.holds.includes(1)) many += f.desk || 0;
        if (place.holds.includes(2)) many += f.downloads || 0;
        if (many > 0) spot.append(h('span', { class: 'count' }, many > 999 ? '999+' : String(many)));
    }
}

function sayAge() {
    const age = $('#age'), said = $('#ageSaid');
    if (!age || !said) return;
    // A dot and a short age, not a sentence. The dot is lit while the
    // reading is fresh and goes quiet as it gets old, so the strip says
    // how current the page is without anyone reading it.
    if (!K.lastRead || !isAction(K.page)) { age.style.display = 'none'; return; }
    age.style.display = '';
    const gone = Math.round((Date.now() - K.lastRead) / 1000);
    said.textContent = gone < 60 ? 'just now'
        : gone < 5400 ? Math.round(gone / 60) + 'm'
        : Math.round(gone / 3600) + 'h';
    age.classList.toggle('stale', gone >= 300);
}
setInterval(sayAge, 5000);

/** Where the window can be dragged by: the top 52 points, less anything
 *  in them you can press. The app does the dragging; this only says where. */
let chromeTimer = 0;
function reportChrome() {
    clearTimeout(chromeTimer);
    chromeTimer = setTimeout(() => {
        const holes = [];
        for (const el of document.querySelectorAll('[data-hole], .bar button, .welcome .way button')) {
            const r = el.getBoundingClientRect();
            if (r.width > 0 && r.height > 0 && r.top < 52) holes.push([r.left, r.top, r.width, r.height]);
        }
        // the page number rides along: if the page's process is jettisoned
        // after a long idle, the app draws it again on the page you were on
        tell('chrome', { height: 52, holes, page: K.page });
    }, 30);
}
window.addEventListener('resize', reportChrome);

/* ── tooltips, for a rail of pictures ─────────────────────────────────── */

let tipTimer = 0;
function wireTips(root) {
    for (const el of root.querySelectorAll('[data-tip]')) {
        el.addEventListener('mouseenter', () => {
            clearTimeout(tipTimer);
            tipTimer = setTimeout(() => showTip(el), el.closest('.rail') ? 250 : 600);
        });
        el.addEventListener('mouseleave', hideTip);
        el.addEventListener('mousedown', hideTip);
    }
}
function showTip(el) {
    if (el.closest('.rail') && K.wide) return;
    const tip = $('#tip');
    tip.replaceChildren(el.dataset.tip, el.dataset.keys ? h('kbd', null, el.dataset.keys) : null);
    const r = el.getBoundingClientRect();
    tip.classList.add('show');
    const w = tip.offsetWidth, th = tip.offsetHeight;
    if (el.closest('.rail')) {
        tip.style.left = (r.right + 10) + 'px';
        tip.style.top = (r.top + r.height / 2 - th / 2) + 'px';
    } else {
        tip.style.left = Math.min(window.innerWidth - w - 8, Math.max(8, r.left + r.width / 2 - w / 2)) + 'px';
        tip.style.top = (r.bottom + 8) + 'px';
    }
}
function hideTip() { clearTimeout(tipTimer); $('#tip').classList.remove('show'); }

/* ── going places ─────────────────────────────────────────────────────── */

function show(i, opts) {
    const remember = !opts || opts.remember !== false;
    if (!K.meta || K.welcome) return;
    if (i < 0 || i > ACTIVITY()) return;
    closeActivity();
    closeLight();
    hideTip();
    if (remember && i !== K.page && K.page >= 0) { K.behind.push(K.page); K.ahead = []; }
    const same = i === K.page;
    K.page = i;
    K.walked = [];
    setFrame();
    if (!same) $('#scroll').scrollTop = 0;
    if (!isAction(i)) { drawPage(); return; }
    const kept = K.kept[i];
    if (kept) {
        drawPage();
        // the fast half of Home, and a reading kept from last time, are both
        // stand-ins: the real one is asked for as soon as the page is up
        if (i === 0 && (kept.fast || kept.old)) setTimeout(() => look(0, true), 60);
        return;
    }
    look(i);
}

function back() {
    if (K.walked.length) { walkUp(); return; }
    if (!K.behind.length) return;
    K.ahead.push(K.page);
    show(K.behind.pop(), { remember: false });
}
function forward() {
    if (!K.ahead.length) return;
    K.behind.push(K.page);
    show(K.ahead.pop(), { remember: false });
}
function fold() {
    K.wide = !K.wide;
    tell('setConfig', { key: 'rail', value: K.wide ? 'list' : 'icons' });
    drawFrame();
    drawPage(true);
}
function flipPreview() {
    K.preview = !K.preview;
    tell('setConfig', { key: 'preview', value: K.preview ? 'on' : 'off' });
    setFrame();
    drawPage(true);
}

/* ── reading and doing ────────────────────────────────────────────────── */

async function look(i, quietly) {
    if (K.busy && !quietly) { K.owedLook = i; drawWaiting(i); return; }
    if (K.busy) return;
    const fast = i === 0 && !K.kept[0];
    K.busy = true;
    if (!quietly) drawWaiting(i);
    let reply;
    try {
        reply = await ask('look', { page: i, fast });
    } finally {
        K.busy = false;
    }
    if (reply.missing) reply = { ok: false, text: '! Kliner did not answer. Try again.' };

    if (reply.ready) {
        K.kept[i] = { ready: true, at: Date.now() };
    } else {
        K.kept[i] = { pieces: parse(reply.text), ok: reply.ok, at: Date.now(), fast };
    }
    if (typeof reply.sighted === 'boolean') K.sighted = reply.sighted;
    if (i === 0 || kind(i) === 'doctor') readHome(K.kept[i].pieces || []);
    K.lastRead = Date.now();

    // a page opened while this one was running is owed its own reading
    if (K.owedLook != null && K.owedLook !== i) {
        const owedPage = K.owedLook;
        K.owedLook = null;
        if (owedPage === K.page) { look(owedPage); return; }
    }
    K.owedLook = null;
    if (i === K.page) drawPage(quietly);

    // Home in two halves: the instant readings first, then the one that
    // walks every cache on the disk
    if (fast && i === 0) setTimeout(() => look(0, true), 60);

    // the wallpapers come from their own, harmless reading
    if (kind(i) === 'next' && !K.walls) readWalls();
}

/** The one that was clicked goes on the screen. */
async function putOnWall(at) {
    if (K.busy) return;
    K.busy = true;
    busyButtons(true);
    let reply;
    try {
        reply = await ask('setWall', { at });
    } finally {
        K.busy = false;
        busyButtons(false);
    }
    if (!reply || !reply.ok) return;
    K.wallOn = at;
    afterRun(K.page, reply, 'Wallpaper', true);
    drawPage(true);
}

async function readWalls() {
    const reply = await ask('walls');
    if (!reply || !reply.text) return;
    K.walls = parse(reply.text).filter(p => p.k === 'item');
    if (kind(K.page) === 'next') drawPage(true);
    // The pictures take a moment, so the names go up first and the
    // pictures fill in behind them.
    const seen = await ask('wallPictures');
    K.wallPics = (seen && seen.pictures) || {};
    if (kind(K.page) === 'next') drawPage(true);
}

/** The big button on a page. The app asks first; this only waits. */
async function act(i) {
    if (K.busy || !isAction(i)) return;
    K.busy = true;
    busyButtons(true);
    let reply;
    try {
        reply = await ask('go', { page: i, preview: K.preview });
    } finally {
        K.busy = false;
    }
    busyButtons(false);
    if (reply.cancelled || reply.missing) return;
    afterRun(i, reply, pages()[i].verb);
}

async function extra(i, n) {
    if (K.busy || !isAction(i)) return;
    const ex = pages()[i].extras[n];
    if (!ex) return;
    K.busy = true;
    busyButtons(true);
    let reply;
    try {
        reply = await ask('extra', { page: i, index: n, preview: K.preview });
    } finally {
        K.busy = false;
    }
    busyButtons(false);
    if (reply.cancelled || reply.missing) return;
    afterRun(i, reply, ex.title);
}

/** Desktop and Downloads behind one question. */
async function tidyBoth(which) {
    if (K.busy) return;
    K.busy = true;
    busyButtons(true);
    let reply;
    try {
        reply = await ask('tidy', { pages: which, preview: K.preview });
    } finally {
        K.busy = false;
    }
    busyButtons(false);
    if (reply.cancelled || reply.missing || !reply.results) return;
    for (const one of reply.results) afterRun(one.page, one, pages()[one.page].verb, true);
    const said = reply.results.map(one => (parse(one.text).find(p => p.k === 'good') || {}).text).filter(Boolean);
    delete K.kept[0];
    show(0);
    if (said.length) toast(which.length > 1 ? swept(reply.results) || said.join(' \u00b7 ') : said.join(' \u00b7 '), null);
}

/* several places tidied at once, said once: the counts each one reported, added up */
function swept(results) {
    let filed = 0, freed = '', heard = 0;
    for (const one of results) {
        const good = (parse(one.text).find(p => p.k === 'good') || {}).text;
        if (!good) continue;
        heard++;
        const items = good.match(/(\d[\d,]*)\s+items?\b/);
        if (items) filed += parseInt(items[1].replace(/,/g, ''), 10);
        const size = good.match(/(\d[\d.]*\s?[KMGT]B)\b/);
        if (size && kind(one.page) === 'clean') freed = size[1];
    }
    if (!heard) return '';
    const bits = [];
    if (filed) bits.push(filed + (filed === 1 ? ' item filed away' : ' items filed away'));
    if (freed) bits.push(freed + ' freed');
    return bits.join(', ');
}

function afterRun(i, reply, what, quiet) {
    const pieces = parse(reply.text);
    const good = pieces.find(p => p.k === 'good');
    const warn = pieces.find(p => p.k === 'warn');
    K.kept[i] = { pieces, ok: reply.ok, at: Date.now(), result: true, changed: !!reply.changed, preview: !!reply.preview };
    K.lastRead = Date.now();
    if (reply.changed) {
        K.copies = {};
        // what changed changes the readings of Home and the log of what was done
        for (const n of Object.keys(K.kept)) {
            if (+n !== i) delete K.kept[n];
        }
        if (kind(i) === 'next' && K.walls) readWalls();
    }
    const line = good ? good.text : warn ? warn.text : (reply.ok ? 'Done' : 'That did not work');
    K.jobs.unshift({ page: i, title: titleOf(i), line, good: !!good && reply.ok, at: new Date(), preview: !!reply.preview });
    K.jobs = K.jobs.slice(0, 30);
    if (reply.changed) K.unread = true;
    setFrame();
    if (!quiet && i === K.page) drawPage();
    // somewhere else, say so; here, the banner says it
    if (!quiet && reply.changed && good && i !== K.page) toast(good.text, null);
}

async function walk(path) {
    if (K.busy) return;
    K.walked = path;
    K.walkedFrom = K.page;
    setFrame();
    K.busy = true;
    drawWaiting(K.page, path[path.length - 1]);
    let reply;
    try {
        reply = await ask('walk', { path });
    } finally {
        K.busy = false;
    }
    if (reply.missing || K.walked !== path) return;
    K.walkedPieces = parse(reply.text);
    K.lastRead = Date.now();
    setFrame();
    drawPage();
}
function walkInto(name) { walk(K.walked.concat([name])); }
function walkUp() {
    const path = K.walked.slice(0, -1);
    if (!path.length) {
        K.walked = [];
        setFrame();
        drawPage();
        return;
    }
    walk(path);
}

/** A file in a folder you have walked into: shown in the Finder, never
 *  opened — a cleaner that launches things is not one anybody trusts. */
function revealThing(name) {
    tell('show', { path: K.walked.concat([name]) });
}

async function stopOne(name) {
    if (K.busy) return;
    K.busy = true;
    busyButtons(true);
    let reply;
    try {
        reply = await ask('stop', { name });
    } finally {
        K.busy = false;
    }
    busyButtons(false);
    if (reply.cancelled || reply.missing) return;
    afterRun(K.page, reply, 'Stop ' + name);
}

function busyButtons(on) {
    for (const b of document.querySelectorAll('.page .btn, .page .todo button')) {
        if (on) { b.dataset.was = b.disabled ? '1' : ''; b.disabled = true; }
        else { b.disabled = b.dataset.was === '1'; }
    }
    for (const b of document.querySelectorAll('.page .btn.fill')) b.classList.toggle('working', on);
}

/* ── Home's figures, read once and used everywhere ────────────────────── */

function readHome(pieces) {
    const f = facts(pieces);
    if (!f.Disk && !f.Desktop) return;
    let total = 0, free = 0;
    if (f.Disk) {
        const [a, b] = f.Disk.value.split(' of ');
        free = bytes((a || '').replace(/\s*free$/, '')) || 0;
        total = bytes(b) || 0;
    }
    const junk = f.Junk ? bytes(f.Junk.value) : null;
    const home = {
        total, free, used: Math.max(0, total - free), junk,
        desk: f.Desktop ? count(f.Desktop.value) : null,
        downloads: f.Downloads ? count(f.Downloads.value) : null,
        trash: f.Trash ? count(f.Trash.value) : null,
        deskOld: f['Desktop older'] ? f['Desktop older'].value : '',
        downloadsOld: f['Downloads older'] ? f['Downloads older'].value : '',
        months: f.Months ? f.Months.value.split(',').map(x => parseFloat(x)).filter(x => !isNaN(x)) : [],
        last: f['Last change'] ? f['Last change'].value : '',
        f,
    };
    // the fast half has no junk figure; keep the last one rather than a hole
    if (home.junk == null && K.home && K.home.junk != null) home.junk = K.home.junk;
    K.home = home;

    // and hand the menu behind ⌘K the same readings
    const figures = {};
    if (f.Desktop) figures['1'] = f.Desktop.value;
    if (f.Downloads) figures['2'] = f.Downloads.value;
    const cleanPage = pages().findIndex(p => p.kind === 'clean');
    if (home.junk > 0 && cleanPage >= 0) figures[String(cleanPage)] = size(home.junk);
    tell('figures', {
        headline: home.junk == null ? '' : home.junk > 0 ? size(home.junk) + ' can be freed' : 'nothing to free up',
        figures,
    });
    tally();
}

/* Home reads itself again every half minute, only while you are looking */
setInterval(() => {
    if (K.page === 0 && !K.busy && !K.welcome && document.visibilityState === 'visible'
        && K.kept[0] && Date.now() - K.kept[0].at > 29000) look(0, true);
}, 5000);

/* ── the page ─────────────────────────────────────────────────────────── */

function drawPage(still) {
    const page = $('#page');
    if (!page) return;
    const i = K.page;
    // A window that is minimised or behind everything else stops painting,
    // and an animation that has not run leaves what it animates invisible.
    // So a page drawn out of sight is drawn without any of them.
    const asleep = document.hidden;
    const out = h('div', { class: (still || asleep ? '' : 'arrive') + (asleep ? ' still' : '') });

    if (i !== ACTIVITY()) stopActivity();
    if (i === SETTINGS()) drawSettings(out);
    else if (i === HELP()) drawHelp(out);
    else if (i === ACTIVITY()) drawActivity(out);
    else if (K.walked.length) drawWalk(out);
    else {
        const kept = K.kept[i];
        if (!kept) { drawWaiting(i); return; }
        if (i === 0) drawHome(out, kept);
        else drawAction(out, i, kept);
    }
    page.replaceChildren(out);
    if (K.scrollTo) {
        const to = out.querySelector(K.scrollTo);
        if (to) { K.scrollTo = null; requestAnimationFrame(() => to.scrollIntoView({ behavior: 'smooth', block: 'start' })); }
    }
    if (!still) runCounts(out);
    else for (const el of out.querySelectorAll('[data-to]')) el.removeAttribute('data-to');
    reportChrome();
}

function drawWaiting(i, what) {
    const page = $('#page');
    if (!page) return;
    const name = what || (isAction(i) ? pages()[i].title.toLowerCase() : '');
    const line = i === 0 && !what ? 'Looking at your Mac…'
        : kind(i) === 'top' || what ? `Scanning ${what || 'your home folder'}…`
        : kind(i) === 'documents' ? 'Looking at your documents…'
        : kind(i) === 'clean' ? 'Looking for caches…'
        : `Looking at ${name}…`;
    page.replaceChildren(h('div', { class: 'wait' },
        eyesMark('waiting'),
        h('h3', null, line),
        h('p', null, kind(i) === 'top' && !what ? 'Measuring every folder in your home takes about a minute. Nothing changes while Kliner looks.'
            : 'Nothing changes while Kliner looks.'),
        h('div', { class: 'ghost' }, h('i'), h('i'), h('i'))));
}

/** The four-cornered frame every panel stands in. */
function panel(cls, ...kids) {
    return h('section', { class: 'panel' + (cls ? ' ' + cls : '') },
             h('i', { class: 'c a' }), h('i', { class: 'c b' }), h('i', { class: 'c d' }), h('i', { class: 'c e' }),
             kids);
}

function cap(symbol, text, right) {
    return h('div', { class: 'cap' }, symbol ? icon(symbol) : null, h('span', null, text),
             right ? h('div', { class: 'r' }, right) : null);
}

function bigFigure(text, sub, move) {
    const [n, unit] = figure(text);
    return h('div', { class: 'big' },
        h('div', null,
            h('div', { class: 'n' }, counted(n), unit ? h('small', null, unit) : null),
            sub ? h('div', { class: 'sub' }, sub) : null),
        move ? h('div', { class: 'move' },
            h('div', { class: 'd ' + (move.tone || '') }, move.icon ? icon(move.icon) : null, move.d),
            move.w ? h('div', { class: 'w' }, move.w) : null) : null);
}

function tile(label, symbol, value, opts) {
    opts = opts || {};
    const [n, unit] = figure(value);
    const card = panel('tile' + (opts.go != null ? ' go' : ''),
        h('div', { class: 'k' }, icon(symbol), label),
        h('div', { class: 'v' }, counted(n), unit ? h('small', null, unit) : null),
        opts.part != null ? h('div', { class: 'meter' }, h('i', { style: `width:${Math.max(1.5, Math.min(100, opts.part * 100))}%` })) : null,
        h('div', { class: 'f' },
            opts.pill ? h('span', { class: 'pill' + (opts.pillTone ? ' ' + opts.pillTone : '') }, opts.pill) : null,
            opts.foot ? h('span', { class: 't' }, opts.foot) : null));
    if (opts.go != null) card.addEventListener('click', () => show(opts.go));
    return card;
}

function dashes(share, many) {
    many = many || 22;
    const on = share > 0 ? Math.max(1, Math.round(share * many)) : 0;
    const out = h('div', { class: 'dash' });
    for (let n = 0; n < many; n++) out.append(h('i', { class: n < on ? 'on' : '', style: n < on ? `animation-delay:${60 + n * 12}ms` : '' }));
    return out;
}

/* weaves, not hues: a breakdown is told apart by texture */
const WEAVES = 6;
function swatch(n) {
    const svg = s('svg', { viewBox: '0 0 14 14' });
    svg.append(s('rect', { width: 14, height: 14, fill: `url(#weave${n % WEAVES})` }));
    return h('span', { class: 'sw' }, svg);
}

/* ── things that move ─────────────────────────────────────────────────── */

/** A figure that counts up to itself when its page arrives. The text is the
 *  final text from the start, so a page drawn quietly never shows a wrong
 *  number — only a page arriving gets the count. */
function counted(text) {
    const m = /^(\D*?)(\d[\d, ]*(?:\.\d+)?)(.*)$/.exec(String(text));
    if (!m) return document.createTextNode(String(text));
    const digits = m[2].replace(/[, ]/g, '');
    return h('span', { 'data-to': digits, 'data-dec': (digits.split('.')[1] || '').length,
                       'data-pre': m[1], 'data-post': m[3], 'data-sep': /[ ]/.test(m[2]) ? 'thin' : '' }, String(text));
}
function runCounts(root) {
    const els = [...root.querySelectorAll('[data-to]')];
    if (!els.length || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const t0 = performance.now(), dur = 450;
    const fmt = (el, v) => {
        const dec = +el.dataset.dec;
        let n = dec ? v.toFixed(dec) : String(Math.round(v));
        if (el.dataset.sep === 'thin') n = n.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
        return el.dataset.pre + n + el.dataset.post;
    };
    const step = now => {
        const k = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - k, 3);
        for (const el of els) if (el.isConnected) el.textContent = fmt(el, parseFloat(el.dataset.to) * e);
        if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
}

/** The small label over the thing it is about. It stands still: a label
 *  that chases the pointer is a label you read while it moves. */
function chipAt(el, parts) {
    let c = $('#chip');
    if (!c) { c = h('div', { class: 'chip', id: 'chip' }); document.body.append(c); }
    c.replaceChildren(...parts);
    c.classList.add('show');
    const r = (el.currentTarget || el).getBoundingClientRect();
    const w = c.offsetWidth, hh = c.offsetHeight;
    c.style.left = Math.min(window.innerWidth - w - 8, Math.max(8, r.left + r.width / 2 - w / 2)) + 'px';
    c.style.top = (r.top - hh - 8 < 60 ? r.bottom + 8 : r.top - hh - 8) + 'px';
}
function chipOff() { const c = $('#chip'); if (c) c.classList.remove('show'); }

/* Nothing here follows the pointer. The window used to light a card under
   the mouse and have the face look at it; both read as a toy, and both cost
   a repaint on every move. */

/* ── Home ─────────────────────────────────────────────────────────────── */

function greeting() {
    const hour = new Date().getHours();
    const part = hour < 5 ? 'Good evening' : hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
    const name = (K.meta.config.name || '').trim().split(/\s+/)[0];
    if (!name) return 'Hello.';
    return /[.!?]$/.test(name) ? `${part}, ${name}` : `${part}, ${name}.`;
}

function drawHome(out, kept) {
    const pieces = kept.pieces || [];
    const home = K.home || {};
    const f = facts(pieces);
    const total = home.total || 0, free = home.free || 0, used = home.used || 0;
    const junk = home.junk;
    const cleanPage = pages().findIndex(p => p.kind === 'clean');
    const topPage = pages().findIndex(p => p.kind === 'top');
    const doctorPage = pages().findIndex((p, n) => n > 0 && p.kind === 'doctor');

    // the first card says, in one sentence, what there is to do — and has
    // the two buttons that do it
    const bits = [];
    if (home.desk) bits.push([String(home.desk), home.desk === 1 ? ' item on your desktop' : ' items on your desktop']);
    if (home.downloads) bits.push([String(home.downloads), ' in Downloads']);
    if (junk > 0) bits.push([size(junk), ' you can free up']);
    const sentence = h('h2');
    if (!bits.length) sentence.append(h('em', null, 'All clear.'), ' Nothing needs doing.');
    bits.forEach((b, n) => {
        if (n) sentence.append(n === bits.length - 1 ? ' and ' : ', ');
        sentence.append(h('em', null, b[0]), b[1]);
    });
    if (bits.length) sentence.append('.');
    const sweep = cleanSweep();
    out.append(panel('hero',
        eyesMark('hero-mark'),
        h('div', null, h('p', { style: 'margin:0 0 4px' }, greeting()), sentence,
          h('p', null, 'Nothing has changed yet. Kliner asks before it does anything, and every move can be undone.')),
        h('div', { class: 'acts' },
            h('button', { class: 'btn line small', 'data-tip': 'Look again', onclick: () => { delete K.kept[0]; look(0); } }, icon('refresh')),
            junk > 0 && cleanPage >= 0 ? h('button', { class: 'btn line', onclick: () => show(cleanPage) }, icon('sparkles'), 'Free ' + size(junk)) : null,
            sweep.length ? h('button', { class: 'btn fill', onclick: () => tidyBoth(sweep) }, icon('sparkles'), 'Clean my Mac') : null)));

    if (!f.Disk && !f.Desktop) {
        drawAction(out, 0, kept, true);
        return;
    }

    // four readings, each a way into the page it is about
    const across = h('div', { class: 'grid four' });
    if (total > 0) {
        across.append(tile('Disk', 'disk', size(used), {
            part: used / total, pill: percent(used, total) + ' used', foot: 'of ' + size(total), go: topPage >= 0 ? topPage : null }));
        across.append(tile('Free', 'sparkles', size(free), {
            part: free / total,
            pill: junk > 0 ? size(junk) + ' can be freed' : null, pillTone: junk > 0 ? 'good' : '',
            foot: junk === 0 ? 'nothing to free up' : junk == null ? 'checking…' : null, go: cleanPage >= 0 ? cleanPage : null }));
    }
    if (home.desk != null) across.append(tile('Desktop', 'desk', String(home.desk), {
        pill: home.deskOld || null, foot: home.deskOld ? null : home.desk === 1 ? 'item' : 'items', go: 1 }));
    if (home.downloads != null) across.append(tile('Downloads', 'download', String(home.downloads), {
        pill: home.downloadsOld || null, foot: home.downloadsOld ? null : home.downloads === 1 ? 'item' : 'items', go: 2 }));
    // as many columns as there are readings, so none sits beside a hole
    if (across.children.length === 3) across.className = 'grid three';
    if (across.children.length === 2) across.className = 'grid two';
    if (across.children.length) out.append(across);

    // Two rows, and every chart in them answers something. There used to be
    // a third: 228 GB flowing into 214 GB flowing into 50 MB. At that scale
    // the last step is a hairline, and a chart whose point cannot be seen is
    // not a chart. The number it carried is on the Free tile and in the
    // ring's own legend, where it reads.
    const deskPage = pages().findIndex(p => p.kind === 'desktop');
    const dlPage = pages().findIndex(p => p.kind === 'downloads');
    const worth = junk == null ? null : junk;

    if (total > 0 || deskPage > 0) {
        const two = h('div', { class: 'grid two' });
        if (deskPage > 0) two.append(typesCard(deskPage, 'Your desktop'));
        if (total > 0) {
            const bands = [
                { name: 'Your files', value: Math.max(0, used - (worth || 0)), go: topPage },
                { name: 'Can be freed', value: worth || 0, go: cleanPage, hot: true },
                { name: 'Free', value: free, go: doctorPage },
            ].filter(b => b.value > 0);
            two.append(panel('',
                bigFigure(size(used), 'used of ' + size(total),
                          { d: percent(used, total) + ' used', w: size(free) + ' free' }),
                ringRow(bands, total, percent(used, total), 'used')));
        }
        if (two.children.length === 1) two.className = 'grid';
        out.append(two);
    }

    // The second row only if it has something to say. An empty Downloads
    // folder across the whole width is a card that says nothing, twice.
    const months = home.months && home.months.length === 12 && home.months.some(x => x > 0);
    if (dlPage > 0 && home.downloads > 0) {
        const two = h('div', { class: 'grid two' }, typesCard(dlPage, 'Your downloads'),
            months ? monthsCard(home) : null);
        if (two.children.length === 1) two.className = 'grid';
        out.append(two);
    } else if (months) {
        out.append(h('div', { class: 'grid' }, monthsCard(home)));
    }

    // four cards, two by two until there is room for four
    const four = h('div', { class: 'grid four cards' });
    four.append(deskCard(home));
    four.append(copiesCard(kept));
    four.append(machineCard(f));
    four.append(todoCard(home));
    out.append(four);
}

/** macOS keeps Desktop, Downloads and Documents behind a permission. Until
 *  it is given, those folders read as empty and every page over them looks
 *  broken, so Kliner says which of the two it is. */
function shut(i) {
    const seen = K.meta && K.meta.seeing;
    const k = kind(i);
    return !!(seen && k in seen && seen[k] === false);
}

/** Ask macOS again. Reading the folder is the question, so this either
 *  raises its prompt or comes straight back with the same answer. */
async function letItLook() {
    const reply = await ask('askFolders');
    if (reply && reply.seeing && K.meta) K.meta.seeing = reply.seeing;
    for (const n of Object.keys(K.kept)) delete K.kept[n];
    K.listing = {};
    look(K.page, true);
}

function shutNote(i) {
    const name = (pages()[i] ? pages()[i].title : 'that folder');
    return h('div', { class: 'shut' },
        icon('shield'),
        h('div', { class: 'say' },
            h('b', null, 'macOS has not let Kliner look at ' + name + ' yet.'),
            h('span', null, 'Until it does, this folder reads as empty. Allow it and everything here works.')),
        h('button', { class: 'btn fill', onclick: letItLook }, 'Allow'));
}

/** Clean my Mac: the three folders Kliner sorts and the caches it clears,
 *  in one run, with one question in front of it. */
function cleanSweep() {
    const want = ['desktop', 'downloads', 'documents', 'clean'];
    return want.map(k => pages().findIndex(p => p.kind === k)).filter(n => n > 0);
}

/* ── what is in a folder, by type: the bar, the list, three figures ───── */

function typesCard(i, title_) {
    const body = h('div', { class: 'types' }, h('div', { class: 'more loadingline' }, 'Reading the folder…'));
    const box = panel('go', cap('grid', title_, h('span', null, 'by type')), body);
    if (!(i > 0)) return panel('', cap('grid', title_), h('div', { class: 'more' }, 'Nothing to read yet.'));
    box.addEventListener('click', () => show(i));
    listing(i).then(items => {
        if (!body.isConnected) return;
        const files = items.filter(countedByNimo);
        if (!files.length) {
            body.replaceChildren(shut(i)
                ? h('div', { class: 'clear' }, h('span', { class: 'tick lock' }, icon('shield')),
                    h('div', null, h('b', null, 'macOS has not let Kliner look yet.'),
                      h('span', null, 'Allow it on the ' + pages()[i].title + ' page and this fills in.')))
                : h('div', { class: 'clear' }, h('span', { class: 'tick' }, icon('check')),
                    h('div', null, h('b', null, 'Nothing in it.'), h('span', null, 'This folder is empty.'))));
            return;
        }
        const by = new Map();
        let room = 0, biggest = null, oldest = null;
        for (const f of files) {
            const kind = kindOf(f);
            const one = by.get(kind) || { name: kind, count: 0, size: 0 };
            one.count += 1;
            one.size += f.size || 0;
            by.set(kind, one);
            room += f.size || 0;
            if (!biggest || (f.size || 0) > (biggest.size || 0)) biggest = f;
            if (f.modified && (!oldest || f.modified < oldest.modified)) oldest = f;
        }
        const kinds = [...by.values()].sort((a, b) => b.count - a.count);
        const most = files.length || 1;
        const bar = h('div', { class: 'stack' });
        kinds.forEach((k, n) => {
            const part = h('i', { class: 'seg' + (n === 0 ? ' lead' : ''), style: `width:${(k.count / most * 100).toFixed(2)}%;animation-delay:${n * 40}ms` });
            part.addEventListener('mouseenter', e => chipAt(e, [k.name, h('b', null, plural(k.count, 'item')), h('span', null, size(k.size))]));
            part.addEventListener('mouseleave', chipOff);
            bar.append(part);
        });
        const legend = h('div', { class: 'legend' });
        kinds.slice(0, 6).forEach((k, n) => legend.append(h('div', { class: 'lg' },
            n === 0 ? swatchHot() : swatch(Math.min(n, WEAVES - 1)),
            h('span', { class: 'n' }, k.name), h('span', { class: 'v' }, whole(k.count)))));
        const facts_ = h('div', { class: 'figs' },
            fig(size(room), 'in the folder'),
            fig(biggest ? size(biggest.size || 0) : '0 B', biggest ? 'biggest: ' + shortName(biggest.name) : 'biggest'),
            fig(oldest ? ago(oldest.modified).replace(' ago', '') : '', 'oldest item'));
        body.replaceChildren(h('div', { class: 'top' }, h('span', { class: 'n' }, counted(whole(files.length))), h('span', { class: 'u' }, 'items')),
                             bar, legend, facts_);
        runCounts(body);
    });
    return box;
}

function fig(value, label) {
    const [n, unit] = figure(value);
    return h('div', { class: 'f' }, h('div', { class: 'v' }, counted(n), unit ? h('small', null, unit) : null),
             h('div', { class: 'l' }, label));
}

function deskCard(home) {
    const rows = [
        { name: 'Desktop', n: home.desk, old: home.deskOld, page: 1 },
        { name: 'Downloads', n: home.downloads, old: home.downloadsOld, page: 2 },
        { name: 'Trash', n: home.trash, old: '', page: -1 },
    ].filter(r => r.n != null);
    const most = Math.max(1, ...rows.map(r => r.n || 0));
    const list = h('div', { class: 'list' });
    for (const r of rows) {
        const one = h('div', { style: r.page >= 0 ? 'cursor:pointer' : '', onclick: r.page >= 0 ? () => show(r.page) : null },
            h('div', { class: 'l' }, h('b', null, r.name),
              r.old ? h('span', { class: 'pill' }, r.old) : null,
              h('span', { class: 'v' }, plural(r.n, 'item'))),
            dashes(r.n / most));
        list.append(one);
    }
    const deskPage = pages().findIndex(p => p.kind === 'desktop');
    const strip = deskPage > 0 ? h('div', { class: 'newest' }) : null;
    if (strip) fillNewest(strip, deskPage);
    return panel('', cap('grid', 'Desktop and Downloads', 'now'), list,
                 strip ? h('div', { class: 'nwcap' }, 'Latest on your desktop') : null, strip);
}

function promiseCard(home) {
    const last = (home.last || '').trim();
    const undoPage = pages().findIndex(p => p.kind === 'undo');
    const first = last ? last.split(', ')[0] : '';
    return panel('', cap('undo', 'Undo'),
        h('div', { class: 'promise' },
            h('div', { class: 'marks' },
                h('span', null, icon('tray')), h('span', null, icon('plus')), h('span', null, icon('undo'))),
            h('h4', null, first ? first.charAt(0).toUpperCase() + first.slice(1) : 'You can undo everything'),
            h('p', null, 'Kliner logs every move, so things can go back exactly where they were.'),
            undoPage >= 0 ? h('button', { class: 'btn fill small', onclick: () => show(undoPage) }, 'Undo everything') : null));
}

function monthsCard(home) {
    const months = home.months;
    const most = Math.max(...months);
    const names = [];
    const now = new Date();
    for (let back = 11; back >= 0; back--) {
        const d = new Date(now.getFullYear(), now.getMonth() - back, 1);
        names.push(d.toLocaleString('en', { month: 'short' }));
    }
    const busiest = names[months.indexOf(most)];
    const all = months.reduce((a, b) => a + b, 0);
    const row = h('div', { class: 'row' });
    const shades = ['var(--sel)', 'var(--w4)', 'var(--w3)', 'var(--w2)', 'var(--w0)'];
    months.forEach((m, n) => {
        const level = m <= 0 ? 0 : Math.min(4, 1 + Math.floor((m / most) * 3.999));
        const cell = h('i', { style: `background:${level === 4 ? 'var(--accent)' : shades[level]};animation-delay:${n * 18}ms` });
        cell.addEventListener('mouseenter', e => chipAt(e, [names[n], h('b', null, whole(m)), h('span', null, m === 1 ? 'item added' : 'items added')]));
        cell.addEventListener('mouseleave', chipOff);
        row.append(cell);
    });
    const ax = h('div', { class: 'ax' });
    names.forEach((n, k) => ax.append(h('span', null, k % 2 === 1 ? n : '')));
    const scale = h('div', { class: 'scale' }, 'fewer',
        shades.map(c => h('i', { style: `background:${c}` })), 'more');

    let move = null;
    const nowM = months[11], before = months[10];
    if (before > 0 && nowM > 0) {
        const by = (nowM - before) / before;
        if (Math.abs(by) >= 0.05) move = h('span', { class: 'pill ' + (by > 0 ? 'bad' : 'good') },
            icon(by > 0 ? 'up' : 'arrdown'), Math.round(Math.abs(by) * 100) + '% vs last month');
    }
    return panel('', cap('clock', 'Added to your desktop', move || '12 months'),
        h('div', { class: 'pair' },
            h('div', null, h('div', { class: 'n' }, whole(all)), h('div', { class: 'c' }, 'items in the last 12 months')),
            h('div', null, h('div', { class: 'n' }, busiest), h('div', { class: 'c' }, 'busiest month'))),
        h('div', { class: 'heat' }, row, ax, scale));
}

function machineCard(f) {
    const keys = ['System', 'Memory', 'Battery', 'Uptime'].filter(k => f[k]);
    const list = h('div', { class: 'facts' });
    for (const k of keys) {
        list.append(h('div', { class: 'fact' }, h('span', { class: 'k' }, k),
            h('span', { class: 'v' }, f[k].value), h('span')));
    }
    const doctor = pages().findIndex((p, n) => n > 0 && p.kind === 'doctor');
    return panel('', cap('cpu', 'This Mac', doctor > 0 ? h('button', { class: 'btn bare small', onclick: () => show(doctor) }, 'More') : null), list);
}

function todoCard(home) {
    const cleanPage = pages().findIndex(p => p.kind === 'clean');
    const undoPage = pages().findIndex(p => p.kind === 'undo');
    const items = [];
    const sweep = cleanSweep();
    if (sweep.length) items.push({ name: 'Clean my Mac', cmd: 'desktop, downloads, documents and caches', fig: '', icon: 'sparkles',
                                   go: () => tidyBoth(sweep), verb: 'Clean' });
    if (!K.sighted) items.push({ name: 'Allow access to your files', cmd: 'macOS has not asked yet', fig: '', icon: 'lock', verb: 'Ask',
                                 go: async () => { await ask('askFolders'); delete K.kept[0]; look(0); } });
    items.push({ name: 'Tidy desktop', cmd: 'into Desktop/Tidy, by type', fig: home.desk ? plural(home.desk, 'item') : 'already tidy',
                 icon: 'desk', done: home.desk === 0, page: 1, verb: 'Clear' });
    items.push({ name: 'Tidy downloads', cmd: 'into Downloads/Tidy, by type', fig: home.downloads ? plural(home.downloads, 'item') : 'already tidy',
                 icon: 'download', done: home.downloads === 0, page: 2, verb: 'Sort' });
    if (cleanPage >= 0) items.push({ name: 'Free up space', cmd: 'app caches and the Trash',
                 fig: home.junk == null ? 'checking…' : home.junk > 0 ? size(home.junk) : 'nothing to free',
                 icon: 'sparkles', done: home.junk === 0, page: cleanPage, verb: 'Free' });
    if (undoPage >= 0) items.push({ name: 'Undo everything', cmd: 'every move, newest first', fig: '', icon: 'undo', page: undoPage, verb: 'Open' });

    const list = h('div', { class: 'todo' });
    for (const it of items) {
        const row = h('div', { class: 't' + (it.done ? ' done' : ''), style: 'cursor:pointer',
                               onclick: () => (it.page != null ? show(it.page) : it.go()) },
            h('span', { class: 'ico' }, icon(it.icon)),
            h('div', { style: 'min-width:0' }, h('div', { class: 'nm' }, h('span', null, it.name)), h('div', { class: 'cm' }, it.cmd)),
            h('div', { class: 'go' }, it.fig ? h('span', { class: 'fig' }, it.fig) : null, icon('right')));
        list.append(row);
    }
    const both = [1, 2].filter(n => (n === 1 ? home.desk : home.downloads) > 0);
    return panel('', cap('bolt', 'Quick actions',
        both.length > 1 ? h('button', { class: 'btn line small', onclick: () => tidyBoth(both) }, 'Tidy both') : null), list);
}

/* ── the ring, and its key ────────────────────────────────────────────── */

function ringRow(bands, whole_, centre, under) {
    // strokes on a circle, not wedges: each slice can be pointed at, grow,
    // and say what it is, and they sweep in one after another
    const C = 100, R = 72, W = 30, circ = 2 * Math.PI * R;
    const svg = s('svg', { class: 'ring', viewBox: '0 0 200 200' });
    svg.append(s('circle', { class: 'track', cx: C, cy: C, r: R, 'stroke-width': W }));
    const g = s('g', { transform: `rotate(-90 ${C} ${C})` });
    svg.append(g);
    const sum = bands.reduce((a, b) => a + b.value, 0) || 1;
    const minShare = 0.012, gap = bands.length > 1 ? 3 : 0;
    const shares = bands.map(b => Math.max(b.value / sum, b.value > 0 ? minShare : 0));
    const norm = shares.reduce((a, b) => a + b, 0) || 1;
    let at = 0;
    const segs = [];
    bands.forEach((b, n) => {
        const len = Math.max(0, shares[n] / norm * circ - gap);
        const seg = s('circle', { class: 'seg', cx: C, cy: C, r: R, 'stroke-width': W,
                                  stroke: b.hot ? 'url(#weaveHot)' : `url(#weave${n % WEAVES})`,
                                  'stroke-dasharray': `0 ${circ}`, 'stroke-dashoffset': String(-at) });
        seg.style.transition = `stroke-dasharray .9s cubic-bezier(.2,.8,.2,1) ${n * 120}ms, stroke-width .25s cubic-bezier(.2,.8,.2,1), opacity .2s ease`;
        g.append(seg);
        segs.push(seg);
        requestAnimationFrame(() => requestAnimationFrame(() => seg.setAttribute('stroke-dasharray', `${len} ${circ}`)));
        at += len + gap;
    });
    const t1 = s('text', { x: C, y: C + 3, 'text-anchor': 'middle', style: 'fill:var(--ink);font-size:24px;font-weight:600;letter-spacing:-.02em' });
    const t2 = s('text', { x: C, y: C + 22, 'text-anchor': 'middle', style: 'fill:var(--faint);font-size:11px' });
    const rest = () => { t1.textContent = centre || ''; t2.textContent = under || ''; };
    rest();
    svg.append(t1, t2);

    const key = h('div', { class: 'key' });
    const rows = [];
    bands.forEach((b, n) => {
        const row = h('div', null,
            h('div', { class: 'k' }, b.hot ? swatchHot() : swatch(n), h('span', { class: 'n' }, b.name),
              h('span', { class: 'p' }, percent(b.value, whole_)), h('span', { class: 'v' }, b.fmt || size(b.value))),
            dashes(b.value / (whole_ || 1), 30));
        key.append(row);
        rows.push(row);
    });
    const point = n => {
        segs.forEach((seg, k) => { seg.classList.toggle('hot', k === n); seg.classList.toggle('dim', n != null && k !== n); });
        rows.forEach((row, k) => { row.classList.toggle('dim', n != null && k !== n); row.firstChild.classList.toggle('hot', k === n); });
        if (n == null) { rest(); return; }
        t1.textContent = bands[n].fmt || size(bands[n].value);
        t2.textContent = bands[n].name.toLowerCase();
    };
    bands.forEach((b, n) => {
        const go = () => { if (b.go != null && b.go >= 0) show(b.go); };
        for (const el of [segs[n], rows[n]]) {
            el.addEventListener('mouseenter', () => point(n));
            el.addEventListener('mouseleave', () => { point(null); chipOff(); });
            el.addEventListener('click', go);
        }
        segs[n].addEventListener('mouseenter', e => chipAt(e, [b.name, h('b', null, b.fmt || size(b.value)), h('span', null, percent(b.value, whole_))]));
    });
    return h('div', { class: 'ringrow' }, svg, key);
}

/** The swatch for the slice Kliner can do something about: solid, not woven. */
function swatchHot() {
    const svg = s('svg', { viewBox: '0 0 14 14' });
    svg.append(s('rect', { width: 14, height: 14, fill: 'url(#weaveHot)' }));
    return h('span', { class: 'sw' }, svg);
}

/* ── every other page ─────────────────────────────────────────────────── */

function head(i, extraActs) {
    const item = pages()[i];
    const acts = h('div', { class: 'acts' });
    if (item.reveal) {
        acts.append(h('button', { class: 'btn bare small', onclick: () => walk([item.reveal]) }, icon('folder'), 'Look inside'));
        acts.append(h('button', { class: 'btn bare small', onclick: () => tell('reveal', { page: i }) }, icon('finder'), 'Show in Finder'));
    }
    item.extras.forEach((ex, n) => {
        acts.append(h('button', { class: 'btn line', onclick: () => extra(i, n) }, ex.symbol ? icon(ex.symbol) : null, ex.title));
    });
    if (extraActs) acts.append(extraActs);
    if (item.verb) {
        const verb = K.preview && item.asks ? 'Preview' : item.verb;
        acts.append(h('button', { class: 'btn fill', onclick: () => act(i) },
                      icon(K.preview && item.asks ? 'eye' : item.does), verb));
    }
    return h('div', { class: 'head' },
        h('div', { class: 'words' },
            h('h1', null, item.title),
            h('p', null, item.blurb)),
        acts);
}

function drawAction(out, i, kept, bodyOnly) {
    if (!bodyOnly) out.append(head(i));
    if (!bodyOnly && K.preview && (pages()[i].asks || !pages()[i].looksOnly)) out.append(looking());
    if (!bodyOnly && shut(i)) out.append(shutNote(i));
    const k = kind(i);
    let pieces = kept.pieces || [];
    if (kept.result) {
        out.append(banner(pieces, kept, i));
        const said = pieces.find(p => p.k === 'good') || pieces.find(p => p.k === 'warn');
        pieces = pieces.filter(p => p !== said);
    }
    if (k === 'next') { drawWalls(out, i, kept.result ? (kept.pieces || []) : []); return; }
    if (kept.ready) {
        drawReady(out, i);
        return;
    }

    // A page with one panel on it leaves half the window empty, so the
    // pages that read short are laid out in two columns instead.
    const aside = sideFor(k, i, pieces, kept);
    const main = aside ? h('div', { class: 'col' }) : out;
    if (k === 'dock') drawDock(main, pieces);
    else if (k === 'startup') drawStartup(main, pieces);
    else if (k === 'undo') drawUndo(main, i, pieces);
    else if (k === 'doctor') drawDoctor(main, pieces);
    else {
        drawSections(main, i, pieces);
        if (pages()[i].reveal) main.append(copiesPanel(i, kept));
    }
    if (aside) out.append(h('div', { class: 'split' }, main, h('div', { class: 'col' }, aside)));
}

/** The second column: what the page is about, said once, with the figures
 *  that belong to it. Nothing invented — every number comes from the same
 *  reading as the panel beside it. */
function sideFor(k, i, pieces, kept) {
    if (kept.result || kept.ready) return null;
    const f = facts(pieces);
    if (k === 'clean') {
        const free = K.home && K.home.free, total = K.home && K.home.total;
        const junk = K.home && K.home.junk;
        const rows = [];
        if (free != null && total > 0) {
            rows.push(h('div', { class: 'after' },
                h('div', { class: 'l' }, 'Free now'), h('div', { class: 'v' }, size(free)),
                h('div', { class: 'meter' }, h('i', { style: `width:${Math.max(1, free / total * 100).toFixed(1)}%` }))));
            if (junk > 0) rows.push(h('div', { class: 'after' },
                h('div', { class: 'l' }, 'Free after cleaning'), h('div', { class: 'v' }, size(free + junk)),
                h('div', { class: 'meter' }, h('i', { style: `width:${Math.max(1, (free + junk) / total * 100).toFixed(1)}%` }))));
        }
        return panel('', cap('disk', 'Your disk', total > 0 ? size(total) : null), h('div', { class: 'afters' }, rows),
            h('div', { class: 'more' }, 'Caches are files your apps write to save themselves work. They come back on their own the next time an app needs them.'));
    }
    if (k === 'startup') {
        const counted_ = pieces.filter(p => p.k === 'row' && p.label && !/^\s*$/.test(p.label));
        const agents = counted_.filter(p => /agent/i.test(p.value || '')).length;
        return panel('', cap('power', 'What this is'),
            h('div', { class: 'afters' },
                h('div', { class: 'after' }, h('div', { class: 'l' }, 'Opens at login'), h('div', { class: 'v' }, whole(counted_.length - agents))),
                h('div', { class: 'after' }, h('div', { class: 'l' }, 'Background agents'), h('div', { class: 'v' }, whole(agents)))),
            h('div', { class: 'more' }, 'Login items are apps that start themselves when you log in. Background agents are smaller helpers that apps install. Stopping one does not uninstall anything, and Undo puts it back.'));
    }
    if (k === 'undo') {
        const items = pieces.filter(p => p.k === 'item');
        const newest = items[0];
        return panel('', cap('clock', 'The log'),
            h('div', { class: 'afters' },
                h('div', { class: 'after' }, h('div', { class: 'l' }, 'Moves Kliner can undo'), h('div', { class: 'v' }, whole(items.length))),
                newest ? h('div', { class: 'after' }, h('div', { class: 'l' }, 'Newest'), h('div', { class: 'v small' }, newest.parts[1] || '')) : null),
            h('div', { class: 'more' }, 'Kliner writes down every move before it makes it, so the log is what actually happened, not what it meant to do.'));
    }
    return null;
}

/** Only look is on, said where the buttons are. */
function looking() {
    return h('div', { class: 'looking' }, icon('eye'),
        h('div', null, h('b', null, 'Preview is on. '),
          h('span', null, 'Buttons only show what would happen. Nothing changes until you turn it off.')),
        h('button', { class: 'btn line small', onclick: flipPreview }, 'Turn it off'));
}

/** What came back after something was done, said once, at the top. */
function banner(pieces, kept, i) {
    const good = pieces.find(p => p.k === 'good');
    const warn = pieces.find(p => p.k === 'warn');
    const said = good || warn;
    if (!said) return null;
    // the lines under the ✓ are its details; the ones telling a terminal
    // what to type next are for a terminal
    const after = [];
    let seen = false;
    for (const p of pieces) {
        if (p === said) { seen = true; continue; }
        if (!seen) continue;
        if (p.k === 'note' || p.k === 'text') {
            if (/^(run |changed your mind|in a terminal|to see )/.test(p.text)) continue;
            // "7 of 8 · min next  min prev" — the commands are a terminal's
            const kept_ = p.text.split(/\s+·\s+/).filter(bit => !/^min /.test(bit.trim())).join(' · ').trim();
            if (kept_) after.push(kept_);
        } else if (p.k === 'row') after.push(p.label + '  ' + p.value);
        if (after.length >= 2) break;
    }
    let way = null;
    if (kept.changed && isAction(i)) {
        const undo = pages()[i].extras.findIndex(e => e.symbol === 'arrow.uturn.backward' && /back|undo/i.test(e.title));
        if (undo >= 0) way = h('button', { class: 'btn line small', onclick: () => extra(i, undo) }, icon('undo'), pages()[i].extras[undo].title);
    }
    return h('div', { class: 'done' + (good ? '' : ' plain') },
        h('span', { class: 'tick' }, icon(good ? (kept.preview ? 'eye' : 'check') : 'x')),
        h('div', { class: 'w' }, h('b', null, said.text),
          after.length ? h('span', null, prose(after.join(' · '))) : kept.preview ? h('span', null, 'Preview only. Nothing changed.') : null),
        way);
}

function drawReady(out, i) {
    out.append(panel('', h('div', { class: 'promise' },
        eyesMark('promise-mark'),
        h('h4', { style: 'margin-top:12px' }, 'Ready when you are.'),
        h('p', null, 'Nothing happens until you press ' + pages()[i].verb + '.'))));
}

/** A reading cut into panels, one for each panel nimo drew. */
function drawSections(out, i, pieces) {
    const parts = sections(pieces);
    const reveal = pages()[i].reveal;
    let drew = 0;
    for (const sec of parts) {
        const rows = sec.pieces.filter(p => p.k === 'row' && p.label);
        if (!sec.title && !rows.length && !sec.pieces.some(p => p.k === 'good' || p.k === 'warn' || p.k === 'text' || p.k === 'item')) continue;
        const sized = rows.filter(r => weigh(r.value) != null);
        if (sized.length > 1) out.append(breakdown(sec, i, { walkable: kind(i) === 'top' || !!reveal }));
        else out.append(plainPanel(sec, i));
        drew++;
    }
    const notes = footnotes(pieces);
    if (notes) out.append(notes);
    if (!drew && !pieces.some(p => p.k === 'good' || p.k === 'warn')) {
        out.append(panel('', h('div', { class: 'said' }, h('div', { class: 's quiet' }, 'No results.'))));
    }
}

function weigh(value) {
    if (hasUnit(value)) return bytes(value);
    const m = /^\s*(\d[\d,]*)\s+[a-z]/i.exec(String(value || ''));
    if (!m) return null;
    const n = parseInt(m[1].replace(/,/g, ''), 10);
    return n > 0 ? n : null;
}

const KIND_ICON = {
    screenshots: 'camera', images: 'photo', pictures: 'photo', documents: 'file', video: 'film', videos: 'film',
    archives: 'box', folders: 'folder', audio: 'music', music: 'music', apps: 'cube', applications: 'cube',
    code: 'code', installers: 'box', other: 'dot',
};

function title(text) { return text ? text.charAt(0).toUpperCase() + text.slice(1) : ''; }

/** nimo's own labels, in a window's words. */
function tidyLabel(text) {
    const t = String(text || '').trim();
    return /^in there$/i.test(t) ? 'Total' : title(t);
}

/** A line nimo wrote for a terminal: capitalised, and without the dash. */
function tidyLine(text) {
    return title(String(text || '').replace(/\s+[—–]\s+/g, ': ').replace(/\s{2,}/g, ' ').trim());
}

function breakdown(sec, i, opts) {
    const rows = [];
    let total = null;
    const after = [];
    let ruled = false;
    for (const p of sec.pieces) {
        if (p.k === 'rule') { ruled = true; continue; }
        if (p.k !== 'row' || !p.label) { if (p.k !== 'note') after.push(p); continue; }
        if (ruled && !total) { total = p; continue; }
        if (ruled) { after.push(p); continue; }
        const much = weigh(p.value);
        if (much == null) { after.push(p); continue; }
        rows.push({ name: p.label, value: much, raw: p.value, note: p.note, folder: /\/$/.test(p.label) });
    }
    const asBytes = rows.some(r => hasUnit(r.raw));
    const amount = v => (asBytes ? size(v) : whole(v));
    rows.sort((a, b) => b.value - a.value);
    const sum = rows.reduce((a, r) => a + r.value, 0) || 1;
    // a page about a folder lists kinds of thing: each one opens on the files
    const kinds = !asBytes && isAction(i) && !!pages()[i].reveal && !K.walked.length;

    const box = panel('');
    const big = total ? total.value : amount(sum);
    box.append(cap(asBytes ? 'bars' : 'grid', title(sec.title) || titleOf(i),
        h('span', null, `${rows.length} ${asBytes ? (rows.some(r => r.folder) ? 'folders' : 'items') : 'types'}`)));
    box.append(h('div', { style: 'margin-top:14px' }, bigFigure(big,
        total ? tidyLabel(total.label) : 'in total',
        rows[0] ? { d: rows[0].name.replace(/\/$/, ''), w: percent(rows[0].value, sum) + ' of everything' } : null)));

    // what pressing a bar or a row does
    const open = r => {
        chipOff();
        if (kinds) return openKind(i, r.name);
        if (opts.walkable && r.folder) return walkInto(r.name.replace(/\/$/, ''));
        if (K.walked.length) return revealThing(r.name);
    };
    const canOpen = r => kinds || (opts.walkable && r.folder) || K.walked.length > 0;

    // the bars: biggest first, the biggest one solid
    const bars = h('div', { class: 'bars' });
    if (rows.length < 4) bars.hidden = true;
    const top = rows[0] ? rows[0].value : 1;
    const barEls = [], rowEls = [];
    const light = n => {
        barEls.forEach((b, k) => { b.classList.toggle('lit', k === n); b.classList.toggle('dim', n != null && k !== n); });
        rowEls.forEach((r, k) => r.classList.toggle('lit', k === n));
    };
    rows.slice(0, 14).forEach((r, n) => {
        const col = h('div', { class: 'col', style: `height:${Math.max(2, r.value / top * 100)}%;animation-delay:${n * 22}ms` });
        const svg = s('svg', { width: '100%', height: '100%' });
        svg.append(s('rect', { width: '100%', height: '100%', fill: n === 0 ? 'url(#weaveHot)' : `url(#weave${Math.min(n, WEAVES - 1)})` }));
        col.append(svg);
        const b = h('div', { class: 'b' }, col, h('div', { class: 'lb' }, r.name.replace(/\/$/, '')));
        b.addEventListener('mouseenter', () => light(n));
        b.addEventListener('mouseenter', e => chipAt(e, [r.name.replace(/\/$/, ''), h('b', null, asBytes ? amount(r.value) : plural(Math.round(r.value), 'item')),
                                                        h('span', null, percent(r.value, sum) + (canOpen(r) ? ' · click to open' : ''))]));
        b.addEventListener('mouseleave', () => { light(null); chipOff(); });
        b.addEventListener('click', () => open(r));
        bars.append(b);
        barEls.push(b);
    });
    box.append(bars);

    // and the table they came from
    const table = h('div', { class: 'table' },
        h('div', { class: 'th' }, h('span'), h('span', null, asBytes ? 'Name' : 'Type'), h('span', null, 'Share'),
          h('span', { class: 'num' }, '%'), h('span', { class: 'num' }, asBytes ? 'Size' : 'Count'), h('span')));
    rows.forEach((r, n) => {
        const can = canOpen(r);
        const tr = h('div', { class: 'tr' + (can ? ' can' : ''), style: (can ? 'cursor:pointer;' : '') + `animation-delay:${40 + n * 16}ms`,
                               onclick: can ? () => open(r) : null },
            n === 0 ? swatchHot() : swatch(Math.min(n, WEAVES - 1)),
            h('span', { class: 'nm' }, r.name),
            h('span', { class: 'share' }, h('i', { style: `width:${Math.max(1, r.value / sum * 100)}%;animation-delay:${60 + n * 20}ms` })),
            h('span', { class: 'num pc' }, percent(r.value, sum)),
            h('span', { class: 'num sz' }, asBytes ? amount(r.value) : plural(Math.round(r.value), 'item')),
            h('span', { class: 'chev' }, can ? icon(kinds || (opts.walkable && r.folder) ? 'right' : 'finder') : null));
        if (kinds) tr.dataset.kind = r.name;
        tr.addEventListener('mouseenter', () => light(n < 14 ? n : null));
        tr.addEventListener('mouseleave', () => light(null));
        table.append(tr);
        rowEls.push(tr);
    });
    if (total) table.append(h('div', { class: 'total' }, h('b', null, tidyLabel(total.label)), h('span', null, total.value)));
    box.append(table);

    const extraRows = after.filter(p => p.k === 'row');
    if (extraRows.length) box.append(factList(extraRows));
    const said = sentences(after.filter(p => p.k !== 'row'));
    if (said) box.append(said);
    if (kinds) box.append(h('div', { class: 'kind-slot', id: 'kindslot' }));
    return box;
}

/* ── one kind of thing, opened: the files themselves ─────────────────── */

/* nimo's own rule for what a file is (lib/desktop.sh, nimo_kind_set), so
   what opens here is exactly what nimo counted */
const KIND_EXT = {
    Images: 'jpg jpeg png gif heic heif webp tiff tif bmp svg ico raw cr2 nef',
    Video: 'mp4 mov m4v avi mkv webm wmv flv',
    Audio: 'mp3 m4a wav aiff aif flac aac ogg',
    Documents: 'pdf doc docx pages txt rtf rtfd md key numbers xls xlsx csv tsv ppt pptx epub odt',
    Archives: 'zip tar gz tgz bz2 xz rar 7z dmg pkg iso',
    Code: 'sh bash zsh py js mjs ts tsx jsx json yml yaml html css scss swift c h cpp hpp java rb go rs php sql toml xml',
    Apps: 'app',
};
const EXT_KIND = {};
for (const [k, list] of Object.entries(KIND_EXT)) for (const e of list.split(' ')) EXT_KIND[e] = k;

function kindOf(f) {
    if (/\.app$/i.test(f.name)) return 'Apps';
    if (f.dir) return 'Folders';
    const name = f.name.toLowerCase();
    if (/^(screenshot|screen shot|snímka|snimka|cleanshot)/.test(name)) return 'Screenshots';
    const dot = name.lastIndexOf('.');
    const ext = dot >= 0 ? name.slice(dot + 1) : '';
    return EXT_KIND[ext] || 'Other';
}

/* what nimo leaves out of a folder altogether (nimo_folder_items): dotfiles,
   its own Tidy folder, anything still downloading, names it could not log */
function tidyName() {
    const said = String(K.meta.config.tidy || '').trim();
    return !said || /[\/\\]/.test(said) || said === '.' || said.includes('..') ? 'Tidy' : said;
}
const ARRIVING = /\.(download|crdownload|part|partial|opdownload|aria2|tmp|!ut)$/;
function countedByNimo(f) {
    return !f.name.startsWith('.') && f.name !== tidyName() && !ARRIVING.test(f.name) && !/[\t\n\r]/.test(f.name);
}

const KIND_PICTURE = { Screenshots: 'camera', Images: 'photo', Video: 'film', Audio: 'music', Documents: 'file',
                       Archives: 'box', Code: 'code', Apps: 'cube', Folders: 'folder', Other: 'dot' };

function ago(ms) {
    if (!ms) return '';
    const days = Math.floor((Date.now() - ms) / 86400000);
    if (days < 1) return 'today';
    if (days < 2) return 'yesterday';
    if (days < 31) return days + ' days ago';
    if (days < 365) return Math.round(days / 30) + ' months ago';
    return Math.round(days / 365) + (days < 730 ? ' year ago' : ' years ago');
}

/** The row of the kind that is open, marked; none when none is. */
function markKind(kind) {
    for (const tr of document.querySelectorAll('.table .tr[data-kind]')) tr.classList.toggle('open', tr.dataset.kind === kind);
}

function closeKind() {
    K.kindOpen = null;
    markKind(null);
    const slot = $('#kindslot');
    if (slot) slot.replaceChildren();
}

/* "Screenshot 2026-09-12 at 17.40.50.png": in a grid of them, the part worth
   reading is the when. The whole name is on the tile's tooltip. */
const SHOT_WORD = /^(screenshot|screen shot|snímka obrazovky|snimka obrazovky|snímka|snimka|cleanshot)\s+/i;
const SHOT_WHEN = /^(\d{4})-(\d{2})-(\d{2})\s+(?:at|o)\s+(\d{1,2}[.:]\d{2}[.:]\d{2}(?:\s?[AP]M)?)(?:\s+\(?(\d+)\)?)?\.[a-z0-9]{2,5}$/i;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function shortName(name) {
    const bare = name.replace(SHOT_WORD, '');
    if (bare === name) return name;
    const m = SHOT_WHEN.exec(bare);
    if (!m) return bare.replace(/\.[a-z0-9]{2,5}$/i, '');
    const [, y, mo, d, time, copy] = m;
    const year = parseInt(y, 10) === new Date().getFullYear() ? '' : ' ' + y;
    return `${parseInt(d, 10)} ${MONTHS[parseInt(mo, 10) - 1] || mo}${year}, ${time}` + (copy ? ` · ${copy}` : '');
}

/** What is in a page's folder, asked again after twenty seconds. */
async function listing(i) {
    K.listing = K.listing || {};
    if (!K.listing[i] || Date.now() - K.listing[i].at > 20000) {
        const reply = await ask('list', { page: i });
        K.listing[i] = { at: Date.now(), items: (reply && Array.isArray(reply.items) && reply.items) || [] };
    }
    return K.listing[i].items;
}

/** Small pictures for some names in a page's folder, laid on the elements
 *  that carry those names in `data-name`. */
async function paint(i, els) {
    const names = [...new Set(els.map(el => el.dataset.name))];
    for (let at = 0; at < names.length; at += 12) {
        const reply = await ask('thumbs', { page: i, names: names.slice(at, at + 12) });
        const got = (reply && reply.thumbs) || {};
        for (const el of els) {
            const uri = got[el.dataset.name];
            if (el.isConnected && uri && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(uri)) {
                el.style.backgroundImage = `url("${uri}")`;
                el.replaceChildren();
                el.classList.add('got');
            }
        }
    }
}

/** The newest few things on the desktop, for the home card about it. */
async function fillNewest(strip, i) {
    const items = await listing(i);
    if (!strip.isConnected) return;
    const folder = pages()[i].reveal;
    const newest = items.filter(countedByNimo).sort((a, b) => (b.modified || 0) - (a.modified || 0)).slice(0, 6);
    if (!newest.length) { strip.remove(); return; }
    const isPicture = f => ['Screenshots', 'Images'].includes(kindOf(f));
    const pictures = newest.filter(isPicture);
    const els = [];
    strip.replaceChildren(...newest.map((f, n) => {
        const kind = kindOf(f);
        const img = h('span', { class: 'img' }, icon(KIND_PICTURE[kind] || 'file'));
        if (isPicture(f)) { img.dataset.name = f.name; els.push(img); }
        return h('button', { class: 'nw', title: f.name, style: `animation-delay:${n * 25}ms`,
                             onclick: () => isPicture(f) ? openLight(i, folder, pictures, pictures.indexOf(f), strip)
                                                         : tell('show', { path: [folder, f.name] }) },
            img, h('span', { class: 'nm' }, shortName(f.name)), h('span', { class: 'when' }, ago(f.modified)));
    }));
    if (els.length) paint(i, els);
}

async function openKind(i, kind) {
    const slot = $('#kindslot');
    if (!slot) return;
    if (K.kindOpen === kind && slot.firstChild) { closeKind(); return; }
    K.kindOpen = kind;
    markKind(kind);
    slot.replaceChildren(h('div', { class: 'kind', style: 'margin-top:18px' }, h('div', { class: 'more loadingline' }, 'Loading…')));
    const items = await listing(i);
    if (K.kindOpen !== kind || !slot.isConnected) return;
    const files = items
        .filter(f => countedByNimo(f) && kindOf(f) === kind)
        .sort((a, b) => (b.modified || 0) - (a.modified || 0));
    const picture = kind === 'Screenshots' || kind === 'Images';
    const folder = pages()[i].reveal;

    const headRow = h('div', { class: 'kh' },
        h('span', { class: 'ico' }, icon(KIND_PICTURE[kind] || 'dot')),
        h('h3', null, kind), h('span', { class: 'pill' }, plural(files.length, 'item')),
        h('div', { class: 'r' },
            h('button', { class: 'btn line small', onclick: () => tell('reveal', { page: i }) }, icon('finder'), 'Show in Finder'),
            h('button', { class: 'btn bare small', 'data-tip': 'Close', onclick: closeKind }, icon('x'))));
    const shown = files.slice(0, picture ? 60 : 200);
    let body;
    if (picture) {
        body = h('div', { class: 'thumbs' });
        shown.forEach((f, n) => {
            const img = h('div', { class: 'img' }, icon(KIND_PICTURE[kind]));
            img.dataset.name = f.name;
            body.append(h('button', { class: 'thumb', style: `animation-delay:${Math.min(n, 20) * 10}ms`, title: f.name,
                                      onclick: () => openLight(i, folder, files, n, card) },
                img, h('div', { class: 'cap2' }, shortName(f.name), h('span', null, [f.size ? size(f.size) : '', ago(f.modified)].filter(Boolean).join(' · ')))));
        });
    } else {
        body = h('div', { class: 'files' });
        shown.forEach((f, n) => {
            body.append(h('div', { class: 'file', style: `animation-delay:${Math.min(n, 20) * 8}ms`,
                                   onclick: () => tell('show', { path: [folder, f.name] }) },
                h('span', { class: 'ico' }, icon(f.dir ? 'folder' : KIND_PICTURE[kind] || 'file')),
                h('span', { class: 'nm' }, f.name),
                h('span', { class: 'sz' }, f.dir ? 'folder' : f.size ? size(f.size) : ''),
                h('span', { class: 'age' }, ago(f.modified)),
                h('span', { class: 'go2' }, icon('finder'))));
        });
    }
    const note = files.length > shown.length ? h('div', { class: 'more' }, `${files.length - shown.length} more in Finder`) : null;
    const card = h('div', { class: 'kind', style: 'margin-top:18px;padding-top:18px;border-top:1px solid var(--line)' }, headRow, body, note,
        h('div', { class: 'more' }, picture
            ? 'Click a picture to see it big. Use the arrow keys to browse.'
            : 'Click a file to show it in Finder.'));
    slot.replaceChildren(card);
    card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

    // the pictures themselves, drawn small by the Mac, a batch at a time
    if (picture && shown.length) {
        const names = shown.map(f => f.name);
        for (let at = 0; at < names.length; at += 12) {
            const reply = await ask('thumbs', { page: i, names: names.slice(at, at + 12) });
            if (K.kindOpen !== kind || !card.isConnected) return;
            const got = (reply && reply.thumbs) || {};
            for (const img of card.querySelectorAll('.img')) {
                const uri = got[img.dataset.name];
                if (uri && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(uri)) {
                    img.style.backgroundImage = `url("${uri}")`;
                    img.replaceChildren();
                    img.classList.add('got');
                }
            }
        }
    }
}

/* ── the same file, kept more than once ───────────────────────────────── */

/* `min duplicates <folder>`: nimo finds files of one size, then reads only
   those to see which really are the same. It never deletes one — it cannot
   know which you meant — so neither does this. */
function copiesOf(raw) {
    const groups = [];
    let total = null;
    for (const line of String(raw || '').split('\n')) {
        const bare = line.replace(ANSI, '').replace(/\s+$/, '');
        const t = bare.trim();
        if (!t) continue;
        let m = /^also {2,}(.+)$/.exec(t);
        if (m) { if (groups.length) groups[groups.length - 1].also.push(m[1]); continue; }
        m = /^(.+?) {2,}(\d[\d.,]*\s?(?:B|KB|MB|GB|TB))(?: {2,}(.+))?$/.exec(t);
        if (!m) continue;
        if (/kept more than once$/.test(m[1])) { total = { label: m[1], value: m[2] }; continue; }
        if (/^ {4,}/.test(bare)) groups.push({ name: m[1], size: m[2], folder: (m[3] || '').replace(/\/$/, ''), also: [] });
    }
    return { groups: groups.filter(g => g.also.length), total };
}

/** Reading every file of the same size takes seconds, so it is asked for
 *  rather than run on its own. The answer is kept until something moves. */
function copiesFor(list) {
    K.copies = K.copies || {};
    return Promise.all(list.map(n => {
        if (!K.copies[n]) {
            K.copies[n] = { at: Date.now(), answer: ask('copies', { page: n })
                .then(reply => Object.assign({ page: n }, copiesOf(reply && reply.text))) };
        }
        return K.copies[n].answer;
    }));
}

function copiesDone(list) {
    return list.every(n => K.copies && K.copies[n]);
}

/** The button that starts it, and the line that says what it will do. */
function copiesAsk(list, where, start) {
    return h('div', { class: 'ask-copies' },
        h('div', null, h('b', null, 'Look for duplicates'),
          h('span', null, 'Kliner compares files of the same size in ' + where + ', byte by byte. It takes a few seconds and changes nothing.')),
        h('button', { class: 'btn line', onclick: start }, icon('copies'), 'Look'));
}

function copyGroups(results) {
    const groups = [];
    for (const r of results) for (const g of r.groups) {
        const each = bytes(g.size) || 0;
        const first = (g.folder ? g.folder + '/' : '') + g.name;
        groups.push(Object.assign({ page: r.page, each, n: 1 + g.also.length, paths: [first, ...g.also] }, g));
    }
    for (const g of groups) g.extra = g.each * (g.n - 1);
    return groups.sort((a, b) => b.extra - a.extra);
}

/** The copies that sit right in the page's own folder, as files it lists. */
function topCopies(g, folder) {
    return g.paths.filter(p => p.startsWith(folder + '/') && !p.slice(folder.length + 1).includes('/'))
                  .map(p => ({ name: p.slice(folder.length + 1), size: g.each }));
}

function showPath(path) {
    const parts = path.split('/').filter(x => x !== '');
    if (parts.length) tell('show', { path: parts });
}

function copiesPanel(i, kept) {
    const folder = pages()[i].reveal;
    const body = h('div', { class: 'copybody' });
    const box = panel('copies', cap('copies', 'Duplicates', h('span', null, 'in ' + folder)), body);
    const run = () => {
        body.replaceChildren(h('div', { class: 'more loadingline' }, 'Reading files of the same size…'));
        fill();
    };
    if (copiesDone([i])) fill();
    else body.append(copiesAsk([i], folder, run));
    function fill() {
    copiesFor([i]).then(results => {
        if (!body.isConnected) return;
        const groups = copyGroups(results);
        if (!groups.length) {
            body.replaceChildren(h('div', { class: 'clear' }, h('span', { class: 'tick' }, icon('check')),
                h('div', null, h('b', null, 'No duplicates.'),
                  h('span', null, 'Files of the same size were compared. None are identical.'))));
            return;
        }
        const extra = groups.reduce((a, g) => a + g.extra, 0);
        const list = h('div', { class: 'copylist' });
        const pictures = [];
        groups.forEach((g, n) => {
            const kind = kindOf({ name: g.name });
            const tops = topCopies(g, folder);
            const pic = h('span', { class: 'pic' }, icon(KIND_PICTURE[kind] || 'file'));
            const viewable = (kind === 'Screenshots' || kind === 'Images') && tops.length > 0;
            if (viewable) { pic.dataset.name = tops[0].name; pictures.push(pic); }
            const paths = h('div', { class: 'paths' });
            g.paths.forEach(path => paths.append(h('button', { class: 'path', onclick: () => showPath(path) },
                h('span', { class: 'nm' }, path), h('span', { class: 'go2' }, icon('finder'), 'Show in Finder'))));
            const row = h('div', { class: 'group', style: `animation-delay:${30 + n * 25}ms` });
            const top = h('button', { class: 'gtop', onclick: () => row.classList.toggle('open') },
                pic,
                h('span', { class: 'nm' }, h('b', null, g.name), h('span', null, whereCopies(g))),
                h('span', { class: 'pill' + (n === 0 ? ' hi' : '') }, '×' + g.n),
                h('span', { class: 'num each' }, size(g.each) + ' each'),
                h('span', { class: 'num extra' }, '+' + size(g.extra)),
                h('span', { class: 'chev' }, icon('right')));
            if (viewable) pic.addEventListener('click', e => { e.stopPropagation(); openLight(i, folder, tops, 0, list); });
            row.append(top, paths);
            list.append(row);
        });
        body.replaceChildren(
            bigFigure(size(extra), 'in extra copies of ' + plural(groups.length, 'file'),
                      { d: plural(groups.reduce((a, g) => a + g.n - 1, 0), 'extra copy', 'extra copies'), w: 'besides the originals' }),
            list,
            h('div', { class: 'more' }, 'Kliner does not delete duplicates. Open them in Finder and keep the one you want.'));
        runCounts(body);
        // the pictures themselves, when there are any
        if (pictures.length) ask('thumbs', { page: i, names: pictures.map(p => p.dataset.name).slice(0, 24) }).then(reply => {
            const got = (reply && reply.thumbs) || {};
            for (const pic of pictures) {
                const uri = got[pic.dataset.name];
                if (uri && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(uri)) {
                    pic.style.backgroundImage = `url("${uri}")`;
                    pic.replaceChildren();
                    pic.classList.add('got');
                }
            }
            for (const img of list.querySelectorAll('.pic.got')) img.dataset.tip = 'See it big';
        });
    });
    }
    return box;
}

function whereCopies(g) {
    const places = [...new Set(g.paths.map(p => p.includes('/') ? p.slice(0, p.lastIndexOf('/')) : '~'))];
    return places.length === 1 ? `${g.n} copies in ${places[0]}` : `in ${places.slice(0, 2).join(' and ')}${places.length > 2 ? ` and ${places.length - 2} more` : ''}`;
}

/** The home card: copies on the desktop and in Downloads, the biggest first. */
function copiesCard(kept) {
    const list = [pages().findIndex(p => p.kind === 'desktop'), pages().findIndex(p => p.kind === 'downloads')].filter(n => n > 0);
    const body = h('div', { class: 'copycard' });
    const box = panel('', cap('copies', 'Duplicates', 'Desktop · Downloads'), body);
    if (!list.length) return promiseCard({});
    const run = () => {
        body.replaceChildren(h('div', { class: 'more loadingline' }, 'Reading files of the same size…'));
        fill();
    };
    if (copiesDone(list)) fill();
    else body.append(copiesAsk(list, 'your desktop and Downloads', run));
    function fill() {
    copiesFor(list).then(results => {
        if (!body.isConnected) return;
        const groups = copyGroups(results);
        if (!groups.length) {
            body.replaceChildren(h('div', { class: 'promise' },
                h('div', { class: 'marks' }, h('span', null, icon('copies')), h('span', null, icon('check'))),
                h('h4', null, 'No duplicates'),
                h('p', null, 'Nothing on your desktop or in Downloads is saved twice.')));
            return;
        }
        const extra = groups.reduce((a, g) => a + g.extra, 0);
        const most = Math.max(1, ...groups.map(g => g.extra));
        const rows = h('div', { class: 'list' });
        for (const g of groups.slice(0, 3)) {
            rows.append(h('div', { style: 'cursor:pointer', onclick: () => { K.scrollTo = '.panel.copies'; show(g.page); } },
                h('div', { class: 'l' }, h('b', null, g.name), h('span', { class: 'pill' }, '×' + g.n),
                  h('span', { class: 'v' }, '+' + size(g.extra))),
                dashes(g.extra / most)));
        }
        body.replaceChildren(
            h('div', { class: 'copyfig' }, h('div', { class: 'n' }, counted(figure(size(extra))[0]), h('small', null, figure(size(extra))[1] || '')),
              h('div', { class: 'sub' }, 'in extra copies of ' + plural(groups.length, 'file'))),
            rows);
        runCounts(body);
    });
    }
    return box;
}

/* ── one picture, big: Kliner's own viewer ────────────────────────────── */

/* the Mac draws it; the page only shows what came back. Nothing is opened in
   another app — Show in Finder is the way out to the file itself. */
const BIG = new Map();
async function bigPicture(i, name) {
    if (BIG.has(name)) return BIG.get(name);
    const reply = await ask('picture', { page: i, name });
    const uri = reply && reply.picture;
    const ok = uri && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(uri) ? uri : null;
    if (ok) {
        BIG.set(name, ok);
        if (BIG.size > 24) BIG.delete(BIG.keys().next().value);
    }
    return ok;
}

function closeLight() {
    const box = $('#light');
    if (!box) return;
    document.removeEventListener('keydown', box._keys, true);
    box.classList.add('going');
    setTimeout(() => box.remove(), 180);
}

function openLight(i, folder, files, at, card) {
    closeLight();
    const small = name => {
        const img = card && [...card.querySelectorAll('[data-name]')].find(el => el.dataset.name === name);
        const m = img && /url\("(.+)"\)/.exec(img.style.backgroundImage || '');
        return m ? m[1] : null;
    };
    const pic = h('img', { class: 'pic', alt: '' });
    const hint = h('div', { class: 'loading' }, icon('photo'));
    const name = h('b');
    const about = h('span');
    const count = h('span', { class: 'of' });
    const stage = h('div', { class: 'stage' }, pic, hint);
    const prev = h('button', { class: 'sq', 'data-tip': 'Previous', onclick: () => go(at - 1) }, icon('left'));
    const next = h('button', { class: 'sq', 'data-tip': 'Next', onclick: () => go(at + 1) }, icon('right'));
    const box = h('div', { class: 'light', id: 'light', role: 'dialog', 'aria-modal': 'true' },
        h('div', { class: 'shade', onclick: closeLight }),
        h('figure', { class: 'sheet' }, stage,
            h('figcaption', null,
                h('div', { class: 't' }, name, about),
                h('div', { class: 'acts' }, prev, count, next,
                    h('button', { class: 'btn line small', onclick: () => tell('show', { path: [folder, files[at].name] }) },
                      icon('finder'), 'Show in Finder'),
                    h('button', { class: 'sq', 'data-tip': 'Close', onclick: closeLight }, icon('x'))))));
    let ask_ = 0;
    async function go(n) {
        if (n < 0 || n >= files.length) return;
        at = n;
        const f = files[at];
        name.textContent = f.name;
        about.textContent = [f.size ? size(f.size) : '', ago(f.modified)].filter(Boolean).join(' · ');
        count.textContent = `${at + 1} of ${files.length}`;
        prev.disabled = at === 0;
        next.disabled = at === files.length - 1;
        // the small one at once, soft; the big one when the Mac has drawn it
        const first = small(f.name);
        stage.classList.remove('sharp');
        stage.classList.toggle('empty', !first);
        if (first) pic.src = first; else pic.removeAttribute('src');
        const mine = ++ask_;
        const big = await bigPicture(i, f.name);
        if (mine !== ask_ || !box.isConnected) return;
        if (big) { pic.src = big; stage.classList.remove('empty'); stage.classList.add('sharp'); }
        else stage.classList.add('sharp');
        // the next one, ready before it is asked for
        if (files[at + 1]) bigPicture(i, files[at + 1].name);
    }
    box._keys = e => {
        if (e.key === 'Escape' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); closeLight(); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); go(at - 1); }
        else if (e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); go(at + 1); }
        else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') { e.preventDefault(); e.stopPropagation(); }
    };
    document.addEventListener('keydown', box._keys, true);
    document.body.append(box);
    wireTips(box);
    go(at);
}

function plainPanel(sec, i) {
    const box = panel('');
    if (sec.title) box.append(cap(null, title(sec.title)));
    const rows = [];
    const rest = [];
    let ruled = false;
    for (const p of sec.pieces) {
        if (p.k === 'rule') { ruled = true; continue; }
        if (p.k === 'row' && p.label) rows.push(Object.assign({ total: ruled }, p));
        else if (p.k !== 'note') rest.push(p);
    }
    const said = sentences(rest.filter(p => p.k !== 'item'));
    if (said) box.append(said);
    if (rows.length) box.append(factList(rows, i));
    const items = rest.filter(p => p.k === 'item');
    if (items.length) box.append(entryList(items));
    return box;
}

function factList(rows, i) {
    const list = h('div', { class: 'facts' });
    for (const r of rows) {
        const halves = r.value.split(' of ');
        let meter = null;
        if (halves.length === 2) {
            const a = bytes(halves[0].replace(/\s*free$/, '')), b = bytes(halves[1]);
            if (a != null && b > 0) {
                const part = /free$/.test(halves[0]) ? 1 - a / b : a / b;
                meter = h('div', { class: 'meter' }, h('i', { style: `width:${(part * 100).toFixed(1)}%` }));
            }
        } else if (r.bar != null) {
            meter = h('div', { class: 'meter' }, h('i', { style: `width:${Math.max(2, r.bar * 100)}%` }));
        }
        const note = r.note ? r.note.replace(/^[→·\s]+/, '') : '';
        list.append(h('div', { class: 'fact' + (r.total ? ' total' : '') },
            h('span', { class: 'k' }, r.label),
            h('span', { class: 'v' + (r.strong ? ' strong' : '') }, /^min /.test(r.value) ? prose(r.value) : r.value),
            meter || (note ? h('span', { class: 'n' }, prose(note)) : h('span'))));
    }
    return list;
}

function entryList(items) {
    const log = h('div', { class: 'log' });
    for (const it of items) {
        log.append(h('div', { class: 'e' },
            h('span', { class: 'no' }, String(it.no)),
            h('span', { class: 'what' }, title(it.parts[0] || '')),
            h('span', { class: 'when' }, it.parts[1] || ''),
            h('span', { class: 'many' }, it.parts.slice(2).join(' · '))));
    }
    return log;
}

function sentences(list) {
    const kept = list.filter(p => p.k === 'good' || p.k === 'warn' || p.k === 'text');
    if (!kept.length) return null;
    const box = h('div', { class: 'said' });
    for (const p of kept) {
        if (p.k === 'text') { box.append(h('div', { class: 's quiet' }, h('span', null, prose(p.text)))); continue; }
        box.append(h('div', { class: 's ' + (p.k === 'good' ? 'good' : 'warn') },
            icon(p.k === 'good' ? 'check' : 'x'), h('span', null, prose(p.text))));
    }
    return box;
}

/** nimo's last lines, under the panels, minus the ones for a terminal. */
function footnotes(pieces) {
    const lines = [];
    let pastGood = false;
    for (const p of pieces) {
        if (p.k === 'good') pastGood = true;
        if (p.k !== 'note') continue;
        const t = p.text;
        if (pastGood) continue;                     // those went into the banner
        if (/^(run |in a terminal|to see what|looking around|changed your mind)/.test(t)) continue;
        // commands for a terminal, and what the page already says in its own words
        if (/\bmin [a-z]|<kind>|^preview only|^nothing was moved|^everything moves into/i.test(t)) continue;
        lines.push(t);
    }
    if (!lines.length) return null;
    // nimo wraps a long line in two for a terminal; a window joins them again
    const joined = [];
    for (const t of lines) {
        if (joined.length && !/[.!?:]$/.test(joined[joined.length - 1])) joined[joined.length - 1] += ' ' + t;
        else joined.push(t);
    }
    return h('div', { class: 'notes' }, joined.map(t => h('div', null, prose(tidyLine(t)))));
}

/* ── the Dock: what is in it, and what can come out ───────────────────── */

function drawDock(out, pieces) {
    const items = pieces.filter(p => p.k === 'item');
    const total = pieces.find(p => p.k === 'row' && /in your dock/i.test(p.label || ''));
    if (!items.length) {
        const said = sentences(pieces);
        out.append(panel('', said || h('div', { class: 'said' }, h('div', { class: 's quiet' }, 'Kliner cannot read your Dock.'))));
        return;
    }
    const list = h('div', { class: 'stops' });
    items.forEach((it, n) => {
        const name = it.parts[0] || '';
        const hint = it.parts.slice(1).join(' ');
        list.append(h('div', { class: 'stop', style: `animation-delay:${Math.min(n, 16) * 18}ms` },
            h('span', { class: 'ico' }, icon('cube')),
            h('div', { style: 'min-width:0' }, h('div', { class: 'nm' }, name),
              hint ? h('div', { class: 'cm' }, hint) : null),
            h('button', { class: 'btn line small', onclick: () => unpin(name) }, icon('x'), 'Take out')));
    });
    out.append(panel('', cap('grid', 'In your Dock', total ? h('span', null, total.value) : null), list,
        h('div', { class: 'more' }, 'Taking an app out of the Dock does not uninstall it. Kliner saves your Dock first, so Put the Dock back is exact.')));
}

async function unpin(name) {
    if (K.busy) return;
    K.busy = true;
    busyButtons(true);
    let reply;
    try { reply = await ask('unpin', { name }); } finally { K.busy = false; }
    busyButtons(false);
    if (!reply || reply.cancelled) return;
    delete K.kept[K.page];
    look(K.page);
    const good = parse(reply.text || '').find(p => p.k === 'good');
    if (good) toast(good.text, null);
}

/* ── Startup: each thing with its own Stop ────────────────────────────── */

function drawStartup(out, pieces) {
    const secs = sections(pieces);
    let stoppable = true;
    let drew = false;
    for (const sec of secs) {
        const rows = [];
        let total = null, ruled = false;
        for (const p of sec.pieces) {
            // nimo lists what it can stop, then says it "only reports" the
            // rest: nothing after that sentence is Kliner's to stop
            if ((p.k === 'note' || p.k === 'text') && /only reports/.test(p.text)) stoppable = false;
            if (p.k === 'rule') { ruled = true; continue; }
            if (p.k === 'row' && p.label) {
                if (ruled) total = p;
                else rows.push(Object.assign({ stoppable }, p));
            }
        }
        if (!rows.length && !total) {
            const said = sentences(sec.pieces);
            if (said) { out.append(panel('', sec.title ? cap(null, title(sec.title)) : null, said)); drew = true; }
            continue;
        }
        const list = h('div', { class: 'stops' });
        for (const r of rows) {
            const agent = /agent/i.test(r.value);
            list.append(h('div', { class: 'stop' },
                h('span', { class: 'ico' }, icon(agent ? 'cpu' : 'power')),
                h('div', { style: 'min-width:0' }, h('div', { class: 'nm' }, r.label), h('div', { class: 'kd' }, r.value)),
                r.stoppable ? h('button', { class: 'btn line small', onclick: () => stopOne(r.label) }, icon('slash'), 'Stop')
                            : h('span', { class: 'pill' }, 'reported only')));
        }
        out.append(panel('', cap('power', title(sec.title), total ? h('span', null, total.label + ' · ' + total.value) : null), list));
        drew = true;
    }
    const notes = footnotes(pieces);
    if (notes) out.append(notes);
    if (!drew) out.append(panel('', sentences(pieces) || h('div', { class: 'said' }, h('div', { class: 's quiet' }, 'No results.'))));
}

/* ── Put it all back: the log, newest first ───────────────────────────── */

function drawUndo(out, i, pieces) {
    if (K.kept[i] && K.kept[i].result) {
        const notes = footnotes(pieces);
        if (notes) out.append(notes);
        return;
    }
    const items = pieces.filter(p => p.k === 'item');
    const count_ = pieces.find(p => p.k === 'text' && /to put back/.test(p.text));
    if (!items.length) {
        const good = pieces.find(p => p.k === 'good');
        out.append(panel('', h('div', { class: 'promise' },
            h('div', { class: 'marks' }, h('span', null, icon('tray')), h('span', null, icon('check'))),
            h('h4', null, good ? good.text : 'Nothing to undo.'),
            h('p', null, 'Every move Kliner makes is logged here, so it can be undone.'))));
        const notes = footnotes(pieces);
        if (notes) out.append(notes);
        return;
    }
    out.append(panel('', cap('undo', count_ ? title(count_.text) : 'History', h('span', null, 'newest first')),
                     entryList(items)));
    const notes = footnotes(pieces);
    if (notes) out.append(notes);
}

/* ── Wallpaper ────────────────────────────────────────────────────────── */

/** Where your own wallpapers go. Kliner lists what is in it first. */
function wallFolder() {
    return panel('', cap('folder', 'Your own wallpapers'),
        h('div', { class: 'ask-copies' },
            h('div', null, h('b', null, 'Pictures / Kliner Wallpapers'),
              h('span', null, 'Anything you drop in that folder is stepped through with the ones that came with your Mac. JPEG, PNG or HEIC.')),
            h('button', { class: 'btn line', onclick: () => tell('wallFolder') }, icon('finder'), 'Open folder')));
}

function drawWalls(out, i, pieces) {
    const now = pieces.find(p => p.k === 'good');
    if (!K.walls) {
        out.append(panel('', h('div', { class: 'promise' }, eyesMark('promise-mark'),
            h('h4', { style: 'margin-top:12px' }, 'Ready when you are.'),
            h('p', null, 'Nothing changes until you press Next.'))));
        return;
    }
    // Click the picture, not a button beside it: the pictures are the
    // control. Previous, Original and Next are still up in the title strip.
    const grid = h('div', { class: 'walls' });
    for (const w of K.walls) {
        const pick = K.wallOn === w.no || (K.wallOn ? false
            : now ? w.parts[0] === now.text : /would pick/.test(w.parts.slice(1).join(' ')));
        const drawn = K.wallPics && K.wallPics[String(w.no)];
        const sheet = drawn
            ? h('span', { class: 'sheet has' }, h('img', { class: 'pic got', src: drawn, alt: '' }))
            : h('span', { class: 'sheet' }, icon('photo'));
        grid.append(h('button', { class: 'wall' + (pick ? ' pick' : ''), 'data-tip': 'Put this one on',
                                  onclick: () => putOnWall(w.no) },
            sheet,
            h('span', { class: 'nm' }, w.parts[0]),
            h('span', { class: 'foot' }, h('span', { class: 'no' }, String(w.no)),
              pick ? h('span', { class: 'pill' + (K.wallOn === w.no || now ? ' hi' : '') },
                        K.wallOn === w.no || now ? 'on now' : 'suggested') : null)));
    }
    out.append(panel('', cap('photo', 'Wallpapers', h('span', null, plural(K.walls.length, 'wallpaper'))), grid));
    out.append(wallFolder());
}

/* ── How it is ────────────────────────────────────────────────────────── */

function drawDoctor(out, pieces) {
    const f = facts(pieces);
    const across = h('div', { class: 'grid four' });
    if (f.Disk) {
        const [a, b] = f.Disk.value.split(' of ');
        const free = bytes((a || '').replace(/\s*free$/, '')) || 0, total = bytes(b) || 0;
        if (total > 0) across.append(tile('Disk', 'disk', size(total - free), { part: (total - free) / total, pill: percent(total - free, total) + ' used', foot: 'of ' + size(total) }));
    }
    if (f.Memory) across.append(tile('Memory', 'cpu', f.Memory.value, { foot: 'installed' }));
    if (f.Battery) {
        const pct = count(f.Battery.value);
        const rest = f.Battery.value.replace(/^\s*\d+%\s*·?\s*/, '');
        across.append(tile('Battery', 'bolt', pct + '%', { part: pct / 100, foot: rest }));
    }
    if (f.Uptime) across.append(tile('Uptime', 'clock', f.Uptime.value, { foot: 'since the last restart' }));
    if (across.children.length) out.append(across);
    // readings are facts, each its own kind of thing — a battery is not a
    // share of a disk — so they are listed, never charted against each other
    // and the rows that only mean something in a terminal
    const own = new Set(['Months', 'Desktop older', 'Downloads older', 'Last change', 'Next', 'nimo']);
    for (const sec of sections(pieces)) {
        const kept = sec.pieces.filter(p => !(p.k === 'row' && own.has(p.label)))
            .map(p => (p.k === 'row' && /\bmin [a-z]/.test(p.note || '') ? Object.assign({}, p, { note: '' }) : p));
        if (!kept.some(p => p.k !== 'note')) continue;
        out.append(plainPanel({ title: sec.title, pieces: kept }, K.page));
    }
    const notes = footnotes(pieces);
    if (notes) out.append(notes);
}

/* ── walking into a folder ────────────────────────────────────────────── */

function drawWalk(out) {
    const where = K.walked[K.walked.length - 1];
    out.append(h('div', { class: 'head' },
        h('div', { class: 'words' },
            h('h1', null, where),
            h('p', null, 'What takes up space in ' + K.walked.join('/') + ', largest first.')),
        h('div', { class: 'acts' },
            h('button', { class: 'btn line', onclick: walkUp }, icon('left'), 'Back out'))));
    const pieces = K.walkedPieces || [];
    const parts = sections(pieces);
    for (const sec of parts) {
        const rows = sec.pieces.filter(p => p.k === 'row' && p.label && weigh(p.value) != null);
        if (rows.length > 1) out.append(breakdown(sec, K.page, { walkable: true }));
        else out.append(plainPanel(sec, K.page));
    }
}

/* ── Settings ─────────────────────────────────────────────────────────── */

async function drawSettings(out) {
    out.append(h('div', { class: 'head' }, h('div', { class: 'words' },
        h('h1', null, 'Settings'), h('p', null, 'Preferences and permissions.'))));
    const holder = h('div');
    out.append(holder);
    const st = await ask('settings');
    if (K.page !== SETTINGS()) return;
    holder.replaceChildren(settingsBody(st || {}));
}

function settingsBody(st) {
    const days = String((K.meta.config.days || '30'));
    const kliner = panel('', cap('gear', 'Kliner'),
        setting('Open at login', st.login && st.login.possible ? 'Kliner starts in the menu bar when you log in.' : 'Opening at login needs macOS 13 or newer.',
            h('button', { class: 'switch' + (st.login && st.login.on ? ' on' : ''), disabled: !(st.login && st.login.possible),
                          onclick: async e => { const b = e.currentTarget; const r = await ask('setLogin', { on: !b.classList.contains('on') }); b.classList.toggle('on', !!(r && r.on)); } })),
        setting('Old files', 'How long before a file counts as old.',
            seg(['7', '30', '90'], days, v => { K.meta.config.days = v; tell('setConfig', { key: 'days', value: v }); }, v => v + ' days')),
        setting('Preview mode', 'Buttons only show what would happen. Nothing changes while this is on.',
            h('button', { class: 'switch' + (K.preview ? ' on' : ''), onclick: e => { flipPreview(); e.currentTarget.classList.toggle('on', K.preview); } })),
        setting('Welcome tour', 'The screens from the first time you opened Kliner.',
            h('button', { class: 'btn line small', onclick: startWelcome }, 'Show again')));

    const fd = !!st.fullDisk, folders = !!st.folders;
    const allowed = panel('', cap('shield', 'Permissions'),
        setting(h('span', { class: 'state' + (fd ? ' yes' : '') }, h('i'), fd ? 'Full Disk Access: on' : 'Full Disk Access: off'),
            'With it on, macOS stops asking about each folder. Kliner still only reads your home folder.',
            h('button', { class: 'btn line small', onclick: async () => { await ask('fullDisk'); drawPage(true); } }, fd ? 'Settings' : 'Turn on')),
        setting(h('span', { class: 'state' + (folders ? ' yes' : '') }, h('i'), folders ? 'Folders' : 'Folders: not allowed yet'),
            'Desktop, Downloads, Pictures and Documents.',
            h('button', { class: 'btn line small', onclick: async () => { await ask('askFolders'); drawPage(true); } }, folders ? 'Check again' : 'Ask')),
        setting('Wallpaper', 'macOS asks once before Kliner can change your wallpaper.',
            h('button', { class: 'btn line small', onclick: () => tell('automation') }, 'Settings')));

    const promise = panel('', cap('lock', 'What Kliner never does'),
        h('div', { class: 'said' },
            ['Ask for your admin password.', 'Go online. There is no network code in it.',
             'Touch anything outside your home folder.', 'Move a file without logging it first.']
                .map(t => h('div', { class: 's no' }, icon('x'), h('span', null, t)))));

    return h('div', { style: 'display:grid;gap:14px' }, h('div', { class: 'grid two' }, kliner, h('div', { style: 'display:grid;gap:14px;align-content:start' }, allowed, promise)),
        h('div', { class: 'notes' }, h('div', null, `Kliner ${K.meta.version} · MIT · kliner.app`)));
}

function setting(t, d, control) {
    return h('div', { class: 'set' }, h('div', null, h('div', { class: 't' }, t), d ? h('div', { class: 'd' }, d) : null), control);
}

function seg(values, current, pick, label) {
    const box = h('div', { class: 'seg' });
    for (const v of values) {
        box.append(h('button', { class: v === current ? 'on' : '', onclick: e => {
            for (const b of box.children) b.classList.remove('on');
            e.currentTarget.classList.add('on');
            pick(v);
        } }, label ? label(v) : v));
    }
    return box;
}

/* ── Help ─────────────────────────────────────────────────────────────── */

function drawHelp(out) {
    out.append(h('div', { class: 'head' }, h('div', { class: 'words' },
        h('h1', null, 'Help'), h('p', null, 'Keyboard shortcuts.'))));
    const keys = [
        ['Quick menu, from anywhere', '⌘K'], ['Refresh', '⌘R'], ['Back', '⌘['], ['Forward', '⌘]'],
        ['Go to a page', '⌘1 – ⌘9'], ['Settings', '⌘,'], ['Show labels', '⌘B'], ['Previous or next page', '↑ ↓'],
    ];
    const left = panel('', cap('bolt', 'Keys'), h('div', { class: 'keys', style: 'margin-top:10px' },
        keys.map(([t, k]) => h('div', { class: 'kr' }, h('span', null, t), h('kbd', null, k)))));
    const list = h('div', { class: 'todo' });
    pages().forEach((p, n) => {
        list.append(h('div', { class: 't', style: 'cursor:pointer', onclick: () => show(n) },
            h('span', { class: 'ico' }, icon(p.symbol)),
            h('div', { style: 'min-width:0' }, h('div', { class: 'nm' }, h('span', null, p.title)), h('div', { class: 'cm' }, p.command || '')),
            h('div', { class: 'go' }, h('span', { class: 'fig' }, n < 9 ? '⌘' + (n + 1) : ''), icon('right'))));
    });
    const right = panel('', cap('list', 'Every page'), list);
    out.append(h('div', { class: 'grid two' }, left, right));
}

/* ── what Kliner has done, since it opened ────────────────────────────── */

function toggleActivity() {
    const open = $('.pop');
    if (open) { open.remove(); return; }
    K.unread = false;
    setFrame();
    const pop = h('div', { class: 'pop' }, h('div', { class: 'ph' }, 'This session'));
    if (!K.jobs.length) pop.append(h('div', { class: 'none' }, 'Nothing yet. What Kliner does shows up here.'));
    for (const j of K.jobs) {
        pop.append(h('div', { class: 'pr', style: 'cursor:pointer', onclick: () => { show(j.page); } },
            icon(j.preview ? 'eye' : j.good ? 'check' : 'x', j.good && !j.preview ? 'good' : ''),
            h('div', { style: 'min-width:0' }, h('div', null, j.title), h('div', { style: 'color:var(--muted);font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis' }, j.line)),
            h('span', null, j.at.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }))));
    }
    document.body.append(pop);
}
function closeActivity() { const open = $('.pop'); if (open) open.remove(); }
document.addEventListener('mousedown', e => {
    const pop = $('.pop');
    if (pop && !pop.contains(e.target) && !e.target.closest('#bell')) pop.remove();
});

let toastTimer = 0;
function toast(text, action) {
    document.querySelector('.toast')?.remove();
    clearTimeout(toastTimer);
    const el = h('div', { class: 'toast' }, icon('check'), h('span', null, text),
        action ? h('button', { class: 'btn line small', onclick: () => { el.remove(); action[1](); } }, action[0]) : null);
    document.body.append(el);
    toastTimer = setTimeout(() => el.remove(), 7000);
}

/* ── Activity: what the Mac is doing, every two seconds ──────────────── */

const LIVE = { timer: 0, cpu: [], mem: [], by: 'cpu', last: null };

function stopActivity() {
    clearTimeout(LIVE.timer);
    LIVE.timer = 0;
}

function drawActivity(out) {
    out.append(h('div', { class: 'head' },
        h('div', { class: 'words' }, h('h1', null, 'Activity'),
          h('p', null, 'What your Mac is doing right now. It updates every two seconds.')),
        h('div', { class: 'acts' },
            h('button', { class: 'btn line', onclick: closeApps }, icon('x'), 'Close all apps'),
            h('button', { class: 'btn line', onclick: () => tell('monitor') }, icon('finder'), 'Open Activity Monitor'))));
    const cpuBox = panel('live', cap('pulse', 'CPU', h('span', { class: 'livedot' }, 'live')),
        h('div', { class: 'lv' }, h('span', { class: 'n', id: 'cpuN' }, '…'), h('span', { class: 'u', id: 'cpuU' }, '')),
        spark('cpuS'));
    const memBox = panel('live', cap('cpu', 'Memory', h('span', { class: 'livedot' }, 'live')),
        h('div', { class: 'lv' }, h('span', { class: 'n', id: 'memN' }, '…'), h('span', { class: 'u', id: 'memU' }, '')),
        h('div', { class: 'meter big-meter' }, h('i', { id: 'memBar', style: 'width:0%' })),
        spark('memS'));
    const seg = h('div', { class: 'seg', id: 'bySeg' },
        h('button', { class: LIVE.by === 'cpu' ? 'on' : '', onclick: () => { LIVE.by = 'cpu'; paintActivity(); } }, 'CPU'),
        h('button', { class: LIVE.by === 'memory' ? 'on' : '', onclick: () => { LIVE.by = 'memory'; paintActivity(); } }, 'Memory'));
    const list = panel('', cap('bars', 'Using the most', seg), h('div', { class: 'apps', id: 'apps' },
        h('div', { class: 'more loadingline' }, 'Looking…')));
    out.append(h('div', { class: 'grid two' }, cpuBox, memBox), list);
    stopActivity();
    if (LIVE.last) requestAnimationFrame(paintActivity);
    tickActivity();
}

async function closeApps() {
    const reply = await ask('closeApps');
    if (!reply || reply.cancelled) return;
    if (reply.closed > 0) toast(plural(reply.closed, 'app') + ' asked to quit', null);
    else toast('Nothing else is open', null);
}

function spark(id) {
    const svg = s('svg', { class: 'spark', id, viewBox: '0 0 300 60', preserveAspectRatio: 'none' });
    svg.append(s('line', { class: 'base', x1: 0, x2: 300, y1: 57, y2: 57 }), s('path', { class: 'area', d: '' }), s('path', { class: 'ln', d: '' }));
    return svg;
}

async function tickActivity() {
    if (K.page !== ACTIVITY()) return;
    const reply = await ask('activity');
    if (K.page !== ACTIVITY()) return;
    if (reply && typeof reply.cpu === 'number') {
        LIVE.last = reply;
        LIVE.cpu.push(reply.cpu);
        const m = reply.memory || {};
        LIVE.mem.push(m.total > 0 ? m.used / m.total * 100 : 0);
        if (LIVE.cpu.length > 60) LIVE.cpu.shift();
        if (LIVE.mem.length > 60) LIVE.mem.shift();
        paintActivity();
    }
    // quicker at first, so the charts fill in while you are looking at them
    LIVE.timer = setTimeout(tickActivity, LIVE.cpu.length < 12 ? 1000 : 2000);
}

function drawSpark(id, values) {
    const svg = document.getElementById(id);
    if (!svg || !values.length) return;
    const n = 60, w = 300, hgt = 60;
    const pts = values.map((v, k) => [w - (values.length - 1 - k) * (w / (n - 1)), hgt - 3 - Math.max(0, Math.min(100, v)) / 100 * (hgt - 8)]);
    const line = pts.map((p, k) => (k ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
    svg.querySelector('.ln').setAttribute('d', line);
    svg.querySelector('.area').setAttribute('d', line + ` L ${w} ${hgt} L ${pts[0][0].toFixed(1)} ${hgt} Z`);
}

function paintActivity() {
    const r = LIVE.last;
    if (!r || K.page !== ACTIVITY()) return;
    const cpuN = $('#cpuN'), memN = $('#memN');
    if (!cpuN || !memN) return;
    cpuN.textContent = Math.round(r.cpu) + '%';
    $('#cpuU').textContent = 'in use · ' + plural(r.cores || 1, 'core');
    const m = r.memory || {};
    memN.textContent = size(m.used || 0);
    $('#memU').textContent = 'used of ' + size(m.total || 0);
    $('#memBar').style.width = (m.total > 0 ? m.used / m.total * 100 : 0).toFixed(1) + '%';
    drawSpark('cpuS', LIVE.cpu);
    drawSpark('memS', LIVE.mem);
    for (const b of document.querySelectorAll('#bySeg button')) b.classList.toggle('on', b.textContent.toLowerCase() === LIVE.by);

    const box = $('#apps');
    const apps = (r.apps || []).slice().sort((a, b) => LIVE.by === 'cpu' ? b.cpu - a.cpu || b.memory - a.memory : b.memory - a.memory).slice(0, 10);
    const top = Math.max(0.0001, ...apps.map(a => LIVE.by === 'cpu' ? a.cpu : a.memory));
    const had = new Map([...box.querySelectorAll('.proc')].map(el => [el.dataset.key, el]));
    const rows = apps.map((a, n) => {
        const key = a.name;
        let row = had.get(key);
        if (!row) {
            const pic = h('span', { class: 'pic' });
            if (a.icon && /^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(a.icon)) pic.style.backgroundImage = `url("${a.icon}")`;
            else pic.append(icon('cube'));
            row = h('div', { class: 'proc fresh' }, pic,
                h('span', { class: 'nm' }, h('b', null, a.name), h('span', { class: 'cnt' })),
                h('span', { class: 'track' }, h('i')), h('span', { class: 'num cpu' }), h('span', { class: 'num mem' }));
            row.dataset.key = key;
        }
        row.querySelector('.cnt').textContent = a.count > 1 ? plural(a.count, 'process', 'processes') : '';
        const v = LIVE.by === 'cpu' ? a.cpu : a.memory;
        row.querySelector('.track i').style.width = Math.max(1, v / top * 100).toFixed(1) + '%';
        row.querySelector('.cpu').textContent = a.cpu >= 10 ? Math.round(a.cpu) + '%' : a.cpu.toFixed(1) + '%';
        row.querySelector('.mem').textContent = size(a.memory);
        row.classList.toggle('lead', n === 0);
        return row;
    });
    box.replaceChildren(h('div', { class: 'ah' }, h('span'), h('span', null, 'App'), h('span'),
        h('span', { class: 'num' + (LIVE.by === 'cpu' ? ' on' : '') }, 'CPU'), h('span', { class: 'num' + (LIVE.by === 'memory' ? ' on' : '') }, 'Memory')), ...rows);
    requestAnimationFrame(() => rows.forEach(row => row.classList.remove('fresh')));
}

/* ── the first minute: hello, how it works, access, you, done ─────────── */

const INTRO = ['hello', 'how', 'access', 'desk', 'dock', 'wall', 'you', 'done'];

/* what each of macOS's questions is for, by the picture Swift sends */
const GATE_WHY = {
    'menubar.dock.rectangle': 'To sort what is on it.',
    'arrow.down.circle': 'To sort your downloads.',
    'photo': 'To show what takes up space.',
    'doc.text': 'To find duplicates and large files.',
    'bell': 'To tell you when something is done.',
};

function startWelcome() {
    const cfg = K.meta.config;
    const first = String(K.meta.user || '').trim().split(/\s+/)[0] || '';
    K.welcome = { step: 0, shown: -1, back: false, name: cfg.name || first, start: cfg.start || 'desktop',
                  tidy: cfg.tidy || 'Tidy', login: !!(K.meta.login && K.meta.login.on), answers: {}, asking: -1,
                  deskCount: null, didDesk: false, didZen: false, didFast: false,
                  dockApps: null, dropped: new Set(), wallAt: 0, busy: false, reading: false };
    drawWelcome();
}

function introGo(by) {
    const w = K.welcome;
    if (!w) return;
    w.back = by < 0;
    w.step = Math.max(0, Math.min(INTRO.length - 1, w.step + by));
    drawWelcome();
}

function drawWelcome() {
    const w = K.welcome;
    const app = $('#app');
    app.className = 'app';
    app.style.gridTemplateColumns = '1fr';
    const step = INTRO[w.step];
    const fresh = w.shown !== w.step;
    w.shown = w.step;

    const card = h('section', { class: 'intro-card s-' + step + (fresh ? (w.back ? ' enter back' : ' enter') : '') });
    const way = h('div', { class: 'way' });
    const back = h('button', { class: 'btn line large', onclick: () => introGo(-1) }, icon('left'), 'Back');
    const gates = K.meta.gates || [];
    const asked = gates.filter((_, n) => n in w.answers).length;
    let primary = null;

    if (step === 'hello') {
        card.append(
            h('div', { class: 'hello-eyes' }, eyesMark()),
            h('h1', null, 'Hey, I’m Kliner.'),
            h('p', { class: 'lead' }, 'I keep your Mac tidy.'),
            h('div', { class: 'demo sort wide' }, ...sortStage()));
        primary = h('button', { class: 'btn fill large', onclick: () => introGo(1) }, 'Get started', icon('right'));
        way.append(primary);
        card.append(way);
    } else if (step === 'how') {
        card.append(h('h1', null, 'Here’s how it works.'),
                    h('p', { class: 'lead' }, 'None of it happens until you press a button.'));
        card.append(h('div', { class: 'how' },
            howTip('sort', 'Sort', 'Loose files into folders, by type.'),
            howTip('look', 'See it first', 'Every page shows what changes, before it does.'),
            howTip('space', 'Free up space', 'Caches and the Trash. Your files stay.'),
            howTip('undo', 'Undo anything', 'One click puts it all back.')));
        primary = h('button', { class: 'btn fill large', onclick: () => introGo(1) }, 'Continue', icon('right'));
        way.append(back, h('span', { class: 'gap' }), primary);
        card.append(way);
    } else if (step === 'access') {
        card.append(h('h1', null, 'Let Kliner see your files.'),
                    h('p', { class: 'lead' }, 'macOS asks once for each. Kliner never goes online.'));
        const list = h('div', { class: 'gates' });
        gates.forEach((g, n) => {
            const title = String(g.title || '').replace(/^your /i, '');
            let state;
            if (n in w.answers) {
                state = w.answers[n] ? h('span', { class: 'st yes' }, icon('check'), 'Allowed')
                                     : h('span', { class: 'st no' }, 'Not allowed');
            } else if (w.asking === n) {
                state = h('span', { class: 'st now' }, h('i', { class: 'spin' }), 'Waiting for macOS');
            } else {
                state = h('button', { class: 'btn line small', disabled: w.asking >= 0 ? '' : null, onclick: () => askGate(n) }, 'Allow');
            }
            list.append(h('div', { class: 'gate', style: `animation-delay:${fresh ? 80 + n * 60 : 0}ms` },
                h('span', { class: 'ico' }, icon(g.symbol)),
                h('div', { class: 'tt' }, h('b', null, title.charAt(0).toUpperCase() + title.slice(1)),
                  h('span', null, GATE_WHY[g.symbol] || '')),
                state));
        });
        card.append(list, h('p', { class: 'small left' }, 'Change any of these later in Settings.'));
        const done = asked === gates.length;
        primary = done ? h('button', { class: 'btn fill large', onclick: () => introGo(1) }, 'Continue', icon('right'))
                       : h('button', { class: 'btn fill large', disabled: w.asking >= 0 ? '' : null, onclick: askAll }, 'Allow all');
        way.append(...[back, h('span', { class: 'gap' }),
                   done ? null : h('button', { class: 'btn bare large', onclick: () => introGo(1) }, 'Skip'), primary].filter(Boolean));
        card.append(way);
    } else if (step === 'desk') {
        card.append(h('h1', null, 'Make your desktop clean.'),
                    h('p', { class: 'lead' }, 'Two ways. Neither deletes anything.'));
        const deskPage = pages().findIndex(p => p.kind === 'desktop');
        const many = w.deskCount;
        card.append(h('div', { class: 'setup' },
            setupRow('desk', 'File it all away',
                many == null ? 'Counting…'
                    : many === 0 ? 'Already clear.'
                    : plural(many, 'thing') + ' into Desktop/Tidy.',
                w.didDesk ? 'done' : many === 0 ? 'skip' : 'Tidy it',
                () => introTidy(deskPage)),
            setupRow('eye', 'Or stop drawing them at all',
                'A bare desktop. The files never move.',
                w.didZen ? 'done' : 'Hide them', introZen)));
        primary = h('button', { class: 'btn fill large', onclick: () => introGo(1) }, 'Continue', icon('right'));
        way.append(back, h('span', { class: 'gap' }), primary);
        card.append(way);
        if (many == null) countDesk(deskPage);
    } else if (step === 'dock') {
        card.append(h('h1', null, 'Make your Dock clean.'),
                    h('p', { class: 'lead' }, 'Untick what you never open. The apps stay installed.'));
        const apps = w.dockApps;
        if (!apps) {
            card.append(h('div', { class: 'setup' }, h('p', { class: 'lead' }, 'Reading your Dock…')));
            readDock();
        } else if (!apps.length) {
            card.append(h('div', { class: 'setup' }, h('p', { class: 'lead' }, 'Nothing in your Dock that Kliner can change.')));
        } else {
            const list = h('div', { class: 'picks' });
            apps.forEach((name, n) => {
                const on = !w.dropped.has(name);
                list.append(h('button', { class: 'keep' + (on ? ' on' : ''), style: `animation-delay:${fresh ? 60 + n * 40 : 0}ms`,
                    onclick: e => {
                        if (w.dropped.has(name)) w.dropped.delete(name); else w.dropped.add(name);
                        e.currentTarget.classList.toggle('on', !w.dropped.has(name));
                        const left = apps.length - w.dropped.size;
                        const say = $('#keepsay');
                        if (say) say.textContent = left === apps.length ? 'Keeping all of them.'
                            : plural(w.dropped.size, 'app') + ' out, ' + left + ' left.';
                    } },
                    h('span', { class: 'tick' }, icon('check')), h('span', { class: 'nm' }, name)));
            });
            card.append(list, h('p', { class: 'small left', id: 'keepsay' },
                w.dropped.size ? plural(w.dropped.size, 'app') + ' out, ' + (apps.length - w.dropped.size) + ' left.' : 'Keeping all of them.'));
        }
        card.append(h('div', { class: 'setup' },
            setupRow('bars', 'And let it slide away',
                'It hides until you reach for it.',
                w.didFast ? 'done' : 'Let it slide', introDockFast)));
        primary = w.dockApps && w.dropped.size
            ? h('button', { class: 'btn fill large', onclick: introDockKeep }, 'Keep the ticked ones', icon('right'))
            : h('button', { class: 'btn fill large', onclick: () => introGo(1) }, 'Continue', icon('right'));
        way.append(back, h('span', { class: 'gap' }), primary);
        card.append(way);
    } else if (step === 'wall') {
        card.append(h('h1', null, 'Pick a wallpaper.'),
                    h('p', { class: 'lead' }, 'Yours first, then your Mac’s. Click one.'));
        if (!K.walls) {
            card.append(h('div', { class: 'setup' }, h('p', { class: 'lead' }, 'Looking for wallpapers…')));
            readWalls().then(() => { if (INTRO[K.welcome.step] === 'wall') drawWelcome(); });
        } else {
            const grid = h('div', { class: 'walls small' });
            K.walls.slice(0, 12).forEach((one_, n) => {
                const drawn = K.wallPics && K.wallPics[String(one_.no)];
                grid.append(h('button', { class: 'wall' + (w.wallAt === one_.no ? ' pick' : ''),
                    style: `animation-delay:${fresh ? 60 + n * 30 : 0}ms`,
                    onclick: () => introWall(one_.no) },
                    drawn ? h('span', { class: 'sheet has' }, h('img', { class: 'pic got', src: drawn, alt: '' }))
                          : h('span', { class: 'sheet' }, icon('photo')),
                    h('span', { class: 'nm' }, one_.parts[0])));
            });
            card.append(grid);
        }
        primary = h('button', { class: 'btn fill large', onclick: () => introGo(1) }, 'Continue', icon('right'));
        way.append(back, h('span', { class: 'gap' }), primary);
        card.append(way);
    } else if (step === 'you') {
        card.append(h('h1', null, 'Make it yours.'),
                    h('p', { class: 'lead' }, 'All of it changes later, in Settings.'));
        const field = h('input', { class: 'field', id: 'name', value: w.name, placeholder: 'Your name', maxlength: '60',
                                   oninput: e => { w.name = e.target.value; } });
        const starts = h('div', { class: 'chips' }, (K.meta.starts || []).map(st =>
            h('button', { class: 'chip2' + (st.value === w.start ? ' on' : ''),
                          onclick: e => { w.start = st.value; for (const c of e.currentTarget.parentNode.children) c.classList.toggle('on', c === e.currentTarget); } },
              st.title)));
        const rows = h('div', { class: 'form' },
            h('label', { class: 'row' }, h('span', { class: 'k' }, 'What should I call you?'), field),
            h('div', { class: 'row' }, h('span', { class: 'k' }, 'Open Kliner on'), starts));
        if (K.meta.login && K.meta.login.possible) {
            rows.append(h('div', { class: 'row' }, h('span', { class: 'k' }, 'Open at login'),
                h('div', { class: 'toggle' }, h('button', { class: 'switch' + (w.login ? ' on' : ''),
                    onclick: e => { w.login = !w.login; e.currentTarget.classList.toggle('on', w.login); } }),
                  h('span', null, 'Kliner waits in the menu bar. Press ⌘K anywhere.'))));
        }
        card.append(rows);
        primary = h('button', { class: 'btn fill large', onclick: () => introGo(1) }, 'Continue', icon('right'));
        way.append(back, h('span', { class: 'gap' }), primary);
        card.append(way);
        if (fresh) setTimeout(() => field.focus(), 60);
    } else {
        const name = (w.name || '').trim();
        card.append(
            h('div', { class: 'hello-eyes happy' }, eyesMark('blinks')),
            h('h1', null, name ? `You’re all set, ${name}.` : 'You’re all set.'),
            h('p', { class: 'lead' }, 'Press ⌘K anywhere.'));
        primary = h('button', { class: 'btn fill large', onclick: finishWelcome }, 'Open Kliner', icon('right'));
        way.append(back, h('span', { class: 'gap' }), primary);
        card.append(way);
    }
    w.primary = primary;

    const dots = h('div', { class: 'dots' }, INTRO.map((_, n) =>
        h('i', { class: n === w.step ? 'on' : n < w.step ? 'past' : '' })));
    const of = h('div', { class: 'of' }, (w.step + 1) + ' of ' + INTRO.length);
    app.replaceChildren(h('div', { class: 'intro', style: 'grid-column:1/-1' }, dots, of, card));
    reportChrome();
}

/* One line of the setup: a picture, what it does, and the button. */
function setupRow(mark, title, text, action, go) {
    const right = action === 'done' ? h('span', { class: 'st yes' }, icon('check'), 'Done')
        : action === 'skip' ? h('span', { class: 'st' }, 'Nothing to do')
        : h('button', { class: 'btn line', onclick: go }, action);
    return h('div', { class: 'gate' },
        h('span', { class: 'ico' }, icon(mark)),
        h('div', { class: 'tt' }, h('b', null, title), h('span', null, text)),
        right);
}

async function countDesk(page) {
    const w = K.welcome;
    if (!(page > 0)) { w.deskCount = 0; drawWelcome(); return; }
    const items = await listing(page);
    w.deskCount = items.filter(countedByNimo).length;
    if (INTRO[K.welcome.step] === 'desk') drawWelcome();
}

async function introTidy(page) {
    const w = K.welcome;
    if (!(page > 0) || w.busy) return;
    w.busy = true;
    const reply = await ask('tidy', { pages: [page] });
    w.busy = false;
    if (reply && reply.results && reply.results.some(r => r.changed)) {
        w.didDesk = true;
        w.deskCount = 0;
        K.listing = {};
        delete K.kept[0];
    }
    drawWelcome();
}

async function introZen() {
    const w = K.welcome;
    if (w.busy) return;
    w.busy = true;
    const reply = await ask('zen', {});
    w.busy = false;
    if (reply && reply.ok) w.didZen = true;
    drawWelcome();
}

async function readDock() {
    const w = K.welcome;
    if (w.reading) return;
    w.reading = true;
    const page = pages().findIndex(p => p.kind === 'dock');
    const reply = page > 0 ? await ask('look', { page }) : null;
    w.reading = false;
    w.dockApps = reply && reply.text
        ? parse(reply.text).filter(p => p.k === 'item').map(p => p.parts[0]).filter(Boolean).slice(0, 40)
        : [];
    if (INTRO[K.welcome.step] === 'dock') drawWelcome();
}

async function introDockKeep() {
    const w = K.welcome;
    if (w.busy || !w.dropped.size) { introGo(1); return; }
    w.busy = true;
    const reply = await ask('dockKeep', { drop: [...w.dropped] });
    w.busy = false;
    if (reply && reply.ok) {
        w.dropped = new Set();
        w.dockApps = null;
        introGo(1);
    } else {
        drawWelcome();
    }
}

async function introDockFast() {
    const w = K.welcome;
    if (w.busy) return;
    w.busy = true;
    const reply = await ask('dockFast', {});
    w.busy = false;
    if (reply && reply.ok) w.didFast = true;
    drawWelcome();
}

async function introWall(at) {
    const w = K.welcome;
    if (w.busy) return;
    w.busy = true;
    const reply = await ask('setWall', { at });
    w.busy = false;
    if (reply && reply.ok) w.wallAt = at;
    drawWelcome();
}

/* four small pictures of what Kliner does, drawn with nothing but shapes */
/** The pieces of the sorting picture: nine loose things and three trays. */
function sortStage() {
    const out = [];
    const spots = [
        ['6%',  '10%', 0], ['24%', '6%',  1], ['41%', '12%', 2],
        ['59%', '7%',  0], ['76%', '13%', 1], ['13%', '30%', 2],
        ['33%', '34%', 0], ['52%', '31%', 1], ['70%', '36%', 2],
    ];
    const lands = ['7%', '38%', '69%'];
    const filled = [0, 0, 0];
    spots.forEach(([x0, y0, tray], n) => {
        const at = filled[tray]++;
        out.push(h('i', { class: 'f f' + tray,
            style: `--x0:${x0};--y0:${y0};--x1:calc(${lands[tray]} + ${at * 13}px);--y1:${58 + at * 2}%;`
                 + `animation-delay:${n * 110}ms;z-index:${2 + at}` }));
    });
    [['4%', 'Screens'], ['35%', 'Images'], ['66%', 'Docs']].forEach(([x, label], n) => {
        out.push(h('span', { class: 'tray', style: `left:${x};animation-delay:${900 + n * 110}ms` },
            h('span', { class: 'lip' }), h('span', { class: 'tag' }, label)));
    });
    return out;
}

function howTip(kind, title, text) {
    const stage = h('div', { class: 'demo ' + kind });
    if (kind === 'sort') {
        stage.append(...sortStage());
    } else if (kind === 'look') {
        // a page of rows, and a line that reads down it saying what each row
        // would become — before anything has moved
        const win = h('div', { class: 'sheetwin' }, h('span', { class: 'top' },
            h('i'), h('i'), h('i')));
        [['Screenshot 12.png', 'Screens'], ['poster.jpg', 'Images'], ['notes.pdf', 'Docs'], ['build.zip', 'Archives']]
            .forEach(([name, to], n) => {
                win.append(h('span', { class: 'row', style: `animation-delay:${n * 220}ms` },
                    h('i', { class: 'dot' }),
                    h('i', { class: 'bar', style: `width:${[58, 42, 50, 38][n]}%` }),
                    h('span', { class: 'to' }, to)));
            });
        stage.append(win, h('span', { class: 'sweep' }));
    } else if (kind === 'space') {
        // a disk with a hatched block of caches in it: the block lifts out,
        // goes, and the free end of the bar grows into the gap
        stage.append(
            h('div', { class: 'dbar' }, h('i', { class: 'used' }), h('i', { class: 'cache' }), h('i', { class: 'free' })),
            h('span', { class: 'chip' }, 'caches'),
            h('span', { class: 'gain' }, '+2.4 GB'));
    } else {
        // the same file as in Sort, coming back out of its tray and landing
        // where it started, with the arc it takes drawn behind it
        stage.append(
            s('svg', { class: 'arc', viewBox: '0 0 200 100' },
              s('path', { d: 'M150 62 C 132 20, 78 14, 52 34', fill: 'none' })),
            h('span', { class: 'tray back', style: 'left:66%' }, h('span', { class: 'lip' }), h('span', { class: 'tag' }, 'Docs')),
            h('i', { class: 'f f2 mover' }),
            h('span', { class: 'ghost' }));
    }
    return h('div', { class: 'howtip' }, stage, h('b', null, title), h('span', null, text));
}

async function askGate(n) {
    const w = K.welcome;
    if (!w || w.asking >= 0) return;
    w.asking = n;
    drawWelcome();
    await new Promise(r => setTimeout(r, 120));
    const reply = await ask('gate', { index: n });
    if (!K.welcome) return;
    w.answers[n] = !!(reply && reply.yes);
    w.asking = -1;
    drawWelcome();
}

async function askAll() {
    const gates = K.meta.gates || [];
    for (let n = 0; n < gates.length; n++) {
        const w = K.welcome;
        if (!w || INTRO[w.step] !== 'access') return;
        if (n in w.answers) continue;
        await askGate(n);
        await new Promise(r => setTimeout(r, 260));
    }
}

async function finishWelcome() {
    const w = K.welcome;
    const reply = await ask('finishSetup', { name: (w.name || '').trim(), start: w.start, tidy: (w.tidy || '').trim(), login: !!w.login });
    K.meta.config.name = (w.name || '').trim();
    K.meta.config.start = w.start;
    K.welcome = null;
    const app = $('#app');
    app.style.gridTemplateColumns = '';
    drawFrame();
    const start = reply && typeof reply.page === 'number' ? reply.page : 0;
    K.page = -1;
    show(start, { remember: false });
}

/* ── the keyboard ─────────────────────────────────────────────────────── */

document.addEventListener('keydown', e => {
    if (e.target.closest && e.target.closest('input, textarea') && !(K.welcome && e.key === 'Enter')) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'Escape') {
        if ($('.pop')) { closeActivity(); return; }
        if (K.walked.length) { walkUp(); return; }
    }
    if (K.welcome) {
        if (e.key === 'Enter' && K.welcome.primary && !K.welcome.primary.disabled) { e.preventDefault(); K.welcome.primary.click(); }
        return;
    }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        const order = [];
        for (const p of K.meta.places) order.push(...p.holds);
        order.push(HELP(), SETTINGS());
        if (!order.includes(ACTIVITY())) order.push(ACTIVITY());
        const at = order.indexOf(K.page);
        const next = order[(at + (e.key === 'ArrowDown' ? 1 : -1) + order.length) % order.length];
        e.preventDefault();
        show(next);
    }
});
document.addEventListener('contextmenu', e => e.preventDefault());

/* and when the window comes back, everything drawn while it was away is
   simply there, without replaying anything */
document.addEventListener('visibilitychange', () => {
    if (document.hidden) return;
    for (const el of document.querySelectorAll('.still')) el.classList.remove('still');
});

/* ── what the app says to the window ──────────────────────────────────── */

const commands = {
    open: n => {
        // ⌘K can ask for a page before this page has finished starting
        if (!K.meta) { K.pendingOpen = Number(n); return; }
        if (K.welcome) return;
        show(Number(n));
    },
    back, forward, fold,
    refresh: () => {
        if (K.welcome) return;
        if (K.walked.length) { walk(K.walked.slice()); return; }
        if (isAction(K.page)) { delete K.kept[K.page]; look(K.page); }
        else drawPage(true);
    },
    settings: () => show(SETTINGS()),
    help: () => show(HELP()),
    setup: () => startWelcome(),
};

window.kliner = {
    reply(id, data) {
        const done = owed.get(id);
        if (!done) return;
        owed.delete(id);
        done(data || {});
    },
    command(name, arg) {
        const run = commands[name];
        if (run) run(arg);
    },
};

/* ── starting ─────────────────────────────────────────────────────────── */

async function boot() {
    const meta = await ask('boot');
    if (!meta || meta.missing || !meta.pages) {
        $('#app').replaceChildren(h('div', { class: 'wait', style: 'grid-column:1/-1' }, eyesMark('waiting'),
            h('h3', null, 'Open this from the Kliner app.'),
            h('p', null, 'This page is part of Kliner and does not work on its own.')));
        return;
    }
    K.meta = meta;
    K.meta.config = K.meta.config || {};
    // What Home read last time the app was open, drawn straight away so the
    // window opens with figures on it. The real reading replaces it as soon
    // as nimo comes back.
    if (meta.lastLook && meta.lastLook.text) {
        const pieces = parse(meta.lastLook.text);
        K.kept[0] = { pieces, ok: true, at: meta.lastLook.at || Date.now(), old: true };
        K.lastRead = meta.lastLook.at || Date.now();
        readHome(pieces);
    }
    // Activity is drawn here rather than run by nimo, so it joins the place
    // the machine's own readings are in, first
    const machine = (meta.places || []).find(p => p.holds.some(n => (meta.pages[n] || {}).kind === 'doctor' && n > 0));
    if (machine && !machine.holds.includes(meta.pages.length + 2)) machine.holds.unshift(meta.pages.length + 2);
    K.wide = K.meta.config.rail === 'list';
    K.preview = K.meta.config.preview === 'on';
    if (!meta.welcomed) { startWelcome(); return; }
    drawFrame();
    const first = K.pendingOpen != null ? K.pendingOpen : 0;
    K.pendingOpen = null;
    show(first, { remember: false });
}

window.__kliner = K;   // for the tests, and nothing else
boot();

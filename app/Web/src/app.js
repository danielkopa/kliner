/* ── Kliner's window ─────────────────────────────────────────────────────

   This page is the window. It draws; it never decides what runs. Every
   request it makes names a page by number, and the Swift side looks the
   command up in its own list, asks you with a real macOS dialog before
   anything changes, and only then runs nimo. There is no way from here to
   hand nimo an argument or open a URL. The page itself never reaches the
   network: kliner.app (your @username, files sent to it, your profile) is
   spoken to by the Swift side, which signs every request with this Mac's
   own key.                                                              */

/* ── talking to the app ───────────────────────────────────────────────── */

const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.kliner;
let serial = 0;
const owed = new Map();

/* How long an answer may take before the window stops waiting for it. A
   question put to you — a dialog, a sheet, a file to pick — waits for you,
   however long that is. A reading that never came back used to leave the
   window waiting for ever: every button after it did nothing, and Home
   stopped reading itself, which is how the window went wrong after a while. */
const ASK_WAIT = { look: 600000, walk: 600000, copies: 600000, list: 60000, thumbs: 60000, walls: 60000,
                   wallPictures: 120000, wallBig: 60000, dockApps: 60000, dockMore: 120000, activity: 15000,
                   settings: 15000, boot: 30000, setWall: 60000, rename: 60000, userCheck: 20000, userClaim: 20000,
                   nearby: 15000, cloudCheck: 130000, cloudClaim: 70000, cloudRename: 70000,
                   profileGet: 130000, profilePut: 70000, accountDelete: 70000, machine: 30000 };

/* What Kliner is busy with, in words, for the dot in the ring. */
const WORK_OPS = { look: 'Reading your Mac', go: 'Working', extra: 'Working', tidy: 'Tidying', walk: 'Measuring',
                   copies: 'Comparing files', setWall: 'Changing the wallpaper', zen: 'Changing the desktop',
                   dockKeep: 'Changing the Dock', dockFast: 'Changing the Dock', stop: 'Stopping it',
                   unpin: 'Changing the Dock', closeApps: 'Asking apps to quit', rename: 'Renaming',
                   send: 'Sending' };
const STATE = { working: 0, label: '' };

/** Ask the app for something and wait for its answer. */
function ask(op, args) {
    const work = WORK_OPS[op] && !(args && args.quiet);
    if (work) { STATE.working++; STATE.label = WORK_OPS[op]; paintState(); }
    return new Promise(resolve => {
        if (!native) { resolve({ ok: false, text: '', missing: true }); return; }
        const id = ++serial;
        let timer = 0;
        const done = data => {
            clearTimeout(timer);
            if (!owed.has(id)) return;
            owed.delete(id);
            resolve(data);
        };
        owed.set(id, done);
        if (ASK_WAIT[op]) {
            timer = setTimeout(() => done({ ok: false, missing: true, late: true,
                                            text: '! Kliner took too long to answer. Try again.' }), ASK_WAIT[op]);
        }
        native.postMessage(Object.assign({}, args || {}, { id, op }));
    }).finally(() => {
        if (!work) return;
        STATE.working = Math.max(0, STATE.working - 1);
        paintState();
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
    base: null,         // the reading the window opened on, that changes are measured from
};

const $ = sel => document.querySelector(sel);
const pages = () => (K.meta ? K.meta.pages : []);
const SETTINGS = () => pages().length;
const HELP = () => pages().length + 1;
const ACTIVITY = () => pages().length + 2;
const SHARE = () => pages().length + 3;
const isAction = i => i >= 0 && i < pages().length;
const kind = i => (isAction(i) ? pages()[i].kind : i === SETTINGS() ? 'settings' : i === ACTIVITY() ? 'activity'
    : i === SHARE() ? 'share' : 'help');

function titleOf(i) {
    if (isAction(i)) return pages()[i].title;
    return i === SETTINGS() ? 'Settings' : i === ACTIVITY() ? 'Activity' : i === SHARE() ? 'Send' : 'Help';
}
function placeOf(i) {
    return (K.meta.places || []).find(p => p.holds.includes(i)) || null;
}

/* ── the frame ────────────────────────────────────────────────────────── */

function drawFrame() {
    const app = $('#app');
    // the pane on the right stands beside the page when the window has the
    // room for it, the first time the frame is drawn; after that it stays
    // the way you left it
    if (INSP.fits == null) { INSP.fits = inspFits(); INSP.open = INSP.fits; }
    app.replaceChildren();
    app.className = 'app' + (K.wide ? ' wide' : '');
    app.style.gridTemplateColumns = '';

    // The sidebar, the way Efferd's is: Kliner beside the three lights, the
    // search, then Home, Send and one line for each place — six names, not
    // fifteen — each with what is waiting in it and one light that slides
    // to where you are. The pages of a place are the tabs along the top
    // (drawWhere). Help, Settings and you at the foot; you open Settings at
    // your profile. Folded (⌘B) it is the same list as pictures.
    const home = K.meta.places.find(p => p.holds[0] === 0);
    const list = h('nav', { class: 'sb-places', 'aria-label': 'Places' }, h('i', { class: 'mark', id: 'railmark' }));
    if (!home) list.append(navSpot(SHARE()));
    for (const place of K.meta.places) {
        list.append(placeSpot(place));
        if (place === home) list.append(navSpot(SHARE()));
    }
    const side = h('aside', { class: 'sb', id: 'side' },
        h('div', { class: 'sb-top' },
            h('button', { class: 'sb-logo', 'data-hole': '', 'aria-label': 'Home', onclick: () => show(0) },
                h('span', { class: 'sb-mark' }, eyesMark('glance blinks')), wordMark()),
            h('button', { class: 'sq sb-fold', id: 'fold', 'data-hole': '', 'data-tip': 'Fold the sidebar', 'data-keys': '⌘B',
                          'aria-label': 'Fold the sidebar', onclick: fold }, icon('sidebar'))),
        h('button', { class: 'sb-app', 'data-tip': 'Kliner', 'aria-label': 'Home', onclick: () => show(0) }),
        h('button', { class: 'sb-find', 'data-tip': 'Search', 'data-keys': '⌘K', 'aria-label': 'Search', onclick: openFind },
            icon('search'), h('span', { class: 'label' }, 'Search…'),
            h('span', { class: 'label sb-keys' }, h('kbd', null, '⌘'), h('kbd', null, 'K'))),
        list,
        h('div', { class: 'sb-foot' },
            h('button', { class: 'spot sb-help', 'data-page': HELP(), 'data-tip': 'Help', 'data-keys': '?', onclick: () => openSettings('help') },
                icon('help'), h('span', { class: 'label' }, 'Help')),
            h('button', { class: 'spot', 'data-page': SETTINGS(), 'data-tip': 'Settings', 'data-keys': '⌘,', onclick: () => openSettings() },
                icon('gear'), h('span', { class: 'label' }, 'Settings')),
            youRow()));

    // the bar along the top: where you are, and on the right what Kliner is
    // doing; search too while the sidebar, which has its own, is folded
    const bar = h('header', { class: 'bar' },
        h('button', { class: 'sq unfold', id: 'unfold', 'data-hole': '', 'data-tip': 'Open the sidebar', 'data-keys': '⌘B',
                      'aria-label': 'Open the sidebar', onclick: fold }, icon('sidebar')),
        h('div', { class: 'where', id: 'where' }),
        // a file on its way, in the middle of the bar, wherever you are
        islandEl(),
        h('div', { class: 'right' },
            // Preview says so only while it is on; turning it on is in
            // Settings and in ⌘K, not a word across the top of every page.
            h('button', { class: 'mode', id: 'mode', 'data-hole': '', onclick: flipPreview, hidden: !K.preview,
                          'data-tip': 'Preview is on: nothing changes. Click to turn it off.' },
              icon('eye'), h('span', null, 'Preview')),
            // Home's reading: how old it is, and the way to read it again. The
            // page itself is only its title and what it says, the way his is.
            h('button', { class: 'sq bar-refresh', id: 'refresh', 'data-hole': '', hidden: true, 'data-tip': 'Read your Mac again',
                          'aria-label': 'Read your Mac again', onclick: () => { delete K.kept[0]; look(0); } }, icon('refresh')),
            h('button', { class: 'bar-find', 'data-hole': '', onclick: openFind, 'aria-label': 'Search' },
              icon('search'), h('span', null, 'Search'), h('kbd', null, '⌘K')),
            // what Kliner is doing, as a dot in a ring; what it has done, when clicked
            h('button', { class: 'state idle', id: 'state', 'data-hole': '', 'data-tip': 'Kliner is idle',
                          'aria-label': 'Kliner is idle', onclick: toggleActivity },
              h('i', { class: 'ring' }), h('i', { class: 'dot' })),
            h('button', { class: 'sq insp-show', id: 'inspShow', 'data-hole': '', 'data-tip': 'Show the pane', 'aria-label': 'Show the pane',
                          hidden: INSP.open, onclick: () => toggleInsp(true) }, icon('sidebar'))));

    const scroll = h('div', { class: 'scroll', id: 'scroll' }, h('div', { class: 'page', id: 'page' }));
    // Home lists the file on its way in its send card: the island steps
    // aside while that row is in sight, and comes back when it scrolls off
    scroll.addEventListener('scroll', () => { if (K.page === 0) paintIsland(); }, { passive: true });
    app.append(side, h('main', { class: 'main' }, bar, scroll), inspFrame());
    paintComposer();

    wireTips(app);
    setFrame();
    reportChrome();
}

/** Your disk, small, at the foot of the sidebar: how full it is, and what
 *  can go. The sidebar after Efferd's has no card for it (Home has the
 *  disk itself); this paints one wherever a frame still has the box. */
function paintSide() {
    const box = $('#sbDisk');
    const home = K.home;
    if (!box) return;
    if (!home || !(home.total > 0)) { box.replaceChildren(); box.hidden = true; return; }
    const junk = home.junk > 0 ? home.junk : 0;
    const cleanPage = pages().findIndex(p => p.kind === 'clean');
    box.hidden = false;
    box.replaceChildren(
        h('div', { class: 'sbd-h' }, icon('disk'), h('span', null, 'Your disk'), h('b', null, Math.round(home.used / home.total * 100) + '%')),
        h('div', { class: 'hm-bar' },
            h('i', { class: 'u', style: `width:${((home.used - junk) / home.total * 100).toFixed(2)}%` }),
            h('i', { class: 'j', style: `width:${(junk / home.total * 100).toFixed(2)}%` })),
        h('div', { class: 'sbd-k' }, size(home.free) + ' free of ' + size(home.total)),
        junk > 0 && cleanPage > 0 ? h('button', { class: 'sbd-go', onclick: () => show(cleanPage) }, 'Free up ' + size(junk), icon('right')) : null);
}

/** One page in the open sidebar: its picture and its name; what is waiting
 *  in it is added by tally(). */
function navSpot(n, symbol) {
    const sym = symbol || (isAction(n) ? pages()[n].symbol : n === ACTIVITY() ? 'gauge' : n === SHARE() ? 'send'
        : n === SETTINGS() ? 'gear' : 'help');
    return h('button', { class: 'spot pg', 'data-page': n, 'data-tip': n === 0 ? 'Home' : titleOf(n), onclick: () => show(n) },
        icon(sym), h('span', { class: 'label' }, n === 0 ? 'Home' : titleOf(n)));
}

/** One place in the folded rail: its picture, named beside it when pointed
 *  at. It opens on the first page the place holds and is lit on any of them
 *  (lightSide), with what is waiting in all of them (tally). */
function placeSpot(place) {
    const n = place.holds[0];
    return h('button', { class: 'spot pl', 'data-page': n, 'data-tip': place.title, 'aria-label': place.title, onclick: () => show(n) },
        icon(place.symbol), h('span', { class: 'label' }, place.title));
}

/** Everything in the frame that depends on where you are. */
function setFrame() {
    const i = K.page;
    lightSide();

    const where = $('#where');
    if (where) drawWhere(where, i);

    const backBtn = $('#back'), fwdBtn = $('#fwd');
    if (backBtn) backBtn.disabled = !K.behind.length && !K.walked.length;
    if (fwdBtn) fwdBtn.disabled = !K.ahead.length;
    const mode = $('#mode');
    if (mode) { mode.classList.toggle('on', K.preview); mode.hidden = !K.preview; }
    paintState();
    tally();
    const onHome = i === 0 && !K.walked.length;
    const again = $('#refresh');
    if (again) again.hidden = !onHome;
    paneFrame();
    sayAge();
    paintIsland();
    reportChrome();
}

/** The place you are in, lit in the rail, and the page you are on, lit in
 *  the sidebar: the light slides from the last one, and is simply there the
 *  first time. */
function lightSide() {
    const i = K.page;
    const place = placeOf(i);
    for (const spot of document.querySelectorAll('.spot')) {
        const n = parseInt(spot.dataset.page, 10);
        spot.classList.toggle('on', spot.classList.contains('pg') || !place ? n === i : place.holds[0] === n);
    }
    const mark = $('#railmark'), onSpot = document.querySelector('.sb-places .spot.on');
    if (mark && onSpot) {
        mark.classList.toggle('jump', !mark.dataset.ready || calm());
        mark.dataset.ready = '1';
        mark.style.opacity = 1;
        mark.style.height = onSpot.offsetHeight + 'px';
        mark.style.transform = `translateY(${onSpot.offsetTop}px)`;
    } else if (mark) mark.style.opacity = 0;
}

/** Where you are, along the top. A place with more than one page is a
 *  switcher: its pages side by side, each with what is waiting in it, and
 *  one light that slides to the page you pick. The switcher is drawn once
 *  per place; moving between its pages only moves the light, so it never
 *  measures and redraws itself on every draw of the page. */
function drawWhere(where, i) {
    const place = placeOf(i);
    // the pages of a place are the tabs along the top, folded or open: the
    // sidebar names the places, and only the places
    const many = place && place.holds.length > 1;
    const key = many ? 'p' + place.holds.join(',') : 'i' + i;
    if (where.dataset.key !== key) {
        where.dataset.key = key;
        const kids = [];
        if (many) {
            kids.push(h('span', { class: 'group' }, place.title));
            const tabs = h('div', { class: 'tabs', role: 'tablist', 'data-hole': '' }, h('i', { class: 'glide' }));
            for (const n of place.holds) {
                tabs.append(h('button', { class: 'tab', role: 'tab', 'data-page': n, onclick: () => show(n),
                                          onkeydown: e => tabKeys(e, place, n) },
                    h('span', { class: 'tn' }, titleOf(n)), h('span', { class: 'tc' })));
            }
            kids.push(tabs);
        } else {
            // where you are, the way a path is said: the place, then the page
            if (place && place.holds.length > 1) {
                kids.push(h('button', { class: 'crumb', 'data-hole': '', onclick: () => show(place.holds[0]) }, place.title),
                          h('span', { class: 'slash' }, icon('right')));
            }
            kids.push(h('span', { class: 'name' }, i === 0 ? 'Home' : titleOf(i)));
        }
        kids.push(h('span', { class: 'trail' }));
        where.replaceChildren(...kids);
        where._fresh = true;
    }
    const tabs = where.querySelector('.tabs');
    if (tabs) {
        const f = K.home || {};
        for (const tab of tabs.querySelectorAll('.tab')) {
            const n = +tab.dataset.page;
            const on = n === i;
            tab.classList.toggle('on', on);
            tab.setAttribute('aria-selected', String(on));
            tab.tabIndex = on ? 0 : -1;
            const k = kind(n);
            const count = k === 'desktop' ? f.desk : k === 'downloads' ? f.downloads : null;
            tab.querySelector('.tc').textContent = count > 0 ? (count > 999 ? '999+' : String(count)) : '';
        }
        const jump = !!where._fresh;
        where._fresh = false;
        requestAnimationFrame(() => glideTo(tabs, jump));
    }
    const reveal = isAction(i) ? pages()[i].reveal : '';
    const trail = K.walked.length && K.walked[0] === reveal ? K.walked.slice(1) : K.walked;
    const tail = where.querySelector('.trail');
    if (tail) tail.replaceChildren(...(trail.length ? [h('span', { class: 'slash' }, icon('right')),
                                                        h('span', { class: 'group' }, trail.join(' / '))] : []));
}

/** The light under the page you are on. A new place puts it there at once;
 *  a new page in the same place slides it across. */
function glideTo(tabs, jump) {
    const on = tabs.querySelector('.tab.on'), glide = tabs.querySelector('.glide');
    if (!glide) return;
    if (!on) { glide.style.opacity = '0'; return; }
    glide.classList.toggle('jump', jump || calm());
    glide.style.opacity = '1';
    glide.style.width = on.offsetWidth + 'px';
    glide.style.transform = `translateX(${on.offsetLeft}px)`;
}

/** ← and → between the pages of a place, the way a row of tabs works. */
function tabKeys(e, place, n) {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    e.preventDefault();
    const at = place.holds.indexOf(n);
    const next = place.holds[(at + (e.key === 'ArrowRight' ? 1 : -1) + place.holds.length) % place.holds.length];
    show(next);
    requestAnimationFrame(() => { const t_ = document.querySelector(`.tab[data-page="${next}"]`); if (t_) t_.focus(); });
}

/** The dot in the ring at the top right: what Kliner is doing right now.
 *  Idle, a quiet dot. Working, the ring turns. Done, the dot is green until
 *  you look at what was done; failed, red until you look. Every state is a
 *  real one, read from what Kliner is doing, never decoration. */
function paintState() {
    const el = $('#state');
    if (!el) return;
    const last = K.jobs[0];
    let state = 'idle', tip = 'Kliner is idle';
    if (STATE.working > 0) { state = 'work'; tip = STATE.label + '…'; }
    else if (K.unread && last) {
        state = last.preview ? 'idle' : last.good ? 'ok' : 'bad';
        tip = last.title + ': ' + last.line;
    }
    if (!el.classList.contains(state)) {
        el.className = 'state ' + state + (state === 'ok' || state === 'bad' ? ' flash' : '');
    }
    el.dataset.tip = tip;
    el.setAttribute('aria-label', tip);
}

/** The count on a place: how many things are waiting there. */
function tally() {
    const f = K.home;
    for (const spot of document.querySelectorAll('.spot')) {
        // what it said before, so a count that changed rolls to the new one
        const old = spot.querySelector('.count');
        const was = old && !old.classList.contains('soft') ? (old.getAttribute('aria-label') || old.textContent) : null;
        old?.remove();
        if (!f) continue;
        const n = parseInt(spot.dataset.page, 10);
        let many = 0, soft = '';
        if (spot.classList.contains('pg')) {
            // one page: what is loose in it, or what it can free
            const k = kind(n);
            if (k === 'desktop') many = f.desk || 0;
            else if (k === 'downloads') many = f.downloads || 0;
            else if (k === 'clean' && f.junk > 0) soft = size(f.junk);
        } else {
            const place = (K.meta.places || []).find(p => p.holds[0] === n);
            if (!place) continue;
            for (const m of place.holds) {
                if (kind(m) === 'desktop') many += f.desk || 0;
                if (kind(m) === 'downloads') many += f.downloads || 0;
            }
        }
        if (many > 0) {
            const c = h('span', { class: 'count' }, many > 999 ? '999+' : String(many));
            spot.append(c);
            if (was != null && was !== c.textContent && K.wide) rollFigure(c, 0, was);
        } else if (soft) spot.append(h('span', { class: 'count soft' }, soft));
    }
    paintSide();
}

/** How long ago Home was read, in words. */
function readAgo() {
    const kept = K.kept[0];
    if (!kept || !kept.at) return '';
    return agoWords(kept.at);
}
/** "Updated just now", "Updated 4 min ago": a reading's age, said once. */
function agoWords(at) {
    const gone = Math.round((Date.now() - at) / 1000);
    return 'Updated ' + (gone < 45 ? 'just now' : gone < 5400 ? Math.max(1, Math.round(gone / 60)) + ' min ago'
        : Math.round(gone / 3600) + ' h ago');
}
function sayAge() {
    const again = $('#refresh');
    const said = readAgo();
    if (again) again.dataset.tip = said ? said + '. Read again' : 'Read your Mac again';
}
setInterval(sayAge, 5000);

/** Where the window can be dragged by: the top 52 points, less anything
 *  in them you can press. The app does the dragging; this only says where. */
let chromeTimer = 0;
function reportChrome() {
    clearTimeout(chromeTimer);
    chromeTimer = setTimeout(() => {
        const holes = [];
        for (const el of document.querySelectorAll('[data-hole], .bar button, .sb button, .welcome .way button')) {
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
    const els = [...root.querySelectorAll('[data-tip]')];
    if (root.dataset && root.dataset.tip) els.unshift(root);
    for (const el of els) {
        el.addEventListener('mouseenter', () => {
            clearTimeout(tipTimer);
            tipTimer = setTimeout(() => showTip(el), el.closest('.rail, .sb') ? 250 : 600);
        });
        el.addEventListener('mouseleave', hideTip);
        el.addEventListener('mousedown', hideTip);
    }
}
function showTip(el) {
    // the sidebar says its names itself while it is open; folded, the
    // pictures are named beside them
    if (el.closest('.rail, .sb') && K.wide && !el.classList.contains('sb-fold')) return;
    const tip = $('#tip');
    // never a null into replaceChildren: it would be drawn as the word "null"
    tip.replaceChildren(...[el.dataset.tip, el.dataset.keys ? h('kbd', null, el.dataset.keys) : null].filter(Boolean));
    const r = el.getBoundingClientRect();
    tip.classList.add('show');
    const w = tip.offsetWidth, th = tip.offsetHeight;
    if (el.closest('.rail, .sb') && !el.classList.contains('sb-fold')) {
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
    if (i < 0 || i > SHARE()) return;
    if (i !== SHARE()) watchNearby(false);
    closeActivity();
    closeLight();
    closeFind(false);
    hideTip();
    if (remember && i !== K.page && K.page >= 0) { K.behind.push(K.page); K.ahead = []; }
    const same = i === K.page;
    K.page = i;
    K.walked = [];
    setFrame();
    if (!same) $('#scroll').scrollTop = 0;
    if (!isAction(i)) { drawPage(); return; }
    // This Mac is the same reading Home made a moment ago — the same `min
    // doctor` — so it opens on that at once instead of on a wait of its own
    if (kind(i) === 'doctor' && i > 0 && !K.kept[i] && K.kept[0] && K.kept[0].pieces
        && !K.kept[0].fast && !K.kept[0].old && !K.kept[0].result && Date.now() - K.kept[0].at < 120000) {
        K.kept[i] = { pieces: K.kept[0].pieces, ok: K.kept[0].ok, at: K.kept[0].at };
    }
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
    tell('setConfig', { key: 'frame', value: K.wide ? 'names' : 'rail' });
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
    // Free up space reads the same caches Home adds up, later: its figure is
    // the newer one, and Home and ⌘K say it from now on
    if (kind(i) === 'clean' && K.home) {
        const own = safeTotal(K.kept[i].pieces || []);
        if (own != null) K.home.junk = own;
    }
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

    // the wallpapers come from their own, harmless reading, every time the
    // page opens: a picture dropped into the folder should be there
    if (kind(i) === 'next') readWalls();
}

/** The one that was clicked goes on the screen. No dialog: it is one
 *  picture, it is there a second later, and the one you had is one click
 *  away. What happened is said at the bottom of the window. */
async function putOnWall(at) {
    if (K.busy) return;
    const one_ = (K.walls || []).find(p => p.no === at);
    if (K.preview) {
        toast('Preview: this would put ' + (one_ ? one_.parts[0] : 'that one') + ' on your screen.', null, 'eye');
        return;
    }
    K.busy = true;
    let reply;
    try {
        reply = await ask('setWall', { at });
    } finally {
        K.busy = false;
    }
    if (!reply || reply.cancelled || reply.missing) return;
    if (reply.ok) {
        K.wallOn = one_ ? one_.parts[0] : '';
        // the ring moves to the one that is on now, in every row that is
        // drawn — Home's as well as the page's — without drawing them again
        for (const el of document.querySelectorAll('.wstrip .wt[data-no]')) {
            el.classList.toggle('on', el.dataset.no === String(at));
        }
    }
    sayWall(reply);
    if (reply.ok) readGlow(true);
    if (kind(K.page) === 'next') drawPage(true);
}

/** What nimo said about a wallpaper, as one line at the bottom. */
function sayWall(reply) {
    const pieces = parse(reply.text || '');
    const good = pieces.find(p => p.k === 'good'), warn = pieces.find(p => p.k === 'warn');
    if (reply.ok && good) toast(good.text, null);
    else if (!reply.ok) toast(warn ? warn.text : 'Your Mac did not take the new wallpaper.', null, 'x');
    K.jobs.unshift({ page: pages().findIndex(p => p.kind === 'next'), title: 'Wallpaper',
                     line: (good || warn || {}).text || '', good: !!reply.ok, at: new Date(), preview: !!reply.preview });
    K.jobs = K.jobs.slice(0, 30);
    if (reply.changed || !reply.ok) K.unread = true;
    setFrame();
}

/** The wallpapers, and small pictures of them. The names go up first, and
 *  the pictures fill in behind them a dozen at a time, each dozen laid in as
 *  it comes, so a Mac with eighty of them shows the first at once. The
 *  pictures are only asked for again when the list itself changed. */
async function readWalls() {
    if (K.readingWalls) return K.readingWalls;
    K.readingWalls = (async () => {
        const reply = await ask('walls');
        const list = reply && reply.text ? parse(reply.text).filter(p => p.k === 'item') : [];
        const same = K.walls && K.walls.length === list.length && K.walls.every((w, n) => w.parts[0] === list[n].parts[0]);
        K.walls = list;
        if (!same) K.wallPics = null;
        wallsArrived(false);
        if (same && K.wallPics) return;
        const pics = {};
        for (let from = 1; from <= list.length; from += 12) {
            const seen = await ask('wallPictures', { from, count: 12 });
            if (!seen) break;
            for (const [no, uri] of Object.entries(seen.pictures || {})) if (goodPicture(uri)) pics[no] = uri;
            const mine = typeof seen.mine === 'number' ? seen.mine : 0;
            const moved = from === 1 && (mine !== (K.wallMine || 0) || (Array.isArray(seen.kinds) && !K.wallKinds));
            if (from === 1) K.wallMine = mine;
            if (from === 1 && Array.isArray(seen.kinds)) K.wallKinds = seen.kinds;
            K.wallPics = Object.assign({}, pics);
            // the first dozen can move the line between yours and the Mac's
            wallsArrived(!moved);
            // a Kliner that sends them all at once says no total
            if (typeof seen.total !== 'number') break;
        }
    })();
    try { await K.readingWalls; } finally { K.readingWalls = null; }
}

/** The wallpapers, or more pictures of them, wherever they are drawn. */
function wallsArrived(picturesOnly) {
    const w = K.welcome;
    if (w) {
        if (INTRO[w.step] !== 'wall') return;
        if (picturesOnly) fillWallTiles(); else drawWelcome();
        return;
    }
    if (picturesOnly) { fillWallTiles(); return; }
    if (kind(K.page) === 'next') drawPage(true);
    // Home draws the same row, and is drawn again without moving anything:
    // the list arriving is not a change worth animating a whole page for.
    else if (K.page === 0) drawPage(true, true);
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
    // a wallpaper says what it did at the bottom, not in a banner over the grid
    if (kind(i) === 'next') { K.wallOn = ''; sayWall(reply); readWalls(); MINI.at = 0; readGlow(true); return; }
    afterRun(i, reply, pages()[i].verb);
    if (!reply.preview) tidyResult([Object.assign({ page: i }, reply)]);
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
    if (kind(i) === 'next') { K.wallOn = ''; sayWall(reply); readWalls(); MINI.at = 0; readGlow(true); return; }
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
    if (!reply.preview && tidyResult(reply.results)) return;
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
        // what is in the folders may have moved: read them again when asked
        K.listing = {};
        // what changed changes the readings of Home and the log of what was done
        for (const n of Object.keys(K.kept)) {
            if (+n !== i) delete K.kept[n];
        }
        if (kind(i) === 'next' && K.walls) readWalls();
    }
    const line = good ? good.text : warn ? warn.text : (reply.ok ? 'Done' : 'That did not work');
    K.jobs.unshift({ page: i, title: titleOf(i), line, good: !!good && reply.ok, at: new Date(), preview: !!reply.preview });
    K.jobs = K.jobs.slice(0, 30);
    if (reply.changed || !reply.ok) K.unread = true;
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
    if (K.preview) { toast('Preview: this would stop ' + name + ' from opening at login.', null, 'eye'); return; }
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
    // and the three readings the menu draws across its top, so ⌘K outside
    // the window is a small Kliner rather than a list of names
    tell('figures', {
        headline: home.junk == null ? '' : home.junk > 0 ? size(home.junk) + ' can be freed' : 'nothing to free up',
        figures,
        readings: [
            home.desk != null ? { name: 'Desktop', value: String(home.desk), unit: home.desk === 1 ? 'item' : 'items',
                                  part: Math.min(1, home.desk / 200) } : null,
            home.downloads != null ? { name: 'Downloads', value: String(home.downloads), unit: home.downloads === 1 ? 'item' : 'items',
                                       part: Math.min(1, home.downloads / 200) } : null,
            total > 0 ? { name: 'Disk', value: percent(home.used, total), unit: size(free) + ' free', part: home.used / total } : null,
        ].filter(Boolean),
    });
    tally();
}

/* Home reads itself again every half minute, only while you are looking:
   the quick half only, and without holding the buttons. The full scan walks
   every cache on the disk, which is for opening Home and for Refresh, not
   for a timer.

   It is drawn again only when what it says has changed, and then without a
   single thing moving. It used to be drawn again every half minute whatever
   came back: the numbers counted up from nought again, the bars grew again
   and every picture blinked out and back — the whole window refreshing
   itself in front of you, twice a minute, for as long as it was open. */
let homeReading = false;
function homeSays(home) {
    if (!home) return '';
    const gb = n => Math.round((n || 0) / 1e8);
    return [home.desk, home.downloads, home.trash, gb(home.free), gb(home.total), home.junk == null ? '' : gb(home.junk / 100),
            (home.months || []).join(','), home.last, home.deskOld, home.downloadsOld].join('|');
}
setInterval(async () => {
    if (K.page !== 0 || K.busy || homeReading || K.welcome || document.visibilityState !== 'visible') return;
    // not under somebody's fingers: Home is not drawn again while the send
    // box on it is being typed in
    if (document.activeElement && document.activeElement.closest && document.activeElement.closest('#snd')) return;
    if (!K.kept[0] || K.kept[0].result || Date.now() - K.kept[0].at <= 29000) return;
    homeReading = true;
    let reply;
    try { reply = await ask('look', { page: 0, fast: true, quiet: true }); } finally { homeReading = false; }
    if (!reply || reply.missing || !reply.ok || K.busy || K.page !== 0) return;
    const was = homeSays(K.home);
    const pieces = parse(reply.text);
    const full = K.kept[0];
    readHome(pieces);
    K.lastRead = Date.now();
    if (homeSays(K.home) === was && full && full.pieces) {
        // the same answer: the reading stays the full one, only fresher
        full.at = Date.now();
        sayAge();
        return;
    }
    K.kept[0] = { pieces, ok: true, at: Date.now(), fast: true };
    drawPage(true, true);
}, 5000);

/* ── the page ─────────────────────────────────────────────────────────── */

const DRAW = { moving: true };

function drawPage(still, hush) {
    const page = $('#page');
    if (!page) return;
    const i = K.page;
    // A window that is minimised or behind everything else stops painting,
    // and an animation that has not run leaves what it animates invisible.
    // So a page drawn out of sight is drawn without any of them. A page
    // drawn again only because its reading was refreshed is hushed: the
    // same page, the new numbers, and nothing moving.
    const asleep = document.hidden;
    const out = h('div', { class: (still || asleep ? '' : 'arrive') + (asleep ? ' still' : '') + (hush ? ' hush' : '') });
    // what is drawn below can ask whether this draw moves at all
    DRAW.moving = !(still || asleep || hush);
    const top = $('#scroll') ? $('#scroll').scrollTop : 0;
    // the same page drawn again: what its figures said, so the ones that
    // changed can roll from it (rollChanged)
    const before = DRAW.at === i && !DRAW.moving ? snapFigures(page) : null;
    DRAW.at = i;

    if (i !== ACTIVITY()) stopActivity();
    if (i !== SHARE() && i !== 0) watchNearby(false);
    // the send box goes back to the foot of the pane before any page is
    // drawn (Home takes it again), and whoever was typing in it keeps on
    const typing = document.activeElement && document.activeElement.id === 'sndTo' ? document.activeElement : null;
    const caret = typing ? [typing.selectionStart, typing.selectionEnd] : null;
    parkSender();
    // every page but Home and Send is drawn the same way as they are, on the
    // page itself, by one class (the v15 part of style.css)
    if (i !== 0 && i !== SHARE()) out.classList.add('apage');
    if (i === SETTINGS()) drawSettings(out);
    else if (i === HELP()) drawHelp(out);
    else if (i === ACTIVITY()) drawActivity(out);
    else if (i === SHARE()) drawShare(out);
    else if (K.walked.length) drawWalk(out);
    else {
        const kept = K.kept[i];
        if (!kept) { drawWaiting(i); return; }
        stopWaiting();
        if (i === 0) drawHome(out, kept);
        else drawAction(out, i, kept);
    }
    stopWaiting();
    if (DRAW.moving) stagger(out);
    page.replaceChildren(out);
    if (typing && typing.isConnected && document.activeElement !== typing) {
        typing.focus({ preventScroll: true });
        try { typing.setSelectionRange(caret[0], caret[1]); } catch (e) { /* not a text field any more */ }
    }
    if (hush && $('#scroll')) $('#scroll').scrollTop = top;
    if (K.scrollTo) {
        const to = out.querySelector(K.scrollTo);
        if (to) { K.scrollTo = null; requestAnimationFrame(() => to.scrollIntoView({ behavior: 'smooth', block: 'start' })); }
    }
    // a page that arrives rolls its figures up; one drawn again only for new
    // numbers keeps still, all but the figures that changed, which roll from
    // what they said
    if (DRAW.moving) runCounts(out, true);
    else {
        for (const el of out.querySelectorAll('[data-to]')) el.removeAttribute('data-to');
        if (before && !asleep) rollChanged(out, before);
    }
    paintInsp();
    if (i === 0 || kind(i) === 'next') readGlow();
    reportChrome();
}

/** The order a page's cards arrive in: one after another as you read them,
 *  and two columns read across, row by row, rather than all of the left one
 *  first. Each card is told its moment in `--d`; what is inside it follows on
 *  from that, so nothing in a card moves before the card is there. */
function stagger(out) {
    const order = [];
    const walk = el => {
        for (const kid of el.children) {
            if (kid.classList.contains('panel') || kid.classList.contains('ef-tray')) { order.push(kid); continue; }
            if (kid.classList.contains('cols') || kid.classList.contains('split')) {
                const cols = [...kid.children].map(c => c.classList.contains('panel') ? [c] : [...c.querySelectorAll(':scope > .panel')]);
                const rows = Math.max(0, ...cols.map(c => c.length));
                for (let r = 0; r < rows; r++) for (const c of cols) if (c[r]) order.push(c[r]);
                continue;
            }
            walk(kid);
        }
    };
    walk(out);
    order.forEach((el, n) => el.style.setProperty('--d', (70 + Math.min(n, 11) * 55) + 'ms'));
}

/** The waiting screen waits its turn. A reading that lands in a tenth of a
 *  second used to flash this over the page and take it away again, which
 *  reads as the window blinking at you. It only appears if the wait is long
 *  enough to be worth telling you about. */
let waitTimer = 0;
function stopWaiting() { clearTimeout(waitTimer); waitTimer = 0; }

function drawWaiting(i, what) {
    stopWaiting();
    // Nothing on the page yet: there is nothing to flash over, so it goes up
    // at once. Otherwise it waits, and usually never arrives.
    const page = $('#page');
    if (!page) return;
    if (page.firstChild) {
        waitTimer = setTimeout(() => { waitTimer = 0; paintWaiting(i, what); }, 220);
        return;
    }
    paintWaiting(i, what);
}

function paintWaiting(i, what) {
    const page = $('#page');
    if (!page) return;
    if (i === 0 && !what) { page.replaceChildren(homeSkeleton()); return; }
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

/* ── the shape of what is coming ─────────────────────────────────────────
   While Home is read, Home is drawn: your greeting as it will be, and every
   card in its place, grey and shimmering, so the page does not jump when the
   figures land. */

const sk = (w, hgt, extra) => h('i', { class: 'sk' + (extra ? ' ' + extra : ''), style: `width:${w};height:${hgt}px` });

function skeletonCard(kind) {
    const top = h('div', { class: 'sk-cap' }, sk('14px', 14), sk('96px', 10));
    if (kind === 'ring') {
        return panel('sk-card', top, h('div', { class: 'sk-ring' }, sk('150px', 150, 'round'),
            h('div', { class: 'sk-lines' }, [0, 1, 2].map(() => h('div', null, sk('46%', 10), sk('100%', 4))))));
    }
    if (kind === 'months') {
        return panel('sk-card', top, h('div', { class: 'sk-row' }, sk('40px', 22), sk('52px', 22)),
            h('div', { class: 'sk-cells' }, Array.from({ length: 12 }, () => sk('100%', 26))));
    }
    if (kind === 'facts') {
        return panel('sk-card', top, h('div', { class: 'sk-lines' }, [0, 1, 2, 3].map(() => h('div', { class: 'sk-fact' }, sk('22%', 10), sk('30%', 10)))));
    }
    return panel('sk-card', top, h('div', { class: 'sk-row' }, sk('44px', 30), sk('42px', 10)), sk('100%', 12),
        h('div', { class: 'sk-row' }, sk('74px', 10), sk('62px', 10), sk('80px', 10)),
        h('div', { class: 'sk-figs' }, [0, 1, 2].map(() => h('div', null, sk('52px', 18), sk('70px', 9)))));
}

/** Home while it is read the first time: the same title, and every tray in
 *  its place in grey, so nothing jumps when the figures land. */
function homeSkeleton() {
    const t = (cls, body) => h('section', { class: 'ef-tray sk-tray ' + cls },
        h('header', { class: 'ef-tray-h' }, sk('92px', 10)), h('div', { class: 'ef-sheet' }, body));
    return h('div', { class: 'skeleton dpage ef-home' + (calm() ? ' calm' : '') }, homeHead(),
        h('div', { class: 'ef-kpis', style: '--k:4' }, [0, 1, 2, 3].map(() => t('ef-kpi', [sk('86px', 22), sk('120px', 10)]))),
        h('section', { class: 'ef-sec' },
            h('header', { class: 'ef-sec-h' }, sk('120px', 16), sk('210px', 30)),
            h('div', { class: 'ef-grid' },
                t('ef-landed', h('div', { class: 'sk-bars' }, Array.from({ length: 30 }, (_, n) => sk('100%', 24 + ((n * 37) % 90))))),
                h('div', { class: 'ef-side' }, t('ef-disk', [sk('110px', 22), sk('100%', 44)]), t('ef-hours', [sk('130px', 14), sk('100%', 60)])))));
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

/** A figure that rolls into place when its page arrives. The text is the
 *  final text from the start, so a page drawn quietly never shows a wrong
 *  number — only a page arriving gets the roll. `data-to` says it has not
 *  rolled yet; `data-fig` stays, so a page drawn again can tell which of its
 *  figures changed. */
function counted(text) {
    if (!/^\D*?\d/.test(String(text))) return document.createTextNode(String(text));
    return h('span', { 'data-to': '', 'data-fig': '' }, String(text));
}
/** Every figure in `root` that has not rolled yet rolls up from nought: on
 *  a page arriving, each when its own card lands, not all of them at once;
 *  filled in later, now. */
function runCounts(root, staggered) {
    const els = [...root.querySelectorAll('[data-to]')];
    for (const el of els) el.removeAttribute('data-to');
    if (!els.length || calm() || document.hidden) return;
    for (const el of els) {
        const card = staggered ? el.closest('.panel, .ef-tray') : null;
        const d = card ? parseFloat(card.style.getPropertyValue('--d')) : NaN;
        rollFigure(el, d > 0 ? d + 120 : 0, '');
    }
}

/* ── v19: the figures roll, the way a counter on a board turns ───────────
   Dan sent kravio's dashboard and seven libraries of moving parts and said:
   all of it, here, now. The figures are the first of them: a number does not
   count up through every value on its way, it rolls — each digit a strip of
   nought to nine behind a window one digit tall, slid from the digit it was
   to the one it is, the one on the left first and the rest just after it. A
   digit that did not change stands still, so a figure that went from 64 to
   61 turns only its last digit. Once it has rolled it is plain text again. */

const ROLL = { dur: 900, step: 55 };
function rollFigure(el, delay, from) {
    const text = el.getAttribute('aria-label') || el.textContent;
    if (!/\d/.test(text) || calm() || document.hidden || !el.animate) return;
    const isDigit = c => c >= '0' && c <= '9';
    const now = [...text], was = [...String(from || '')].filter(isDigit);
    const digits = now.filter(isDigit).length;
    const cells = [];
    let k = 0, moving = 0;
    for (const c of now) {
        if (!isDigit(c)) { cells.push(document.createTextNode(c)); continue; }
        // the old digits are lined up with the new ones from the right; a
        // digit the old figure did not have rolls up from nought
        const old = was[was.length - (digits - k)];
        k++;
        const a = from && old != null ? +old : 0, b = +c;
        if (from && old != null && a === b) { cells.push(document.createTextNode(c)); continue; }
        const strip = h('span', { class: 'rd-s' }, '0123456789'.split('').map(x => h('span', null, x)));
        strip.style.transform = `translateY(${-b * 10}%)`;
        const at = delay + moving * ROLL.step;
        strip.animate([{ transform: `translateY(${-a * 10}%)` }, { transform: `translateY(${-b * 10}%)` }],
                      { duration: ROLL.dur, delay: at, easing: 'cubic-bezier(.16, 1, .3, 1)', fill: 'backwards' });
        // a little blur while it travels, the way a turning wheel looks
        strip.animate([{ filter: 'blur(0px)' }, { filter: 'blur(1.1px)', offset: .3 }, { filter: 'blur(0px)' }],
                      { duration: ROLL.dur * .75, delay: at, easing: 'ease-out' });
        moving++;
        cells.push(h('span', { class: 'rd', 'aria-hidden': 'true' }, h('span', { class: 'rd-v' }, c), strip));
    }
    if (!moving) return;
    el.setAttribute('aria-label', text);
    el.replaceChildren(...cells);
    const me = el._roll = (el._roll || 0) + 1;
    setTimeout(() => {
        if (el._roll !== me || !el.isConnected) return;
        el.textContent = text;
        el.removeAttribute('aria-label');
    }, delay + (moving - 1) * ROLL.step + ROLL.dur + 80);
}

/** Where a figure stands on its page: the card it is in, and its place in
 *  that card. The same page drawn again puts the same figure in the same
 *  place, so this is how a redraw knows what each figure said before. */
function figureKey(el) {
    const card = el.closest('.ef-tray, .panel, section, .ef-kpis');
    const t = card && (card.id || ((card.querySelector('.ef-tray-t, .cap, h2, h3') || {}).textContent) || card.className);
    const all = card ? [...card.querySelectorAll('[data-fig]')] : [];
    return (t || '') + '#' + all.indexOf(el);
}
function snapFigures(root) {
    const said = new Map();
    if (!root) return said;
    for (const el of root.querySelectorAll('[data-fig]')) said.set(figureKey(el), el.getAttribute('aria-label') || el.textContent);
    // and which cards had a small picture drawn in them already
    for (const el of root.querySelectorAll('.ef-viz')) if (el.firstChild) said.set('viz:' + figureKey(el), '');
    return said;
}
/** A page drawn again, quietly: only a figure that changed moves, and it
 *  rolls from what it said to what it says; a small picture that was not
 *  there before draws itself in (the junk figure, once it is measured). */
function rollChanged(root, before) {
    if (!before || !before.size) return;
    for (const el of root.querySelectorAll('[data-fig]')) {
        const was = before.get(figureKey(el));
        if (was != null && was !== el.textContent) rollFigure(el, 0, was);
    }
    if (calm() || document.hidden) return;
    for (const el of root.querySelectorAll('.ef-viz')) {
        if (el.firstChild && !before.has('viz:' + figureKey(el))) el.firstChild.classList.add('grow');
    }
}

/** The light under the picked button of a switch (14 · 30 · 90 days, and
 *  Settings' choices): one piece that slides to the button you press, the
 *  way the tabs along the top do, and is simply there the first time. */
function segGlide(box, jump, tries) {
    let g = box.querySelector(':scope > .sg');
    if (!g) { g = h('i', { class: 'sg', 'aria-hidden': 'true' }); box.prepend(g); box.classList.add('glides'); jump = true; }
    // drawn before it is on the page: placed once it is, a frame later
    if (!box.isConnected || !box.offsetWidth) {
        if ((tries || 0) < 8) requestAnimationFrame(() => segGlide(box, true, (tries || 0) + 1));
        return;
    }
    const on = box.querySelector(':scope > button.on');
    if (!on) { g.style.opacity = '0'; return; }
    g.classList.toggle('jump', !!jump || calm());
    g.style.opacity = '1';
    g.style.width = on.offsetWidth + 'px';
    g.style.height = on.offsetHeight + 'px';
    g.style.transform = `translate(${on.offsetLeft}px, ${on.offsetTop}px)`;
}

/** Something over the page going away: it plays its way out and only then
 *  leaves. `from` is the class it stops answering to at once (the sheet's),
 *  so whatever asks whether one is open hears no while it fades. */
function leave(el, from) {
    if (!el || !el.isConnected) return;
    if (calm() || document.hidden) { el.remove(); return; }
    if (from) { el.classList.remove(from); el.classList.add(from + '-out'); }
    else el.classList.add('out');
    el.setAttribute('aria-hidden', 'true');
    setTimeout(() => el.remove(), 230);
}

/** A line of words that arrives a letter at a time, each out of a little
 *  blur, the way beui's text does. Words are kept whole, so a line never
 *  breaks inside one. `since` is how far in it already is, in ms: the same
 *  greeting drawn again a moment later carries on rather than starting over. */
function letters(el, since) {
    const text = el.textContent;
    let n = 0;
    el.classList.add('glt');
    el.setAttribute('aria-label', text);
    el.style.setProperty('--gt', Math.round(since || 0) + 'ms');
    el.replaceChildren(...text.split(/(\s+)/).filter(Boolean).map(w => /^\s+$/.test(w) ? document.createTextNode(w)
        : h('span', { class: 'glt-w', 'aria-hidden': 'true' }, [...w].map(c => h('span', { class: 'glt-c', style: `--c:${n++}` }, c)))));
    return el;
}

/** The small label over the thing it is about. It stands still: a label
 *  that chases the pointer is a label you read while it moves. */
function chipAt(el, parts, cls) {
    let c = $('#chip');
    if (!c) { c = h('div', { class: 'chip', id: 'chip' }); document.body.append(c); }
    c.replaceChildren(...parts);
    // shown already, over the bar beside: it slides across to this one
    // rather than blinking out and in, the way kravio's does
    const was = c.classList.contains('show');
    c.className = 'chip show' + (cls ? ' ' + cls : '') + (was ? ' slides' : '');
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

/** Morning, afternoon or evening, by the clock on this Mac. */
function dayPart() {
    const hour = new Date().getHours();
    return hour < 5 ? 'Good evening' : hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
}

/** The wallpapers, on Home. The one on your screen is ringed and named, the
 *  rest are a row you can slide through, and a click puts one on — the same
 *  as on its own page: no dialog, and the one you had is one click back.
 *
 *  Home asks for the list the first time it draws this and not again; its own
 *  page asks again every time you open it, which is where a wallpaper you
 *  have just added turns up. */
function greeting() {
    const part = dayPart();
    const name = capital((K.meta.config.name || '').trim().split(/\s+/)[0]);
    if (!name) return 'Hello.';
    return /[.!?]$/.test(name) ? `${part}, ${name}` : `${part}, ${name}.`;
}

/* ── Home, the way Efferd's dashboards are ───────────────────────────────
   Dan sent Efferd's dashboard and said: like that, for Kliner. So Home is
   built the way it is. The greeting, then four figures, each in a tray with
   its name along the top and what goes with it on the right, and a sheet
   laid in the tray, raised a little, with the figure and how far it moved
   since the reading Kliner kept from last time. Then your folders: what
   landed in them day by day as stacked grey bars, your disk as a meter with
   a mark where it is used up to, and the hours your downloads arrive in.
   Every figure is read from this Mac — the reading, the folders' own
   listings, the undo log — and a block with nothing to say says so. Nothing
   on it is an example. How old the reading is, and Refresh, are in the bar. */

/** The pages Home sends you to, found once a draw. */
function homePages() {
    const at = k => pages().findIndex((p, n) => n > 0 && p.kind === k);
    return { desk: at('desktop'), dl: at('downloads'), docs: at('documents'), clean: at('clean'), wall: at('next'),
             dock: at('dock'), storage: at('top'), doctor: at('doctor'), undo: at('undo') };
}

/** How far back the folders are drawn, in days; the switch over them
 *  changes it for as long as the window is open. */
const HOME_SPANS = [14, 30, 90];
const HOME_VIEW = { days: 30 };

function drawHome(out, kept) {
    const pieces = kept.pieces || [];
    const home = K.home || {};
    const f = facts(pieces);
    const go = homePages();
    out.classList.add('dpage', 'ef-home');
    out.append(homeHead(home, go));
    if (!f.Disk && !f.Desktop) {
        drawAction(out, 0, kept, true);
        return;
    }
    out.append(homeKpis(home, go), homeToday(home, go), homeFolders(home, go), homeLater(f, go));
    // the people the send box offers: the Macs nearby are looked for while
    // Home is up as well as on Send, now that the box is on it
    watchNearby(true);
    // the reading this was drawn from is new: say so in the bar now, not
    // at the next tick of its clock
    sayAge();
}

/** A block's own line along its top: its name, and on the right what goes
 *  with it — a count, a switch, or the way to all of it. Send draws its
 *  blocks with it. */
function dcap(sym, text, right) {
    return h('div', { class: 'dc-h' }, icon(sym), h('span', { class: 'dc-t' }, text), right ? h('div', { class: 'dc-r' }, right) : null);
}
function dcLink(text, go) {
    return h('button', { class: 'dc-link', onclick: go }, text, icon('right'));
}

const GREET = { at: 0 };
/** Home's title: the greeting, and on the right Clean all, when there is
 *  more than one thing it would do. */
function homeHead(home, go) {
    const hm = home || {}, g = go || {};
    const todo = [g.dl > 0 && hm.downloads > 0, g.desk > 0 && hm.desk > 0, g.clean > 0 && hm.junk > 0].filter(Boolean).length;
    const sweep = todo > 1 ? cleanSweep() : [];
    // the first greeting of the session arrives a letter at a time (letters);
    // Home drawn again while it is still arriving carries on from where it was
    const title = h('h1', null, greeting());
    const since = GREET.at ? performance.now() - GREET.at : 0;
    if (!GREET.at && !calm() && !document.hidden) { GREET.at = performance.now(); letters(title, 0); }
    else if (GREET.at && since < 2400) letters(title, since);
    return h('header', { class: 'ef-head' }, title,
        sweep.length ? h('div', { class: 'ef-acts' },
            h('button', { class: 'ef-btn', onclick: () => tidyBoth(sweep) }, icon('sparkles'), 'Clean all')) : null);
}

/* ── the pieces: a tray, and the sheet in it ── */

/** A tray with its name along the top — a small picture and the name in
 *  grey — and on the right a button for what goes with it; and the sheet
 *  laid in it with what it says. A sheet that goes somewhere is pressed
 *  like a button, from the keyboard as well. */
function tray(o) {
    const sheet = h('div', { class: 'ef-sheet' + (o.sheet ? ' ' + o.sheet : '') + (o.go ? ' go' : '') }, o.body);
    if (o.go) {
        sheet.setAttribute('role', 'button');
        sheet.tabIndex = 0;
        sheet.setAttribute('aria-label', o.title);
        sheet.addEventListener('click', o.go);
        sheet.addEventListener('keydown', e => { if ((e.key === 'Enter' || e.key === ' ') && e.target === sheet) { e.preventDefault(); o.go(); } });
    }
    return h('section', { class: 'ef-tray' + (o.cls ? ' ' + o.cls : ''), id: o.id || null },
        h('header', { class: 'ef-tray-h' }, h('span', { class: 'ef-tray-t' }, icon(o.icon), h('span', null, o.title)), o.right || null),
        sheet);
}
/** The small square button at the right of a tray's top: a picture, named
 *  when you point at it. */
function trayIcon(sym, tip, go) {
    return h('button', { class: 'ef-ib', 'data-tip': tip, 'aria-label': tip, onclick: e => { e.stopPropagation(); go(); } }, icon(sym));
}
/** The same place with a word in it: the thing itself, done from here. */
function trayBtn(label, go) {
    return h('button', { class: 'ef-tb', onclick: e => { e.stopPropagation(); go(e.currentTarget); } }, label);
}

/* ── four figures ── */

/** When the reading Kliner kept from last time was made: the one the
 *  window opened on, which every change on Home is measured from. */
function baseWhen() {
    const at = K.base && K.base.at;
    if (!at) return '';
    const d = new Date(at), now = new Date();
    const day = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    const days = Math.round((day(now) - day(d)) / 864e5);
    if (days <= 0) return d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
    if (days === 1) return 'yesterday';
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

/** How far a figure moved since then, the way Efferd says it: a round
 *  arrow and the amount, green when it moved the way you want it to and
 *  red when it did not, then since when. Nothing when it did not move or
 *  there is nothing to measure it from. */
function moved(now, then, o) {
    if (!K.base || now == null || then == null || !isFinite(now) || !isFinite(then)) return null;
    const by = now - then;
    if (Math.abs(by) < (o.least || 1)) return null;
    const good = o.better === 'more' ? by > 0 : by < 0;
    return h('div', { class: 'ef-move' },
        h('span', { class: 'ef-d ' + (good ? 'good' : 'bad') }, h('i', null, icon(by > 0 ? 'up' : 'arrdown')),
          o.bytes ? size(Math.abs(by)) : whole(Math.abs(by))),
        h('span', { class: 'ef-since' }, 'since ' + baseWhen()));
}
/** One figure in its tray: the number, with its unit smaller and grey, a
 *  small picture of it on the right (a ring or a line, `o.viz`), and under
 *  it how far it moved, or a line about it when it did not. */
function kpiTray(o) {
    const [n, unit] = figure(o.value);
    return tray({ cls: 'ef-kpi', icon: o.icon, title: o.label, right: o.right, go: o.go,
        body: [h('div', { class: 'ef-kv' }, h('div', { class: 'ef-num' }, h('b', null, counted(n)), unit ? h('small', null, unit) : null), o.viz || null),
               o.move || h('div', { class: 'ef-sub' + (o.busy ? ' shim' : '') }, o.sub || '')] });
}

/* ── v19: a small picture beside each figure ─────────────────────────────
   kravio puts a line beside every figure; boardui a ring. Here a small
   donut of the disk is for a share — what is free of it; what cleaning
   would free, beside what is free already — and the line is for what
   landed in a folder each day of the last two weeks. A ring with one short
   arc on a pale track reads as something still loading, so the donut is
   all parts, each in its own grey with a gap between. Warm grey like every
   chart here; each one is read from this Mac, never drawn for show. */

const RING_C = 2 * Math.PI * 15;
/** A small donut of your disk: each part a share of it in its own grey, a
 *  little gap between them, starting at the top. The part the figure is
 *  about comes first, in the strongest grey. */
function donutViz(parts, title) {
    const GAP = 2.2;
    const shown = parts.filter(p => p.share > 0);
    let at = 0;
    const arcs = shown.map((p, n) => {
        const len = Math.max(.8, p.share * RING_C - (shown.length > 1 ? GAP : 0));
        const arc = s('circle', { class: p.cls, cx: 18, cy: 18, r: 15, transform: 'rotate(-90 18 18)',
            style: `--n:${n};stroke-dasharray:${len.toFixed(2)} ${RING_C.toFixed(2)};stroke-dashoffset:${(-(at + (shown.length > 1 ? GAP / 2 : 0))).toFixed(2)}` });
        at += p.share * RING_C;
        return arc;
    });
    return h('span', { class: 'ef-viz', title, role: 'img', 'aria-label': title },
        s('svg', { class: 'ef-ring', viewBox: '0 0 36 36', width: 36, height: 36, 'aria-hidden': 'true' }, arcs));
}

/** The place a folder's line goes; it is drawn once the folder has been
 *  read (paintSparks), which on the first Home is a moment after. */
function sparkViz(page, name) {
    return h('span', { class: 'ef-viz ef-sparkbox', 'data-spark': page, role: 'img',
                       title: 'What landed in ' + name + ' each day, the last 14 days',
                       'aria-label': 'What landed in ' + name + ' each day, the last 14 days' });
}
let SPARK_N = 0;
function paintSparks(root, grow) {
    const DAYS = 14;
    for (const box of (root || document).querySelectorAll('[data-spark]')) {
        const got = K.listing && K.listing[+box.dataset.spark];
        if (!got || got.shut) { box.replaceChildren(); continue; }
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const dayOf = dayCounter(today.getTime() - (DAYS - 1) * 864e5);
        const per = new Array(DAYS).fill(0);
        for (const f of got.items) {
            if (!f.modified || !countedByNimo(f)) continue;
            const k = dayOf(f.modified);
            if (k >= 0 && k < DAYS) per[k]++;
        }
        const was = box.dataset.said, now = per.join(',');
        box.dataset.said = now;
        // the same line again is left alone
        if (was === now && box.firstChild) continue;
        box.replaceChildren(sparkSvg(per, grow));
    }
}
function sparkSvg(values, grow) {
    const W = 88, H = 32, pad = 3;
    const most = Math.max(1, ...values);
    const x = k => pad + k / (values.length - 1) * (W - pad * 2);
    const y = v => H - pad - v / most * (H - pad * 2 - 2);
    const pts = values.map((v, k) => [x(k), y(v)]);
    const line = pts.map((p, k) => (k ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
    const id = 'efsp' + (++SPARK_N);
    const end = pts[pts.length - 1];
    return s('svg', { class: 'ef-spark' + (grow ? ' grow' : ''), viewBox: `0 0 ${W} ${H}`, width: W, height: H, 'aria-hidden': 'true' },
        s('defs', null, s('linearGradient', { id, x1: 0, y1: 0, x2: 0, y2: 1 },
            s('stop', { offset: 0, 'stop-color': 'currentColor', 'stop-opacity': .2 }),
            s('stop', { offset: 1, 'stop-color': 'currentColor', 'stop-opacity': 0 }))),
        s('path', { class: 'ar', d: `${line} L${end[0].toFixed(1)} ${H} L${pad} ${H} Z`, fill: `url(#${id})` }),
        s('path', { class: 'ln', d: line }),
        s('circle', { class: 'pg', cx: end[0].toFixed(1), cy: end[1].toFixed(1), r: 2.5 }),
        s('circle', { class: 'pt', cx: end[0].toFixed(1), cy: end[1].toFixed(1), r: 2.5 }));
}

/** "3 over 30 days", the way nimo says it, as a line under a count. */
function olderLine(text, n) {
    const m = /^(\d+) over (\d+) days$/.exec(String(text || '').trim());
    if (m) return m[1] === String(n) ? 'All of it older than ' + m[2] + ' days' : m[1] + ' older than ' + m[2] + ' days';
    return n > 0 ? 'Nothing older than 30 days' : '';
}

function homeKpis(home, go) {
    const b = (K.base && K.base.home) || {};
    const cells = [];
    if (home.total > 0) {
        cells.push(kpiTray({ icon: 'gauge', label: 'Free', value: size(home.free),
            move: moved(home.free, b.free, { bytes: true, better: 'more', least: 50e6 }),
            sub: percent(home.free, home.total) + ' of your disk',
            // the disk as a ring: what is used, dark, and the free part the
            // light gap in it. A short dark arc on a pale ring was a spinner.
            viz: donutViz([{ share: home.used / home.total, cls: 'k' }, { share: home.free / home.total, cls: 'u' }],
                          percent(home.free, home.total) + ' of your disk is free'),
            go: go.storage > 0 ? () => show(go.storage) : null,
            right: go.storage > 0 ? trayIcon('expand', 'Storage', () => show(go.storage)) : null }));
    }
    const junk = home.junk;
    cells.push(kpiTray({ icon: 'sparkles', label: 'Can be freed',
        value: junk == null ? '…' : junk > 0 ? size(junk) : 'Nothing',
        sub: junk == null ? 'Measuring the caches…' : junk > 0 ? 'Caches and the Trash' : 'Your caches are clean',
        busy: junk == null,
        // the same ring: what stays, dark; what cleaning frees, lighter;
        // and what is free already, the gap
        viz: junk > 0 && home.total > 0 ? donutViz([{ share: Math.max(0, home.used - junk) / home.total, cls: 'k' },
                                                    { share: Math.min(junk, home.used) / home.total, cls: 'f' },
                                                    { share: home.free / home.total, cls: 'u' }],
            percent(home.free, home.total) + ' free now, ' + percent(home.free + junk, home.total) + ' once it is cleaned') : null,
        move: junk > 0 ? moved(junk, b.junk, { bytes: true, better: 'less', least: 50e6 }) : null,
        go: go.clean > 0 ? () => show(go.clean) : null,
        right: go.clean > 0 && junk > 0 ? trayBtn('Clean', () => act(go.clean))
             : go.clean > 0 ? trayIcon('expand', 'Free up space', () => show(go.clean)) : null }));
    for (const [k, key, label, sym, old, none] of [['desk', 'desk', 'Desktop', 'grid', 'deskOld', 'Clear'],
                                                   ['downloads', 'dl', 'Downloads', 'download', 'downloadsOld', 'Empty']]) {
        const n = home[k], page = go[key];
        if (n == null || !(page > 0)) continue;
        cells.push(kpiTray({ icon: (pages()[page] || {}).symbol || sym, label, value: plural(n, 'item'),
            move: moved(n, b[k], { better: 'less' }),
            sub: n > 0 ? olderLine(home[old], n) : none,
            viz: sparkViz(page, label),
            go: () => show(page),
            right: n > 0 ? trayBtn('Tidy', () => act(page)) : trayIcon('expand', label, () => show(page)) }));
    }
    const row = h('div', { class: 'ef-kpis', style: `--k:${cells.length}` }, cells);
    // the folders' own listings, when Kliner has read them already
    paintSparks(row, false);
    return row;
}

/* ── v20: Home, with the sender and the rest of the day ───────────────────
   Dan, after v19: "add the sender too, and the rest, so Home is not so
   empty". So under the four figures, the box you send from — the one send
   box, moved here from Send's pane while Home is up (homeSender), so what
   you typed and the file you chose come with it — with the last files on
   their way, or the people, under it; and beside it what Kliner can do in
   one click that the figures do not offer already. Under the folders, what
   Kliner did lately with the way back, and this Mac in a few lines. All of
   it is read from this Mac, and a block with nothing to say says so. */

function homeToday(home, go) {
    return h('div', { class: 'ef-grid ef-today' }, sendTray(), quickTray(home, go));
}
function homeLater(f, go) {
    return h('div', { class: 'ef-grid ef-later' }, doneTray(go), macTray(f, go));
}

/** The send box on Home: the same box as at the foot of Send's pane,
 *  moved in, and under it the last files or the people. */
function sendTray() {
    const slot = h('div', { class: 'ef-snd', id: 'homeSnd' });
    homeSender(slot);
    const list = h('div', { class: 'ef-snd-l', id: 'homeTx' });
    const me = bareName(handle());
    const card = tray({ cls: 'ef-send', icon: 'send', title: me ? 'Send a file · @' + me : 'Send a file',
                        right: trayIcon('expand', 'Send', () => show(SHARE())), body: [slot, list] });
    paintHomeTx(list);
    return card;
}

/** The one send box, put where it is used. It is moved rather than drawn
 *  twice, so the name typed into it and the file chosen go with it, and
 *  every part of it keeps the one id the rest of the page knows it by.
 *  drawPage puts it back at the foot of the pane before each page
 *  (parkSender); Home takes it again. */
function homeSender(slot) {
    const snd = $('#snd');
    if (snd) slot.append(snd);
}
function parkSender() {
    const snd = $('#snd'), foot = $('#insp .insp-f');
    if (snd && foot && snd.parentElement !== foot) foot.append(snd);
}

/** Under the box: the last three files on their way or arrived, or, before
 *  there are any, the people — the Macs nearby, then whoever you sent to
 *  before — each with Send. */
function paintHomeTx(root) {
    const el = root || $('#homeTx');
    if (!el) return;
    const jobs = [...SEND.jobs.values()].reverse().slice(0, 3);
    if (jobs.length) {
        const card = el.closest('.ef-send');
        if (card) card.classList.remove('lists-people');
        const open = j => () => { INSP.pick = { kind: 'job', id: j.id }; show(SHARE()); if (!INSP.open && inspFits()) toggleInsp(true); };
        el.replaceChildren(h('div', { class: 'ef-snd-h' }, 'Lately'), h('div', { class: 'tl' }, jobs.map(j => txRow(j, open(j)))));
        return;
    }
    const me = bareName(handle());
    const nearby = SEND.people.filter(u => u !== me);
    const recent = recentNames().filter(u => u !== me && !nearby.includes(u));
    const people = [...nearby.map(u => personRow(u, true)), ...recent.map(u => personRow(u, false))].slice(0, 3);
    // the people are listed here, so the box over it need not offer them too
    const card = el.closest('.ef-send');
    if (card) card.classList.toggle('lists-people', people.length > 0);
    el.replaceChildren(...(people.length
        ? [h('div', { class: 'ef-snd-h' }, nearby.length ? plural(nearby.length, 'Mac') + ' nearby' : 'Sent before'), h('div', { class: 'tl' }, people)]
        : [h('div', { class: 'ef-none' }, SEND.offline || 'Nobody nearby right now. Any @username works, near or far.')]));
}

/** What Kliner can do from here in one click that the figures over it do
 *  not offer already: the desktop's icons, the next wallpaper, Documents,
 *  the Dock, and what starts with the Mac. A row with a button does the
 *  thing (still asking first where its page asks); the rest open their
 *  page. */
function quickTray(home, go) {
    const rows = [];
    const hidden = !!(K.meta && K.meta.desktopHidden);
    rows.push(todoRow({ icon: hidden ? 'eye' : 'eyeoff', title: hidden ? 'Show desktop icons' : 'Hide desktop icons',
                        sub: hidden ? 'Finder draws your desktop again' : 'A bare desktop; every file stays', key: '\\', go: toggleIcons }));
    if (go.wall > 0) {
        const on = (K.walls || []).find(w => /\bon now\b/.test(w.parts.slice(1).join(' ')));
        rows.push(todoRow({ icon: 'photo', title: 'Next wallpaper', sub: on ? 'Now: ' + on.parts[0] : 'The next one in your list',
                            act: ['Next', () => act(go.wall)], go: () => show(go.wall) }));
    }
    if (go.docs > 0) {
        const got = K.listing && K.listing[go.docs];
        const loose = got && !got.shut ? got.items.filter(f => countedByNimo(f) && !(f.dir && f.name === tidyName())).length : 0;
        if (loose > 0) rows.push(todoRow({ icon: 'file', title: 'Tidy documents', sub: plural(loose, 'item') + ' loose in Documents',
                                           act: ['Tidy', () => act(go.docs)], go: () => show(go.docs) }));
    }
    if (go.dock > 0) rows.push(todoRow({ icon: 'desk', title: 'Clean the Dock', sub: 'Only what you use; the apps stay', go: () => show(go.dock) }));
    const startup = pages().findIndex((p, n) => n > 0 && p.kind === 'startup');
    if (startup > 0) rows.push(todoRow({ icon: 'power', title: 'What starts with your Mac', sub: 'Login items and agents', go: () => show(startup) }));
    return tray({ cls: 'ef-quick', icon: 'bolt', title: 'Quick actions', body: h('div', { class: 'tl' }, rows) });
}

/** What Kliner did lately, this session first and then its log, each with
 *  the way back (paintHomeDone). */
function doneTray(go) {
    const body = h('div', { class: 'tl', id: 'homeDone' });
    paintHomeDone(body);
    return tray({ cls: 'ef-done', icon: 'undo', title: 'Done lately', body,
                  right: go.undo > 0 ? trayIcon('expand', 'Undo', () => show(go.undo)) : null });
}

/** This Mac in a few lines, from the same reading Home was drawn from; the
 *  battery with how full it is. */
function macTray(f, go) {
    const rows = [];
    for (const [k, label] of [['System', 'System'], ['Memory', 'Memory'], ['Battery', 'Battery'], ['Uptime', 'Up for'], ['Trash', 'Trash']]) {
        const p = f[k];
        if (!p || !p.value) continue;
        const pct = k === 'Battery' ? /(\d{1,3})\s*%/.exec(p.value) : null;
        rows.push(h('div', { class: 'ef-fact' }, h('span', null, label),
            pct ? h('span', { class: 'ef-batt', style: `--b:${Math.min(100, +pct[1])}%`, 'aria-hidden': 'true' }, h('i')) : null,
            h('b', null, k === 'Trash' ? p.value : counted(p.value))));
    }
    return tray({ cls: 'ef-mac', icon: 'cpu', title: 'This Mac',
                  right: go.doctor > 0 ? trayIcon('expand', 'This Mac', () => show(go.doctor)) : null,
                  body: rows.length ? h('div', { class: 'ef-facts' }, rows) : h('div', { class: 'ef-none' }, 'Kliner has no reading of this Mac yet.') });
}

/* ── your folders ──
   Three trays the way Efferd's Today is laid: the big one on the left,
   two on the right. What is in each folder is read from the folders
   themselves, the way their own pages read them (listing), and what Kliner
   tidied out of them from its undo log. */

const FOLDER_ROWS = [['desktop', 'desk', 'Desktop', 'c1'], ['downloads', 'dl', 'Downloads', 'c2'], ['documents', 'docs', 'Documents', 'c3']];

/** The folders Home has a row for: the ones with a page, less any macOS
 *  has said Kliner may not look in. */
function folderRows() {
    const go = homePages();
    const seeing = (K.meta && K.meta.seeing) || {};
    return FOLDER_ROWS.map(([k, key, name, tone]) => ({ k, page: go[key], name, tone })).filter(r => r.page > 0 && seeing[r.k] !== false);
}

function homeFolders(home, go) {
    const days = HOME_VIEW.days;
    const seg = h('div', { class: 'ef-seg', role: 'tablist', 'aria-label': 'How far back' });
    for (const d of HOME_SPANS) {
        seg.append(h('button', { class: d === days ? 'on' : '', role: 'tab', 'aria-selected': String(d === days), 'data-days': d,
                                 onclick: e => {
                                     if (HOME_VIEW.days === d) return;
                                     HOME_VIEW.days = d;
                                     for (const b of seg.querySelectorAll('button')) { const on = +b.dataset.days === d; b.classList.toggle('on', on); b.setAttribute('aria-selected', String(on)); }
                                     segGlide(seg);
                                     paintLanded(null, true);
                                 } }, d + ' days'));
    }
    segGlide(seg);
    const landed = tray({ cls: 'ef-landed', icon: 'trend', title: 'Landed in your folders',
        right: go.undo > 0 ? trayIcon('undo', 'What Kliner moved', () => show(go.undo)) : null,
        body: h('div', { class: 'ef-landed-b', id: 'efLanded' }) });
    const hours = tray({ cls: 'ef-hours', icon: 'clock', title: 'Busiest hours',
        right: go.dl > 0 ? trayIcon('expand', 'Downloads', () => show(go.dl)) : null,
        body: h('div', { class: 'ef-hours-b', id: 'efHours' }) });
    const sec = h('section', { class: 'ef-sec' },
        h('header', { class: 'ef-sec-h' }, h('h2', null, 'Your folders'), seg),
        h('div', { class: 'ef-grid' }, landed, h('div', { class: 'ef-side' }, diskTray(home, go), hours)));
    paintLanded(sec, false);
    paintHours(sec);
    readFolders();
    // what Kliner tidied out of them is in the undo log
    readHomeLog();
    return sec;
}

/** What is in each folder, read again when it is older than its page
 *  would keep it (listing), and the trays drawn again when it comes. */
let FOLDERS_READING = false;
async function readFolders() {
    const rows = folderRows();
    const fresh = r => K.listing && K.listing[r.page] && Date.now() - K.listing[r.page].at <= 20000;
    if (FOLDERS_READING || rows.every(fresh)) return;
    const had = rows.some(r => K.listing && K.listing[r.page]);
    FOLDERS_READING = true;
    try { await Promise.all(rows.map(r => listing(r.page))); } finally { FOLDERS_READING = false; }
    // the bars rise the first time there is something to draw, and only then
    paintLanded(null, !had && !calm());
    paintHours(null, !had && !calm());
    paintSparks(null, !had && !calm());
}

/** "03.10.2026 08:37", the way nimo writes a time, as the time it is. */
function nimoWhen(text) {
    const m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2}):(\d{2})/.exec(String(text || '').trim());
    return m ? new Date(+m[3], +m[2] - 1, +m[1], +m[4], +m[5]).getTime() : 0;
}

/** The day a moment falls on, counted from the first day drawn; rounded,
 *  so the hour a clock change takes or gives moves nothing to the wrong day. */
function dayCounter(first) {
    return t => { const d = new Date(t); d.setHours(0, 0, 0, 0); return Math.round((d.getTime() - first) / 864e5); };
}

/** A scale for counts: a round step, about three of them, and the top the
 *  last step reaches, so every line on the chart names a value it has. */
function niceScale(most) {
    const rough = Math.max(1, most / 3);
    const mag = Math.pow(10, Math.floor(Math.log10(rough)));
    const f = rough / mag;
    const step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * mag;
    return { step, top: Math.max(step, Math.ceil(most / step) * step) };
}

/** What landed in your folders, a bar a day: Downloads at the foot of each
 *  bar, then Desktop, then Documents, in three greys, the last of them
 *  hatched — evilcharts' way of telling a third series apart without a
 *  colour. A scale up the right with a faint line at each step, the way
 *  kravio draws one, and the busiest day named over its bar with a dashed
 *  line across at its height; the line goes to whichever day you point at.
 *  The totals across the top, with what Kliner tidied away in the same
 *  days, roll to their new figures when the span changes; the days are
 *  under it. */
function paintLanded(root, grow) {
    const box = (root || document).querySelector('#efLanded');
    if (!box) return;
    const rows = folderRows();
    if (!rows.length) {
        box.replaceChildren(h('div', { class: 'ef-none' }, 'Kliner cannot look in your folders yet.'));
        return;
    }
    const days = HOME_VIEW.days, DAY = 864e5;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const first = today.getTime() - (days - 1) * DAY;
    const dayOf = dayCounter(first);
    const noon = k => new Date(first + k * DAY + 12 * 3600e3);
    const dateOf = k => noon(k).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    const dayName = k => k === days - 1 ? 'Today' : dateOf(k);
    // Downloads first: it is the one that fills up, and it is the bottom of
    // every bar, in the strongest grey
    const order = ['downloads', 'desktop', 'documents'];
    const series = rows.slice().sort((a, b) => order.indexOf(a.k) - order.indexOf(b.k)).map((r, n) => {
        const got = K.listing && K.listing[r.page];
        const per = new Array(days).fill(0);
        let total = 0;
        if (got && !got.shut) {
            for (const f of got.items) {
                if (!f.modified || !countedByNimo(f)) continue;
                const k = dayOf(f.modified);
                if (k < 0 || k >= days) continue;
                per[k]++;
                total++;
            }
        }
        return { name: r.name, k: r.k, per, total, got: !!got, shut: !!(got && got.shut), tone: 's' + (n + 1) };
    });
    // what Kliner tidied away out of these folders in the same days
    let away = 0;
    for (const it of HOME_LOG.items || []) {
        const p = it.parts || [];
        const what = String(p[0] || '').trim().toLowerCase();
        if (!/^(cleared your desktop|sorted your downloads|sorted your documents)/.test(what)) continue;
        if (nimoWhen(p[1]) >= first) away += count(p[2] || '');
    }
    const legend = h('div', { class: 'ef-legend' }, series.map(x =>
        h('div', { class: 'ef-lg' }, h('div', { class: 'ef-lg-k' }, h('i', { class: 'ef-dot ' + x.tone }), x.name),
          h('b', null, !x.got ? '…' : x.shut ? '—' : counted(whole(x.total))))));
    const right = away > 0 ? h('div', { class: 'ef-move' },
        h('span', { class: 'ef-d good' }, h('i', null, icon('arrdown')), whole(away)), h('span', { class: 'ef-since' }, 'tidied away')) : null;
    const sums = new Array(days).fill(0).map((_, k) => series.reduce((s, x) => s + x.per[k], 0));
    const scale = niceScale(Math.max(1, ...sums));
    const tall = v => (v / scale.top * 100).toFixed(3) + '%';
    const plot = h('div', { class: 'ef-bars' + (grow ? ' grow' : ''), style: `--n:${days}` });
    // the scale first, under the bars: a line at each step, its figure on the right
    const ys = h('div', { class: 'ef-ys', 'aria-hidden': 'true' });
    for (let v = 0; v <= scale.top; v += scale.step) {
        ys.append(h('i', { class: v ? '' : 'z', style: `bottom:${tall(v)}` }), h('span', { style: `bottom:${tall(v)}` }, whole(v)));
    }
    plot.append(ys);
    for (let k = 0; k < days; k++) {
        const col = h('div', { class: 'ef-bar', 'data-k': k, style: `--i:${Math.min(k, 60)}` });
        for (const x of series) {
            const v = x.per[k];
            if (v) col.append(h('i', { class: x.tone, style: `height:${tall(v)}` }));
        }
        if (!sums[k]) col.append(h('i', { class: 'nil' }));
        plot.append(col);
    }
    // the busiest day, named; the latest of them when two are as busy
    let peak = -1;
    for (let k = 0; k < days; k++) if (sums[k] > 0 && (peak < 0 || sums[k] >= sums[peak])) peak = k;
    const guide = h('i', { class: 'ef-guide', 'aria-hidden': 'true' });
    const flag = h('span', { class: 'ef-peak', 'aria-hidden': 'true' });
    const pin = k => {
        guide.style.bottom = k < 0 ? '0%' : tall(sums[k]);
        guide.classList.toggle('off', k < 0);
    };
    if (peak >= 0) {
        flag.append(h('span', null, dayName(peak)), h('b', null, whole(sums[peak])));
        flag.style.left = ((peak + .5) / days * 100).toFixed(3) + '%';
        flag.style.bottom = tall(sums[peak]);
        // near either end it leans in, so it stays over the chart
        flag.classList.toggle('l', peak < days * .12);
        flag.classList.toggle('r', peak > days * .88);
    }
    pin(peak);
    plot.append(guide);
    if (peak >= 0) plot.append(flag);
    const tip = col => {
        const k = +col.dataset.k;
        const parts = [h('span', { class: 'ef-tip-d' }, dayName(k))];
        for (const x of series) {
            parts.push(h('span', { class: 'ef-tip-r' }, h('i', { class: 'ef-dot ' + x.tone }), h('span', null, x.name), h('b', null, whole(x.per[k]))));
        }
        chipAt(col.querySelector('i') || col, parts, 'ef');
    };
    const cols = () => plot.querySelectorAll('.ef-bar');
    plot.addEventListener('mouseover', e => {
        const col = e.target.closest('.ef-bar');
        if (!col) return;
        for (const c of cols()) c.classList.toggle('dim', c !== col);
        plot.classList.add('pointing');
        pin(+col.dataset.k);
        tip(col);
    });
    plot.addEventListener('mouseleave', () => {
        for (const c of cols()) c.classList.remove('dim');
        plot.classList.remove('pointing');
        pin(peak);
        chipOff();
    });
    // the days under it, counted back from today so today is always named
    const step = days <= 14 ? 2 : days <= 30 ? 5 : 15;
    const axis = h('div', { class: 'ef-axis', 'aria-hidden': 'true' });
    for (let k = days - 1; k >= 0; k -= step) {
        axis.prepend(h('span', { style: `left:${((k + .5) / days * 100).toFixed(3)}%` }, dayName(k)));
    }
    const quiet = series.every(x => x.got) && !sums.some(Boolean)
        ? h('div', { class: 'ef-quiet' }, 'Nothing landed in these ' + days + ' days.') : null;
    // drawn again where it already was: its totals roll from what they said
    const was = root ? null : snapFigures(box);
    box.replaceChildren(h('div', { class: 'ef-top' }, legend, right), h('div', { class: 'ef-plot' }, plot, quiet), axis);
    if (was) {
        if (was.size) {
            for (const el of box.querySelectorAll('[data-to]')) el.removeAttribute('data-to');
            rollChanged(box, was);
        } else runCounts(box);
    }
}

/** Your disk as a gauge, the way evilcharts draws a share: thirty-two ticks
 *  round half a circle, as many lit as the share of it in use, lit one
 *  after another when it arrives, and the share in the middle; what is used
 *  and how big it is under it, side by side. */
function diskTray(home, go) {
    let body;
    if (!(home.total > 0)) {
        body = h('div', { class: 'ef-none' }, 'Kliner could not read your disk.');
    } else {
        const part = Math.max(0, Math.min(1, home.used / home.total));
        body = [gaugeViz(part, size(home.free) + ' free of ' + size(home.total)),
                h('div', { class: 'ef-pair' },
                    h('div', null, h('p', { class: 'ef-k' }, 'Used'), h('p', { class: 'ef-v' }, counted(size(home.used)))),
                    h('div', { class: 'ef-pair-r' }, h('p', { class: 'ef-k' }, 'Capacity'), h('p', { class: 'ef-v sm' }, size(home.total))))];
    }
    return tray({ cls: 'ef-disk', icon: 'disk', title: 'Your disk', body,
                  right: go.storage > 0 ? trayIcon('expand', 'Storage', () => show(go.storage)) : null });
}
function gaugeViz(part, title) {
    const N = 32, lit = Math.round(part * N), cx = 110, cy = 104, r1 = 83, r2 = 97;
    const svg = s('svg', { class: 'ef-gauge-g', viewBox: '0 0 220 110', 'aria-hidden': 'true' });
    for (let n = 0; n < N; n++) {
        const a = Math.PI * (1 - n / (N - 1)), c = Math.cos(a), sn = Math.sin(a);
        svg.append(s('line', { class: n < lit ? 'on' : null, style: n < lit ? `--t:${n}` : null,
            x1: (cx + c * r1).toFixed(2), y1: (cy - sn * r1).toFixed(2), x2: (cx + c * r2).toFixed(2), y2: (cy - sn * r2).toFixed(2) }));
    }
    const pct = Math.round(part * 100);
    return h('div', { class: 'ef-gauge', title, role: 'img', 'aria-label': pct + '% of your disk is used' }, svg,
        h('div', { class: 'ef-gv' }, h('b', null, counted(pct + '%')), h('span', null, 'used')));
}

/** The hours your downloads arrive in: a bar an hour, each standing in its
 *  own grey track the way boardui draws them, the busiest two lit, and what
 *  share of everything in Downloads came in them; four hours named under. */
function paintHours(root, grow) {
    const box = (root || document).querySelector('#efHours');
    if (!box) return;
    const dl = homePages().dl;
    const got = dl > 0 && K.listing && K.listing[dl];
    const say = (title, sub) => h('div', { class: 'ef-st' }, h('b', null, title), sub ? h('span', null, sub) : null);
    if (!(dl > 0)) { box.replaceChildren(say('No Downloads folder')); return; }
    if (!got) { box.replaceChildren(say('Reading your downloads…')); return; }
    if (got.shut) { box.replaceChildren(say('Not allowed', 'macOS has not let Kliner look in Downloads.')); return; }
    const items = got.items.filter(f => f.modified && countedByNimo(f));
    if (items.length < 4) {
        box.replaceChildren(say('Too few to tell', items.length ? plural(items.length, 'download') + ' so far' : 'Downloads is empty'));
        return;
    }
    const per = new Array(24).fill(0);
    for (const f of items) per[new Date(f.modified).getHours()]++;
    let best = -1, at = 0;
    for (let x = 0; x < 23; x++) if (per[x] + per[x + 1] > best) { best = per[x] + per[x + 1]; at = x; }
    const clock = x => String(x % 24).padStart(2, '0') + ':00';
    const most = Math.max(1, ...per);
    const plot = h('div', { class: 'ef-bars hours' + (grow ? ' grow' : ''), style: '--n:24' });
    per.forEach((v, x) => plot.append(h('div', { class: 'ef-bar' + (x === at || x === at + 1 ? ' hot' : ''), 'data-x': x, style: `--i:${x}` },
        h('i', { class: v ? 's1' : 'nil', style: v ? `height:${(v / most * 100).toFixed(2)}%` : null }))));
    plot.addEventListener('mouseover', e => {
        const col = e.target.closest('.ef-bar');
        if (!col) return;
        const x = +col.dataset.x;
        chipAt(col.querySelector('i') || col, [h('span', { class: 'ef-tip-d' }, clock(x) + ' – ' + clock(x + 1)),
            h('span', { class: 'ef-tip-r' }, h('span', null, 'Downloads'), h('b', null, whole(per[x])))], 'ef');
    });
    plot.addEventListener('mouseleave', chipOff);
    const axis = h('div', { class: 'ef-axis hours', 'aria-hidden': 'true' },
        [0, 6, 12, 18].map(x => h('span', { style: `left:${(x / 24 * 100).toFixed(3)}%` }, clock(x))));
    box.replaceChildren(say(clock(at) + ' – ' + clock(at + 2), Math.round(best / items.length * 100) + '% of your downloads arrive then'), plot, axis);
}

/* ── a thing to do, as a row: Send's people and transfers, and the log ── */

/** One thing: its picture, what it is and a line about it, and on the
 *  right the button that does it, the key, or the way to its page. The row
 *  is the way in; the button, when there is one, is the thing itself. */
function todoRow(o) {
    const row = h('div', { class: 'tl-row' + (o.done ? ' is-done' : '') + (o.go ? ' go' : ''), id: o.id || null, 'data-pick': o.pick || null,
                           role: o.go ? 'button' : null, tabindex: o.go ? '0' : null, 'aria-label': o.go ? o.title : null },
        h('span', { class: 'tl-ic' }, icon(o.icon)),
        h('span', { class: 'tl-w' }, h('b', null, o.title), h('span', null, o.sub || '')),
        o.when ? h('span', { class: 'tl-when' }, o.when) : null,
        o.act ? h('button', { class: 'btn line small tl-do', onclick: e => { e.stopPropagation(); o.act[1](e.currentTarget); } }, o.act[0])
              : o.key ? h('kbd', { class: 'tl-key' }, o.key)
              : o.right ? o.right
              : o.go ? h('span', { class: 'tl-go' }, icon('right')) : null);
    if (o.go) {
        row.addEventListener('click', () => o.go());
        row.addEventListener('keydown', e => {
            if ((e.key === 'Enter' || e.key === ' ') && e.target === row) { e.preventDefault(); (o.act ? o.act[1] : o.go)(); }
        });
    }
    return row;
}

/* ── what Kliner has done ── */

/** "03.10.2026 08:37", the way nimo writes it, said shortly: the time when
 *  it was today, the day when it was not. */
function shortWhen(text) {
    const m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2}:\d{2})/.exec(String(text || '').trim());
    if (!m) return String(text || '');
    const d = new Date(+m[3], +m[2] - 1, +m[1]);
    const now = new Date();
    if (d.toDateString() === now.toDateString()) return m[4];
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function homeDone(go) {
    const body = h('div', { class: 'tl', id: 'homeDone' });
    paintHomeDone(body);
    readHomeLog();
    return panel('ddone', dcap('undo', 'Done lately', go.undo > 0 ? dcLink('View all', () => show(go.undo)) : null), body);
}

/** The picture for a line of the undo log: what kind of thing it put away. */
function logPicture(what) {
    const w = String(what || '').toLowerCase();
    return /desktop icons/.test(w) ? 'eyeoff' : /desktop/.test(w) ? 'grid' : /downloads/.test(w) ? 'download'
        : /screenshots/.test(w) ? 'camera' : /wallpaper/.test(w) ? 'photo' : /dock/.test(w) ? 'desk'
        : /starting|login/.test(w) ? 'power' : /file/.test(w) ? 'file' : 'undo';
}

/** This session first, then the log Kliner keeps of every move, each with
 *  the way back; a run of the same small thing is one line. Three at most:
 *  the rest is one click away. */
function paintHomeDone(body) {
    const undoPage = pages().findIndex(p => p.kind === 'undo');
    const rows = [];
    const clock = d => d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
    const icons = j => j.title === 'Desktop' && /^Icons /.test(j.line || '');
    for (const run of foldRuns(K.jobs, icons).slice(0, 3)) {
        const j = run.first, many = run.all.length;
        const state = j.preview ? ['eye', 'Preview', ''] : j.good ? ['check', 'Done', 'good'] : ['x', 'Did not work', 'bad'];
        const title = many > 1 ? 'Hid and showed desktop icons' : j.title;
        const id = 'j' + rows.length;
        rows.push(todoRow({ icon: many > 1 ? 'eyeoff' : j.page === SHARE() ? 'send' : (pages()[j.page] || {}).symbol || 'check',
                            title, sub: many > 1 ? plural(many, 'time') : j.line, pick: 'done:' + id,
                            when: clock(j.at), right: h('span', { class: 'pill ' + state[2] }, icon(state[0]), state[1]),
                            go: pickOr({ kind: 'done', id, job: j, title }, () => show(j.page)) }));
    }
    const toggled = it => /desktop icons$/i.test(((it.parts || [])[0] || '').trim());
    for (const run of foldRuns(HOME_LOG.items || [], toggled).slice(0, Math.max(0, 3 - rows.length))) {
        const p = run.first.parts || [];
        const many = run.all.length;
        const both = many > 1 && new Set(run.all.map(it => ((it.parts || [])[0] || '').split(' ')[0].toLowerCase())).size > 1;
        const back = undoPage > 0 ? () => show(undoPage) : null;
        const title = both ? 'Hid and showed desktop icons' : capital(p[0] || '');
        const id = 'l' + rows.length;
        rows.push(todoRow({ icon: logPicture(p[0]), title, sub: many > 1 ? plural(many, 'time') : p[2] || '', when: shortWhen(p[1] || ''),
                            act: back ? ['Undo', back] : null, pick: 'done:' + id,
                            go: pickOr({ kind: 'done', id, parts: p, many, title }, back) }));
    }
    if (!rows.length) {
        body.replaceChildren(h('div', { class: 'd-none' }, HOME_LOG.items == null && undoPage > 0 ? 'Reading the log…'
            : 'Nothing yet. What Kliner does shows up here, with the way back.'));
        return;
    }
    body.replaceChildren(...rows);
}

/* ── the pane on the right ──────────────────────────────────────────────
   His dashboard has the pull request open beside it: a pane on the glass,
   the wallpaper behind it, and on it what the thing is — a line in its own
   colour, its name, its facts as names and values, what is in it under
   headings that fold — with the box you write in at its foot. Here the
   pane is what you picked: this Mac until a row on Home picks a folder, a
   thing to do or something Kliner did; the folder on a folder's page; what
   Free up space, Startup and Undo used to keep in a column beside them; a
   file on its way. At its foot, on every page, the box that sends a file.
   A window too narrow for it keeps it behind the button at the right of
   the bar, and it comes in over the page. */

const INSP = { open: false, fits: null, pick: null, folded: new Set() };
const INSP_ROOM = 1180;   // the window width the pane stands beside the page at

const inspFits = () => window.innerWidth >= INSP_ROOM;

function inspFrame() {
    return h('aside', { class: 'insp', id: 'insp', 'aria-label': 'Details' },
        h('header', { class: 'insp-h' },
            h('button', { class: 'sq insp-x', 'data-hole': '', 'data-tip': 'Hide the pane', 'aria-label': 'Hide the pane',
                          onclick: () => toggleInsp(false) }, icon('sidebar')),
            h('span', { class: 'insp-t', id: 'inspTitle' }, 'Details')),
        h('div', { class: 'insp-b', id: 'inspBody' }),
        h('div', { class: 'insp-f' }, h('section', { class: 'panel snd', id: 'snd' })));
}

function toggleInsp(on) {
    INSP.open = !!on;
    paneFrame();
    if (INSP.open) paintInsp();
    // Send keeps you on its page while the pane is away, and gives you to it
    // when it comes back
    if (K.page === SHARE()) drawPage(true, true);
}

/** The pane in the frame, or not: there on Home and Send while it is open,
 *  its button in the bar while it is not. */
function paneFrame() {
    const app = $('#app');
    if (app) app.classList.toggle('insp-on', INSP.open && paneHere());
    const show_ = $('#inspShow');
    if (show_) show_.hidden = INSP.open || !paneHere();
    reportChrome();
}

/** Room for the pane or not, said once each time the window crosses the
 *  line: beside the page when there is room, behind its button when not. */
window.addEventListener('resize', () => {
    const fits = inspFits();
    if (fits === INSP.fits || !$('#insp')) return;
    INSP.fits = fits;
    toggleInsp(fits);
});

/** Whether the pane stands beside the page, and so has a page's summary
 *  in it rather than the page itself. */
const inspBeside = () => INSP.open && inspFits() && !!$('#insp') && paneHere();

/** A row on Home: a click shows it in the pane, or, with the pane away,
 *  opens its page the way it always did. */
function pickOr(what, go) {
    return () => {
        // only a pane that is there to see can show what was picked; Home
        // has none, and the row goes to its page
        if (!inspBeside()) { if (go) go(); return; }
        INSP.pick = what;
        paintInsp();
    };
}
const pickKey = w => !w ? 'mac' : w.kind + ':' + (w.page != null ? w.page : w.id != null ? w.id : w.what || '');

/** The pane is Send's: the file on its way, and the box you send from.
 *  Home is a dashboard the width of the window, the way Efferd's are, and
 *  every other page has the room to itself too. */
const paneHere = () => K.page === SHARE();

/** What the pane shows on the page you are on. */
function inspSubject() {
    const job = INSP.pick && INSP.pick.kind === 'job' && SEND.jobs.has(INSP.pick.id) ? INSP.pick : null;
    if (K.page === SHARE()) return job || { kind: 'send' };
    return INSP.pick && (INSP.pick.kind !== 'job' || job) ? INSP.pick : { kind: 'mac' };
}

function paintInsp() {
    const body = $('#inspBody');
    if (!body || !K.meta || K.welcome || !paneHere()) return;
    const what = inspSubject();
    let got;
    try { got = inspContent(what); } catch (e) { got = { title: 'Details', kids: [iText('Kliner could not draw this.')] }; }
    const t = $('#inspTitle');
    if (t) t.textContent = got.title;
    const top = body.scrollTop;
    const kids = got.kids.filter(Boolean);
    body.replaceChildren(...kids);
    // something new in the pane arrives, one line after another; the same
    // thing drawn again — a file a little further along — just changes
    const fresh = body.dataset.key !== pickKey(what);
    if (!fresh) body.scrollTop = top;
    body.classList.toggle('fresh', fresh && !calm());
    kids.forEach((el, n) => el.style.setProperty('--k', String(Math.min(n, 8))));
    body.dataset.key = pickKey(what);
    const key = pickKey(INSP.pick && K.page === 0 ? INSP.pick : what);
    for (const el of document.querySelectorAll('[data-pick]')) el.classList.toggle('is-picked', INSP.open && el.dataset.pick === key);
}

function inspContent(w) {
    switch (w.kind) {
        case 'folder': return inspFolder(w.page);
        case 'clean': return inspClean(w.page != null ? w.page : homePages().clean);
        case 'job': return inspJob(SEND.jobs.get(w.id));
        case 'send': return inspSend();
        default: return inspMac();
    }
}

/* the pieces a pane is made of */
const iStat = (tone, sym, text, dot) => h('div', { class: 'td-st' + (tone ? ' ' + tone : '') },
    dot ? h('i', { class: 'td-dot ' + dot }) : sym ? icon(sym) : h('i', { class: 'spin' }), h('span', null, text));
const iName = text => h('div', { class: 'td-name', title: text }, text);
const iText = text => h('p', { class: 'itext' }, text);
function iRows(rows) {
    const got = rows.filter(Boolean);
    return got.length ? h('dl', { class: 'lv' }, got.map(([k, v]) => h('div', null, h('dt', null, k), h('dd', null, v)))) : null;
}
/** A heading that folds what is under it, the way his Problem and Approach
 *  do; folded stays folded while the window is open. */
function iFold(title, kids) {
    const d = h('details', { class: 'ifold' }, h('summary', null, title), h('div', { class: 'ifold-b' }, kids));
    d.open = !INSP.folded.has(title);
    d.addEventListener('toggle', () => { if (d.open) INSP.folded.delete(title); else INSP.folded.add(title); });
    return d;
}
const iItem = (sym, name, value) => h('div', { class: 'irow' }, icon(sym), h('span', { title: name }, name), h('b', null, value));
const iActs = (...btns) => { const got = btns.filter(Boolean); return got.length ? h('div', { class: 'iacts' }, got) : null; };
const iFill = (label, go, sym) => h('button', { class: 'btn fill', onclick: go }, sym ? icon(sym) : null, label);
const iLine = (label, go, sym) => h('button', { class: 'btn line', onclick: go }, sym ? icon(sym) : null, label);

/* ── this Mac ── */

const MACHINE = { info: null, asked: false };
function readMachine() {
    if (MACHINE.asked) return;
    MACHINE.asked = true;
    ask('machine').then(r => { if (r && !r.missing) { MACHINE.info = r; paintInsp(); } }, () => {});
}

function inspMac() {
    readMachine();
    const home = K.home || {};
    const f = facts((K.kept[0] && K.kept[0].pieces) || []);
    const m = MACHINE.info || {};
    const go = homePages();
    const low = home.total > 0 && home.free / home.total < 0.1;
    const os = String((f.System && f.System.value) || m.macos || '').replace(/^macOS\s*/i, '').replace(/\s*\(.*\)\s*$/, '');
    return { title: 'This Mac', kids: [
        home.total > 0 ? iStat(low ? 'bad' : 'good', low ? 'disk' : 'check', size(home.free) + ' free') : null,
        iName(m.model || 'This Mac'),
        iRows([
            m.chip ? ['Chip', m.chip] : null,
            f.Memory ? ['Memory', f.Memory.value] : m.memory ? ['Memory', m.memory] : null,
            os ? ['macOS', os] : null,
        ]),
        iActs(home.junk > 0 && go.clean > 0 ? iFill('Free up ' + size(home.junk), () => act(go.clean), 'sparkles') : null),
    ] };
}

/* ── a folder ── */

/** When Kliner last tidied a folder, from its own log: the newest line for it. */
function lastTidied(k) {
    const re = k === 'desktop' ? /^cleared your desktop/ : k === 'downloads' ? /^sorted your downloads/ : /^sorted your documents/;
    const it = (HOME_LOG.items || []).find(x => re.test(String((x.parts || [])[0] || '').trim().toLowerCase()));
    return it ? { when: (it.parts || [])[1] || '', many: (it.parts || [])[2] || '' } : null;
}

function inspFolder(page) {
    const k = kind(page), item = pages()[page] || {};
    const home = K.home || {};
    const loose = k === 'desktop' ? home.desk : k === 'downloads' ? home.downloads : null;
    const old = k === 'desktop' ? home.deskOld : k === 'downloads' ? home.downloadsOld : '';
    const got = K.listing && K.listing[page];
    if (!got || Date.now() - got.at > 20000) listing(page).then(() => paintInsp());
    if (HOME_LOG.items == null) readHomeLog();
    const items = got && !got.shut ? got.items.filter(countedByNimo) : null;
    const n = loose != null ? loose : items ? items.length : null;
    const tone = { desktop: 'c1', downloads: 'c2', documents: 'c3' }[k] || 'c1';
    const last = lastTidied(k);
    const kids = [n == null ? iStat('', null, 'Reading…') : n === 0 ? iStat('good', 'check', 'Nothing loose') : iStat('', null, whole(n) + ' loose', tone),
        iName(item.title || titleOf(page)),
        iRows([
            n != null ? ['Items', whole(n)] : null,
            old ? ['Old', old.replace(/ over 30 days$/, '')] : null,
            last ? ['Last tidied', shortWhen(last.when)] : null,
        ])];
    if (items && items.length) {
        kids.push(iFold('Newest', items.slice().sort((a_, b_) => (b_.modified || 0) - (a_.modified || 0)).slice(0, 4)
            .map(f => iItem(f.dir ? 'folder' : KIND_PICTURE[kindOf(f)] || 'file', f.name, ago(f.modified)))));
    }
    kids.push(iActs(n > 0 && item.verb ? iFill('Tidy', () => act(page), item.does) : null, iLine('Open', () => show(page))));
    return { title: item.title || titleOf(page), kids };
}

/* ── what can go ── */

function inspClean(page) {
    const home = K.home || {};
    const kept = K.kept[page];
    const pieces = (kept && kept.pieces) || [];
    const own = kept ? safeTotal(pieces) : null;
    const junk = own != null ? own : home.junk;
    const safe = sections(pieces)[0];
    const rows = [];
    if (safe) for (const p of safe.pieces) { if (p.k === 'rule') break; if (p.k === 'row' && p.label && p.value) rows.push([p.label, p.value]); }
    const item = pages()[page] || {};
    return { title: 'Free up space', kids: [
        junk > 0 ? iStat('good', 'sparkles', size(junk) + ' can go') : junk === 0 ? iStat('good', 'check', 'Nothing to free') : iStat('', null, 'Measuring…'),
        iName('Caches and the Trash'),
        iRows(rows.slice(0, 3)),
        iActs(junk > 0 && item.verb ? iFill('Clean up', () => act(page), item.does) : null, iLine('Open', () => show(page))),
    ] };
}

/* ── sending ── */

function inspJob(job) {
    if (!job) return inspSend();
    const acts = [];
    if (job.dir === 'in' && job.state === 'asking') acts.push(iFill('Answer', () => { if (!SEND.queue.includes(job.id)) SEND.queue.unshift(job.id); if (!$('.ksheet')) nextIncoming(); }));
    if (ACTIVE.includes(job.state)) acts.push(iLine('Stop', () => tell('sendCancel', { job: job.id })));
    if (job.state === 'done' && job.dir === 'in' && job.path) acts.push(iLine('Show in Finder', () => tell('showReceived', { path: job.path }), 'finder'));
    return { title: job.dir === 'out' ? 'Sending' : 'Coming to you', kids: [...jobDetail(job), iActs(...acts)] };
}

/** On the Send page, with nothing picked: you, the way people find you,
 *  and how a file travels. */
function inspSend() {
    const me = bareName(handle());
    const where = nameWhere();
    const receive = K.meta.config.receive !== 'off';
    const near = SEND.people.filter(u => u !== me).length;
    const sw = h('button', { class: 'switch' + (receive && me ? ' on' : ''), disabled: !me, 'aria-label': 'Macs nearby can send you files',
                             onclick: async e => {
                                 const b = e.currentTarget;
                                 const r = await ask('receiving', { on: !b.classList.contains('on') });
                                 K.meta.config.receive = r && r.on ? 'on' : 'off';
                                 b.classList.toggle('on', !!(r && r.on));
                             } });
    return { title: 'You', kids: [
        near ? iStat('good', null, plural(near, 'Mac') + ' nearby', 'near') : iStat('', 'wifi', 'No one nearby'),
        iName(me ? '@' + me : 'No username yet'),
        iRows([
            ['Where', h('span', { class: 'ad-where' + (where === 'cloud' ? ' ok' : '') }, h('i', { class: 'dot' }),
                where === 'cloud' ? 'kliner.app' : where === 'here' ? 'This Mac' : 'Nowhere yet')],
            ['Nearby can send to you', sw],
        ]),
        me ? null : iActs(iFill('Pick a username', () => openSettings('profile'), 'at')),
    ] };
}

/* ── the wallpaper's colour, on the page ──────────────────────────────────
   His page is dark glass, so the wallpaper behind it shows faintly through:
   warm at the top left, cool at the far right. Kliner's page is opaque —
   glass all over went brown on a warm photograph — so it takes the colour
   instead: the wallpaper on the screen, read small, its corners laid on the
   page as two faint glows (`--glow-1`, `--glow-2`). On a black wallpaper
   there is nothing to take, and the page is simply dark. */

const GLOW = { at: 0, reading: false, pic: null };
async function readGlow(force) {
    if (GLOW.reading || (!force && GLOW.at && Date.now() - GLOW.at < 300000)) return;
    GLOW.reading = true;
    try {
        const r = await ask('wallBig', {});
        if (r && goodPicture(r.picture)) { GLOW.pic = r.picture; await glowFrom(r.picture); }
        GLOW.at = Date.now();
    } catch (e) { /* the page stays its own colour */ } finally { GLOW.reading = false; }
}
function glowFrom(uri) {
    return new Promise(done => {
        const img = new Image();
        img.onload = () => {
            try {
                const W = 16, H = 10;
                const c = document.createElement('canvas');
                c.width = W; c.height = H;
                const g = c.getContext('2d');
                g.drawImage(img, 0, 0, W, H);
                const px = g.getImageData(0, 0, W, H).data;
                const avg = (x0, y0, x1, y1) => {
                    const t = [0, 0, 0]; let n = 0;
                    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const i = (y * W + x) * 4; t[0] += px[i]; t[1] += px[i + 1]; t[2] += px[i + 2]; n++; }
                    return 'rgb(' + t.map(v => Math.round(v / n)).join(', ') + ')';
                };
                const root = document.documentElement.style;
                root.setProperty('--glow-1', avg(0, 0, 7, 5));
                root.setProperty('--glow-2', avg(9, 4, 16, 10));
            } catch (e) { /* a picture it cannot read leaves the glows as they were */ }
            done();
        };
        img.onerror = () => done();
        img.src = uri;
    });
}

/* ── the views under a page's title ── */

const VIEWS = {};   // page → the view picked on it, for as long as the window is open
const viewOf = (i, first) => VIEWS[i] || first;

/** Tabs under a page's title, the way the picture has them: a picture and a
 *  word each, the one you are on underlined. */
function viewTabs(i, views, on) {
    const bar = h('div', { class: 'vtabs', role: 'tablist' });
    for (const [key, label, sym] of views) {
        bar.append(h('button', { class: 'vtab' + (key === on ? ' on' : ''), role: 'tab', 'aria-selected': String(key === on),
                                 onclick: () => { if (viewOf(i, views[0][0]) === key) return; VIEWS[i] = key; drawPage(true); } },
            icon(sym), h('span', null, label)));
    }
    return bar;
}

/** A fact about a page as a chip under its title: a picture, what it is,
 *  and its value. One you can press takes you to where it is from. */
function pchip(sym, label, value, go) {
    return h(go ? 'button' : 'span', { class: 'pchip' + (go ? ' go' : ''), onclick: go || null },
        icon(sym), h('span', { class: 'pc-l' }, label + ':'), h('b', null, value));
}

/* ── the board ── */

/** One card on a board: what it is, a line of small facts, and on the right
 *  the button that does it, the key, or a picture. */
function bcard(o) {
    const card = h('div', { class: 'bcard' + (o.go ? ' go' : '') + (o.cls ? ' ' + o.cls : ''), role: o.go ? 'button' : null,
                            tabindex: o.go ? '0' : null, title: o.tip || null, 'data-name': o.name || null },
        o.pic ? h('div', { class: 'bc-top' }, o.pic, h('div', { class: 'bc-t' }, o.title)) : h('div', { class: 'bc-t' }, o.title),
        h('div', { class: 'bc-m' },
            ...(o.meta || []).filter(Boolean).map(([sym, text, cls]) => h('span', { class: 'bc-k' + (cls ? ' ' + cls : '') }, sym ? icon(sym) : null, text)),
            h('span', { class: 'bc-gap' }),
            o.act ? h('button', { class: 'btn line small bc-do', onclick: e => { e.stopPropagation(); o.act[1](e.currentTarget); } }, o.act[0])
                  : o.key ? h('kbd', { class: 'bc-key' }, o.key) : null));
    if (o.go) {
        card.addEventListener('click', () => o.go());
        card.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target === card) { e.preventDefault(); (o.act ? o.act[1] : o.go)(); } });
    }
    return card;
}

/** A column of cards with its name, its mark and how many are in it. */
function bcol(cls, title, mark, cards, empty, id, count) {
    return h('section', { class: 'bcol ' + cls },
        h('div', { class: 'bcol-h' }, h('span', { class: 'bcol-ic' }, mark), h('b', null, title),
            h('span', { class: 'bcol-n' }, String(count != null ? count : cards.length))),
        h('div', { class: 'bcol-b', id: id || null }, cards.length ? cards : h('div', { class: 'bcol-none' }, empty || 'Nothing here.')));
}

/** What Kliner has done lately, from the log it keeps of every move: read
 *  for Home's card, which is drawn before it comes. */
const HOME_LOG = { at: 0, items: null, reading: false };

/** The undo log, read at most every half minute; whatever shows it is
 *  painted again when it comes. */
function readHomeLog() {
    const undoPage = pages().findIndex(p => p.kind === 'undo');
    if (undoPage <= 0 || HOME_LOG.reading || Date.now() - HOME_LOG.at <= 30000) return;
    HOME_LOG.reading = true;
    ask('look', { page: undoPage }).then(r => {
        HOME_LOG.reading = false;
        HOME_LOG.at = Date.now();
        HOME_LOG.items = r && r.text ? parse(r.text).filter(p => p.k === 'item').slice(0, 40) : [];
        const done = $('#homeDone');
        if (done) paintHomeDone(done);
        // what Kliner tidied away is said over the folders' bars too
        paintLanded(null, false);
    }, () => { HOME_LOG.reading = false; });
}

/** A run of one small thing done over and over — the desktop's icons hidden
 *  and shown, again and again — as one entry with how many times, newest
 *  first, rather than a list of nothing else. */
function foldRuns(list, small) {
    const out = [];
    for (const x of list) {
        const last = out[out.length - 1];
        if (last && small(x) && small(last.first)) { last.all.push(x); continue; }
        out.push({ first: x, all: [x] });
    }
    return out;
}

/* ── your Mac, small ─────────────────────────────────────────────────────
   Your Mac as it is, drawn from it — the wallpaper on your
   screen (wallBig), the desktop with Finder's own icons (list and thumbs),
   the Dock with each app's own icon (dockApps) — and under it every
   wallpaper, one click each. Nothing in it is an example. The card is drawn
   at once; the pictures are read after and laid in where they belong. */

const MINI_DESK = 8;

/** What the small Mac is drawn from: read once, and again when it is a
 *  minute old or when something on Home has just changed it. */
async function readMini(force) {
    if (MINI.reading) return;
    if (!force && MINI.at && Date.now() - MINI.at < 60000) return;
    MINI.reading = true;
    MINI.at = Date.now();
    const deskPage = pages().findIndex(p => p.kind === 'desktop');
    try {
        await Promise.all([
            ask('wallBig', {}).then(r => {
                if (r && goodPicture(r.picture)) { MINI.wallPic = r.picture; paintMini(); }
            }),
            (async () => {
                if (!(deskPage > 0)) { MINI.desk = []; return; }
                if (K.listing) delete K.listing[deskPage];
                const items = await listing(deskPage);
                const got = K.listing && K.listing[deskPage];
                MINI.desk = got && got.shut ? [] : items.filter(countedByNimo).concat(items.filter(f => f.dir && f.name === tidyName()))
                    .sort((a, b) => (b.modified || 0) - (a.modified || 0));
                paintMini(true);
                const want = MINI.desk.slice(0, MINI_DESK).map(f => f.name).filter(n => !(n in MINI.deskPics));
                if (!want.length) return;
                const reply = await ask('thumbs', { page: deskPage, names: want, icons: true });
                for (const [name, uri] of Object.entries((reply && reply.thumbs) || {})) {
                    if (goodPicture(uri)) MINI.deskPics[name] = uri;
                }
                paintMini();
            })(),
            readMiniDock().then(() => paintMini(true)),
        ]);
    } finally {
        MINI.reading = false;
    }
}

/** The pictures that arrived after the card was drawn, laid in. With
 *  `lists`, the desktop and the Dock are drawn again from what was read. */
function paintMini(lists) {
    const mac = $('#mxMac');
    if (!mac) return;
    const wall = mac.querySelector('.mac-wall');
    if (wall && MINI.wallPic) wallPicture(wall, MINI.wallPic);
    if (lists) {
        const desk = mac.querySelector('.mac-desk');
        if (desk) desk.replaceWith(miniDesk(true));
        const dock = mac.querySelector('.mac-dock');
        if (dock) dock.replaceWith(miniDock());
    }
    for (const el of mac.querySelectorAll('.mac-desk .di[data-name]:not(.got)')) {
        const uri = MINI.deskPics[el.dataset.name];
        if (uri) deskPicture(el, uri);
    }
}

/* Inside the small Mac an em is a hundredth of its width, so all of it grows
   and shrinks with the card. The room is measured, never the screen: a
   screen sized from itself fed its own growth back into it once. */
const miniFit = typeof ResizeObserver === 'function'
    ? new ResizeObserver(list => {
        for (const e of list) {
            const w = e.contentRect.width;
            const mac = e.target.querySelector('.mac');
            if (mac && w > 0) mac.style.fontSize = (w / 100).toFixed(3) + 'px';
        }
    }) : null;

function miniMac() {
    const wall = h('div', { class: 'mac-wall' });
    if (MINI.wallPic) wallPicture(wall, MINI.wallPic);
    return h('div', { class: 'mac mx-mac', id: 'mxMac' },
        wall,
        h('div', { class: 'mac-bar' }, h('span', { class: 'menus' }, h('i'), h('i'), h('i'), h('i'), h('i')),
          h('span', { class: 'gap' }), h('span', { class: 'kl' }, eyesMark()),
          h('span', { class: 'clock' }, miniClock())),
        miniDesk(false), miniDock());
}

function miniClock() {
    const now = new Date();
    return now.toLocaleDateString('en-US', { weekday: 'short' }) + ' '
        + now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

/** The desktop on the small screen: what is on yours, newest first, with
 *  Finder's own icon for each. Faded out, not taken away, while \ has the
 *  icons hidden, so \ again brings them back in front of you. */
function miniDesk(pop) {
    const layer = h('div', { class: 'mac-desk' + (K.meta && K.meta.desktopHidden ? ' fade' : '') });
    const items = MINI.desk || [];
    const shown = items.length > MINI_DESK ? items.slice(0, MINI_DESK - 1) : items;
    const moving = pop && DRAW.moving !== false && !calm();
    shown.forEach((f, n) => {
        const el = h('div', { class: 'di' + (moving ? ' st-pop' : ''), 'data-name': f.name, title: f.name,
                              style: moving ? `animation-delay:${80 + n * 40}ms` : null },
            h('span', { class: 'dp' }, f.dir && f.name === tidyName() ? folderArt('') : fileArt(f)), h('span', { class: 'dn' }, f.name));
        const uri = MINI.deskPics[f.name];
        if (uri) deskPicture(el, uri);
        layer.append(el);
    });
    if (shown.length < items.length) {
        layer.append(h('div', { class: 'di more' }, h('span', { class: 'dp' }, h('b', null, '+' + (items.length - shown.length))),
            h('span', { class: 'dn' }, 'more')));
    }
    return layer;
}

/** The Dock along the bottom of the small screen, the way every Dock is:
 *  Finder, your apps, a line, the Trash. */
function miniDock() {
    const d = MINI.dock;
    const dock = h('div', { class: 'mac-dock' });
    if (!d) return dock;
    const all = (d.finder ? 1 : 0) + d.apps.length + (d.trash ? 1 : 0);
    dock.style.setProperty('--ds', Math.min(4.2, 82 / Math.max(1, all)).toFixed(2) + 'em');
    const tile = a => h('span', { class: 'dt', title: a.name }, appArt(a));
    if (d.finder) dock.append(tile({ name: 'Finder', icon: d.finder }));
    d.apps.forEach(a => dock.append(tile(a)));
    if (d.trash) dock.append(h('span', { class: 'dsep' }), tile({ name: 'Trash', icon: d.trash }));
    return dock;
}

/** A wallpaper picked on Home: on the small screen straight away, from the
 *  picture already drawn, then on yours. Should the Mac not take it, the
 *  small screen goes back to the one you still have. */
async function homeWall(no) {
    const one_ = (K.walls || []).find(p => p.no === no);
    const pic = K.wallPics && K.wallPics[String(no)];
    const wall = $('#mxMac .mac-wall');
    const before = MINI.wallPic;
    if (wall && goodPicture(pic) && !K.preview) wallPicture(wall, pic);
    await putOnWall(no);
    if (!one_ || K.wallOn !== one_.parts[0]) {
        if (wall && before) wallPicture(wall, before);
        return;
    }
    const name = $('#ycWall');
    if (name) name.textContent = one_.parts[0];
    const r = await ask('wallBig', { at: no });
    if (r && goodPicture(r.picture)) { MINI.wallPic = r.picture; paintMini(); }
}

/* ── your Dock's apps, with their own icons ─────────────────────────────

   The Dock's page draws each app with the icon Finder draws for it. They are
   read once, laid in where the names are, and read again after an app is
   taken out, so the page never shows one still there. */

const MINI = { dock: null, wallPic: '', desk: null, deskPics: {}, at: 0, reading: false };

async function readMiniDock() {
    const r = await ask('dockApps', {});
    const apps = r && Array.isArray(r.apps)
        ? r.apps.filter(a => a && typeof a.name === 'string' && a.name)
                .map(a => ({ name: a.name, icon: goodPicture(a.icon) ? a.icon : '' }))
        : [];
    MINI.dock = { apps, finder: goodPicture(r && r.finder) ? r.finder : '',
                  trash: goodPicture(r && r.trash) ? r.trash : '' };
    const page = $('#page .stops');
    if (page) fillDockIcons(page);
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

/** The icons on your desktop go, or come back. No question: nothing moves,
 *  and the same key or switch puts them back. (`quick` false still asks.) */
async function hideIcons(hide, quiet, quick = true) {
    if (K.preview) {
        toast('Preview: this would ' + (hide ? 'hide' : 'show') + ' the icons on your desktop.', null, 'eye');
        return false;
    }
    const reply = await ask('zen', { back: !hide, quick: !!quick });
    if (!reply || reply.cancelled || reply.missing) return false;
    if (reply.ok) {
        // what the Mac's side says it did, when it says — it read the screen
        K.meta.desktopHidden = typeof reply.hidden === 'boolean' ? reply.hidden : hide;
        // the starter says it in its own title, over the picture of it
        if (!quiet) toast(hide ? 'Desktop icons hidden. Press \\ to bring them back.' : 'Your desktop icons are back', null);
        return true;
    }
    const why = parse(reply.text || '').find(p => p.k === 'warn');
    toast(why ? why.text : 'Your Mac did not take that', null, 'x');
    return false;
}

/** \ : the files on your desktop, the other way from how they are. No
 *  question — they do not move, and \ again puts them back — and no button:
 *  a small sign in the middle of the window says what happened.
 *
 *  Which way round it goes is decided on the Mac's side, from what is on
 *  screen rather than from what this page last remembered, and comes straight
 *  back. So the sign says what happened, not what was asked for, and a key
 *  pressed twice in a second cannot get the two out of step. */
let iconsTurning = false;
async function quickIcons() {
    if (iconsTurning || !K.meta) return;
    if (K.preview) {
        hud('eye', 'Preview: \\ hides the files on your desktop', '');
        return;
    }
    iconsTurning = true;
    try {
        const reply = await ask('zen', { quick: true, toggle: true });
        if (!reply || !reply.ok) { hud('x', 'Your Mac did not take that', ''); return; }
        const hide = !!reply.hidden;
        K.meta.desktopHidden = hide;
        hud(hide ? 'eyeoff' : 'eye', hide ? 'Desktop files hidden' : 'Desktop files back', hide ? 'shows them again' : 'hides them');
        // in what this session did, like everything else Kliner does — the
        // sign in the middle of the window is gone a second later
        K.jobs.unshift({ page: 0, title: 'Desktop', line: hide ? 'Icons hidden. Press \\ to bring them back.' : 'Icons back on your desktop.',
                         good: true, at: new Date() });
        K.jobs = K.jobs.slice(0, 30);
        if (kind(K.page) === 'desktop' || K.page === SETTINGS() || K.page === 0) drawPage(true, true);
        const sd = $('#sdIcons');
        if (sd) {
            const now = !!(K.meta && K.meta.desktopHidden);
            sd.querySelector('.sd-t').textContent = now ? 'Show desktop files' : 'Hide desktop files';
            sd.querySelector('.sd-ic').replaceChildren(icon(now ? 'eye' : 'eyeoff'));
        }
        const chip = $('#iconsChip span');
        if (chip) chip.textContent = hide ? 'Show desktop files' : 'Hide desktop files';
        const desk = $('#mxMac .mac-desk');
        if (desk) desk.classList.toggle('fade', hide);
        const row = $('#hsIcons');
        if (row) {
            row.querySelector('.hs-t').textContent = hide ? 'Show desktop files' : 'Hide desktop files';
            row.querySelector('.hs-s').textContent = hide ? 'Hidden. Every file is still where it was.' : 'The icons go; every file stays where it is.';
            row.querySelector('.hs-ic').replaceChildren(icon(hide ? 'eye' : 'eyeoff'));
        }
    } finally {
        iconsTurning = false;
    }
}

/** A sign in the middle of the window for a moment, like the Mac's own for
 *  volume: what just happened, and the key that does it. */
let hudTimer = 0;
function hud(sym, text, keyNote) {
    let el = $('#hud');
    if (!el) { el = h('div', { class: 'hud', id: 'hud', role: 'status' }); document.body.append(el); }
    el.replaceChildren(...[icon(sym), h('b', null, text), keyNote ? h('span', null, h('kbd', null, '\\'), keyNote) : null].filter(Boolean));
    el.classList.remove('show');
    void el.offsetWidth;
    el.classList.add('show');
    clearTimeout(hudTimer);
    hudTimer = setTimeout(() => el.classList.remove('show'), 1500);
}

/** The other way from how it is now, and the pages that show it drawn again. */
async function toggleIcons() {
    const hide = !(K.meta && K.meta.desktopHidden);
    if (!(await hideIcons(hide))) return;
    if (K.welcome) { drawWelcome(); return; }
    if (kind(K.page) === 'desktop' || K.page === SETTINGS() || K.page === 0) drawPage(true);
}

/** Said on the Desktop page while the icons are hidden, with the way back. */
function hiddenNote() {
    return h('div', { class: 'shut hidden-note' }, icon('eyeoff'),
        h('div', { class: 'say' }, h('b', null, 'Your desktop icons are hidden.'),
          h('span', null, 'The files are all still in your Desktop folder. Finder just is not drawing them.')),
        h('button', { class: 'btn fill', onclick: toggleIcons }, icon('eye'), 'Show them'));
}

/** Clean my Mac: the three folders Kliner sorts and the caches it clears,
 *  in one run, with one question in front of it. */
function cleanSweep() {
    const want = ['desktop', 'downloads', 'documents', 'clean'];
    return want.map(k => pages().findIndex(p => p.kind === k)).filter(n => n > 0);
}

/* ── what is in a folder, by type: the bar, the list, three figures ───── */

function typesCard(i, title_, old) {
    const body = h('div', { class: 'types' }, h('div', { class: 'sk-body' }, h('div', { class: 'sk-row' }, sk('44px', 30), sk('42px', 10)), sk('100%', 12),
        h('div', { class: 'sk-row' }, sk('74px', 10), sk('62px', 10), sk('80px', 10))));
    const box = panel('go', cap(i > 0 ? pages()[i].symbol : 'grid', title_, old ? h('span', { class: 'pill' }, old) : h('span', null, 'by type')), body);
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
                    // nothing loose, but not empty when it holds what Kliner sorted
                    items.some(f => f.dir && f.name === tidyName())
                        ? h('div', null, h('b', null, 'All sorted.'),
                            h('span', null, 'Nothing loose. What was here is in ' + pages()[i].reveal + '/' + tidyName() + '.'))
                        : h('div', null, h('b', null, 'Nothing in it.'), h('span', null, 'This folder is empty.'))));
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
        if (body.closest('.arrive') && !body.closest('.hush')) runCounts(body);
    });
    return box;
}

function fig(value, label) {
    const [n, unit] = figure(value);
    return h('div', { class: 'f' }, h('div', { class: 'v' }, counted(n), unit ? h('small', null, unit) : null),
             h('div', { class: 'l' }, label));
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
    const deskPage = pages().findIndex(p => p.kind === 'desktop');
    const strip = deskPage > 0 ? h('div', { class: 'newest' }) : null;
    if (strip) fillNewest(strip, deskPage);
    return panel('', cap('clock', 'Added to your desktop', move || '12 months'),
        h('div', { class: 'pair' },
            h('div', null, h('div', { class: 'n' }, whole(all)), h('div', { class: 'c' }, 'items in the last 12 months')),
            h('div', null, h('div', { class: 'n' }, busiest), h('div', { class: 'c' }, 'busiest month'))),
        h('div', { class: 'heat' }, row, ax, scale),
        strip ? h('div', { class: 'nwcap' }, 'Newest') : null, strip);
}

/* ── search, inside the window ───────────────────────────────────────────
   ⌘K outside the window is the small panel over whatever you are doing.
   Inside, the window has its own: what the Mac is doing, drawn live across
   the top, then the pages, the things Kliner can do and the files on your
   desk, found as you type. Nothing in it changes anything without the same
   question the page itself would ask. */

/** Letters in order, anywhere in the word: "dsk" finds Desktop. */
function loosely(text, want) {
    let at = 0;
    for (const letter of want) {
        at = text.indexOf(letter, at);
        if (at < 0) return false;
        at += 1;
    }
    return true;
}

/** How well a row answers what was typed. Nought means it does not. */
function scoreRow(row, want) {
    const title_ = row.name.toLowerCase();
    if (title_ === want) return 1000;
    if (title_.startsWith(want)) return 900 - title_.length;
    if (title_.split(/[\s._-]+/).some(w => w.startsWith(want))) return 800 - title_.length;
    if (title_.includes(want)) return 700 - title_.length;
    if (want.length > 1 && loosely(title_, want)) return 500 - title_.length;
    if ((row.hint || '').toLowerCase().includes(want)) return 300;
    if ((row.also || '').toLowerCase().includes(want)) return 250;
    return 0;
}

/** The pages, each with its own reading beside it and the key that opens it. */
function findPages() {
    const home = K.home || {};
    const out = pages().map((p, n) => {
        let fig = '';
        if (p.kind === 'desktop' && home.desk != null) fig = plural(home.desk, 'item');
        if (p.kind === 'downloads' && home.downloads != null) fig = plural(home.downloads, 'item');
        if (p.kind === 'clean' && home.junk != null) fig = home.junk > 0 ? size(home.junk) : 'nothing to free';
        if (p.kind === 'top' && home.total > 0) fig = percent(home.used, home.total) + ' used';
        if (n === 0 && home.total > 0) fig = size(home.free) + ' free';
        return { sec: 'Pages', name: p.title, hint: p.blurb || '', icon: p.symbol || 'dot', page: n, fig,
                 keys: n < 9 ? ['⌘', String(n + 1)] : null, verb: 'Open' };
    });
    out.push({ sec: 'Pages', name: 'Activity', hint: 'What is using this Mac right now.', also: 'cpu memory processes apps',
               icon: 'pulse', page: ACTIVITY(), verb: 'Open' });
    out.push({ sec: 'Pages', name: 'Settings', hint: 'Preferences and permissions.', also: 'name email picture login permissions',
               icon: 'gear', page: SETTINGS(), keys: ['⌘', ','], verb: 'Open' });
    out.push({ sec: 'Pages', name: 'Help', hint: 'Keyboard shortcuts.', also: 'keys shortcuts', icon: 'help', page: HELP(), verb: 'Open' });
    out.push({ sec: 'Pages', name: 'Send', hint: 'Files on their way, and a new one to any @username.',
               also: 'send share transfer username airdrop drop received', icon: 'send', page: SHARE(), verb: 'Open' });
    return out;
}

/** What Kliner can do from here. Each one goes through the same question
 *  its own page asks; the ones that only show something just show it. */
function findActions() {
    const home = K.home || {};
    const out = [];
    const sweep = cleanSweep();
    const deskPage = pages().findIndex(p => p.kind === 'desktop');
    const dlPage = pages().findIndex(p => p.kind === 'downloads');
    const wallPage = pages().findIndex(p => p.kind === 'next');
    if (sweep.length) {
        const bits = [];
        const things = (home.desk || 0) + (home.downloads || 0);
        if (things) bits.push(plural(things, 'item'));
        if (home.junk > 0) bits.push(size(home.junk));
        out.push({ sec: 'Suggested', name: 'Clean my Mac', hint: 'Desktop, Downloads, Documents and caches.',
                   also: 'clean tidy sweep', icon: 'sparkles', fig: bits.join(' · '), go: () => tidyBoth(sweep), verb: 'Clean', lead: true });
    }
    if (deskPage > 0 && home.desk > 0) {
        out.push({ sec: 'Suggested', name: 'Tidy desktop', hint: 'Into Desktop/Tidy, by type.', icon: 'desk',
                   fig: plural(home.desk, 'item'), go: () => act(deskPage), verb: 'Tidy' });
    }
    if (dlPage > 0 && home.downloads > 0) {
        out.push({ sec: 'Suggested', name: 'Tidy downloads', hint: 'Into Downloads/Tidy, by type.', icon: 'download',
                   fig: plural(home.downloads, 'item'), go: () => act(dlPage), verb: 'Tidy' });
    }
    const hidden = !!(K.meta && K.meta.desktopHidden);
    out.push({ sec: 'Actions', name: hidden ? 'Show desktop icons' : 'Hide desktop icons',
               hint: hidden ? 'Finder draws your desktop again.' : 'A bare desktop. The files stay where they are.',
               also: 'desktop icons zen bare', icon: hidden ? 'eye' : 'eyeoff', go: toggleIcons, verb: hidden ? 'Show' : 'Hide' });
    if (wallPage > 0) {
        out.push({ sec: 'Actions', name: 'Next wallpaper', hint: 'The next one in your list, straight onto the screen.',
                   also: 'wallpaper background picture', icon: 'photo', go: () => act(wallPage), verb: 'Next' });
    }
    out.push({ sec: 'Actions', name: 'Send a file', hint: 'To any @username, near or far. Nothing is compressed.',
               also: 'send share transfer username airdrop', icon: 'send', go: () => openSend(), verb: 'Send' });
    out.push({ sec: 'Actions', name: K.preview ? 'Turn Preview off' : 'Turn Preview on',
               hint: K.preview ? 'Buttons change things again, after asking.' : 'Buttons only show what would happen.',
               also: 'preview dry run look', icon: 'eye', go: flipPreview, verb: K.preview ? 'Turn off' : 'Turn on' });
    out.push({ sec: 'Actions', name: K.wide ? 'Fold the sidebar' : 'Open the sidebar',
               also: 'sidebar rail fold labels', icon: 'sidebar', go: fold, keys: ['⌘', 'B'], verb: K.wide ? 'Hide' : 'Show' });
    out.push({ sec: 'Actions', name: 'Close all apps', hint: 'Asks every open app to quit, the way ⌘Q does.',
               also: 'quit apps', icon: 'x', go: closeApps, verb: 'Ask' });
    out.push({ sec: 'Actions', name: 'Open Activity Monitor', hint: 'Apple’s own, for anything more.',
               also: 'activity monitor processes', icon: 'gauge', go: () => tell('monitor'), verb: 'Open' });
    return out;
}

/** Files on your desktop and in Downloads whose names match, newest first
 *  among equals. Shown in Finder, never opened. */
function findFiles(want) {
    if (want.length < 2) return [];
    const out = [];
    for (const kind_ of ['desktop', 'downloads']) {
        const n = pages().findIndex(p => p.kind === kind_);
        const got = n > 0 && K.listing && K.listing[n];
        if (!got) continue;
        const folder = pages()[n].reveal;
        for (const f of got.items) {
            if (!countedByNimo(f)) continue;
            const row = { sec: 'Files', name: f.name, where: folder, icon: f.dir ? 'folder' : KIND_PICTURE[kindOf(f)] || 'file',
                          fig: f.dir ? 'folder' : f.size ? size(f.size) : '', file: [folder, f.name], verb: 'Show in Finder' };
            const mark = scoreRow(row, want);
            if (mark > 0) out.push([row, mark - (Date.now() - (f.modified || 0)) / 864e8]);
        }
    }
    return out.sort((a, b) => b[1] - a[1]).slice(0, 8).map(x => x[0]);
}

const FIND_SCOPES = [['all', 'All'], ['pages', 'Pages'], ['actions', 'Actions'], ['files', 'Files']];

/* Rows of one section together, the sections in the order of their best row. */
function grouped(rows) {
    const order = [];
    for (const r of rows) if (!order.includes(r.sec)) order.push(r.sec);
    return order.flatMap(sec => rows.filter(r => r.sec === sec));
}

/** The rows ⌘K shows for what was typed: everything while nothing is; once
 *  something is, the best matches in their sections, then files on your desk. */
function findRows(want, scope) {
    scope = scope || 'all';
    const all = findActions().concat(findPages());
    const fits = r => scope === 'all' || (scope === 'pages' ? r.sec === 'Pages' : scope === 'actions' ? r.sec !== 'Pages' : false);
    if (!want) return all.filter(fits);
    const hits = all.filter(fits).map(r => [r, scoreRow(r, want)]).filter(x => x[1] > 0).sort((a, b) => b[1] - a[1])
        .slice(0, 12).map(x => Object.assign({}, x[0], { sec: x[0].sec === 'Suggested' ? 'Actions' : x[0].sec }));
    const files = scope === 'all' || scope === 'files' ? findFiles(want) : [];
    return grouped(hits).concat(files);
}

function openFind() {
    if ($('.finder')) { closeFind(); return; }
    if (!K.meta || K.welcome) return;
    closeActivity();
    hideTip();
    let scope = 'all', at = 0, shown = [], lastX = -1, lastY = -1;

    const field = h('input', { class: 'fq', placeholder: 'Search pages, actions and files', spellcheck: 'false',
                               autocapitalize: 'off', autocomplete: 'off', 'aria-label': 'Search Kliner' });
    const token = h('span', { class: 'ftoken', hidden: true });
    const scopes = h('div', { class: 'fscopes' });
    const list = h('div', { class: 'flist glides fresh', role: 'listbox' });
    // one light under the row you are on, sliding from row to row as the
    // arrows or the pointer move it, the way the sidebar's does
    const glide = h('i', { class: 'fglide', 'aria-hidden': 'true' });
    setTimeout(() => list.classList.remove('fresh'), 700);
    const strip = pulseStrip();
    const card = h('div', { class: 'fcard', role: 'dialog', 'aria-label': 'Search Kliner' },
        h('div', { class: 'ftop' }, icon('search'), token, field, h('kbd', { class: 'fesc' }, 'esc')),
        scopes, strip, list,
        h('div', { class: 'ffoot' },
            h('span', null, h('kbd', null, '↑'), h('kbd', null, '↓'), 'Move'),
            h('span', null, h('kbd', null, '↵'), 'Open'),
            h('span', null, h('kbd', null, 'tab'), 'Narrow'),
            h('span', { class: 'r' }, h('kbd', null, '⌘K'), 'Close')));
    const box = h('div', { class: 'finder' }, card);
    box._back = document.activeElement;

    const rowsFor = want => findRows(want, scope);

    function rowEl(r, n) {
        return h('button', { class: 'frow' + (r.lead ? ' lead' : ''), role: 'option', tabindex: '-1', style: `--r:${Math.min(n, 12)}`,
            onmousemove: e => {
                // Only a pointer that really moved picks a row. A list that
                // scrolls under a resting pointer would otherwise take the
                // light back from the arrow keys.
                if (e.clientX === lastX && e.clientY === lastY) return;
                lastX = e.clientX; lastY = e.clientY;
                if (at !== n) { at = n; mark(false); }
            },
            onclick: () => run(n) },
            h('span', { class: 'ft' }, icon(r.icon)),
            h('span', { class: 'fx' }, h('span', { class: 'fn' }, r.name),
              r.where ? h('span', { class: 'fw' }, r.where) : r.hint ? h('span', { class: 'fh' }, r.hint) : null),
            h('span', { class: 'fr' },
                r.fig ? h('span', { class: 'ff' }, r.fig) : null,
                r.keys ? h('span', { class: 'fkeys' }, r.keys.map(k => h('kbd', null, k))) : null,
                h('span', { class: 'fgo' }, r.verb || 'Open', h('kbd', null, '↵'))));
    }

    function emptyEl(want) {
        if (scope === 'files' && want.length < 2) {
            return h('div', { class: 'fnone' }, icon('file'), h('b', null, 'Type to find a file'),
                     h('span', null, 'On your desktop and in Downloads, by name.'));
        }
        return h('div', { class: 'fnone' }, icon('search'), h('b', null, 'Nothing found'),
            h('span', null, '“' + field.value.trim() + '” is not the name of a page, an action or a file on your desk.'),
            h('button', { class: 'btn line small', onmousedown: e => e.preventDefault(),
                          onclick: () => { field.value = ''; scope = 'all'; at = 0; paint(); field.focus(); } }, 'Clear search'));
    }

    function paint() {
        const want = field.value.trim().toLowerCase();
        shown = rowsFor(want);
        if (at >= shown.length) at = Math.max(0, shown.length - 1);
        strip.hidden = !!want || scope !== 'all' || !!strip._dead;
        token.hidden = scope === 'all';
        token.textContent = scope === 'all' ? '' : (FIND_SCOPES.find(x => x[0] === scope) || ['', ''])[1];
        scopes.replaceChildren(...FIND_SCOPES.map(([k, label]) => h('button', { class: 'fscope' + (k === scope ? ' on' : ''),
            onmousedown: e => e.preventDefault(), onclick: () => { scope = k; at = 0; paint(); } }, label)));
        const kids = [];
        let sec = '';
        shown.forEach((r, n) => {
            if (r.sec !== sec) { sec = r.sec; kids.push(h('div', { class: 'fsec' }, sec)); }
            kids.push(rowEl(r, n));
        });
        if (!shown.length) kids.push(emptyEl(want));
        list.replaceChildren(glide, ...kids);
        list.scrollTop = 0;
        mark(false, true);
        if (!strip.hidden) requestAnimationFrame(strip._paint);
    }

    function mark(scroll, jump) {
        const els = list.querySelectorAll('.frow');
        els.forEach((el, k) => { el.classList.toggle('on', k === at); el.setAttribute('aria-selected', String(k === at)); });
        const on = els[at];
        if (on && on.offsetHeight) {
            glide.classList.toggle('jump', !!jump || calm());
            glide.style.opacity = '1';
            glide.style.width = on.offsetWidth + 'px';
            glide.style.height = on.offsetHeight + 'px';
            glide.style.transform = `translate(${on.offsetLeft}px, ${on.offsetTop}px)`;
        } else glide.style.opacity = '0';
        if (scroll && on) on.scrollIntoView({ block: 'nearest' });
    }

    function run(n) {
        const r = shown[n];
        if (!r) return;
        closeFind(false);
        if (r.file) tell('show', { path: r.file });
        else if (r.page != null) show(r.page);
        else if (r.go) r.go();
    }

    field.addEventListener('input', () => { at = 0; paint(); });
    box._keys = e => {
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeFind(); return; }
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault(); e.stopPropagation();
            if (!shown.length) return;
            at = (at + (e.key === 'ArrowDown' ? 1 : -1) + shown.length) % shown.length;
            mark(true);
            return;
        }
        if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); run(at); return; }
        if (e.key === 'Tab') {
            e.preventDefault(); e.stopPropagation();
            const k = FIND_SCOPES.findIndex(x => x[0] === scope);
            scope = FIND_SCOPES[(k + (e.shiftKey ? -1 : 1) + FIND_SCOPES.length) % FIND_SCOPES.length][0];
            at = 0;
            paint();
            return;
        }
        if (e.key === 'Backspace' && !field.value && scope !== 'all') { e.preventDefault(); scope = 'all'; paint(); return; }
        if (e.target !== field && e.key.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) field.focus();
    };
    // a click in the card that is not on a button leaves the typing where it was
    card.addEventListener('mousedown', e => { if (e.target !== field && !e.target.closest('button')) e.preventDefault(); });
    box.addEventListener('mousedown', e => { if (e.target === box) closeFind(); });
    document.addEventListener('keydown', box._keys, true);
    box._resize = () => { if (!strip.hidden) strip._paint(); };
    window.addEventListener('resize', box._resize);

    // the files it finds are the ones in the folders' own listings, read now
    // if they are more than a moment old
    for (const k of ['desktop', 'downloads']) {
        const n = pages().findIndex(p => p.kind === k);
        if (n > 0) listing(n).then(() => { if (box.isConnected && field.value.trim().length > 1) paint(); });
    }

    paint();
    document.body.append(box);
    // the light can only be put under a row once the rows are on the page
    mark(false, true);
    field.focus();
    requestAnimationFrame(strip._paint);
    // the readings, live for as long as the finder is open
    const tick = async () => {
        if (!box.isConnected) return;
        // the Activity page is already reading; two readers would count twice
        if (!(LIVE.timer && K.page === ACTIVITY())) {
            const r = await ask('activity');
            if (!box.isConnected) return;
            if (r && typeof r.cpu === 'number') pushLive(r);
            else if (!LIVE.last) { strip._dead = true; strip.hidden = true; return; }
        }
        if (!strip.hidden) strip._paint();
        box._timer = setTimeout(tick, LIVE.cpu.length < 10 ? 600 : 1300);
    };
    tick();
}

function closeFind(restore) {
    const box = $('.finder');
    if (!box) return;
    clearTimeout(box._timer);
    document.removeEventListener('keydown', box._keys, true);
    window.removeEventListener('resize', box._resize);
    // The field lets go of the keyboard before it goes, rather than being
    // taken out of the page while it still has it.
    const typing = document.activeElement;
    if (typing && box.contains(typing) && typing.blur) typing.blur();
    box.remove();
    const back = box._back;
    if (restore !== false && back && back.isConnected && back !== document.body && back.focus) back.focus();
}

/** What the Mac is doing, across the top of the finder: the processor and
 *  the memory over the last minute as two lines, and the disk. Every figure
 *  is read from this Mac, the same way the Activity page reads it. */
function pulseStrip() {
    const home = K.home || {};
    const cpuV = h('span', { class: 'pv' }, '–'), memV = h('span', { class: 'pv' }, '–'), memS = h('span', { class: 'ps' });
    const graph = h('div', { class: 'pg', 'aria-hidden': 'true' });
    const disk = home.total > 0 ? h('div', { class: 'pd' },
        h('span', { class: 'pk' }, 'Disk'),
        h('span', { class: 'pv' }, size(home.free)),
        h('span', { class: 'ps' }, 'free of ' + size(home.total)),
        h('span', { class: 'pm' }, h('i', { style: `width:${Math.max(2, home.used / home.total * 100).toFixed(1)}%` }))) : null;
    const strip = h('div', { class: 'fpulse' + (disk ? '' : ' nodisk') },
        h('div', { class: 'pl' },
            h('div', { class: 'pr' }, h('span', { class: 'pk' }, h('i', { class: 'lk cpu' }), 'CPU'), cpuV),
            h('div', { class: 'pr' }, h('span', { class: 'pk' }, h('i', { class: 'lk mem' }), 'Memory'),
              h('span', { class: 'pvw' }, memV, memS))),
        graph, disk);
    strip._paint = () => {
        const r = LIVE.last;
        if (r && typeof r.cpu === 'number') {
            cpuV.textContent = Math.round(r.cpu) + '%';
            const m = r.memory || {};
            memV.textContent = m.total > 0 ? Math.round(m.used / m.total * 100) + '%' : '–';
            memS.textContent = m.total > 0 ? size(m.used) + ' of ' + size(m.total) : '';
        }
        if (graph.isConnected) drawPulse(graph, LIVE.cpu, LIVE.mem);
    };
    return strip;
}

/** Two lines over a minute, drawn at the size they are shown, so the dot at
 *  the end of the processor's line stays round. Nought at the bottom, a
 *  hundred per cent at the top. */
function drawPulse(box, cpu, mem) {
    const w = Math.max(60, Math.round(box.clientWidth)), hgt = Math.max(30, Math.round(box.clientHeight));
    const top = 4, bottom = 4, right = 7;
    // The first readings are spread across the width and close up as more
    // arrive, until a minute of them fills it; a line in the last few
    // pixels of an empty chart reads as a chart that is not working.
    if (cpu.length === 1) { cpu = [cpu[0], cpu[0]]; mem = mem.length ? [mem[0], mem[0]] : mem; }
    const span = Math.max(1, Math.max(cpu.length, mem.length) - 1);
    const x = (vals, k) => (w - right) - (vals.length - 1 - k) * ((w - right) / span);
    const y = v => top + (hgt - top - bottom) * (1 - Math.max(0, Math.min(100, v)) / 100);
    const line = vals => vals.map((v, k) => (k ? 'L' : 'M') + x(vals, k).toFixed(1) + ' ' + y(v).toFixed(1)).join(' ');
    const svg = s('svg', { width: w, height: hgt, viewBox: `0 0 ${w} ${hgt}` });
    svg.append(s('defs', null, s('linearGradient', { id: 'fpg', x1: 0, y1: 0, x2: 0, y2: 1 },
        s('stop', { offset: '0', style: 'stop-color:var(--ink);stop-opacity:.26' }),
        s('stop', { offset: '1', style: 'stop-color:var(--ink);stop-opacity:0' }))));
    for (const f of [0, 0.5, 1]) {
        const at = (top + (hgt - top - bottom) * f).toFixed(1);
        svg.append(s('line', { class: 'gl' + (f === 1 ? ' base' : ''), x1: 0, x2: w - right, y1: at, y2: at }));
    }
    if (mem.length > 1) svg.append(s('path', { class: 'ml', d: line(mem) }));
    if (cpu.length > 1) {
        const d = line(cpu);
        svg.append(s('path', { class: 'ca', d: d + ` L ${(w - right).toFixed(1)} ${hgt - bottom} L ${x(cpu, 0).toFixed(1)} ${hgt - bottom} Z`,
                               fill: 'url(#fpg)' }),
                   s('path', { class: 'cl', d }));
    }
    if (cpu.length) {
        const ex = x(cpu, cpu.length - 1), ey = y(cpu[cpu.length - 1]);
        svg.append(s('circle', { class: 'halo', cx: ex.toFixed(1), cy: ey.toFixed(1), r: 7 }),
                   s('circle', { class: 'dot', cx: ex.toFixed(1), cy: ey.toFixed(1), r: 2.8 }));
    }
    box.replaceChildren(svg);
}

/** What to call you: the name you gave, else your account's first name. */
function firstName() {
    const said = String((K.meta && K.meta.config && K.meta.config.name) || '').trim();
    if (said) return capital(said);
    const full = String((K.meta && K.meta.user) || '').trim();
    return capital(full.split(/\s+/)[0]) || 'You';
}

/** Your name as the window writes it: the one you gave, else your account's. */
function displayName() {
    const said = String((K.meta && K.meta.config && K.meta.config.name) || '').trim()
        || String((K.meta && K.meta.user) || '').trim();
    return capital(said) || 'You';
}

/** A name typed all in small letters — an account's short name, usually —
 *  still starts with a capital. One written with capitals is left alone. */
function capital(text) {
    const t = String(text || '');
    return t && t === t.toLowerCase() ? t.charAt(0).toUpperCase() + t.slice(1) : t;
}

/* ── you, at the foot of the rail ─────────────────────────────────────── */

/** Your @username, with the @, or nothing if you have not picked one. */
function handle() {
    const user = String((K.meta && K.meta.config && K.meta.config.user) || '').trim();
    return user ? '@' + user : '';
}

/** You, at the foot of the sidebar: your picture, your name and your
 *  @username, the way Efferd's sidebar ends with its account. It opens
 *  Settings at your profile, where all of it is changed. */
function youRow() {
    return h('div', { class: 'you', id: 'you' },
        h('button', { class: 'me', 'data-tip': 'Your profile', 'aria-label': 'Your profile', onclick: () => openSettings('profile') },
            face('small'),
            h('span', { class: 'label who2' }, h('b', null, displayName()),
              h('span', null, handle() || 'Pick your @username')),
            h('span', { class: 'label me-go' }, icon('updown'))));
}


/** A picture of your own. The Mac shows its own chooser, draws the picture
 *  small on its side and keeps that copy; the page only shows it. */
async function changePicture() {
    const r = await ask('pickPicture');
    if (!r || r.cancelled || r.missing) return false;
    if (r.bad || !(typeof r.portrait === 'string' && r.portrait)) {
        toast('Kliner could not read that picture. Try a JPEG, PNG or HEIC.', null, 'x');
        return false;
    }
    K.meta.portrait = r.portrait;
    K.meta.customPicture = true;
    redrawYou();
    toast('Picture changed', null);
    return true;
}

/** Back to the picture macOS has for your account. */
async function accountPicture() {
    const r = await ask('accountPicture');
    if (!r || r.missing) return;
    K.meta.portrait = r.portrait || '';
    K.meta.customPicture = false;
    redrawYou();
    toast('Back to your account picture', null);
}

/** Everywhere your picture or name is drawn, drawn again. */
function redrawYou() {
    const old = $('#you');
    if (old) { const row = youRow(); old.replaceWith(row); wireTips(row); }
    if (K.welcome) drawWelcome();
    else if (K.page === SETTINGS() || K.page === 0) drawPage(true);
}

/** An address, near enough: one @, something either side, a dot after it. */
function looksLikeEmail(text) {
    const one_ = String(text || '').trim();
    if (one_.length < 6 || one_.length > 120 || /\s/.test(one_)) return false;
    const halves = one_.split('@');
    if (halves.length !== 2 || !halves[0]) return false;
    const host = halves[1];
    return host.length >= 3 && host.includes('.') && !host.startsWith('.') && !host.endsWith('.');
}

/** Your account picture, the one macOS shows at the login window. If there
 *  is none, your initials in the same circle. */
function face(cls) {
    const face_ = K.meta && K.meta.portrait;
    if (face_ && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(face_)) {
        return h('span', { class: 'face2 ' + (cls || '') }, h('img', { src: face_, alt: '' }));
    }
    const name = String((K.meta && K.meta.user) || '').trim();
    const letters = name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('');
    return h('span', { class: 'face2 letters ' + (cls || '') }, letters || '?');
}

function machineCard(f) {
    const keys = ['Memory', 'Battery', 'Uptime'].filter(k => f[k]);
    const list = h('div', { class: 'facts' });
    for (const k of keys) {
        list.append(h('div', { class: 'fact' }, h('span', { class: 'k' }, k),
            h('span', { class: 'v' }, f[k].value), h('span')));
    }
    if (f.System) list.prepend(h('div', { class: 'fact' }, h('span', { class: 'k' }, 'System'), h('span', { class: 'v' }, f.System.value), h('span')));
    const doctor = pages().findIndex((p, n) => n > 0 && p.kind === 'doctor');
    const box = panel(doctor > 0 ? 'go' : '', cap('cpu', 'This Mac', doctor > 0 ? h('span', null, 'More') : null), list);
    if (doctor > 0) box.addEventListener('click', () => show(doctor));
    return box;
}


/* ── the ring, and its key ────────────────────────────────────────────── */

let RINGS = 0;

function ringRow(bands, whole_, centre, under) {
    // Arcs on a circle, not wedges: each slice can be pointed at, grow, and
    // say what it is. Each is drawn where it ends up, as a path of its own,
    // and one plain white stroke in a mask sweeps them in. Growing the woven
    // strokes themselves with a dash left specks of the weave scattered round
    // the ring in WebKit — the window's own engine, not the one it was tried in.
    const C = 100, R = 72, W = 30, circ = 2 * Math.PI * R;
    const svg = s('svg', { class: 'ring', viewBox: '0 0 200 200' });
    svg.append(s('circle', { class: 'track', cx: C, cy: C, r: R, 'stroke-width': W }));
    const id = 'ringsweep' + (++RINGS);
    const sweep = s('circle', { cx: C, cy: C, r: R, fill: 'none', stroke: '#fff', 'stroke-width': W + 18,
                                transform: `rotate(-90 ${C} ${C})`, 'stroke-dasharray': `${circ} ${circ}` });
    const still = calm() || !DRAW.moving;
    sweep.style.strokeDashoffset = still ? '0' : String(circ);
    svg.append(s('defs', null, s('mask', { id, maskUnits: 'userSpaceOnUse', x: 0, y: 0, width: 200, height: 200 }, sweep)));
    const g = s('g', { mask: `url(#${id})` });
    svg.append(g);
    const sum = bands.reduce((a, b) => a + b.value, 0) || 1;
    const minShare = 0.012, gap = bands.length > 1 ? 3 : 0;
    const shares = bands.map(b => Math.max(b.value / sum, b.value > 0 ? minShare : 0));
    const norm = shares.reduce((a, b) => a + b, 0) || 1;
    const spot = a => (C + R * Math.cos(a)).toFixed(2) + ' ' + (C + R * Math.sin(a)).toFixed(2);
    // from angle a to angle b, clockwise; a whole turn in two halves, since
    // an arc that ends where it starts draws nothing
    const arc = (a, b) => b - a >= 2 * Math.PI - 1e-6
        ? `M ${spot(a)} A ${R} ${R} 0 1 1 ${spot(a + Math.PI)} A ${R} ${R} 0 1 1 ${spot(a)}`
        : `M ${spot(a)} A ${R} ${R} 0 ${b - a > Math.PI ? 1 : 0} 1 ${spot(b)}`;
    let at = -Math.PI / 2;
    const segs = [];
    bands.forEach((b, n) => {
        const len = Math.max(0, shares[n] / norm * circ - gap);
        const seg = s('path', { class: 'seg', d: len > 0 ? arc(at, at + len / R) : '', 'stroke-width': W,
                                stroke: b.hot ? 'url(#weaveHot)' : `url(#weave${n % WEAVES})` });
        g.append(seg);
        segs.push(seg);
        at += (len + gap) / R;
    });
    if (!still) {
        sweep.style.transition = 'stroke-dashoffset 1.1s cubic-bezier(.2,.8,.2,1)';
        requestAnimationFrame(() => requestAnimationFrame(() => { sweep.style.strokeDashoffset = '0'; }));
    }
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

/** A page's picture in a tile beside its name, the way Home has you beside
 *  yours: the same picture the rail shows for it, a little bigger. */
function pageTile(symbol) {
    return h('span', { class: 'pg-ic', 'aria-hidden': 'true' }, icon(symbol || 'dot'));
}



function head(i, extraActs) {
    const item = pages()[i];
    const acts = h('div', { class: 'acts' });
    if (item.kind === 'next') {
        // The pictures are the control. Up here only the two ways out: your
        // own folder, and the wallpaper you had before Kliner changed it.
        const original = item.extras.findIndex(e => e.symbol === 'arrow.uturn.backward');
        acts.append(h('button', { class: 'sq', 'data-tip': 'Open your wallpaper folder', onclick: () => tell('wallFolder') }, icon('folder')));
        if (original >= 0) acts.append(h('button', { class: 'sq', 'data-tip': 'Put back the one you had', onclick: () => extra(i, original) }, icon('undo')));
        return h('div', { class: 'head' }, pageTile(item.symbol),
            h('div', { class: 'words' }, h('h1', null, item.title), h('p', null, item.blurb)), acts);
    }
    if (item.reveal) {
        // The two ways of looking are pictures. Four labelled buttons across
        // the top of every page is three more things to read than the one
        // that does something.
        acts.append(h('button', { class: 'sq', 'data-tip': 'Look inside', onclick: () => walk([item.reveal]) }, icon('folder')));
        acts.append(h('button', { class: 'sq', 'data-tip': 'Show in Finder', onclick: () => tell('reveal', { page: i }) }, icon('finder')));
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
    return h('div', { class: 'head' }, pageTile(item.symbol),
        h('div', { class: 'words' },
            h('h1', null, item.title),
            h('p', null, item.blurb)),
        acts);
}

function drawAction(out, i, kept, bodyOnly) {
    if (!bodyOnly) out.append(head(i));
    // a folder's page: its facts as chips, and two ways to see it — what
    // nimo reads in it, or the files themselves on a board by kind
    let board = false;
    if (!bodyOnly && pages()[i].reveal && !kept.ready && !kept.result) {
        const view = viewOf(i, 'overview');
        out.append(folderChips(i), viewTabs(i, [['overview', 'Overview', 'grid'], ['board', 'Board', 'board']], view));
        board = view === 'board';
    }
    if (board) {
        if (K.preview && (pages()[i].asks || !pages()[i].looksOnly)) out.append(looking());
        if (shut(i)) out.append(shutNote(i));
        if (kind(i) === 'desktop' && K.meta.desktopHidden) out.append(hiddenNote());
        drawFolderBoard(out, i);
        return;
    }
    if (!bodyOnly && K.preview && (pages()[i].asks || !pages()[i].looksOnly)) out.append(looking());
    if (!bodyOnly && shut(i)) out.append(shutNote(i));
    if (!bodyOnly && kind(i) === 'desktop' && K.meta.desktopHidden) out.append(hiddenNote());
    const k = kind(i);
    let pieces = kept.pieces || [];
    if (kept.result && k !== 'next') {
        out.append(banner(pieces, kept, i));
        const said = pieces.find(p => p.k === 'good') || pieces.find(p => p.k === 'warn');
        pieces = pieces.filter(p => p !== said);
    }
    if (k === 'next') { drawWalls(out); return; }
    if (kept.ready) {
        drawReady(out, i);
        return;
    }

    // A page with one panel on it leaves half the window empty, so the
    // pages that read short are laid out in two columns instead.
    const aside = null;
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

/** A folder's facts, under its title: how much is loose in it, how much of
 *  that is old, and the folder it is sorted into. */
function folderChips(i) {
    const item = pages()[i];
    const k = kind(i);
    const home = K.home || {};
    const n = k === 'desktop' ? home.desk : k === 'downloads' ? home.downloads : null;
    const old = k === 'desktop' ? home.deskOld : k === 'downloads' ? home.downloadsOld : '';
    const chips = [];
    if (n != null) chips.push(pchip(KIND_LOOSE[k] || 'folder', 'Loose', plural(n, 'item')));
    if (old) chips.push(pchip('clock', 'Old', old));
    chips.push(pchip('tray', 'Sorts into', item.reveal + '/' + tidyName(), () => tell('show', { path: [item.reveal, tidyName()] })));
    return h('div', { class: 'ph-chips' }, chips);
}
const KIND_LOOSE = { desktop: 'desk', downloads: 'download', documents: 'file' };

/** The files in a folder on a board: one column per kind, in nimo's own
 *  order, newest first, each with Finder's picture of it. A picture opens
 *  big; anything else is shown in Finder. */
function drawFolderBoard(out, i) {
    const board = h('div', { class: 'board fboard' }, h('div', { class: 'bcol-none wide' }, 'Reading the folder…'));
    out.append(h('div', { class: 'view' }, board));
    listing(i).then(items => {
        if (!board.isConnected) return;
        const folder = pages()[i].reveal;
        const files = items.filter(countedByNimo).sort((a, b) => (b.modified || 0) - (a.modified || 0));
        const groups = new Map();
        for (const f of files) {
            const k = kindOf(f);
            if (!groups.has(k)) groups.set(k, []);
            groups.get(k).push(f);
        }
        const pics = [];
        const cols = [];
        for (const k of ['Screenshots', 'Images', 'Video', 'Audio', 'Documents', 'Archives', 'Code', 'Apps', 'Folders', 'Other']) {
            const list = groups.get(k);
            if (!list) continue;
            const picture = k === 'Screenshots' || k === 'Images';
            const cards = list.slice(0, 40).map((f, n) => {
                const pic = h('span', { class: 'bc-pic' + (picture ? ' photo' : '') }, icon(f.dir ? 'folder' : KIND_PICTURE[k] || 'file'));
                pic.dataset.name = f.name;
                pics.push(pic);
                return bcard({ title: shortName(f.name), tip: f.name, pic, name: f.name,
                    go: () => picture ? openLight(i, folder, list, n, board) : tell('show', { path: [folder, f.name] }),
                    meta: [[null, f.dir ? 'folder' : f.size ? size(f.size) : ''], ['clock', ago(f.modified)]] });
            });
            if (list.length > 40) cards.push(h('button', { class: 'bcol-more', onclick: () => tell('reveal', { page: i }) },
                `${list.length - 40} more in Finder`));
            cols.push(bcol('b-kind', k, icon(KIND_PICTURE[k] || 'dot'), cards, '', null, list.length));
        }
        if (K.listing && K.listing[i] && K.listing[i].shut) {
            board.replaceChildren(h('div', { class: 'bcol-none wide' }, 'macOS has not let Kliner see this folder yet.'));
            return;
        }
        board.replaceChildren(...(cols.length ? cols : [h('div', { class: 'bcol-none wide' }, 'Nothing loose in here. Everything is sorted.')]));
        paintIcons(i, pics);
    });
}

/** What the Free up space reading says can safely go: its own total, the row
 *  under the line in the "safe to clean" panel, or the rows above it added up. */
function safeTotal(pieces) {
    const sec = sections(pieces).find(x => /safe to clean/i.test(x.title || ''));
    if (!sec) return null;
    let ruled = false, sum = 0, total = null;
    for (const p of sec.pieces) {
        if (p.k === 'rule') { ruled = true; continue; }
        if (p.k !== 'row' || !p.label || !hasUnit(p.value)) continue;
        const v = bytes(p.value);
        if (v == null) continue;
        if (ruled) { if (total == null) total = v; continue; }
        sum += v;
    }
    return total != null ? total : sum > 0 ? sum : null;
}

/** The second column: what the page is about, said once, with the figures
 *  that belong to it. Nothing invented — every number comes from the same
 *  reading as the panel beside it. */
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
/** A panel's name from nimo's heading: "your mac" is Your Mac, the way the
 *  Mac and its Dock are written everywhere else in the window. */
function panelTitle(text) { return title(text).replace(/\bmac\b/g, 'Mac').replace(/\bdock\b/g, 'Dock'); }

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
    box.append(cap(asBytes ? 'bars' : 'grid', panelTitle(sec.title) || titleOf(i),
        h('span', null, `${rows.length} ${asBytes ? (rows.every(r => r.folder) ? 'folders' : 'items') : 'types'}`)));
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
    return !f.name.startsWith('.') && f.name !== tidyName() && f.name !== 'Kliner.app'
        && !ARRIVING.test(f.name) && !/[\t\n\r]/.test(f.name);
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
        // `shut`: macOS would not let Kliner read it, which is not the same
        // as there being nothing in it
        K.listing = K.listing || {};
        K.listing[i] = { at: Date.now(), items: (reply && Array.isArray(reply.items) && reply.items) || [], shut: !!(reply && reply.shut) };
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
    if (!newest.length) {
        const cap_ = strip.previousElementSibling;
        if (cap_ && cap_.classList.contains('nwcap')) cap_.remove();
        strip.remove();
        return;
    }
    const isPicture = f => ['Screenshots', 'Images'].includes(kindOf(f));
    const pictures = newest.filter(isPicture);
    const els = [];
    strip.replaceChildren(...newest.map((f, n) => {
        const kind = kindOf(f);
        const img = h('span', { class: 'img' + (isPicture(f) ? ' pic' : '') }, icon(KIND_PICTURE[kind] || 'file'));
        img.dataset.name = f.name;
        els.push(img);
        return h('button', { class: 'nw', title: f.name, style: `animation-delay:${n * 25}ms`,
                             onclick: () => isPicture(f) ? openLight(i, folder, pictures, pictures.indexOf(f), strip)
                                                         : tell('show', { path: [folder, f.name] }) },
            img, h('span', { class: 'nm' }, shortName(f.name)), h('span', { class: 'when' }, ago(f.modified)));
    }));
    paintIcons(i, els);
}

/* Pictures of files, kept for as long as the window is open: the same file
   is not drawn by the Mac twice, and a card drawn again is drawn at once,
   without its pictures blinking out and back. Keyed by name and date, so a
   file that changed is drawn again. */
const THUMBS = new Map();

/** A picture for each element: its own for a photo or screenshot, the icon
 *  Finder draws for everything else. */
async function paintIcons(i, els) {
    const items = (K.listing && K.listing[i] && K.listing[i].items) || [];
    const when = name => { const f = items.find(x => x.name === name); return f ? f.modified || 0 : 0; };
    const keyOf = name => i + '/' + name + '@' + when(name);
    const put = (el, uri) => {
        if (!el.isConnected) return;
        el.replaceChildren(h('img', { src: uri, alt: '', class: uri.startsWith('data:image/jpeg') ? 'photo' : 'icon' }));
        el.classList.add('got');
    };
    const want = [];
    for (const el of els) {
        const uri = THUMBS.get(keyOf(el.dataset.name));
        if (uri) put(el, uri); else want.push(el.dataset.name);
    }
    const names = [...new Set(want)];
    for (let at = 0; at < names.length; at += 12) {
        const reply = await ask('thumbs', { page: i, names: names.slice(at, at + 12), icons: true });
        const got = (reply && reply.thumbs) || {};
        for (const [name, uri] of Object.entries(got)) {
            if (!goodPicture(uri)) continue;
            THUMBS.set(keyOf(name), uri);
            for (const el of els) if (el.dataset.name === name) put(el, uri);
        }
    }
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
          h('span', null, 'Byte by byte, in ' + where + '. Changes nothing.')),
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
    if (sec.title) box.append(cap(isAction(i) ? pages()[i].symbol : null, panelTitle(sec.title)));
    const rows = [];
    const rest = [];
    let ruled = false;
    for (const p of sec.pieces) {
        if (p.k === 'rule') { ruled = true; continue; }
        if (p.k === 'row' && p.label) rows.push(Object.assign({ total: ruled }, p));
        else if (p.k !== 'note') rest.push(p);
    }
    const words = rest.filter(p => p.k !== 'item');
    // nothing in it but nimo saying all is well: that one line, as the state
    // of the page, with when it was read
    if (!rows.length && !rest.some(p => p.k === 'item') && words.length === 1 && words[0].k === 'good') {
        const kept = K.kept[i];
        box.append(h('div', { class: 'clearstate' }, h('span', { class: 'tick' }, icon('check')),
            h('div', null, h('b', null, prose(words[0].text)),
              kept && kept.at ? h('span', null, agoWords(kept.at)) : null)));
        return box;
    }
    const said = sentences(words);
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
            h('span', { class: 'ico appico', 'data-app': name }, dockIcon(name) || icon('cube')),
            h('div', { style: 'min-width:0' }, h('div', { class: 'nm' }, name),
              hint ? h('div', { class: 'kd' }, hint) : null),
            h('button', { class: 'btn line small', onclick: () => unpin(name) }, icon('x'), 'Take out')));
    });
    out.append(panel('', cap('grid', 'In your Dock', total ? h('span', null, total.value) : null), list,
        h('div', { class: 'more' }, 'Taking an app out of the Dock does not uninstall it. Kliner saves your Dock first, so Put the Dock back is exact.')));
    // each app's own icon, the same ones the Dock draws: read once, laid in
    // where the names are, without drawing the list again
    if (!MINI.dock) readMiniDock();
}

/** An app's own icon, when the Dock has been read: the one Finder draws. */
function dockIcon(name) {
    const a = MINI.dock && MINI.dock.apps.find(x => x.name === name);
    return a && a.icon ? h('img', { src: a.icon, alt: '' }) : null;
}

function fillDockIcons(root) {
    for (const el of root.querySelectorAll('.ico.appico[data-app]')) {
        const pic = dockIcon(el.dataset.app);
        if (pic && el.isConnected) el.replaceChildren(pic);
    }
}

async function unpin(name) {
    if (K.busy) return;
    if (K.preview) { toast('Preview: this would take ' + name + ' out of your Dock.', null, 'eye'); return; }
    K.busy = true;
    busyButtons(true);
    let reply;
    try { reply = await ask('unpin', { name }); } finally { K.busy = false; }
    busyButtons(false);
    if (!reply || reply.cancelled || reply.missing) return;
    delete K.kept[K.page];
    look(K.page);
    if (reply.ok) readMiniDock();
    // what nimo said, either way: an app it could not find is not silence
    const pieces = parse(reply.text || '');
    const good = pieces.find(p => p.k === 'good'), warn = pieces.find(p => p.k === 'warn');
    if (reply.ok && good) toast(good.text, null);
    else if (!reply.ok) toast(warn ? warn.text : name + ' is still in your Dock.', null, 'x');
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
    out.append(panel('', cap('undo', count_ ? title(count_.text) : 'History'), entryList(items)));
    const notes = footnotes(pieces);
    if (notes) out.append(notes);
}

/* ── Wallpaper ────────────────────────────────────────────────────────── */

/** The wallpaper on the screen now, as far as this window knows: the one it
 *  put there, else the one nimo says is on. */
function wallNow() {
    if (K.wallOn) return K.wallOn;
    const on = (K.walls || []).find(w => /\bon now\b/.test(w.parts.slice(1).join(' ')));
    return on ? on.parts[0] : '';
}

/** One wallpaper. The picture is the button; the one on the screen has a
 *  ring and a tick. */
function wallTile(w, on, big, onclick, delay) {
    const drawn = K.wallPics && K.wallPics[String(w.no)];
    return h('button', { class: 'wall' + (on ? ' on' : ''), title: w.parts[0], 'aria-pressed': on ? 'true' : 'false',
                         'data-no': String(w.no), style: delay ? `animation-delay:${delay}ms` : '', onclick },
        h('span', { class: 'sheet' + (drawn ? ' has' : '') },
          drawn ? h('img', { class: 'pic', src: drawn, alt: '' }) : icon('photo'),
          on ? h('span', { class: 'onmark' }, icon('check')) : null),
        h('span', { class: 'nm' }, w.parts[0]));
}

/** The way to your own: a tile like the others, that opens the folder. */
function wallAdd() {
    return h('button', { class: 'wall add', onclick: () => tell('wallFolder') },
        h('span', { class: 'sheet' }, icon('plus')), h('span', { class: 'nm' }, 'Add your own'));
}

/* The shelves the wallpapers sit on, in the order they are listed. */
const SHELVES = { kliner: 'Kliner', yours: 'Yours', mac: 'macOS', colors: 'Colours' };

/** Which shelf one wallpaper is on: what the app said, or, from a Kliner
 *  that does not say, yours before the line and the Mac's after it. */
function shelfOf(one_, n) {
    const said = K.wallKinds && K.wallKinds[one_.no - 1];
    if (said && SHELVES[said]) return said;
    return n < Math.min(K.wallMine || 0, (K.walls || []).length) ? 'yours' : 'mac';
}

/** The wallpapers on their shelves: Kliner's own, yours, the Mac's, and its
 *  plain colours — each with how many are on it, its name staying at the
 *  top while you scroll past it. The tile that adds your own sits with yours. */
function drawWalls(out) {
    if (!K.walls) {
        out.append(panel('', h('div', { class: 'more loadingline' }, 'Looking for wallpapers…')));
        return;
    }
    const now = wallNow();
    const groups = [];
    K.walls.forEach((one_, n) => {
        const k = shelfOf(one_, n);
        let g = groups[groups.length - 1];
        if (!g || g.k !== k) groups.push(g = { k, walls: [] });
        g.walls.push([one_, n]);
    });
    let added = false;
    for (const g of groups) {
        const grid = h('div', { class: 'walls' });
        for (const [one_, n] of g.walls) {
            grid.append(wallTile(one_, !!now && one_.parts[0] === now, true, () => putOnWall(one_.no), Math.min(n, 30) * 12));
        }
        if (!added && (g.k === 'kliner' || g.k === 'yours')) { grid.append(wallAdd()); added = true; }
        out.append(h('section', { class: 'wshelf' },
            h('div', { class: 'wshelf-h' }, h('b', null, SHELVES[g.k]), h('span', null, String(g.walls.length))), grid));
    }
    if (!added) {
        out.append(h('section', { class: 'wshelf' }, h('div', { class: 'wshelf-h' }, h('b', null, 'Yours')),
            h('div', { class: 'walls' }, wallAdd())));
    }
    // a shelf's name gets its glass only while it holds on at the top
    const sc = $('#scroll');
    if (sc && !sc.dataset.shelves) { sc.dataset.shelves = '1'; sc.addEventListener('scroll', markStuck, { passive: true }); }
    requestAnimationFrame(markStuck);
}

function markStuck() {
    const sc = $('#scroll');
    if (!sc) return;
    const top = sc.getBoundingClientRect().top;
    for (const hd of document.querySelectorAll('.wshelf-h')) hd.classList.toggle('stuck', hd.getBoundingClientRect().top - top < -8);
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
    // The four that are already tiles above do not need a row as well: the
    // list is for what the tiles do not show.
    const own = new Set(['Months', 'Desktop older', 'Downloads older', 'Last change', 'Next', 'nimo']);
    for (const [label, tiled] of [['Disk', !!f.Disk], ['Memory', !!f.Memory], ['Battery', !!f.Battery], ['Uptime', !!f.Uptime]]) {
        if (tiled && across.children.length) own.add(label);
    }
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
    out.append(h('div', { class: 'head' }, pageTile('folder'),
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

/* ── Settings, the way Dan's two pictures have it ────────────────────────
   A menu down the left with you at the top of it — your picture, your name
   and your @username — and under you the parts: your profile, how Kliner
   behaves on this Mac, what macOS lets it see, then Help and About. On the
   right the part you picked, one row per thing: its name and a line about
   it on the left, the thing itself on the right. Clicking your name at the
   foot of the sidebar opens it at your profile; Help (?) opens it at Help. */

const SET = { tab: 'profile' };
const SET_TABS = [
    ['profile', 'user', 'Profile'],
    ['public', 'globe', 'Public page'],
    ['general', 'sliders', 'General'],
    ['access', 'shield', 'Permissions'],
    null,
    ['help', 'help', 'Help'],
    ['about', 'info', 'About'],
];

/** Settings at one of its parts, or at the one you were last on. Help is
 *  its own page, so its key and the light in the sidebar stay true. */
function openSettings(tab) {
    if (tab) SET.tab = tab;
    const want = SET.tab === 'help' ? HELP() : SETTINGS();
    if (K.page === want && !K.walked.length) drawPage(true);
    else show(want);
}

async function drawSettings(out) {
    const tab = K.page === HELP() ? 'help' : SET.tab === 'help' ? 'profile' : SET.tab;
    SET.tab = tab;
    out.classList.add('setp');
    const body = h('section', { class: 'set-body', id: 'setBody' });
    out.append(h('div', { class: 'set-wrap' }, settingsNav(tab), body));
    if (tab === 'help') { body.append(...helpPart()); return; }
    if (tab === 'about') { body.append(...aboutPart()); return; }
    if (tab === 'profile') { body.append(...profilePart()); return; }
    if (tab === 'public') { body.append(...publicPart()); return; }
    body.append(partHead(tab === 'general' ? 'General' : 'Permissions'));
    const st = await ask('settings');
    if (K.page !== SETTINGS() || SET.tab !== tab || !body.isConnected) return;
    body.append(...(tab === 'general' ? generalPart(st || {}) : accessPart(st || {})));
}

/** The menu down the left: you, then the parts, the one you are on lit. */
function settingsNav(tab) {
    const nav = h('nav', { class: 'set-nav', 'aria-label': 'Settings' },
        h('button', { class: 'set-me', onclick: () => openSettings('profile') }, face('small'),
            h('span', { class: 'set-me-w' }, h('b', null, displayName()), h('span', null, handle() || K.meta.email || 'Pick your @username'))));
    for (const t of SET_TABS) {
        if (!t) { nav.append(h('i', { class: 'set-sep' })); continue; }
        const [key, sym, label] = t;
        nav.append(h('button', { class: 'set-tab' + (key === tab ? ' on' : ''), 'aria-current': key === tab ? 'page' : null,
                                 onclick: () => { if (SET.tab !== key || K.page !== (key === 'help' ? HELP() : SETTINGS())) openSettings(key); } },
            icon(sym), h('span', null, label)));
    }
    return nav;
}

/** A part's name, and a line under it. */
function partHead(title, sub) {
    return h('header', { class: 'set-h' }, h('h1', null, title), sub ? h('p', null, sub) : null);
}

/** One thing in Settings: its name and a line about it on the left, the
 *  thing itself on the right. */
function srow(title, desc, control, cls) {
    return h('div', { class: 'srow' + (cls ? ' ' + cls : '') },
        h('div', { class: 'srow-l' }, h('div', { class: 'srow-t' }, title), desc ? h('div', { class: 'srow-d' }, desc) : null),
        control ? h('div', { class: 'srow-r' }, control) : null);
}

/** A switch that says what it is. */
function switchEl(on, label, go, disabled) {
    return h('button', { class: 'switch' + (on ? ' on' : ''), role: 'switch', 'aria-checked': String(!!on), 'aria-label': label,
                         disabled: disabled ? '' : null, onclick: go });
}

/* ── General: how Kliner behaves on this Mac ── */

function generalPart(st) {
    const days = String(K.meta.config.days || '30');
    const receive = K.meta.config.receive !== 'off';
    const login = st.login || {};
    return [
        srow('Open at login', login.possible ? 'Kliner opens when you sign in.' : 'Needs macOS 13 or newer.',
            switchEl(login.on, 'Open at login', async e => {
                const b = e.currentTarget;
                const r = await ask('setLogin', { on: !b.classList.contains('on') });
                const on = !!(r && r.on);
                b.classList.toggle('on', on);
                b.setAttribute('aria-checked', String(on));
            }, !login.possible)),
        srow(h('span', null, 'Desktop files ', h('kbd', { class: 'inkey' }, '\\')),
            K.meta.desktopHidden ? 'Hidden. They are still in your Desktop folder.' : 'On your desktop. \\ hides them, from anywhere in Kliner.',
            switchEl(!K.meta.desktopHidden, 'Desktop files', toggleIcons)),
        srow('Macs nearby can send you files', handle() ? 'To ' + handle() + ', into Downloads, after you say yes.' : 'Pick a username first.',
            switchEl(receive && handle(), 'Receive files', async e => {
                const b = e.currentTarget;
                const r = await ask('receiving', { on: !b.classList.contains('on') });
                const on = !!(r && r.on);
                K.meta.config.receive = on ? 'on' : 'off';
                b.classList.toggle('on', on);
                b.setAttribute('aria-checked', String(on));
            }, !handle())),
        srow('Preview mode', 'Nothing changes while this is on.', switchEl(K.preview, 'Preview mode', () => flipPreview())),
        srow('Old files', 'Old means older than this.',
            seg(['7', '30', '90'], days, v => { K.meta.config.days = v; tell('setConfig', { key: 'days', value: v }); }, v => v + ' days')),
        srow('Sidebar', 'With the names of the places, or folded to their pictures. ⌘B',
            seg(['open', 'folded'], K.wide ? 'open' : 'folded', v => { if ((v === 'open') !== K.wide) fold(); }, v => v === 'open' ? 'Open' : 'Folded')),
        srow('Introduction', 'The first minute with Kliner, again.', h('button', { class: 'ef-btn', onclick: startWelcome }, 'Show again')),
    ];
}

/* ── Permissions: what macOS lets Kliner see ── */

function accessPart(st) {
    const fd = !!st.fullDisk, folders = !!st.folders;
    const said = (on, text) => h('span', { class: 'okdot' + (on ? ' yes' : '') }, h('i'), text);
    return [
        srow(said(folders, 'Your folders'), folders ? 'Kliner can look in the folders it tidies.' : 'macOS asks once for each folder.',
            h('button', { class: 'ef-btn', onclick: async () => { await ask('askFolders'); drawPage(true); } }, folders ? 'Check again' : 'Allow')),
        srow(said(fd, 'Full Disk Access'), 'Kliner still only reads your home folder.',
            h('button', { class: 'ef-btn', onclick: async () => { await ask('fullDisk'); drawPage(true); } }, fd ? 'Settings' : 'Turn on')),
    ];
}

/* ── Help: the keys, and what is where ── */

function helpPart() {
    const keys = [
        ['Search, from anywhere', '⌘K'], ['Hide or show the files on your desktop', '\\'], ['Refresh', '⌘R'], ['Back', '⌘['], ['Forward', '⌘]'],
        ['Go to a page', '⌘1 – ⌘9'], ['Settings', '⌘,'], ['Fold the sidebar', '⌘B'], ['Previous or next page', '↑ ↓'], ['Help', '?'],
    ];
    return [
        partHead('Help', 'Keyboard shortcuts, and what is where.'),
        srow('What is where', 'One part of the window at a time, with a few words.', h('button', { class: 'ef-btn', onclick: showMap }, 'Show me')),
        h('div', { class: 'set-keys' }, keys.map(([t, k]) => h('div', { class: 'kr' }, h('span', null, t),
            h('span', { class: 'kc' }, keyCaps(k))))),
    ];
}

/** "⌘1 – ⌘9" as the keys you press: one cap a key, the dash between. */
function keyCaps(k) {
    const caps = [];
    for (const part of k.split(' ')) {
        if (part === '–') { caps.push(h('i', null, '–')); continue; }
        if (part.length > 1 && part[0] === '⌘') caps.push(h('kbd', null, '⌘'), h('kbd', null, part.slice(1)));
        else caps.push(h('kbd', null, part));
    }
    return caps;
}

/* ── About ── */

function aboutPart() {
    return [
        partHead('About'),
        h('div', { class: 'set-about' }, h('span', { class: 'sb-mark big' }, eyesMark('glance blinks')),
            h('div', null, wordMark(), h('p', null, 'Version ' + K.meta.version + ' · MIT · kliner.app'))),
        srow('Your password', 'Kliner never asks for it.', icon('check')),
        srow('Your home folder', 'Nothing outside it is ever touched.', icon('check')),
        srow('Every move', 'Written down, so it can be undone.', icon('check')),
    ];
}

/* ── your profile: you, and your public page at kliner.app/@you ─────────

   Off until you turn it on, and then only what you tick: your picture and
   words, this Mac, and how it is set up. Every part of it is read from the
   Mac when you publish, nothing typed in for you. The words are kept on this
   Mac as well, so hiding the profile does not lose them.                   */

function profileWords() {
    try { return JSON.parse(K.meta.config.profile || '{}') || {}; } catch (e) { return {}; }
}

let PROFILE_MAC = null;
let PROFILE_WALL = '';

/** The profile's words and choices: what was kept on this Mac, with what
 *  the page starts from when nothing was. */
function profileSel() {
    const w = profileWords();
    return { visible: !!w.visible, display: w.display != null ? w.display : (K.meta.config.name || ''),
             bio: w.bio || '', links: (w.links || []).concat(['', '']).slice(0, 2),
             role: w.role || '', place: w.place || '',
             work: (w.work || []).concat([{}, {}, {}, {}]).slice(0, PROFILE_WORK_ROWS)
                   .map(it => ({ name: (it && it.name) || '', note: (it && it.note) || '',
                                 when: (it && it.when) || '', url: (it && it.url) || '' })),
             picture: w.picture !== false, mac: w.mac !== false, setup: w.setup !== false };
}
/** Where kliner.app said the profile is, once published; kliner.app/@you before. */
function profileUrl() {
    const mine = bareName(handle());
    const said = profileWords().url;
    return typeof said === 'string' && /^https:\/\/[^\s]+\/@/.test(said) && said.endsWith('/@' + mine) ? said : 'https://kliner.app/@' + mine;
}

/** The top of both parts: your wallpaper across it, you in front of it,
 *  and whether your page is up, with the way to it. */
function profileCover(sel) {
    const mine = bareName(handle());
    const cloud = nameWhere() === 'cloud';
    const coverName = h('b', null, (sel && sel.display) || displayName());
    const coverState = h('span', { class: 'set-cover-s' + (sel && sel.visible ? ' on' : '') }, sel && sel.visible ? 'Public' : 'Hidden');
    const coverPic = h('div', { class: 'set-cover-pic' });
    const cover = h('div', { class: 'set-cover' }, coverPic,
        h('div', { class: 'set-cover-me' }, face('big'), h('div', { class: 'set-cover-w' }, coverName, h('span', null, mine ? '@' + mine : 'No username yet'))),
        h('div', { class: 'set-cover-r' }, cloud ? coverState : null,
            cloud && mine && sel && sel.visible ? h('button', { class: 'ef-btn glass', onclick: () => tell('openProfile', { url: profileUrl() }) },
                profileUrl().replace(/^https:\/\//, ''), icon('finder')) : null));
    cover._paint = () => {
        coverName.textContent = (sel && sel.display) || displayName();
        if ((!sel || sel.setup) && goodPicture(PROFILE_WALL)) {
            if (!coverPic.firstChild) coverPic.append(h('img', { src: PROFILE_WALL, alt: '' }));
        } else coverPic.replaceChildren();
        cover.classList.toggle('pic', !!coverPic.firstChild);
        coverState.textContent = sel && sel.visible ? 'Public' : 'Hidden';
        coverState.classList.toggle('on', !!(sel && sel.visible));
    };
    cover._paint();
    if (!PROFILE_WALL) ask('wallBig', {}).then(r => { if (r && goodPicture(r.picture)) { PROFILE_WALL = r.picture; cover._paint(); } });
    return cover;
}

/** Profile: you, and only you — your name, your @username, your email and
 *  your picture — and one line about your page at kliner.app, which has a
 *  part of its own (publicPart). Dan: the profile was too busy; the page's
 *  dozen fields under your name were most of why. */
function profilePart() {
    const mine = bareName(handle());
    const cloud = nameWhere() === 'cloud';
    const sel = profileSel();
    const nameField = h('input', { class: 'field', value: K.meta.config.name || '', placeholder: firstName(), maxlength: '60', 'aria-label': 'Name',
        oninput: e => { K.meta.config.name = e.target.value; tell('setConfig', { key: 'name', value: e.target.value }); } });
    const mailField = h('input', { class: 'field', value: K.meta.email || '', placeholder: 'you@example.com', maxlength: '120', 'aria-label': 'Email',
        oninput: e => {
            const ok = looksLikeEmail(e.target.value);
            e.target.classList.toggle('bad', !!e.target.value && !ok);
            if (ok || !e.target.value) { K.meta.email = e.target.value; tell('setConfig', { key: 'email', value: e.target.value }); }
        } });
    const pic = h('div', { class: 'set-pic' }, face('big'),
        h('div', { class: 'set-pic-b' },
            h('button', { class: 'ef-btn', onclick: async () => { if (await changePicture()) drawPage(true); } }, icon('upload'), 'Upload a picture'),
            K.meta.customPicture ? h('button', { class: 'ef-btn', onclick: async () => { await accountPicture(); drawPage(true); } }, 'Use account picture') : null));
    const page = !mine ? 'Pick a username first: your page lives at kliner.app/@yourname.'
        : !cloud ? 'It goes up at kliner.app/@' + mine + ' once the name is there. Kliner does that as soon as it can.'
        : sel.visible ? 'Public at ' + profileUrl().replace(/^https:\/\//, '') + '.' : 'Hidden. Only you can see it.';
    const out = [partHead('Profile', 'You, here and at kliner.app.'), profileCover(sel),
        srow('Name', 'How Kliner greets you.', nameField),
        srow('Username', 'How anyone with Kliner sends you files, near or far.', usernameField()),
        srow('Email', 'Kept on this Mac.', mailField),
        srow('Picture', 'Here and on your page.', pic),
        srow('Public page', page, h('button', { class: 'ef-btn', disabled: !cloud || !mine ? '' : null, onclick: () => openSettings('public') },
            sel.visible ? 'Edit page' : 'Set up', icon('right')))];
    if (cloud && mine) out.push(h('div', { class: 'set-foot quiet' }, h('span', { class: 'gap' }), accountLeave(mine)));
    return out;
}

/** The way to leave kliner.app: two clicks, the second saying what goes. */
function accountLeave(mine) {
    const leave = h('button', { class: 'btn bare small danger' }, 'Delete my kliner.app account');
    leave.addEventListener('click', async e => {
        e.preventDefault();
        if (!leave.classList.contains('sure')) { leave.classList.add('sure'); leave.textContent = 'Delete @' + mine + ' and its page? Click again'; return; }
        leave.disabled = true;
        const r = await ask('accountDelete');
        if (r && r.ok) { K.meta.config.user = ''; K.meta.config.cloudUser = ''; toast('@' + mine + ' is gone from kliner.app.', null); drawFrame(); openSettings('profile'); }
        else { leave.disabled = false; toast((r && r.bad) || 'Kliner could not reach kliner.app.', null, 'x'); }
    });
    return leave;
}

/* ── your page at kliner.app/@you ─────────────────────────────────────────
   Its own part, in three blocks: whether it is up, your words, and what it
   shows besides them; Publish at the foot. Off until you turn it on, and
   then only what you tick: your picture and words, this Mac, and how it is
   set up. Every part of it is read from the Mac when you publish, nothing
   typed in for you. The words are kept on this Mac too, so hiding the page
   does not lose them. */

function publicPart() {
    const mine = bareName(handle());
    const cloud = nameWhere() === 'cloud';
    const sel = profileSel();
    let url = profileUrl();
    const out = [partHead('Public page', mine ? 'kliner.app/@' + mine + ', for anyone you give the link to.' : 'Your page at kliner.app.')];
    if (!cloud || !mine) {
        out.push(srow('Not yet', mine ? 'It goes up once @' + mine + ' is on kliner.app. Kliner does that as soon as it can.'
                                      : 'Pick a username first. Your page then lives at kliner.app/@yourname.',
            mine ? null : h('button', { class: 'ef-btn', onclick: () => openSettings('profile') }, 'Pick a username'), 'note'));
        return out;
    }
    const cover = profileCover(sel);
    const keep = () => {
        const value = JSON.stringify(Object.assign({}, sel, { links: sel.links.filter(Boolean), work: sel.work.filter(it => it.name.trim()), url }));
        K.meta.config.profile = value;
        tell('setConfig', { key: 'profile', value });
    };
    const display = h('input', { class: 'field', value: sel.display, maxlength: '60', placeholder: 'Your name', 'aria-label': 'Name on the page',
                                 oninput: e => { sel.display = e.target.value; cover._paint(); } });
    const bio = h('textarea', { class: 'field area', maxlength: '280', rows: '3', placeholder: 'A line about you', 'aria-label': 'About you',
                                oninput: e => { sel.bio = e.target.value; } });
    bio.value = sel.bio;
    const links = sel.links.map((value, n) => h('input', { class: 'field', value, maxlength: '200', placeholder: 'https://…', spellcheck: 'false',
        'aria-label': 'Link ' + (n + 1), oninput: e => { sel.links[n] = e.target.value.trim(); } }));
    const role = h('input', { class: 'field', value: sel.role, maxlength: '60', placeholder: 'What you do',
        'aria-label': 'What you do', oninput: e => { sel.role = e.target.value; } });
    const place = h('input', { class: 'field', value: sel.place, maxlength: '60', placeholder: 'Where you are',
        'aria-label': 'Where you are', oninput: e => { sel.place = e.target.value; } });
    const both = h('div', { class: 'prof-two' }, role, place);
    // One row per thing you made: its name and the year on one line, what it
    // is and where it lives under them. A row with no name is not published.
    const workRows = sel.work.map((it, n) => {
        const put = (key, el, trim) => { el.addEventListener('input', () => { it[key] = trim ? el.value.trim() : el.value; }); return el; };
        const nth = ' ' + (n + 1);
        return h('div', { class: 'wk-row' },
            h('div', { class: 'wk-line' },
                put('name', h('input', { class: 'field wk-name', value: it.name, maxlength: '60', placeholder: 'Something you made', 'aria-label': 'Name' + nth })),
                put('when', h('input', { class: 'field wk-when', value: it.when, maxlength: '20', placeholder: 'Year', 'aria-label': 'Year' + nth }))),
            h('div', { class: 'wk-line' },
                put('note', h('input', { class: 'field wk-note', value: it.note, maxlength: '90', placeholder: 'What it is', 'aria-label': 'What it is' + nth })),
                put('url', h('input', { class: 'field wk-url', value: it.url, maxlength: '200', placeholder: 'https://… (optional)', spellcheck: 'false', 'aria-label': 'Address' + nth }), true)));
    });
    // Only the rows with something in them, and one empty one to write in;
    // the rest come one at a time. Four empty rows of four boxes each, and
    // two empty links, were most of why this part looked busy.
    const growing = (rows, filled, label) => {
        const firstEmpty = rows.findIndex((r, n) => !filled(n));
        rows.forEach((r, n) => { r.hidden = !(filled(n) || n === firstEmpty); });
        const more = h('button', { class: 'btn bare small grow-more', type: 'button' }, icon('plus'), label);
        const paintMore = () => { more.hidden = !rows.some(r => r.hidden); };
        more.addEventListener('click', e => {
            e.preventDefault();
            const next = rows.find(r => r.hidden);
            if (next) { next.hidden = false; (next.querySelector('input') || next).focus(); }
            paintMore();
        });
        paintMore();
        return [...rows, more];
    };
    const tick = (key, label) => {
        const b = h('button', { class: 'tick-chip' + (sel[key] ? ' on' : ''), 'aria-pressed': String(!!sel[key]) }, icon('check'), label);
        b.addEventListener('click', e => { e.preventDefault(); sel[key] = !sel[key]; b.classList.toggle('on', sel[key]); b.setAttribute('aria-pressed', String(sel[key])); cover._paint(); });
        return b;
    };
    const note = h('span', { class: 'prof-note' });
    const publish = h('button', { class: 'btn fill small' }, sel.visible ? 'Publish' : 'Save hidden');
    const visible = switchEl(sel.visible, 'Show my page');
    visible.addEventListener('click', e => {
        e.preventDefault();
        sel.visible = !sel.visible;
        visible.classList.toggle('on', sel.visible);
        visible.setAttribute('aria-checked', String(sel.visible));
        publish.textContent = sel.visible ? 'Publish' : 'Save hidden';
        cover._paint();
    });
    publish.addEventListener('click', async e => {
        e.preventDefault();
        if (publish.disabled) return;
        const https = l => /^https:\/\/[^\s/]+\.[^\s]+$/i.test(l);
        const bad = sel.links.find(l => l && !https(l)) || (sel.work.find(it => it.url && !https(it.url)) || {}).url;
        if (bad) { note.textContent = 'Links start with https://'; note.className = 'prof-note bad'; return; }
        publish.disabled = true;
        note.textContent = 'Reading your Mac…'; note.className = 'prof-note';
        keep();
        const profile = await profileGather(sel);
        note.textContent = 'Publishing…';
        const r = await ask('profilePut', { profile });
        publish.disabled = false;
        if (r && r.ok) {
            if (typeof r.url === 'string' && /^https:\/\//.test(r.url)) { url = r.url; keep(); }
            note.textContent = sel.visible ? 'Live at ' + url.replace(/^https:\/\//, '') : 'Saved. Nobody can see it until you turn it on.';
            note.className = 'prof-note good';
        } else {
            note.textContent = (r && (r.bad || r.text)) || 'Kliner could not reach kliner.app.';
            note.className = 'prof-note bad';
        }
    });
    out.push(cover,
        srow('Show my page', 'Anyone with the link can see it.', visible),
        h('h2', { class: 'set-sub' }, 'Your words'),
        srow('Name', 'Over your @username.', display),
        srow('About you', 'A line or two.', bio),
        srow('What you do, and where', null, both),
        srow('Work', 'Things you made. A row without a name is left out.',
             h('div', { class: 'prof-work' }, growing(workRows, n => !!(sel.work[n].name || sel.work[n].note || sel.work[n].url || sel.work[n].when), 'Add another'))),
        srow('Links', 'They start with https://', h('div', { class: 'prof-links' }, growing(links, n => !!sel.links[n], 'Add a link'))),
        h('h2', { class: 'set-sub' }, 'Besides your words'),
        srow('Show', 'Read from this Mac each time you publish.', h('div', { class: 'ticks' }, tick('picture', 'Picture'), tick('mac', 'This Mac'), tick('setup', 'Setup'))),
        h('div', { class: 'set-foot' }, publish, note, h('span', { class: 'gap' }),
            h('button', { class: 'ef-btn', onclick: () => tell('openProfile', { url }) }, 'Open the page', icon('finder'))));
    // what this Mac is, for the page, while you look at it
    if (!PROFILE_MAC) ask('machine').then(m => { if (m && !m.missing) PROFILE_MAC = m; });
    return out;
}

/** Everything the profile says, read from this Mac now: nothing remembered
 *  from before and nothing filled in for you. */
async function profileGather(sel) {
    const p = { visible: !!sel.visible, display: (sel.display || '').trim(), bio: (sel.bio || '').trim(),
                role: (sel.role || '').trim(), place: (sel.place || '').trim(),
                work: (sel.work || []).map(it => ({
                        name: (it.name || '').trim(), note: (it.note || '').trim(),
                        when: (it.when || '').trim(), url: (it.url || '').trim(),
                    })).filter(it => it.name).map(it => {
                        const one = { name: it.name };
                        if (it.when) one.when = it.when;
                        if (it.note) one.note = it.note;
                        if (it.url) one.url = it.url;
                        return one;
                    }),
                links: sel.links.filter(l => /^https:\/\/[^\s/]+\.[^\s]+$/i.test(l || '')).map(url => ({ title: url.replace(/^https:\/\/(www\.)?/i, '').split('/')[0].slice(0, 40), url })),
                since: new Date().toISOString().slice(0, 10) };
    if (sel.picture && K.meta.portrait) {
        const small = await shrinkPicture(K.meta.portrait, 512, 150000);
        if (small) p.avatar = small;
    }
    const machine = PROFILE_MAC || await ask('machine');
    if (machine && !machine.missing) PROFILE_MAC = machine;
    if (sel.mac && machine) {
        const mac = {};
        for (const k of ['model', 'chip', 'memory', 'macos']) if (machine[k]) mac[k] = String(machine[k]).slice(0, 60);
        if (K.home && K.home.total) mac.storage = size(K.home.total);
        p.mac = mac;
    }
    if (sel.setup) {
        const setup = { appearance: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light' };
        if (machine && typeof machine.dockAutohide === 'boolean') setup.dockAutohide = machine.dockAutohide;
        setup.desktop = K.meta.desktopHidden ? 'icons hidden' : K.home && K.home.desk === 0 ? 'clear' : K.home && K.home.desk ? K.home.desk + ' items' : 'clear';
        if (!K.walls) await readWalls();
        const on = (K.walls || []).find(w => /on now/i.test((w.parts || []).slice(1).join(' ')));
        if (on) setup.wallpaper = String(on.parts[0]).slice(0, 80);
        const big = await ask('wallBig', {});
        if (big && goodPicture(big.picture)) {
            // 1400 is what the Mac hands over, so this keeps it as it is.
            const thumb = await shrinkPicture(big.picture, 1400, 440000);
            if (thumb) setup.wallpaperThumb = thumb;
        }
        p.setup = setup;
        // The Dock, with each app's own icon, so the page draws a real Dock
        // and not a row of letters. Last, and against what is left of the
        // 300 KB kliner.app takes: the icons are the part worth dropping,
        // and an app whose icon does not fit still gets its name. Only the
        // ones the page draws carry a picture at all.
        const dock = await ask('dockApps');
        if (dock && dock.apps) {
            setup.dock = dock.apps.slice(0, 40).map(a => ({ name: String(a.name).slice(0, 40) }));
            let room = PROFILE_ROOM - JSON.stringify(p).length;
            for (let n = 0; n < Math.min(setup.dock.length, DOCK_DRAWN); n++) {
                const art = dock.apps[n].icon;
                if (!goodPicture(art) || room < 9000) continue;
                // 128 is the size macOS hands the icon over at, and the size
                // the page needs to draw it on a Retina screen without it
                // going soft. Anything smaller and it is a preview of an
                // icon, not the icon.
                const small = await shrinkIcon(art, 128, Math.min(26000, room));
                if (!small) continue;
                setup.dock[n].icon = small;
                room -= small.length + 12;
            }
            // The bin closes a real Dock. Last, out of what is left.
            if (goodPicture(dock.trash) && room > 9000) {
                const bin = await shrinkIcon(dock.trash, 128, Math.min(26000, room));
                if (bin) setup.trash = bin;
            }
        }
        // The wallpapers they keep, with the one that is on now marked. Out
        // of whatever is left after the screen and the Dock, which are the
        // page's subject; a wallpaper whose picture does not fit is still
        // named, and a name is a row of the page either way.
        if (K.walls && K.walls.length) {
            const walls = K.walls.slice(0, PROFILE_WALLS).map((w, n) => ({
                name: String((w.parts || [])[0] || '').slice(0, 80),
                on: /on now/i.test((w.parts || []).slice(1).join(' ')),
                at: n + 1,
            })).filter(w => w.name);
            let room = PROFILE_ROOM - JSON.stringify(p).length;
            for (const w of walls) {
                const art = K.wallPics && K.wallPics[w.at];
                if (!goodPicture(art) || room < 20000) { delete w.at; continue; }
                const small = await shrinkPicture(art, 320, Math.min(55000, room));
                delete w.at;
                if (!small) continue;
                w.thumb = small;
                room -= small.length + 16;
            }
            if (walls.length) setup.walls = walls;
        }
    }
    // What Kliner has done here, in min's own words. Nothing is worked out:
    // the lines are the ones `min undo --list` prints, newest first.
    const undoPage = pages().findIndex(pg => pg.kind === 'undo');
    if (undoPage > 0) {
        const seen = await ask('look', { page: undoPage });
        const items = seen && seen.text ? parse(seen.text).filter(it => it.k === 'item') : [];
        const done = items.slice(0, PROFILE_DONE).map(it => {
            const parts = (it.parts || []).map(x => String(x).trim()).filter(Boolean);
            return { what: (parts[0] || '').slice(0, 80), when: (parts[1] || '').slice(0, 40) };
        }).filter(d => d.what);
        if (done.length) p.done = done;
    }
    return p;
}

/* What kliner.app takes for a whole profile, less a little for the words
   around the pictures; and how many apps of the Dock its page draws. The
   room is in characters of JSON, which is about a third more than the bytes
   the pictures weigh, so it stays under the 800 KB the server takes. */
const PROFILE_ROOM = 760000;
const DOCK_DRAWN = 16;
/* How many wallpapers the page draws, and how many of the things Kliner has
   done it lists. Both are the page's own limits, not the server's. */
const PROFILE_WALLS = 8;
const PROFILE_DONE = 10;
/* How many things you can list under Work in Settings. */
const PROFILE_WORK_ROWS = 4;

/** An app's icon, small enough for kliner.app: a PNG at most `side` across,
 *  under `most` characters, or nothing. A PNG, not a JPEG: an icon has
 *  corners it does not fill, and a JPEG would make them black. */
function shrinkIcon(uri, side, most) {
    return new Promise(resolve => {
        const img = new Image();
        img.onload = () => {
            for (const wide of [side, Math.round(side * 0.75), Math.round(side * 0.56)]) {
                const scale = Math.min(1, wide / Math.max(img.width, img.height));
                const c = document.createElement('canvas');
                c.width = Math.max(1, Math.round(img.width * scale));
                c.height = Math.max(1, Math.round(img.height * scale));
                c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
                const out = c.toDataURL('image/png');
                if (out.length <= most) { resolve(out); return; }
            }
            resolve(null);
        };
        img.onerror = () => resolve(null);
        img.src = uri;
    });
}

/** A picture made small enough for kliner.app: a JPEG at most `side` wide,
 *  under `most` characters, or nothing. */
function shrinkPicture(uri, side, most) {
    return new Promise(resolve => {
        const img = new Image();
        img.onload = () => {
            for (const q of [0.82, 0.7, 0.58]) {
                const scale = Math.min(1, side / Math.max(img.width, img.height));
                const c = document.createElement('canvas');
                c.width = Math.max(1, Math.round(img.width * scale));
                c.height = Math.max(1, Math.round(img.height * scale));
                c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
                const out = c.toDataURL('image/jpeg', q);
                if (out.length <= most) { resolve(out); return; }
            }
            resolve(null);
        };
        img.onerror = () => resolve(null);
        img.src = uri;
    });
}

/** Your @username. Claimed, it is the name itself and where it is held,
 *  and Change opens the field. The field asks kliner.app as you type (the
 *  Macs nearby, when kliner.app cannot be reached) and says plainly what it
 *  found: free, somebody's, kept a week for whoever gave it up a moment ago,
 *  or held on kliner.app for whoever has its code, which can be typed in
 *  here. A name on kliner.app already is changed rather than claimed again
 *  (nameClaim): the files on their way follow it, and the old name stays
 *  yours for a week, so changing back is one click. */
function usernameField(editing) {
    const mine = bareName(handle());
    const cloud = nameWhere() === 'cloud';
    const slot = h('span', { class: 'userline' });
    // the name you had, while kliner.app keeps it for you
    const was = bareName(K.meta.config.userWas), wasUntil = +(K.meta.config.userWasUntil || 0);
    const kept = cloud && was && was !== mine && wasUntil * 1000 > Date.now();
    const edit = want => {
        const fresh = usernameField(true);
        slot.replaceWith(fresh);
        const f = fresh.querySelector('input');
        if (f && want) { f.value = want; f.dispatchEvent(new Event('input')); }
    };
    // the way Dan's picture has it: the address it lives at, the name in
    // it, and a tick once it is yours there
    if (mine && !editing) {
        slot.append(h('span', { class: 'ugroup' }, h('span', { class: 'ug-pre' }, 'kliner.app/@'), h('span', { class: 'ug-v' }, mine),
                h('span', { class: 'ug-ok ' + nameWhere(), title: cloud ? 'Yours on kliner.app' : 'Yours on this Mac' },
                    cloud ? icon('check') : 'this Mac only')),
            h('button', { class: 'ef-btn', onclick: e => { e.preventDefault(); edit(''); } }, 'Change'));
        if (kept) {
            slot.append(h('span', { class: 'unote kept' }, '@' + was + ' is kept for you until ' + untilDay(wasUntil) + '. ',
                h('button', { class: 'link', onclick: e => { e.preventDefault(); edit(was); } }, 'Change back')));
        }
        return slot;
    }
    const field = h('input', { class: 'field', value: mine, placeholder: 'yourname', spellcheck: 'false', autocapitalize: 'off',
                               autocomplete: 'off', maxlength: '21', 'aria-label': 'Username' });
    const sign = h('span', { class: 'ustat' });
    const note = h('span', { class: 'unote' });
    const code = h('input', { class: 'field ucode', placeholder: 'Code from kliner.app', maxlength: '11', spellcheck: 'false',
                              autocapitalize: 'characters', autocomplete: 'off', hidden: true, 'aria-label': 'Code from kliner.app' });
    const claim = h('button', { class: 'btn fill small', hidden: true }, 'Claim');
    // the code and its button get a line of their own, under the name
    const codeLine = h('span', { class: 'ucodeline', hidden: true }, code);
    const cancel = mine ? h('button', { class: 'ef-btn', onclick: e => { e.preventDefault(); slot.replaceWith(usernameField(false)); } }, 'Cancel') : null;
    const ideas = h('span', { class: 'uideas small off' });
    const pickIdea = x => { field.value = x; field.focus(); paint(); };
    // what the button does for the name in the field: changes your name on
    // kliner.app, claims it, or claims it with the code kliner.app showed
    let mode = '', timer = 0, asked = 0;
    const moving = () => [...SEND.jobs.values()].some(j => ACTIVE.includes(j.state));
    const say = (text, tone) => {
        note.textContent = text;
        note.className = 'unote' + (tone ? ' ' + tone : '');
        sign.className = 'ustat ' + (tone === 'wait' ? 'wait' : tone || '');
        sign.replaceChildren(tone === 'wait' ? h('i', { class: 'spin' }) : tone === 'good' ? icon('check') : tone === 'bad' ? icon('x') : '');
    };
    const offer = (label, how) => {
        mode = how;
        claim.textContent = label;
        claim.hidden = false;
        claim.disabled = how === 'code' ? codeTyped(code.value).length < 11 : false;
        codeLine.hidden = how !== 'code';
        code.hidden = how !== 'code';
        if (how === 'code') codeLine.append(claim);
        else if (claim.parentElement !== slot) slot.insertBefore(claim, cancel || note);
    };
    const paint = () => {
        const want = bareName(field.value);
        claim.hidden = true;
        code.hidden = true;
        codeLine.hidden = true;
        mode = '';
        ideas.classList.add('off');
        IDEAS.asked++;
        clearTimeout(timer);
        if (!want) { say(mine ? '' : 'How people send you files, from anywhere.', ''); return; }
        if (want === mine) { say('Yours', 'good'); return; }
        const trouble = nameTrouble(want);
        if (trouble) { say(trouble, 'bad'); return; }
        say('Looking…', 'wait');
        const n = ++asked;
        timer = setTimeout(async () => {
            const r = await nameLook(want);
            if (n !== asked) return;
            if (!r || r.missing || !r.ok) { say((r && r.bad) || 'Kliner could not check that.', 'bad'); return; }
            if (r.mine) { say('Yours', 'good'); return; }
            if (r.taken) {
                say(r.local ? 'A Mac nearby has it' : 'Somebody has it', 'bad');
                if (!r.local) offerIdeas(want, ideas, pickIdea);
                return;
            }
            if (r.held && r.yours) { say('Your old name, kept for you until ' + untilDay(r.until), 'good'); offer('Change back', 'name'); return; }
            if (r.held) { say('Kept until ' + untilDay(r.until) + ' for whoever gave it up', 'bad'); return; }
            if (r.claimed) {
                say('Held on kliner.app until ' + untilDay(r.until) + '. If you held it, type its code.', '');
                offer('Claim with code', 'code');
                return;
            }
            if (cloud && mine && moving()) { say('Free. Change to it once your files on their way have arrived.', ''); return; }
            say(r.local ? 'Free nearby' : cloud && mine ? 'Free. @' + mine + ' stays yours for 7 days.' : 'Free', 'good');
            offer(cloud && mine ? 'Change to @' + want : 'Claim', 'name');
        }, 350);
    };
    claim.addEventListener('click', async e => {
        e.preventDefault();
        const want = bareName(field.value);
        claim.disabled = true;
        say(cloud && mine ? 'Changing…' : 'Claiming…', 'wait');
        const r = await nameClaim(want, mode === 'code' ? codeTyped(code.value) : '');
        claim.disabled = false;
        if (r && r.ok && r.user) {
            K.meta.config.user = r.user;
            burst(slot);
            toast(r.was ? 'You are @' + r.user + ' now. @' + r.was + ' is kept for you until ' + untilDay(r.until) + '.'
                : r.local ? 'You are @' + r.user + ' on this Mac. Kliner claims it on kliner.app as soon as it can.'
                : 'You are @' + r.user + '. Anyone with Kliner can send you files.', null);
            drawFrame();
            drawPage(true);
        } else if (r && r.wrongCode) { say('That code does not hold @' + want + '. Check it and try again.', 'bad'); code.focus(); }
        else if (r && r.claimed) { say('Held on kliner.app. If you held it, type its code.', ''); offer('Claim with code', 'code'); code.focus(); }
        else if (r && r.taken) say(r.local ? 'A Mac nearby has it' : 'Somebody has it', 'bad');
        else say((r && (r.bad || r.text)) || 'Kliner could not claim that.', 'bad');
    });
    field.addEventListener('input', () => { field.value = field.value.replace(/^@+/, '').replace(/\s+/g, '').toLowerCase(); paint(); });
    field.addEventListener('keydown', e => { if (e.key === 'Enter' && !claim.hidden && !claim.disabled) { e.preventDefault(); claim.click(); } });
    code.addEventListener('input', () => {
        const typed = codeTyped(code.value);
        if (typed !== code.value) code.value = typed;
        if (mode === 'code') claim.disabled = typed.length < 11;
    });
    code.addEventListener('keydown', e => { if (e.key === 'Enter' && !claim.disabled) { e.preventDefault(); claim.click(); } });
    paint();
    if (editing) setTimeout(() => field.focus(), 30);
    slot.append(h('span', { class: 'ufield ugroup' }, h('span', { class: 'ug-pre' }, 'kliner.app/@'), field, sign), claim, cancel, codeLine, note, ideas);
    return slot;
}

function setting(t, d, control) {
    return h('div', { class: 'set' }, h('div', null, h('div', { class: 't' }, t), d ? h('div', { class: 'd' }, d) : null), control);
}

function seg(values, current, pick, label) {
    const box = h('div', { class: 'seg' });
    for (const v of values) {
        box.append(h('button', { class: v === current ? 'on' : '', onclick: e => {
            for (const b of box.querySelectorAll('button')) b.classList.remove('on');
            e.currentTarget.classList.add('on');
            segGlide(box);
            pick(v);
        } }, label ? label(v) : v));
    }
    segGlide(box);
    return box;
}

/* ── Help ─────────────────────────────────────────────────────────────── */

/** Help is a part of Settings, drawn on its own page so ? and the light in
 *  the sidebar still say where you are. */
function drawHelp(out) {
    return drawSettings(out);
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
    if (pop && !pop.contains(e.target) && !e.target.closest('#state')) pop.remove();
});

let toastTimer = 0;
/** A line at the bottom of the window. `mark` 'x' is for what did not work. */
function toast(text, action, mark) {
    // a new one takes the old one's place at once; one on its own time
    // goes the way it came (leave)
    for (const old of document.querySelectorAll('.toast')) old.remove();
    clearTimeout(toastTimer);
    const bad = mark === 'x';
    const el = h('div', { class: 'toast' + (bad ? ' bad' : '') }, icon(mark || 'check'), h('span', null, text),
        action ? h('button', { class: 'btn line small', onclick: () => { leave(el); action[1](); } }, action[0]) : null);
    document.body.append(el);
    toastTimer = setTimeout(() => leave(el), 7000);
}

/* ── Activity: what the Mac is doing, every two seconds ──────────────── */

const LIVE = { timer: 0, cpu: [], mem: [], by: 'cpu', last: null };

function stopActivity() {
    clearTimeout(LIVE.timer);
    LIVE.timer = 0;
}

function drawActivity(out) {
    out.append(h('div', { class: 'head' }, pageTile('pulse'),
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
    segGlide(seg);
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

/** One reading of the Mac, kept: the last minute of it is what Activity and
 *  the finder both draw. */
function pushLive(reply) {
    LIVE.last = reply;
    LIVE.cpu.push(reply.cpu);
    const m = reply.memory || {};
    LIVE.mem.push(m.total > 0 ? m.used / m.total * 100 : 0);
    if (LIVE.cpu.length > 60) LIVE.cpu.shift();
    if (LIVE.mem.length > 60) LIVE.mem.shift();
}

async function tickActivity() {
    if (K.page !== ACTIVITY()) return;
    const reply = await ask('activity');
    if (K.page !== ACTIVITY()) return;
    if (reply && typeof reply.cpu === 'number') {
        pushLive(reply);
        paintActivity();
    }
    // quicker at first, so the charts fill in while you are looking at them
    LIVE.timer = setTimeout(tickActivity, LIVE.cpu.length < 12 ? 1000 : 2000);
}

function drawSpark(id, values) {
    const svg = document.getElementById(id);
    if (!svg || !values.length) return;
    // spread across the width from the first reading, closing up as more
    // arrive, the same way the line in ⌘K is drawn
    const w = 300, hgt = 60;
    const span = Math.max(1, values.length - 1);
    if (values.length === 1) values = [values[0], values[0]];
    const pts = values.map((v, k) => [w - (values.length - 1 - k) * (w / Math.max(1, span)), hgt - 3 - Math.max(0, Math.min(100, v)) / 100 * (hgt - 8)]);
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
    // a reading without the memory in it says so, rather than "0 B of 0 B"
    const m = r.memory || {};
    const known = m.total > 0;
    memN.textContent = known ? size(m.used || 0) : '–';
    $('#memU').textContent = known ? 'used of ' + size(m.total) : 'not read yet';
    $('#memBar').style.width = (known ? m.used / m.total * 100 : 0).toFixed(1) + '%';
    drawSpark('cpuS', LIVE.cpu);
    drawSpark('memS', LIVE.mem);
    for (const b of document.querySelectorAll('#bySeg button')) b.classList.toggle('on', b.textContent.toLowerCase() === LIVE.by);
    if ($('#bySeg')) segGlide($('#bySeg'));

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

/* ── the first minute: your Mac, in miniature ─────────────────────────── */

/* The starter draws your Mac small: your own wallpaper, a menu bar with
   Kliner in it, what is on your desktop, and your Dock with its icons. Each
   step tidies one part of that picture, for real, and the last step shows
   all of it done. Nothing in it is made up: every icon, name and picture is
   read from this Mac, and a part that has not been read yet is left plain. */

const INTRO = ['hello', 'access', 'desk', 'dock', 'wall', 'account', 'done'];

/* each of macOS's questions, by the picture Swift sends: the folder's name
   as Finder shows it, and the glyph on the folder */
const GATE_ART = {
    'menubar.dock.rectangle': ['Desktop', 'desk'],
    'arrow.down.circle': ['Downloads', 'download'],
    'photo': ['Pictures', 'photo'],
    'doc.text': ['Documents', 'file'],
    'bell': ['Notifications', 'bell'],
};

/* how many things the small desktop draws before it says how many more */
const DESK_MAX = 28;

const PICTURE = /^data:image\/(jpeg|png);base64,[A-Za-z0-9+/=]+$/;
const goodPicture = uri => typeof uri === 'string' && PICTURE.test(uri);
const pause = ms => new Promise(r => setTimeout(r, ms));
const calm = () => window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

function startWelcome() {
    const cfg = K.meta.config;
    const first = String(K.meta.user || '').trim().split(/\s+/)[0] || '';
    K.welcome = { step: 0, shown: -1, back: false, name: cfg.name || first,
                  tidy: cfg.tidy || 'Tidy', email: K.meta.email || '', login: !!(K.meta.login && K.meta.login.on),
                  answers: {}, asking: -1, read: false, popped: {},
                  desk: null, deskShut: false, deskPics: {}, didDesk: false,
                  dock: null, dockReading: false, dropped: new Set(), dockGone: 0,
                  adding: new Set(), more: null, moreReading: false, moreFailed: false, shelf: false, dockAdded: 0,
                  wallPic: '', wallAt: 0, wallName: '',
                  pal: { open: false, q: '', at: 0, rows: [], touched: false, token: 0, focus: false },
                  renaming: null, mailWarn: false, busy: false,
                  user: bareName(cfg.user), want: bareName(cfg.user), uState: cfg.user ? 'mine' : '', uNote: '',
                  uBusy: false, uAsked: 0, uTimer: 0, later: null };
    drawWelcome();
    // The Dock is in no folder macOS guards, so it is read while you say hello.
    readDockApps();
}

function introGo(by) {
    const w = K.welcome;
    if (!w) return;
    w.back = by < 0;
    w.step = Math.max(0, Math.min(INTRO.length - 1, w.step + by));
    // Past the step that asks about folders, what is in them can be read
    // without macOS asking a question out of turn.
    if (w.step > INTRO.indexOf('access')) introRead();
    drawWelcome();
}

/** A step drawn again when what it shows has arrived, if it is on screen. */
function redrawIf(...steps) {
    const w = K.welcome;
    if (w && steps.includes(INTRO[w.step])) drawWelcome();
}

/** True the first time something is drawn with what it shows, so it arrives
 *  once, and a step drawn again does not play it again. */
function popOnce(key, ready) {
    const w = K.welcome;
    if (!ready || w.popped[key]) return false;
    w.popped[key] = true;
    return !calm();
}

function drawWelcome() {
    const w = K.welcome;
    const app = $('#app');
    app.className = 'app';
    app.style.gridTemplateColumns = '1fr';
    const step = INTRO[w.step];
    const fresh = w.shown !== w.step;
    w.shown = w.step;
    if (stageFit) stageFit.disconnect();

    const card = h('section', { class: 'st-card s-' + step + (fresh ? ' enter' + (w.back ? ' back' : '') : '') });
    const top = h('header', { class: 'st-head' });
    const stage = h('div', { class: 'st-stage' });
    const under = h('div', { class: 'st-under' });
    const head = (title, sub) => top.append(...[h('h1', null, title), sub ? h('p', { class: 'lead' }, sub) : null].filter(Boolean));
    // The main button of a step. Its words live in a span of their own, so a
    // step can change what it says without drawing the step again.
    const next = (label, go) => h('button', { class: 'btn fill large', onclick: go || (() => introGo(1)) },
                                  h('span', { class: 'lbl' }, label || 'Continue'), icon('right'));
    const bare = (label, go) => h('button', { class: 'btn bare large', onclick: go }, label);
    const extras = [];
    let primary = null;

    if (step === 'hello') {
        // the eyes land, the words come one after another, then what Kliner
        // does and the one way on
        const title = h('h1', { class: 'hello-t' });
        'Hey, I’m Kliner.'.split(' ').forEach((word, n) => title.append(h('span', { class: 'w', style: `--i:${n}` }, word), ' '));
        const does = h('div', { class: 'hello-does' }, ...[
            ['desk', 'Tidy your desktop'], ['sparkles', 'Free up space'], ['photo', 'New wallpapers'], ['send', 'Files to any @username'],
        ].map(([sym, t], n) => h('span', { class: 'hd', style: `--i:${n}` }, icon(sym), t)));
        primary = next('Get started');
        top.append(h('div', { class: 'hello-eyes' }, eyesMark('glance blinks')), title,
                   h('p', { class: 'lead' }, 'I keep your Mac tidy.'), does,
                   h('div', { class: 'go' }, primary, h('span', { class: 'go-key' }, 'or press', h('kbd', null, '↵'))));
    } else if (step === 'access') {
        const gates = K.meta.gates || [];
        const done = gates.every((_, n) => n in w.answers);
        head('Let Kliner see your files.');
        const row = h('div', { class: 'acc-row' });
        gates.forEach((g, n) => {
            const art = GATE_ART[g.symbol];
            const label = art ? art[0] : capital(String(g.title || '').replace(/^your /i, ''));
            let state;
            if (n in w.answers) {
                state = w.answers[n] ? h('span', { class: 'st yes' }, icon('check'), 'Allowed')
                                     : h('span', { class: 'st' }, 'Not allowed');
            } else if (w.asking === n) {
                state = h('span', { class: 'st' }, h('i', { class: 'spin' }));
            } else {
                state = h('button', { class: 'btn line small', disabled: w.asking >= 0 ? '' : null, onclick: () => askGate(n) }, 'Allow');
            }
            row.append(h('div', { class: 'acc' + (w.answers[n] ? ' yes' : '') + (fresh && !calm() ? ' st-pop' : ''),
                                  style: fresh ? `animation-delay:${40 + n * 45}ms` : null },
                g.symbol === 'bell' ? bellArt() : folderArt(art ? art[1] : 'folder'),
                h('b', null, label), state));
        });
        stage.append(row);
        primary = done ? next()
            : h('button', { class: 'btn fill large', disabled: w.asking >= 0 ? '' : null, onclick: askAll },
                h('span', { class: 'lbl' }, 'Allow all'));
        if (!done) extras.push(bare('Later', () => introGo(1)));
    } else if (step === 'desk') {
        const hidden = !!(K.meta && K.meta.desktopHidden);
        const items = w.desk;
        const n = items ? items.length : 0;
        if (hidden) head('Perfectly clean.');
        else if (w.didDesk) head('Desktop clear.');
        else if (w.deskShut) head('Kliner cannot see your desktop yet.');
        else if (items && !n) head('Your desktop is clear.');
        else head('Clear your desktop.', n ? 'Click a name to rename it.' : null);
        stage.append(macScreen({ pop: popOnce('desk', !!items), edit: !hidden && !w.deskShut }));
        if (hidden) {
            primary = next();
        } else if (w.didDesk || !items || (!n && !w.deskShut)) {
            primary = next();
        } else if (w.deskShut) {
            primary = next('Allow', introSeeDesk);
            extras.push(bare('Later', () => introGo(1)));
        } else {
            primary = next('Tidy ' + plural(n, 'thing'), introTidy);
            extras.push(bare('Later', () => introGo(1)));
        }
    } else if (step === 'dock') {
        const d = w.dock;
        head(w.dockGone || w.dockAdded ? 'Your Dock is set.' : 'Keep only what you use.');
        stage.append(dockStage(fresh));
        // the other half of a clean Dock: one that is not there until you
        // reach for it, and then is, at once
        under.append(h('label', { class: 'tog dockfast' + (w.dockFastBusy ? ' busy' : '') },
            h('button', { class: 'switch' + (w.dockFast ? ' on' : ''), role: 'switch', 'aria-checked': String(!!w.dockFast),
                          'aria-label': 'Hide the Dock until you reach for it', disabled: w.dockFastBusy ? '' : null, onclick: introDockFast }),
            h('span', null, 'Hide the Dock until you reach for it'),
            h('span', { class: 'sub' }, w.dockFast ? 'Move to the bottom edge and it is there at once.' : '')));
        primary = next(d && d.apps.length ? dockLabel() : 'Continue', introDockKeep);
    } else if (step === 'wall') {
        head('Pick a wallpaper.');
        stage.append(macScreen({}));
        under.append(wallStrip());
        primary = next();
    } else if (step === 'account') {
        const mine = w.uState === 'mine';
        head(mine ? 'Your Kliner account.' : 'Create your Kliner account.',
             'Your name, and the @username anyone with Kliner sends you files by, near or far.');
        stage.append(accountStage(fresh));
        primary = next(mine ? 'Continue' : 'Create account', introAccount);
        extras.push(w.later = bare('Skip the username', introSkipName));
    } else {
        const name = capital((w.name || '').trim());
        head(name ? `All set, ${name}.` : 'All set.');
        top.append(h('p', { class: 'lead st-keys' }, h('kbd', null, '⌘'), h('kbd', null, 'K'), ' anywhere'));
        stage.append(macScreen({ done: true }));
        primary = h('button', { class: 'btn fill large open-kl', 'aria-label': 'Open Kliner', onclick: () => finishWelcome() },
                    h('span', { class: 'lbl' }, 'Open', wordMark()), icon('right'));
    }
    w.primary = primary;

    const way = h('footer', { class: 'way' });
    if (step !== 'hello') {
        way.append(h('button', { class: 'btn bare large back', onclick: () => introGo(-1) }, icon('left'), 'Back'),
                   h('span', { class: 'gap' }), ...extras, primary);
    }
    card.append(top);
    if (stage.childNodes.length) card.append(stage);
    if (under.childNodes.length) card.append(under);
    card.append(way);

    const dots = h('div', { class: 'dots' + (fresh ? ' fresh' : ''), role: 'img', 'aria-label': 'Step ' + (w.step + 1) + ' of ' + INTRO.length },
        INTRO.map((_, n) => h('i', { class: n === w.step ? 'on' : n < w.step ? 'past' : '' })));
    app.replaceChildren(h('div', { class: 'intro', style: 'grid-column:1/-1' }, dots, card));
    for (const el of app.querySelectorAll('.st-stage')) {
        fitStage(el);
        if (stageFit) stageFit.observe(el);
    }
    const strip = $('.wstrip');
    if (strip) centreOn(strip, strip.querySelector('.wt.on'));
    if (step === 'account') {
        userPaint();
        // the first box that still wants something
        if (fresh) setTimeout(() => {
            const f = $(!String(w.name || '').trim() ? '#name' : !looksLikeEmail(w.email) ? '#mail' : w.uState === 'mine' ? null : '#uname');
            if (f) f.focus();
        }, 60);
    }
    if (step === 'done') palMount(fresh);
    reportChrome();
}

/* ── what the starter reads, and when ── */

/** Everything the rest of the starter draws: your desktop, the wallpaper on
 *  your screen, and the wallpapers there are to pick from. Read once, after
 *  the folders have been asked about, so macOS asks nothing out of turn. */
function introRead() {
    const w = K.welcome;
    if (!w || w.read) return;
    w.read = true;
    readDesk();
    ask('wallBig', {}).then(r => {
        const now = K.welcome;
        if (!now || now.wallPic || !r || !goodPicture(r.picture)) return;
        now.wallPic = r.picture;
        fillScreens();
    });
    readWalls();
}

/** What is on the desktop, newest first, and a picture for each: its own
 *  for a picture, the icon Finder draws for everything else. */
async function readDesk() {
    const w = K.welcome;
    const page = pages().findIndex(p => p.kind === 'desktop');
    if (!(page > 0)) { w.desk = []; redrawIf('desk'); return; }
    K.listing = {};
    const items = await listing(page);
    if (!K.welcome) return;
    const got = K.listing && K.listing[page];
    w.deskShut = !!(got && got.shut);
    w.desk = w.deskShut ? [] : items.filter(countedByNimo).sort((a, b) => (b.modified || 0) - (a.modified || 0));
    redrawIf('desk', 'wall', 'done');
    const want = w.desk.slice(0, DESK_MAX).map(f => f.name).filter(name => !(name in w.deskPics));
    for (let at = 0; at < want.length; at += 12) {
        const reply = await ask('thumbs', { page, names: want.slice(at, at + 12), icons: true });
        if (!K.welcome) return;
        const got_ = (reply && reply.thumbs) || {};
        for (const [name, uri] of Object.entries(got_)) if (goodPicture(uri)) w.deskPics[name] = uri;
        fillScreens();
    }
}

/** Your Dock, with the icon of every app in it. */
async function readDockApps() {
    const w = K.welcome;
    if (!w || w.dockReading) return;
    w.dockReading = true;
    const reply = await ask('dockApps', {});
    if (!K.welcome) return;
    let apps = reply && Array.isArray(reply.apps)
        ? reply.apps.filter(a => a && typeof a.name === 'string' && a.name)
                    .map(a => ({ name: a.name, icon: goodPicture(a.icon) ? a.icon : '' }))
        : [];
    // A Kliner whose nimo cannot list paths yet: the names nimo lists, drawn
    // without their icons rather than not at all.
    if (!apps.length) apps = await dockNames();
    if (!K.welcome) return;
    w.dock = { apps, finder: goodPicture(reply && reply.finder) ? reply.finder : '',
               trash: goodPicture(reply && reply.trash) ? reply.trash : '' };
    w.dockReading = false;
    redrawIf('desk', 'dock', 'wall', 'done');
}

async function dockNames() {
    const page = pages().findIndex(p => p.kind === 'dock');
    const reply = page > 0 ? await ask('look', { page }) : null;
    return reply && reply.text
        ? parse(reply.text).filter(p => p.k === 'item').map(p => ({ name: p.parts[0], icon: '' })).filter(a => a.name).slice(0, 40)
        : [];
}

/** Pictures that arrived after the screen was drawn, laid in where they
 *  belong without drawing anything again. */
function fillScreens() {
    const w = K.welcome;
    if (!w) return;
    for (const el of document.querySelectorAll('.mac-desk .di[data-name]')) {
        const uri = w.deskPics[el.dataset.name];
        if (uri && !el.classList.contains('got')) deskPicture(el, uri);
    }
    if (w.wallPic) for (const box of document.querySelectorAll('.mac-wall, .dockstage .ground, .idc-wall')) wallPicture(box, w.wallPic);
    // and the light round the small screen takes the wallpaper's colour
    if (w.wallPic) glowFrom(w.wallPic);
}

/* ── the small screen ── */

/* Everything inside the screen is measured in em, and an em is a hundredth
   of the screen's width: the screen is sized to the room there is for it,
   and all of it grows and shrinks together. */
const stageFit = typeof ResizeObserver === 'function'
    ? new ResizeObserver(list => { for (const e of list) fitStage(e.target); }) : null;

function fitStage(stage) {
    const W = stage.clientWidth, H = stage.clientHeight;
    if (!W || !H) return;
    for (const el of stage.children) {
        if (el.classList.contains('mac')) {
            const size = Math.max(260, Math.min(W, H * 1.6, 800));
            el.style.width = size + 'px';
            el.style.fontSize = (size / 100).toFixed(3) + 'px';
        } else if (el.classList.contains('dockstage')) {
            el.style.width = Math.max(320, Math.min(W, H * 16 / 7, 800)) + 'px';
        }
    }
}

function macScreen(o) {
    const w = K.welcome;
    const scr = h('div', { class: 'mac' + (o.done ? ' done' : '') + (o.done && w.pal.open ? ' pal' : '') });
    const wall = h('div', { class: 'mac-wall' });
    if (w.wallPic) wallPicture(wall, w.wallPic);
    const now = new Date();
    const clock = now.toLocaleDateString('en-US', { weekday: 'short' }) + ' '
        + now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    // on the last step it is what it is in your menu bar: click it, and
    // the search opens
    const kl = h('span', { class: 'kl' + (o.done && !calm() ? ' ping' : ''), onclick: o.done ? () => palToggle(true) : null,
                           title: o.done ? 'Kliner  ⌘K' : null }, eyesMark());
    if (o.done) kl.append(h('span', { class: 'call' }, '⌘K'));
    scr.append(wall,
        h('div', { class: 'mac-bar' }, h('span', { class: 'menus' }, h('i'), h('i'), h('i'), h('i'), h('i')),
          h('span', { class: 'gap' }), kl, h('span', { class: 'clock' }, clock)),
        deskLayer(o.pop, o.edit), smallDock());
    if (o.done) scr.append(palLayer());
    if (o.edit || (K.meta && K.meta.desktopHidden && INTRO[w.step] === 'desk')) {
        const hidden = !!(K.meta && K.meta.desktopHidden);
        scr.append(h('button', { class: 'mac-hint', onclick: introIcons, title: hidden ? 'Show the files' : 'Hide the files' },
            h('kbd', null, '\\'), hidden ? 'shows your files' : 'hides your files'));
    }
    return scr;
}

function wallPicture(box, uri) {
    const had = [...box.querySelectorAll('img')];
    if (had.length && had[had.length - 1].getAttribute('src') === uri) return;
    const img = h('img', { src: uri, alt: '' });
    if (had.length && !calm()) {
        img.classList.add('fadein');
        setTimeout(() => had.forEach(el => el.remove()), 600);
    } else {
        had.forEach(el => el.remove());
    }
    box.append(img);
}

/** What is on the desktop: as it is, the one folder it was filed into, or
 *  nothing at all while Finder is not drawing icons. */
function deskLayer(pop, edit) {
    const w = K.welcome;
    const layer = h('div', { class: 'mac-desk' });
    if (K.meta && K.meta.desktopHidden) return layer;
    if (w.didDesk) {
        layer.append(h('div', { class: 'di tidy' + (popOnce('tidy', true) ? ' land' : '') },
            h('span', { class: 'dp' }, folderArt('')), h('span', { class: 'dn' }, tidyName())));
    }
    const items = w.desk || [];
    const room = w.didDesk ? DESK_MAX - 1 : DESK_MAX;
    const shown = items.length > room ? items.slice(0, room - 1) : items;
    shown.forEach((f, n) => layer.append(deskIcon(f, n, pop, edit)));
    if (shown.length < items.length) {
        layer.append(h('div', { class: 'di more' + (pop ? ' st-pop' : ''), style: pop ? `animation-delay:${80 + shown.length * 26}ms` : null },
            h('span', { class: 'dp' }, h('b', null, '+' + (items.length - shown.length))), h('span', { class: 'dn' }, 'more')));
    }
    return layer;
}

function deskIcon(f, n, pop, edit) {
    const el = h('div', { class: 'di' + (pop ? ' st-pop' : '') + (edit ? ' can' : ''), 'data-name': f.name, title: f.name,
                          style: pop ? `animation-delay:${80 + n * 26}ms` : null },
        h('span', { class: 'dp' }, fileArt(f)), h('span', { class: 'dn' }, f.name));
    const uri = K.welcome.deskPics[f.name];
    if (uri) deskPicture(el, uri);
    if (edit) {
        // Finder's own manners: a click picks it and opens its name,
        // Return does the same from the keyboard
        el.tabIndex = 0;
        el.setAttribute('role', 'button');
        el.setAttribute('aria-label', 'Rename ' + f.name);
        el.addEventListener('click', e => { if (!e.target.closest('.dn-edit')) deskRename(el, f); });
        el.addEventListener('keydown', e => {
            if (e.key !== 'Enter' || e.target !== el) return;
            e.preventDefault();
            e.stopPropagation();
            deskRename(el, f);
        });
    }
    return el;
}

function deskPicture(el, uri) {
    const box = el.querySelector('.dp');
    box.replaceChildren(h('img', { src: uri, alt: '', class: uri.startsWith('data:image/jpeg') ? 'photo' : 'icon' }));
    el.classList.add('got');
}

/** Until Finder's own icon arrives: a folder, or a page with its kind on it. */
function fileArt(f) {
    if (f.dir && !/\.app$/i.test(f.name)) return folderArt('');
    const dot = f.name.lastIndexOf('.');
    const ext = dot > 0 ? f.name.slice(dot + 1).toUpperCase().slice(0, 4) : '';
    return h('span', { class: 'paper' }, h('i', null, ext));
}

/** The Dock along the bottom of the small screen: Finder, your apps, a line,
 *  and the Trash, the way every Dock is. It answers the pointer the way the
 *  real one does — the icons under it grow — and an icon you click hops. */
function smallDock() {
    const w = K.welcome;
    const d = w.dock;
    const dock = h('div', { class: 'mac-dock' });
    if (!d) return dock;
    const all = (d.finder ? 1 : 0) + d.apps.length + (d.trash ? 1 : 0);
    // the real Dock makes its icons smaller before it runs off the screen
    dock.style.setProperty('--ds', Math.min(4.2, 82 / Math.max(1, all)).toFixed(2) + 'em');
    const tile = a => h('span', { class: 'dt', title: a.name, onclick: e => hop(e.currentTarget) }, appArt(a));
    if (d.finder) dock.append(tile({ name: 'Finder', icon: d.finder }));
    d.apps.forEach(a => dock.append(tile(a)));
    if (d.trash) dock.append(h('span', { class: 'dsep' }), tile({ name: 'Trash', icon: d.trash }));
    magnify(dock, '.dt', 1.75);
    return dock;
}

/** The Dock's own manners: the icon under the pointer grows, and the ones
 *  beside it less and less, out to two and a half icons either side, the
 *  way macOS magnifies its Dock. The width grows with it, so the row opens
 *  up around the icon instead of covering its neighbours. */
function magnify(dock, sel, most) {
    if (!dock || calm()) return;
    dock.classList.add('mag');
    let raf = 0, x = 0;
    const paint = () => {
        raf = 0;
        for (const el of dock.querySelectorAll(sel)) {
            const r = el.getBoundingClientRect();
            const base = r.width / (parseFloat(el.style.getPropertyValue('--mag')) || 1);
            if (!base) continue;
            const d = Math.abs(x - (r.left + r.width / 2)) / base;
            const k = d >= 2.5 ? 0 : Math.cos(d / 2.5 * Math.PI / 2);
            el.style.setProperty('--mag', (1 + (most - 1) * k * k).toFixed(3));
        }
    };
    dock.addEventListener('mousemove', e => { x = e.clientX; if (!raf) raf = requestAnimationFrame(paint); });
    dock.addEventListener('mouseleave', () => {
        cancelAnimationFrame(raf);
        raf = 0;
        for (const el of dock.querySelectorAll(sel)) el.style.removeProperty('--mag');
    });
}

/** An icon in a Dock, clicked: it hops, the way an app does as it opens. */
function hop(el) {
    if (!el || calm()) return;
    el.classList.remove('hop');
    void el.offsetWidth;
    el.classList.add('hop');
    setTimeout(() => el.classList.remove('hop'), 800);
}

function appArt(a) {
    if (a.icon) return h('img', { src: a.icon, alt: '' });
    return h('span', { class: 'noicon' }, (a.name || '?').charAt(0).toUpperCase());
}

let artId = 0;

/** A folder the way Finder draws one, with the glyph of what it holds. */
function folderArt(glyph) {
    const id = 'art' + (++artId);
    const svg = s('svg', { class: 'folder-art', viewBox: '0 0 64 50', 'aria-hidden': 'true' },
        s('defs', null,
          s('linearGradient', { id: id + 'b', x1: '0', y1: '0', x2: '0', y2: '1' },
            s('stop', { offset: '0', 'stop-color': '#8ad3fc' }), s('stop', { offset: '1', 'stop-color': '#48abef' })),
          s('linearGradient', { id: id + 't', x1: '0', y1: '0', x2: '0', y2: '1' },
            s('stop', { offset: '0', 'stop-color': '#62baf4' }), s('stop', { offset: '1', 'stop-color': '#3a95de' }))),
        s('path', { d: 'M5 6.5A3.5 3.5 0 0 1 8.5 3h13.3c1 0 1.9.4 2.6 1.1L27.5 7h28A3.5 3.5 0 0 1 59 10.5V16H5z', fill: `url(#${id}t)` }),
        s('rect', { x: '3', y: '11', width: '58', height: '36', rx: '4', fill: `url(#${id}b)` }),
        s('rect', { x: '4', y: '11.4', width: '56', height: '1', rx: '.5', fill: '#ffffff', 'fill-opacity': '.55' }));
    if (glyph && PATHS[glyph]) {
        const g = s('g', { transform: 'translate(21.8 18.8) scale(.85)', fill: 'none', stroke: '#2a7fc4',
                           'stroke-width': '2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-opacity': '.9' });
        PATHS[glyph].forEach(d => g.append(s('path', { d })));
        svg.append(g);
    }
    return svg;
}

/** Notifications have no folder: the red square with a bell that System
 *  Settings shows for them. */
function bellArt() {
    const id = 'art' + (++artId);
    const g = s('g', { transform: 'translate(19.4 12.4) scale(1.05)', fill: 'none', stroke: '#ffffff',
                       'stroke-width': '2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
    PATHS.bell.forEach(d => g.append(s('path', { d })));
    return s('svg', { class: 'folder-art', viewBox: '0 0 64 50', 'aria-hidden': 'true' },
        s('defs', null, s('linearGradient', { id, x1: '0', y1: '0', x2: '0', y2: '1' },
            s('stop', { offset: '0', 'stop-color': '#ff6c65' }), s('stop', { offset: '1', 'stop-color': '#e3352e' }))),
        s('rect', { x: '9', y: '2', width: '46', height: '46', rx: '11', fill: `url(#${id})` }), g);
}

/* ── the desktop ── */

async function introTidy() {
    const w = K.welcome;
    const page = pages().findIndex(p => p.kind === 'desktop');
    if (!(page > 0) || w.busy) return;
    if (K.preview) { toast('Preview is on, so nothing moves. Turn it off in Settings first.', null, 'eye'); return; }
    w.busy = true;
    // a name still being changed is changed first, then everything moves
    if (w.renaming) await w.renaming;
    if (!K.welcome) return;
    const reply = await ask('tidy', { pages: [page] });
    const one = reply && reply.results && reply.results[0];
    if (!K.welcome) return;
    if (one && one.ok && one.changed) {
        await flyIntoFolder();
        w.didDesk = true;
        w.desk = [];
        K.listing = {};
        delete K.kept[0];
        w.busy = false;
        drawWelcome();
        // whatever nimo left where it was — something still being written,
        // say — is read again and drawn beside the folder
        readDesk();
        return;
    }
    w.busy = false;
    if (one && !one.ok) {
        const warn = parse(one.text || '').find(p => p.k === 'warn');
        toast(warn ? warn.text : 'Kliner could not tidy your desktop.', null, 'x');
    }
}

/** Everything on the small desktop flies into one place in the corner,
 *  where the folder it went into then lands. */
function flyIntoFolder() {
    const icons = [...document.querySelectorAll('.mac-desk .di')];
    if (!icons.length || calm()) return Promise.resolve();
    const to = icons[0].getBoundingClientRect();
    icons.forEach((el, n) => {
        const at = el.getBoundingClientRect();
        el.style.setProperty('--dx', (to.left - at.left).toFixed(1) + 'px');
        el.style.setProperty('--dy', (to.top - at.top).toFixed(1) + 'px');
        el.style.transitionDelay = Math.min(n * 24, 480) + 'ms';
        el.classList.add('fly');
    });
    return pause(540 + Math.min(icons.length * 24, 480));
}

async function introIcons() {
    const w = K.welcome;
    if (!w || w.busy) return;
    w.busy = true;
    const hide = !(K.meta && K.meta.desktopHidden);
    const done = await hideIcons(hide, true, true);
    w.busy = false;
    if (!K.welcome || !done) return;
    const layer = $('.mac-desk');
    if (hide && layer && !calm()) { layer.classList.add('fade'); await pause(340); }
    if (!hide) w.popped.desk = false;
    drawWelcome();
}

/** macOS said no to the Desktop, or has not been asked: ask again, and look. */
async function introSeeDesk() {
    const reply = await ask('askFolders');
    if (reply && reply.seeing && K.meta) K.meta.seeing = reply.seeing;
    if (!K.welcome) return;
    K.welcome.desk = null;
    K.welcome.deskShut = false;
    drawWelcome();
    readDesk();
}

/* ── a name on the desktop, changed ── */

/* Finder's way: a click picks the file and opens its name as a field, with
   everything but the extension chosen. Return keeps the new name, Escape
   leaves the old one, a click anywhere else keeps it too, and Tab moves on
   to the next file. The file is renamed by nimo, which writes it down first,
   so Undo here and `min undo` later can put the old name back. */

const measureName = (() => {
    let pen = null;
    return (el, text) => {
        pen = pen || document.createElement('canvas').getContext('2d');
        const cs = getComputedStyle(el);
        pen.font = `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
        return pen.measureText(text).width;
    };
})();

/** The field as wide as the name in it, and never off the small screen. */
function fitName(field) {
    field.style.transform = '';
    field.style.width = Math.ceil(measureName(field, field.value || ' ') + 18) + 'px';
    const scr = field.closest('.mac');
    if (!scr) return;
    const a = field.getBoundingClientRect(), b = scr.getBoundingClientRect();
    const over = a.right - (b.right - 6), under = (b.left + 6) - a.left;
    if (over > 0) field.style.transform = `translateX(${-over}px)`;
    else if (under > 0) field.style.transform = `translateX(${under}px)`;
}

/** Why a name cannot be used, in a sentence; nothing when it can. */
function badName(to, f) {
    if (/[\t\n\r]/.test(to)) return 'A name cannot have a tab or a new line in it.';
    if (/[/:]/.test(to)) return 'A name cannot have “/” or “:” in it.';
    if (to === '.' || to === '..') return 'That name is taken by macOS itself.';
    if (to.startsWith('.')) return 'A name that starts with a dot would hide the file.';
    if (new TextEncoder().encode(to).length > 255) return 'That name is too long for macOS.';
    const same = (K.welcome.desk || []).find(o => o !== f && o.name.toLowerCase() === to.toLowerCase());
    if (same) return `There is already something called “${same.name}” on your desktop.`;
    return '';
}

function deskRename(el, f) {
    const w = K.welcome;
    if (!w || w.busy || el.classList.contains('editing')) return;
    const open = document.querySelector('.mac-desk .dn-edit');
    if (open) open.blur();
    const page = pages().findIndex(p => p.kind === 'desktop');
    if (!(page > 0)) return;
    const label = el.querySelector('.dn');
    const field = h('input', { class: 'dn-edit', spellcheck: 'false', autocomplete: 'off', autocapitalize: 'off',
                               'aria-label': 'New name for ' + f.name });
    field.value = f.name;
    el.classList.add('sel', 'editing');
    label.replaceWith(field);
    fitName(field);
    field.focus({ preventScroll: true });
    // the name without its extension, the way Finder picks it
    const dot = f.dir ? -1 : f.name.lastIndexOf('.');
    field.setSelectionRange(0, dot > 0 ? dot : f.name.length);

    let settled = false;
    const close = (renamed) => {
        const now = h('span', { class: 'dn' + (renamed && !calm() ? ' renamed' : '') }, f.name);
        if (field.isConnected) field.replaceWith(now);
        el.classList.remove('editing', 'saving');
        // picked until you click somewhere else, as in Finder
        const off = e => {
            if (el.contains(e.target)) return;
            el.classList.remove('sel');
            document.removeEventListener('mousedown', off, true);
        };
        document.addEventListener('mousedown', off, true);
        el.dataset.name = f.name;
        el.title = f.name;
        el.setAttribute('aria-label', 'Rename ' + f.name);
    };
    const refuse = (why, stay) => {
        toast(why, null, 'x');
        if (!stay) { settled = true; close(false); el.classList.remove('sel'); return; }
        field.classList.remove('bad');
        void field.offsetWidth;
        field.classList.add('bad');
        field.focus({ preventScroll: true });
    };
    const moveOn = (by) => {
        if (!by) return;
        const all = [...document.querySelectorAll('.mac-desk .di.can')];
        const next = all[all.indexOf(el) + by];
        el.classList.remove('sel');
        if (next) next.click();
    };
    const finish = async (keep, by, stay) => {
        if (settled) return;
        const to = field.value.trim();
        if (!keep || !to || to === f.name) {
            settled = true;
            close(false);
            if (by) moveOn(by); else if (!keep) el.focus({ preventScroll: true });
            return;
        }
        const why = badName(to, f);
        if (why) { refuse(why, stay); return; }
        if (K.preview) {
            settled = true;
            close(false);
            toast('Preview is on, so nothing is renamed. Turn it off in Settings first.', null, 'eye');
            return;
        }
        settled = true;
        field.readOnly = true;
        el.classList.add('saving');
        const was = f.name;
        const going = ask('rename', { page, name: was, to });
        w.renaming = going;
        const reply = await going;
        if (w.renaming === going) w.renaming = null;
        if (!K.welcome) return;
        if (reply && reply.ok) {
            deskRenamed(f, was, reply.name || to);
            close(true);
            toast(`Renamed to “${f.name}”`, ['Undo', () => deskUnrename(f, was)]);
            if (by) moveOn(by);
            return;
        }
        settled = false;
        field.readOnly = false;
        el.classList.remove('saving');
        const said = reply && reply.text ? parse(reply.text).find(x => x.k === 'warn' || x.k === 'err') : null;
        refuse(said ? capital(said.text) : 'Kliner could not rename it.', true);
    };
    field.addEventListener('keydown', e => {
        e.stopPropagation();
        if (e.key === 'Enter') { e.preventDefault(); finish(true, 0, true); }
        else if (e.key === 'Escape') { e.preventDefault(); finish(false); }
        else if (e.key === 'Tab') { e.preventDefault(); finish(true, e.shiftKey ? -1 : 1, true); }
    });
    field.addEventListener('input', () => { field.classList.remove('bad'); fitName(field); });
    field.addEventListener('blur', () => { if (!field.readOnly) finish(true); });
    field.addEventListener('click', e => e.stopPropagation());
    field.addEventListener('mousedown', e => e.stopPropagation());
}

/** Everything that knows the file by its name learns the new one. */
function deskRenamed(f, was, now) {
    const w = K.welcome;
    f.name = now;
    if (w && w.deskPics[was]) { w.deskPics[now] = w.deskPics[was]; delete w.deskPics[was]; }
}

/** Undo: nimo puts back the name it changed last, which is this one. */
async function deskUnrename(f, was) {
    const page = pages().findIndex(p => p.kind === 'desktop');
    const now = f.name;
    const reply = await ask('rename', { page, undo: true });
    if (!(reply && reply.ok)) {
        const said = reply && reply.text ? parse(reply.text).find(x => x.k === 'warn' || x.k === 'err') : null;
        toast(said ? capital(said.text) : 'Kliner could not put the name back.', null, 'x');
        return;
    }
    deskRenamed(f, now, was);
    const el = [...document.querySelectorAll('.mac-desk .di.can')].find(x => x.dataset.name === now);
    if (el) {
        const label = el.querySelector('.dn');
        if (label) { label.textContent = was; label.classList.remove('renamed'); void label.offsetWidth; if (!calm()) label.classList.add('renamed'); }
        el.dataset.name = was;
        el.title = was;
        el.setAttribute('aria-label', 'Rename ' + was);
    }
    toast(`Back to “${was}”`, null, 'undo');
}

/* ── the Dock ── */

/** The bottom of your screen, and your Dock on it, big enough to click: an
 *  app to take out, the + for one to put in. */
function dockStage(fresh) {
    const w = K.welcome;
    const box = h('div', { class: 'dockstage' + (w.shelf ? ' shelved' : '') });
    const ground = h('div', { class: 'ground' });
    if (w.wallPic) wallPicture(ground, w.wallPic);
    box.append(ground);
    const d = w.dock;
    if (!d) {
        box.append(h('div', { class: 'bigdock waiting' }, h('i', { class: 'spin' })));
        return box;
    }
    const rise = fresh && !calm();
    const dock = h('div', { class: 'bigdock' + (rise ? ' rise' : '') + (w.dockFast ? ' slid' : '') });
    let n = 0;
    const tile = (a, kind) => {
        const out = kind === 'app' && w.dropped.has(a.name);
        const b = h('button', { class: 'dk' + (kind === 'fixed' ? ' fixed' : kind === 'new' ? ' new' : '') + (out ? ' out' : '') + (rise ? ' st-pop' : ''),
                                'aria-label': a.name, 'aria-pressed': kind === 'app' ? String(out) : null, 'data-app': a.name,
                                style: rise ? `animation-delay:${140 + n * 24}ms` : null,
                                onclick: kind === 'fixed' ? e => hop(e.currentTarget) : kind === 'new' ? () => toggleAdd(a.name) : e => toggleDrop(a.name, e.currentTarget) },
            h('span', { class: 'lbl' }, kind === 'new' ? a.name + ' · new' : a.name), appArt(a),
            kind === 'fixed' ? null : h('span', { class: 'mk', title: kind === 'new' ? 'Take it out again' : 'Take it out' }, icon('x')));
        n++;
        return b;
    };
    if (d.finder) dock.append(tile({ name: 'Finder', icon: d.finder }, 'fixed'));
    d.apps.forEach(a => dock.append(tile(a, 'app')));
    for (const name of w.adding) dock.append(tile((w.more || []).find(a => a.name === name) || { name, icon: '' }, 'new'));
    dock.append(h('button', { class: 'dk plus' + (w.shelf ? ' on' : '') + (rise ? ' st-pop' : ''), 'aria-label': 'Add apps',
                              style: rise ? `animation-delay:${140 + n * 24}ms` : null, onclick: toggleShelf },
        h('span', { class: 'lbl' }, 'Add apps'), h('span', { class: 'plusart' }, icon('plus'))));
    if (d.trash) dock.append(h('span', { class: 'dsep' }), tile({ name: 'Trash', icon: d.trash }, 'fixed'));
    magnify(dock, '.dk', 1.5);
    box.append(dock);
    if (w.shelf) box.append(shelf());
    return box;
}

/** Every app you have that is not in the Dock, to put in with a click. */
function shelf() {
    const w = K.welcome;
    const grid = h('div', { class: 'sh-grid' });
    if (!w.more) {
        grid.append(h('div', { class: 'sh-say' }, h('i', { class: 'spin' })));
        readDockMore();
    } else if (!w.more.length) {
        grid.append(h('div', { class: 'sh-say' }, w.moreFailed ? 'Kliner could not list your apps.' : 'Every app you have is already in your Dock.'));
    } else {
        for (const a of w.more) {
            grid.append(h('button', { class: 'sa' + (w.adding.has(a.name) ? ' on' : ''), 'data-app': a.name, title: a.name,
                                      onclick: () => toggleAdd(a.name) },
                h('span', { class: 'pic' }, appArt(a)), h('span', { class: 'nm' }, a.name)));
        }
    }
    return h('div', { class: 'shelf' }, grid);
}

function toggleShelf() {
    const w = K.welcome;
    if (!w || w.busy) return;
    w.shelf = !w.shelf;
    drawWelcome();
}

function toggleAdd(name) {
    const w = K.welcome;
    if (!w || w.busy) return;
    if (w.adding.has(name)) w.adding.delete(name); else w.adding.add(name);
    // drawn again around the shelf, which stays where it was scrolled to
    const grid = $('.sh-grid'), top = grid ? grid.scrollTop : 0;
    drawWelcome();
    const again = $('.sh-grid');
    if (again) again.scrollTop = top;
}

/** The apps you have that are not in your Dock, with their icons. */
async function readDockMore() {
    const w = K.welcome;
    if (!w || w.moreReading) return;
    w.moreReading = true;
    const reply = await ask('dockMore', {});
    if (!K.welcome) return;
    w.moreReading = false;
    const listed = reply && Array.isArray(reply.apps);
    w.moreFailed = !listed;
    w.more = listed ? reply.apps.filter(a => a && typeof a.name === 'string' && a.name)
                           .map(a => ({ name: a.name, icon: goodPicture(a.icon) ? a.icon : '' })) : [];
    redrawIf('dock');
}

function toggleDrop(name, el) {
    const w = K.welcome;
    if (!w || w.busy) return;
    if (w.dropped.has(name)) w.dropped.delete(name); else w.dropped.add(name);
    const out = w.dropped.has(name);
    el.classList.toggle('out', out);
    el.setAttribute('aria-pressed', String(out));
    const lbl = w.primary && w.primary.querySelector('.lbl');
    if (lbl) lbl.textContent = dockLabel();
}

function dockLabel() {
    const w = K.welcome;
    const out = w.dropped.size, inn = w.adding.size;
    if (out && inn) return 'Save the Dock';
    if (out) return 'Take ' + plural(out, 'app') + ' out';
    if (inn) return 'Add ' + plural(inn, 'app');
    return 'Continue';
}

async function introDockKeep() {
    const w = K.welcome;
    if (!w || w.busy) return;
    if (!w.dropped.size && !w.adding.size) { introGo(1); return; }
    if (K.preview) { toast('Preview is on, so your Dock stays as it is.', null, 'eye'); return; }
    w.busy = true;
    const out = [...w.dropped], inn = [...w.adding];
    const reply = await ask('dockKeep', { drop: out, add: inn });
    if (!K.welcome) return;
    if (!reply || reply.cancelled || reply.missing) { w.busy = false; return; }
    const took = typeof reply.closed === 'number' ? reply.closed : 0;
    const put = typeof reply.added === 'number' ? reply.added : 0;
    // out of the picture the way they go out of the Dock
    if (took) {
        for (const el of document.querySelectorAll('.bigdock .dk.out')) el.classList.add('gone');
        if (!calm()) await pause(420);
    }
    const exact = reply.ok && took === out.length && put === inn.length;
    if (exact) {
        w.dock.apps = w.dock.apps.filter(a => !out.includes(a.name))
            .concat(inn.map(name => (w.more || []).find(a => a.name === name) || { name, icon: '' }));
        if (w.more) w.more = w.more.filter(a => !inn.includes(a.name));
    } else {
        toast(took + put ? 'Some of it changed. Your Dock is shown as it is now.' : 'Your Dock did not change.', null, 'x');
    }
    w.dockGone += took;
    w.dockAdded += put;
    w.dropped = new Set();
    w.adding = new Set();
    w.shelf = false;
    w.busy = false;
    drawWelcome();
    // whatever nimo managed, the Dock as it really is now
    if (!exact) { K.welcome.dockReading = false; K.welcome.more = null; readDockApps(); }
}

/** The Dock slides away, fast — or comes back to how it was. The switch
 *  says only what the Mac says after it was asked. */
async function introDockFast() {
    const w = K.welcome;
    if (!w || w.busy || w.dockFastBusy) return;
    if (K.preview) { toast('Preview is on, so your Dock stays as it is.', null, 'eye'); return; }
    const on = !w.dockFast;
    w.dockFastBusy = true;
    drawWelcome();
    const reply = await ask('dockFast', { back: !on });
    if (!K.welcome) return;
    w.dockFastBusy = false;
    if (reply && reply.ok && !reply.cancelled) w.dockFast = on;
    else if (reply && !reply.cancelled && !reply.missing) toast(on ? 'Your Mac did not take that.' : 'Your Dock stayed as it is.', null, 'x');
    drawWelcome();
}

/* ── the wallpaper ── */

/** Every wallpaper, small, in one row you can slide through: yours first,
 *  then the ones your Mac came with. The welcome and Home both draw this
 *  row; `now` is the one to ring and `pick` what a click does, so neither
 *  has to know anything about the other. */
function wallStrip(opts) {
    const o = opts || {};
    const w = K.welcome;
    const strip = h('div', { class: 'wstrip', onwheel: e => {
        // a mouse wheel turns the row, the way a trackpad already does
        if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) { e.currentTarget.scrollLeft += e.deltaY; e.preventDefault(); }
    } });
    if (!K.walls) {
        for (let n = 0; n < 12; n++) strip.append(h('span', { class: 'wt ph' }));
        return strip;
    }
    const now = o.now != null ? o.now : (w && w.wallName) || wallNow();
    const pick = o.pick || introWall;
    let shelf_ = '';
    K.walls.forEach((one_, n) => {
        const k = shelfOf(one_, n);
        if (shelf_ && k !== shelf_) strip.append(h('span', { class: 'wsep', title: SHELVES[k] }));
        shelf_ = k;
        const pic = K.wallPics && K.wallPics[String(one_.no)];
        strip.append(h('button', { class: 'wt' + (one_.parts[0] === now ? ' on' : '') + (goodPicture(pic) ? '' : ' ph'),
                                   'data-no': String(one_.no), title: one_.parts[0], 'aria-label': one_.parts[0],
                                   onclick: () => pick(one_.no) },
            goodPicture(pic) ? h('img', { src: pic, alt: '' }) : null));
    });
    return strip;
}

/** The row slid so that one is in the middle of it. */
function centreOn(strip, el) {
    if (!el) return;
    strip.scrollLeft = Math.max(0, el.offsetLeft - (strip.clientWidth - el.offsetWidth) / 2);
}

/** Pictures of wallpapers that arrived after their row was drawn. */
function fillWallTiles() {
    const pics = K.wallPics || {};
    for (const el of document.querySelectorAll('.wstrip .wt.ph[data-no]')) {
        const uri = pics[el.dataset.no];
        if (!goodPicture(uri)) continue;
        el.classList.remove('ph');
        el.append(h('img', { src: uri, alt: '' }));
    }
    for (const el of document.querySelectorAll('.walls .wall[data-no] .sheet:not(.has)')) {
        const uri = pics[el.parentNode.dataset.no];
        if (!goodPicture(uri)) continue;
        el.classList.add('has');
        el.querySelector('.ic')?.remove();
        el.prepend(h('img', { class: 'pic', src: uri, alt: '' }));
    }
}

async function introWall(at) {
    const w = K.welcome;
    if (!w || w.busy) return;
    if (K.preview) { toast('Preview is on, so your wallpaper stays as it is.', null, 'eye'); return; }
    const one_ = (K.walls || []).find(p => p.no === at);
    if (!one_) return;
    w.busy = true;
    const before = w.wallPic;
    const small = K.wallPics && K.wallPics[String(at)];
    // on the small screen at once, and marked in the row
    const mark = no => { for (const el of document.querySelectorAll('.wstrip .wt')) el.classList.toggle('on', el.dataset.no === String(no)); };
    mark(at);
    if (goodPicture(small)) { for (const box of document.querySelectorAll('.mac-wall')) wallPicture(box, small); glowFrom(small); }
    const reply = await ask('setWall', { at });
    w.busy = false;
    if (!K.welcome) return;
    if (reply && reply.ok) {
        w.wallName = one_.parts[0];
        w.wallAt = at;
        K.wallOn = w.wallName;
        if (goodPicture(small)) w.wallPic = small;
        const big = await ask('wallBig', { at });
        if (K.welcome && K.welcome.wallAt === at && big && goodPicture(big.picture)) {
            K.welcome.wallPic = big.picture;
            fillScreens();
        }
        return;
    }
    // it did not take: the screen and the row go back to what is really on
    if (before) { for (const box of document.querySelectorAll('.mac-wall')) wallPicture(box, before); glowFrom(before); }
    const was = (K.walls || []).find(p => p.parts[0] === (w.wallName || wallNow()));
    mark(was ? was.no : -1);
    if (reply && !reply.cancelled) {
        const warn = parse(reply.text || '').find(p => p.k === 'warn');
        toast(warn ? warn.text : 'Your Mac did not take that wallpaper.', null, 'x');
    }
}

/* ── your account ──

   Dan, after v20: "and you did not make the login better either". The two
   steps that were your name and email, and then your @username, are one,
   the way an app's sign-up is one form: your name, your email and the
   @username anyone sends you files by. Beside it your card, drawn again as
   you type — your picture (click it for another), your name, your
   @username and what kliner.app said about it. One button makes it: it
   claims the name and goes on. A name held on kliner.app is had here too,
   with the code the site showed (userClaimLine).                       */

function accountStage(fresh) {
    const w = K.welcome;
    const mailOk = () => looksLikeEmail(w.email);
    const hint = h('span', { class: 'acct-hint' + (w.mailWarn ? '' : ' quiet'), id: 'mailHint', role: 'alert' }, 'That is not an email address yet.');
    const name = h('input', { class: 'field', id: 'name', value: w.name, placeholder: 'Your name', maxlength: '60', autocomplete: 'off',
                              oninput: e => { w.name = e.target.value; userPaint(); } });
    const mail = h('input', { class: 'field' + (w.mailWarn ? ' bad' : ''), id: 'mail', type: 'email', value: w.email,
                              placeholder: 'you@example.com', maxlength: '120', spellcheck: 'false', autocapitalize: 'off', autocomplete: 'off',
                              oninput: e => {
                                  w.email = e.target.value;
                                  w.mailWarn = false;
                                  e.target.classList.remove('bad');
                                  hint.classList.add('quiet');
                              },
                              onblur: e => {
                                  if (!w.email || mailOk()) return;
                                  e.target.classList.add('bad');
                                  hint.classList.remove('quiet');
                              } });
    const enter = e => { if (e.key === 'Enter') { e.preventDefault(); introAccount(); } };
    name.addEventListener('keydown', enter);
    mail.addEventListener('keydown', enter);
    const form = h('div', { class: 'acct-form' },
        h('label', { class: 'acct-row' }, h('span', { class: 'acct-k' }, 'Name'), name),
        h('label', { class: 'acct-row' }, h('span', { class: 'acct-k' }, 'Email', h('i', null, 'Kept on this Mac')), mail, hint),
        h('div', { class: 'acct-row' }, h('label', { class: 'acct-k', for: 'uname' }, 'Username'), userClaimLine()));
    if (K.meta.login && K.meta.login.possible) {
        form.append(h('button', { class: 'tog acct-login', type: 'button', onclick: e => {
            w.login = !w.login;
            e.currentTarget.querySelector('.switch').classList.toggle('on', w.login);
        } }, h('span', { class: 'switch' + (w.login ? ' on' : '') }), 'Open Kliner when you log in'));
    }
    return h('div', { class: 'acct' + (fresh && !calm() ? ' st-pop' : '') }, form, idCard());
}

/** Your card, the way it reads to anyone: over your wallpaper, your
 *  picture, your name and your @username, and what kliner.app says about
 *  the name. Painted by userPaint as you type. */
function idCard() {
    const w = K.welcome;
    const wall = h('div', { class: 'idc-wall' });
    if (goodPicture(w.wallPic)) wallPicture(wall, w.wallPic);
    return h('figure', { class: 'idc-wrap' },
        h('div', { class: 'idc', id: 'idCard' },
            wall,
            h('button', { class: 'idc-face', type: 'button', onclick: changePicture, 'aria-label': 'Change your picture' },
                face('big'), h('span', { class: 'cam' }, icon('camera'))),
            h('div', { class: 'idc-w' }, h('b', { id: 'idName' }), h('span', { id: 'idUser' })),
            h('div', { class: 'idc-foot' }, h('span', { class: 'idc-url', id: 'idUrl' }), h('span', { class: 'idc-st', id: 'idState' }))),
        h('figcaption', { class: 'idc-say' }, 'Click the picture to change it.'));
}

/** The one button: the email first, then the name — claimed, or already
 *  yours — and on to the last step once it is. */
async function introAccount() {
    const w = K.welcome;
    if (!w || w.uBusy || INTRO[w.step] !== 'account') return;
    if (!looksLikeEmail(w.email)) { mailWarn(); return; }
    if (w.uState === 'mine') { introGo(1); return; }
    await introClaim();
    if (K.welcome !== w || w.uState !== 'mine') return;
    // a moment for the tick and the paper, then the last step
    await pause(calm() ? 0 : 900);
    if (K.welcome === w && INTRO[w.step] === 'account') introGo(1);
}

/** On without a username: it can be picked in Settings any time. The email
 *  is still asked for. */
function introSkipName() {
    const w = K.welcome;
    if (!w) return;
    if (!looksLikeEmail(w.email)) { mailWarn(); return; }
    introGo(1);
}

function mailWarn() {
    const w = K.welcome;
    if (w) w.mailWarn = true;
    const m = $('#mail'), hint = $('#mailHint');
    if (m) { m.classList.add('bad'); m.focus(); }
    if (hint) hint.classList.remove('quiet');
}

function userClaimLine() {
    const w = K.welcome;
    const field = h('input', { class: 'field', id: 'uname', placeholder: 'yourname', maxlength: '21', spellcheck: 'false',
                               autocapitalize: 'off', autocomplete: 'off', 'aria-label': 'Username', 'aria-describedby': 'ustate' });
    field.value = w.want;
    field.addEventListener('input', () => {
        const clean = field.value.replace(/^@+/, '').replace(/\s+/g, '').toLowerCase();
        if (clean !== field.value) field.value = clean;
        w.want = clean;
        userLook();
    });
    // a name held on kliner.app is had with the code the site showed
    const code = h('input', { class: 'field ucode', id: 'ucode', placeholder: 'Code from kliner.app', maxlength: '11', spellcheck: 'false',
                              autocapitalize: 'characters', autocomplete: 'off', hidden: true, 'aria-label': 'Code from kliner.app' });
    code.value = w.uCode || '';
    code.addEventListener('input', () => {
        const typed = codeTyped(code.value);
        if (typed !== code.value) code.value = typed;
        w.uCode = typed;
        if (w.uState === 'code' || w.uState === 'wrongCode') { w.uState = 'code'; userPaint(); }
    });
    code.addEventListener('keydown', e => { if (e.key === 'Enter' && w.primary && !w.primary.disabled) { e.preventDefault(); introAccount(); } });
    field.addEventListener('keydown', e => { if (e.key === 'Enter' && w.primary && !w.primary.disabled) { e.preventDefault(); introAccount(); } });
    return h('div', { class: 'uclaim', id: 'uclaim' },
        h('label', { class: 'ufield', id: 'ufield' }, h('span', { class: 'at' }, '@'), field, h('span', { class: 'ustat', id: 'ustat' })),
        h('div', { class: 'uline' },
            h('span', { class: 'uurl' }, 'kliner.app/', h('b', { id: 'uurl' }, '@' + (w.want || 'yourname'))),
            h('span', { class: 'ustate', id: 'ustate', role: 'status' })),
        code,
        h('div', { class: 'uideas off', id: 'uideas' }));
}

/* ── names that are free ──

   When the name you typed is taken, Kliner asks kliner.app about a few
   close to it — your name and surname together, with a dot, your initial
   and surname, the year after it — and offers only the ones it said are
   free. Each answer is kept a minute, so a name is not asked about twice. */

const NAMES_SEEN = new Map();
const IDEAS = { asked: 0 };

async function checkName(name) {
    const was = NAMES_SEEN.get(name);
    if (was && Date.now() - was.at < 60000) return was.r;
    const r = await nameLook(name);
    if (r && r.ok && !r.local) NAMES_SEEN.set(name, { r, at: Date.now() });
    return r;
}

/** Names close to the one you typed, by the rules, at most four. */
function nameIdeas(want) {
    // the name you gave, or the one this Mac has for you, whichever has a surname
    const names = [K.welcome && K.welcome.name, K.meta.config && K.meta.config.name, K.meta.user].map(x => String(x || '').trim()).filter(Boolean);
    const said = (names.find(x => x.split(/\s+/).length > 1) || names[0] || '').toLowerCase()
        .normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    const words = said.split(/\s+/).map(x => x.replace(/[^a-z0-9]/g, '')).filter(Boolean);
    const first = words[0] || '', last = words.length > 1 ? words[words.length - 1] : '';
    const yy = String(new Date().getFullYear()).slice(2);
    const out = [];
    const add = x => { if (x && x !== want && !nameTrouble(x) && !out.includes(x)) out.push(x); };
    if (first && last) { add(first + '.' + last); add(first + last); add(first.charAt(0) + last); }
    add(want + '.' + (last ? last.charAt(0) : 'mac'));
    add(want + yy);
    return out.slice(0, 4);
}

/** Ask about the names close to `want` and put the free ones in `box`, each
 *  a button that takes it. Nothing is shown until kliner.app has answered. */
async function offerIdeas(want, box, pick) {
    const n = ++IDEAS.asked;
    box.classList.add('off');
    box.replaceChildren();
    const list = nameIdeas(want);
    if (!list.length) return;
    const answers = await Promise.all(list.map(x => checkName(x)));
    if (n !== IDEAS.asked || !box.isConnected) return;
    const free = list.filter((x, k) => answers[k] && answers[k].ok && !answers[k].local && answers[k].free && !answers[k].taken);
    if (!free.length) return;
    box.replaceChildren(h('span', { class: 'ui-l' }, 'Free now'),
        ...free.slice(0, 3).map((x, k) => h('button', { class: 'ui-c', style: `--i:${k}`, onclick: e => { e.preventDefault(); pick(x); } }, '@' + x)));
    box.classList.remove('off');
}

/** A handful of paper, once, from the middle of `el`: what getting your name
 *  looks like. Greys and white, like the rest of the window. */
function burst(el) {
    if (calm() || !el) return;
    const r = el.getBoundingClientRect();
    const c = h('canvas', { class: 'burst', 'aria-hidden': 'true' });
    const dpr = window.devicePixelRatio || 1;
    const W = innerWidth, H = innerHeight;
    c.width = W * dpr; c.height = H * dpr;
    document.body.append(c);
    const g = c.getContext('2d');
    g.scale(dpr, dpr);
    const dark = !(window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches);
    const inks = dark ? ['#ffffff', '#dcdee3', '#a3a6af', '#6b6f78'] : ['#0e0f11', '#3a3c42', '#83868e', '#b9bcc2'];
    const bits = Array.from({ length: 90 }, (_, k) => {
        const a = -Math.PI / 2 + (Math.random() - .5) * Math.PI * 1.2;
        const v = 5 + Math.random() * 8;
        return { x: r.left + r.width / 2 + (Math.random() - .5) * r.width * .7, y: r.top + r.height / 2,
                 vx: Math.cos(a) * v, vy: Math.sin(a) * v - 2.5, s: 3 + Math.random() * 5, rot: Math.random() * 6,
                 vr: (Math.random() - .5) * .45, ink: inks[k % inks.length], round: k % 3 === 0 };
    });
    const t0 = performance.now();
    const frame = t => {
        const age = (t - t0) / 1000;
        g.clearRect(0, 0, W, H);
        for (const b of bits) {
            b.vy += .3; b.vx *= .985; b.vy *= .988; b.x += b.vx; b.y += b.vy; b.rot += b.vr;
            g.save();
            g.globalAlpha = Math.max(0, Math.min(1, 1.7 - age * 1.1));
            g.translate(b.x, b.y); g.rotate(b.rot); g.fillStyle = b.ink;
            if (b.round) { g.beginPath(); g.arc(0, 0, b.s / 2.2, 0, Math.PI * 2); g.fill(); }
            else g.fillRect(-b.s / 2, -b.s / 4, b.s, b.s / 2);
            g.restore();
        }
        if (age < 1.6) requestAnimationFrame(frame); else c.remove();
    };
    requestAnimationFrame(frame);
}

/** Whether the name being typed can be had: the rules first, which need
 *  nobody, then kliner.app (or the Macs nearby, when it cannot be reached),
 *  a moment after the typing stops. */
function userLook() {
    const w = K.welcome;
    if (!w) return;
    const want = bareName(w.want);
    clearTimeout(w.uTimer);
    const n = ++w.uAsked;
    if (!want) w.uState = '';
    else if (want === w.user) w.uState = 'mine';
    else if (nameTrouble(want)) { w.uState = 'bad'; w.uNote = nameTrouble(want); }
    else {
        w.uState = 'looking';
        w.uTimer = setTimeout(async () => {
            const r = await nameLook(want);
            if (K.welcome !== w || n !== w.uAsked) return;
            w.uLocal = !!(r && r.local);
            w.uUntil = r && r.until;
            if (!r || r.missing || !r.ok) { w.uState = 'bad'; w.uNote = (r && r.bad) || 'Kliner could not check that name. Try again.'; }
            else w.uState = r.mine ? 'mine' : r.taken ? 'taken' : r.claimed ? 'code' : r.held ? 'held' : 'free';
            userPaint();
        }, 350);
    }
    userPaint();
}

/** The step, said again from what is known: the name in the picture, the
 *  sign in the field, the line under it, and what the button does. */
function userPaint() {
    const w = K.welcome;
    if (!w || INTRO[w.step] !== 'account') return;
    const want = bareName(w.want);
    const mine = w.uState === 'mine';
    const where = w.uLocal ? ' on this Mac' : ' on kliner.app';
    const words = {
        '': ['3 to 20 small letters, numbers, dots or underscores.', ''],
        looking: ['Looking…', ''],
        free: ['@' + want + ' is free.', 'good'],
        taken: [w.uLocal ? 'A Mac nearby already answers to @' + want + '.' : 'Somebody already has @' + want + '.', 'bad'],
        mine: ['@' + want + ' is yours' + where + '.' + (w.uLocal ? ' Kliner claims it on kliner.app as soon as it can reach it.' : ''), 'good'],
        bad: [w.uNote, 'bad'],
        claiming: ['Claiming @' + want + '…', ''],
        held: ['@' + want + ' was given up a moment ago. It is kept for its owner until ' + untilDay(w.uUntil) + '.', 'bad'],
        code: ['@' + want + ' is held on kliner.app until ' + untilDay(w.uUntil) + '. If you held it, type its code.', ''],
        wrongCode: ['That code does not hold @' + want + '. Check it and try again.', 'bad'],
    }[w.uState] || ['', ''];
    const codeBox = $('#ucode');
    if (codeBox) {
        const show = ['code', 'wrongCode'].includes(w.uState) || (w.uState === 'claiming' && !!w.uCode && w.uHeld);
        if (codeBox.hidden === show) { codeBox.hidden = !show; if (show && !calm()) codeBox.classList.add('st-pop'); }
    }
    const line = $('#ustate');
    if (line) { line.textContent = words[0]; line.className = 'ustate' + (words[1] ? ' ' + words[1] : ''); }
    const url = $('#uurl');
    if (url) url.textContent = '@' + (want || 'yourname');
    const fieldBox = $('#ufield');
    if (fieldBox) fieldBox.dataset.state = w.uState || '';
    const ideas = $('#uideas');
    if (ideas) {
        if (w.uState === 'taken' && !w.uLocal) {
            if (ideas.dataset.for !== want) {
                ideas.dataset.for = want;
                offerIdeas(want, ideas, x => {
                    const f = $('#uname');
                    if (f) { f.value = x; f.focus(); }
                    w.want = x;
                    userLook();
                });
            }
        } else if (ideas.dataset.for) { ideas.dataset.for = ''; ideas.classList.add('off'); IDEAS.asked++; }
    }
    const stat = $('#ustat');
    if (stat) {
        const kind = ['looking', 'claiming'].includes(w.uState) ? 'wait' : ['free', 'mine'].includes(w.uState) ? 'good'
            : ['taken', 'bad', 'held', 'wrongCode'].includes(w.uState) ? 'bad' : '';
        if (stat.dataset.kind !== kind) {
            stat.dataset.kind = kind;
            stat.className = 'ustat ' + kind;
            stat.replaceChildren(kind === 'wait' ? h('i', { class: 'spin' }) : kind === 'good' ? icon('check') : kind === 'bad' ? icon('x') : '');
        }
    }
    const box = $('#uclaim');
    if (box) box.classList.toggle('claimed', mine);
    const lbl = w.primary && w.primary.querySelector('.lbl');
    if (lbl) lbl.textContent = mine ? 'Continue' : w.uState === 'claiming' ? 'Creating…' : 'Create account';
    if (w.primary) w.primary.disabled = !(mine || w.uState === 'free' || (w.uState === 'code' && codeTyped(w.uCode).length === 11));
    if (w.later) w.later.hidden = mine;
    // the card: your name, your @username, and what kliner.app said
    const card = $('#idCard');
    if (card) {
        const nm = $('#idName'), us = $('#idUser'), url = $('#idUrl'), st = $('#idState');
        if (nm) { nm.textContent = capital(String(w.name || '').trim()) || 'Your name'; nm.classList.toggle('blank', !String(w.name || '').trim()); }
        if (us) { us.textContent = '@' + (want || 'username'); us.classList.toggle('blank', !want); }
        if (url) url.textContent = 'kliner.app/@' + (want || 'yourname');
        const pill = { looking: ['Looking…', ''], free: ['Free', 'good'], mine: ['Yours', 'good'], taken: ['Taken', 'bad'],
                       bad: ['Not this one', 'bad'], claiming: ['Claiming…', ''], held: ['Kept for its owner', 'bad'],
                       code: ['Needs its code', ''], wrongCode: ['Wrong code', 'bad'] }[w.uState] || ['', ''];
        if (st) { st.textContent = pill[0]; st.className = 'idc-st' + (pill[1] ? ' ' + pill[1] : ''); }
        card.classList.toggle('mine', mine);
    }
}

async function introClaim() {
    const w = K.welcome;
    if (!w || w.uBusy) return;
    if (w.uState === 'mine') { introGo(1); return; }
    const withCode = w.uState === 'code' && codeTyped(w.uCode).length === 11;
    if (w.uState !== 'free' && !withCode) return;
    const want = bareName(w.want);
    w.uBusy = true;
    w.uHeld = withCode;
    w.uState = 'claiming';
    userPaint();
    const r = await nameClaim(want, withCode ? codeTyped(w.uCode) : '');
    if (K.welcome !== w) return;
    w.uBusy = false;
    if (bareName(w.want) !== want) { userLook(); return; }
    w.uLocal = !!r.local;
    if (r && r.ok && r.user) {
        w.user = r.user;
        K.meta.config.user = r.user;
        w.uState = 'mine';
        w.uWon = Date.now();
        requestAnimationFrame(() => burst($('#ufield')));
    } else if (r && r.taken) w.uState = 'taken';
    else if (r && r.wrongCode) w.uState = 'wrongCode';
    else if (r && r.claimed) w.uState = 'code';
    else if (r && r.held) w.uState = 'held';
    else { w.uState = 'bad'; w.uNote = (r && (r.bad || String(r.text || '').replace(/^[!✗]\s*/, ''))) || 'Kliner could not claim that name. Try again.'; }
    userPaint();
    if (w.uState === 'wrongCode' || w.uState === 'code') { const c = $('#ucode'); if (c) c.focus(); }
}

/* ── the questions macOS asks ── */

async function askGate(n) {
    const w = K.welcome;
    if (!w || w.asking >= 0) return;
    w.asking = n;
    drawWelcome();
    await pause(120);
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
        await pause(260);
    }
}

/* ── ⌘K, on the last step ── */

/* The search the window has, on the small screen. It opens by itself, types
   a few things you could ask it, and then it is yours: type, move with the
   arrows, pick a row. Picking one finishes the starter and does what the row
   says, as ⌘K will from now on. Every row in it is one the real search has. */

const PAL_WORDS = ['wall', 'hide', 'disk', 'dock', 'down'];

const palState = () => K.welcome && K.welcome.pal;
const palRowsFor = q => findRows(q.trim().toLowerCase(), 'all');

function palLayer() {
    const p = K.welcome.pal;
    const field = h('input', { class: 'mk-q', placeholder: 'Search pages, actions and files', spellcheck: 'false',
                               autocapitalize: 'off', autocomplete: 'off', 'aria-label': 'Search Kliner' });
    field.value = p.q;
    field.addEventListener('keydown', palKeys);
    field.addEventListener('input', () => { palTouch(); p.q = field.value; p.at = 0; palPaint(true); });
    field.addEventListener('focus', () => { p.focus = true; });
    field.addEventListener('blur', () => { p.focus = false; });
    const card = h('div', { class: 'mk-card', role: 'dialog', 'aria-label': 'Search Kliner' },
        h('div', { class: 'mk-top' }, icon('search'), field, h('kbd', null, 'esc')),
        h('div', { class: 'mk-list', role: 'listbox' }, h('i', { class: 'mk-glide' })),
        h('div', { class: 'mk-foot' },
            h('span', null, h('kbd', null, '↑'), h('kbd', null, '↓'), 'Move'),
            h('span', null, h('kbd', null, '↵'), 'Open'),
            h('span', { class: 'r' }, h('kbd', null, '⌘K'), 'Close')));
    // the moment you reach for it, the show stops and it is yours
    card.addEventListener('pointerenter', () => palTouch());
    card.addEventListener('mousedown', e => {
        palTouch();
        if (e.target !== field && !e.target.closest('.mk-row')) { e.preventDefault(); palFocus(); }
    });
    return h('div', { class: 'mk' + (p.open ? ' open' : '') },
             h('div', { class: 'mk-scrim', onclick: () => palShut() }), card);
}

/** The rows for what is in the field now; `fresh` ones slide in. */
function palPaint(fresh) {
    const p = palState();
    const list = $('.mk-list');
    if (!p || !list) return;
    const rows = p.rows = palRowsFor(p.q);
    if (p.at >= rows.length) p.at = Math.max(0, rows.length - 1);
    const kids = [h('i', { class: 'mk-glide' })];
    let sec = '', k = 0;
    rows.forEach((r, n) => {
        if (r.sec !== sec) { sec = r.sec; kids.push(h('div', { class: 'mk-sec' }, sec)); }
        kids.push(palRow(r, n, fresh && !calm() ? k++ : -1));
    });
    if (!rows.length) kids.push(h('div', { class: 'mk-none' }, `Nothing called “${p.q.trim()}”`));
    list.replaceChildren(...kids);
    list.scrollTop = 0;
    palMark(false, true);
}

function palRow(r, n, k) {
    const p = palState();
    return h('button', { class: 'mk-row' + (k >= 0 ? ' in' : '') + (r.lead ? ' lead' : ''), role: 'option', tabindex: '-1',
                          style: k >= 0 ? `animation-delay:${Math.min(k, 8) * 24}ms` : null,
                          onmousemove: () => { if (p.at !== n) { p.at = n; palMark(false); } },
                          onclick: () => palRun(n) },
        h('span', { class: 'mk-ic' }, icon(r.icon)),
        h('span', { class: 'mk-x' }, h('span', { class: 'mk-n' }, r.name),
          r.where ? h('span', { class: 'mk-h' }, r.where) : r.hint ? h('span', { class: 'mk-h' }, r.hint) : null),
        h('span', { class: 'mk-r' },
          r.fig ? h('span', { class: 'mk-f' }, r.fig) : null,
          h('span', { class: 'mk-go' }, r.verb || 'Open', h('kbd', null, '↵'))));
}

/** The light on the chosen row: one piece that slides from row to row. */
function palMark(scroll, jump) {
    const p = palState();
    const list = $('.mk-list');
    if (!p || !list) return;
    const els = list.querySelectorAll('.mk-row');
    els.forEach((el, k) => { el.classList.toggle('on', k === p.at); el.setAttribute('aria-selected', String(k === p.at)); });
    const glide = list.querySelector('.mk-glide');
    const on = els[p.at];
    if (!glide) return;
    if (!on) { glide.style.opacity = '0'; return; }
    glide.classList.toggle('jump', !!jump);
    glide.style.opacity = '1';
    glide.style.height = on.offsetHeight + 'px';
    glide.style.transform = `translateY(${on.offsetTop}px)`;
    if (scroll) {
        const top = on.offsetTop, bottom = top + on.offsetHeight;
        if (top < list.scrollTop + 4) list.scrollTop = Math.max(0, top - 28);
        else if (bottom > list.scrollTop + list.clientHeight - 4) list.scrollTop = bottom - list.clientHeight + 6;
    }
}

/** ⌘ and K go down, the eyes in the menu bar light up, and the search
 *  drops in under the menu bar, the way it does on your Mac. */
async function palOpen(press, focus) {
    const p = palState();
    if (!p) return;
    if (press) palPress();
    if (!p.open) {
        if (press && !calm()) await pause(160);
        if (palState() !== p) return;
        p.open = true;
        const box = $('.mk'), scr = $('.mac.done');
        if (box) box.classList.add('open');
        if (scr) scr.classList.add('pal');
        palPaint(true);
    }
    if (focus) palFocus();
}

function palShut() {
    const p = palState();
    if (!p || !p.open) return;
    palTouch();
    p.open = false;
    const f = $('.mk-q');
    if (f && document.activeElement === f) f.blur();
    const box = $('.mk'), scr = $('.mac.done');
    if (box) box.classList.remove('open');
    if (scr) scr.classList.remove('pal');
}

function palToggle(focus) {
    const p = palState();
    if (!p) return;
    palTouch();
    if (p.open && document.activeElement === $('.mk-q')) palShut();
    else palOpen(true, focus);
}

/** ⌘K itself, pressed while the starter is open: on the last step it is
 *  the search on the small screen; anywhere else it waits for the end. */
function palKey() {
    const w = K.welcome;
    if (w && INTRO[w.step] === 'done') palToggle(true);
}

function palPress() {
    if (calm()) return;
    document.querySelectorAll('.st-keys kbd').forEach((k, n) => {
        k.classList.remove('press');
        void k.offsetWidth;
        k.style.animationDelay = n * 70 + 'ms';
        k.classList.add('press');
    });
    const kl = $('.mac-bar .kl');
    if (kl) { kl.classList.remove('lit'); void kl.offsetWidth; kl.classList.add('lit'); }
}

function palFocus() {
    const f = $('.mk-q');
    if (!f) return;
    f.focus({ preventScroll: true });
    const n = f.value.length;
    f.setSelectionRange(n, n);
}

/** Yours from here: the show stops, and what it typed stays put. */
function palTouch() {
    const p = palState();
    if (!p || p.touched) return;
    p.touched = true;
    p.token++;
    const box = $('.mk');
    if (box) box.classList.remove('demo');
}

function palKeys(e) {
    const p = palState();
    if (!p) return;
    const k = e.key;
    if (k === 'Enter') {
        // until you have touched it, Return is still the button's
        if (!p.touched) return;
        e.preventDefault(); e.stopPropagation();
        palRun(p.at);
        return;
    }
    if (k === 'Escape') {
        e.preventDefault(); e.stopPropagation();
        palTouch();
        if (p.q) { palType(''); } else palShut();
        return;
    }
    if (k === 'ArrowDown' || k === 'ArrowUp') {
        e.preventDefault(); e.stopPropagation();
        palTouch();
        if (!p.rows.length) return;
        p.at = (p.at + (k === 'ArrowDown' ? 1 : -1) + p.rows.length) % p.rows.length;
        palMark(true);
        return;
    }
    if (k.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey && !p.touched) {
        // the first letter you type: what the show typed goes
        palTouch();
        e.target.value = '';
        p.q = '';
    }
}

function palType(q) {
    const p = palState();
    if (!p) return;
    p.q = q;
    p.at = 0;
    const f = $('.mk-q');
    if (f) f.value = q;
    palPaint(true);
}

/** What the show types: a file of yours first, if one is on the desktop,
 *  then things Kliner does. Only words that find something here. */
function palWords() {
    const w = K.welcome;
    const out = [];
    if (!w) return out;
    for (const f of (w.desk || []).slice(0, 12)) {
        const word = f.name.toLowerCase().replace(/[^a-z].*$/, '').slice(0, 5);
        if (word.length >= 3 && palRowsFor(word).some(r => r.file)) { out.push(word); break; }
    }
    for (const word of PAL_WORDS) {
        if (out.length >= 3) break;
        if (!out.includes(word) && palRowsFor(word).length) out.push(word);
    }
    return out;
}

async function palDemo() {
    const w = K.welcome, p = w.pal;
    const token = ++p.token;
    const alive = () => K.welcome === w && p.token === token && !p.touched && INTRO[w.step] === 'done';
    const box = $('.mk');
    if (box) box.classList.add('demo');
    await pause(calm() ? 150 : 1100);
    if (!alive()) return;
    await palOpen(true, true);
    if (calm()) return;
    await pause(700);
    if (!alive()) return;
    for (const word of palWords()) {
        for (const ch of word) {
            if (!alive()) return;
            palType(p.q + ch);
            await pause(105 + (ch.charCodeAt(0) % 4) * 22);
        }
        await pause(560);
        if (!alive()) return;
        if (p.rows.length > 1) {
            p.at = 1; palMark(true);
            await pause(640);
            if (!alive()) return;
            p.at = 0; palMark(true);
        }
        await pause(1150);
        while (p.q && alive()) { palType(p.q.slice(0, -1)); await pause(42); }
        await pause(380);
    }
    if (!alive()) return;
    const b = $('.mk');
    if (b) b.classList.remove('demo');
}

/** After the step is drawn, again or for the first time. */
function palMount(fresh) {
    const p = palState();
    if (!p) return;
    palPaint(false);
    if (fresh && !p.touched) { palDemo(); return; }
    if (p.open && p.focus) palFocus();
}

/** A row picked: it lights up, the starter goes, and the row happens. */
function palRun(n) {
    const w = K.welcome, p = palState();
    if (!w || !p || w.busy) return;
    const r = p.rows[n];
    if (!r) return;
    palTouch();
    const el = document.querySelectorAll('.mk-row')[n];
    if (el) el.classList.add('hit');
    const intro = $('.intro');
    if (intro && !calm()) intro.classList.add('leaving');
    setTimeout(() => {
        finishWelcome(r).then(() => { const i = $('.intro'); if (i) i.classList.remove('leaving'); });
    }, calm() ? 0 : 200);
}

async function finishWelcome(pick) {
    const w = K.welcome;
    if (!w || w.busy) return;
    // No way round the email: without one, back to the step that asks for it.
    const toYou = () => { w.step = INTRO.indexOf('account'); w.back = true; w.mailWarn = true; drawWelcome(); };
    if (!looksLikeEmail(w.email)) { toYou(); return; }
    w.busy = true;
    const reply = await ask('finishSetup', { name: (w.name || '').trim(), email: (w.email || '').trim(),
                                             tidy: (w.tidy || '').trim(), login: !!w.login });
    w.busy = false;
    if (!reply || reply.missing || reply.bad) { toYou(); return; }
    K.meta.config.name = (w.name || '').trim();
    K.meta.email = (w.email || '').trim();
    // the starter steps back first, and the window comes in after it
    const intro = $('.intro');
    if (intro && !calm()) { intro.classList.add('leaving'); await pause(200); }
    K.welcome = null;
    if (stageFit) stageFit.disconnect();
    const app = $('#app');
    app.style.gridTemplateColumns = '';
    drawFrame();
    arrive();
    // Home, unless a row was picked in ⌘K on the last step: then where that
    // row goes, and what it does, the way ⌘K itself would.
    K.page = -1;
    show(pick && pick.page != null ? pick.page : 0, { remember: false });
    if (pick && pick.file) tell('show', { path: pick.file });
    else if (pick && pick.page == null && pick.go) pick.go();
    // what macOS answered about the folders, now that it has been asked
    ask('askFolders').then(r => { if (r && r.seeing && K.meta) K.meta.seeing = r.seeing; });
    // and then what is where, once: not over a row that is still running
    if (!(pick && (pick.go || pick.file))) mapLater(900);
}

/** The window arriving: the side first, one place after another, then the
 *  page. Once, after the starter; never on an ordinary open. */
function arrive() {
    if (calm()) return;
    const app = $('#app');
    app.classList.add('arrive');
    setTimeout(() => app.classList.remove('arrive'), 1100);
}

/* ── what is where ──────────────────────────────────────────────────────

   The first time the window opens, and from Help whenever it is wanted
   again: the window dimmed but for one thing, a few words on it, and the
   light moving on to the next — every place down the side, search,
   sending and the dot in the ring.                                      */

// what each place down the side is for, by the name it has there
const TOUR_PLACES = {
    Home: ['home', 'Your Mac right now: what is on your desktop and in Downloads, and what can be freed. Clean all does the lot.'],
    Desk: ['desk', 'Desktop, Downloads and Documents, sorted into a Tidy folder by type. Nothing is deleted, and every move can go back.'],
    Screen: ['photo', 'Wallpapers, what opens when you log in, and your Dock.'],
    Disk: ['disk', 'What takes the space in your home, and the caches that are safe to clear.'],
    Computer: ['cpu', 'What is running right now, this Mac, and Undo for everything Kliner did.'],
};

function mapLater(ms) {
    setTimeout(() => {
        if (K.welcome || $('.tour') || $('.ksheet') || $('.finder')) return;
        showMap();
    }, ms);
}

/** The steps, from what is in the window right now. */
function tourSteps() {
    const steps = [];
    for (const place of K.meta.places) {
        const el = $('.sb-places .spot.pl[data-page="' + place.holds[0] + '"]');
        const words = TOUR_PLACES[place.title];
        if (el && words) steps.push({ el, sym: words[0], title: place.title, text: words[1], key: place.title === 'Screen' ? ['\\', 'hides the files on your desktop, from anywhere in Kliner'] : null });
    }
    const seek = $('.sb .sb-find');
    if (seek) steps.push({ el: seek, sym: 'search', title: 'Search', text: 'Pages, actions and the files in your folders, found as you type.', key: ['⌘K', 'opens it from any app'] });
    const send = $('.sb-places .spot.pg[data-page="' + SHARE() + '"]');
    if (send) steps.push({ el: send, sym: 'send', title: 'Send to an @username', text: 'Any file, to anyone with Kliner, near or far. Full quality, encrypted from your Mac to theirs.' });
    const state = $('#state');
    if (state) steps.push({ el: state, sym: 'pulse', title: 'What Kliner is doing', text: 'The dot turns while Kliner works and goes green when it is done. Click it for what happened.', side: 'below' });
    return steps;
}

/** What is where: a light on one thing at a time, a few words beside it,
 *  and the light moving on to the next. Enter or → goes on, ← back, Esc
 *  stops. Seen once by itself; Help has it again. */
function showMap() {
    if (K.welcome || $('.tour')) return;
    closeActivity();
    const steps = tourSteps();
    if (!steps.length) return;
    let at = 0;
    const hole = h('div', { class: 'tour-hole' });
    const card = h('div', { class: 'tour-card', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'What is where' });
    const box = h('div', { class: 'tour' + (calm() ? ' calm' : '') }, hole, card);
    const finish = () => {
        box.classList.add('out');
        setTimeout(() => box.remove(), calm() ? 0 : 260);
        window.removeEventListener('resize', place);
        document.removeEventListener('keydown', keys, true);
        if (K.meta.config.tour !== 'done') {
            K.meta.config.tour = 'done';
            tell('setConfig', { key: 'tour', value: 'done' });
        }
    };
    const go = n => { at = Math.max(0, Math.min(steps.length - 1, n)); paint(); };
    const keys = e => {
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(); }
        else if (e.key === 'Enter' || e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); at === steps.length - 1 ? finish() : go(at + 1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); go(at - 1); }
    };
    function place() {
        const s = steps[at];
        const r = s.el.getBoundingClientRect();
        const pad = 5;
        Object.assign(hole.style, { left: (r.left - pad) + 'px', top: (r.top - pad) + 'px', width: (r.width + pad * 2) + 'px', height: (r.height + pad * 2) + 'px' });
        const W = window.innerWidth, H = window.innerHeight;
        const cw = card.offsetWidth || 340, ch = card.offsetHeight || 180;
        let left, top;
        if (s.side === 'below') { left = Math.min(W - cw - 14, Math.max(14, r.right - cw)); top = r.bottom + 16; card.dataset.arrow = 'up'; }
        else { left = r.right + 18; top = Math.max(14, Math.min(H - ch - 14, r.top + r.height / 2 - 34)); card.dataset.arrow = 'left'; }
        card.style.left = left + 'px';
        card.style.top = top + 'px';
        card.style.setProperty('--arrow', (s.side === 'below' ? (r.left + r.width / 2 - left) : (r.top + r.height / 2 - top)) + 'px');
    }
    function paint() {
        const s = steps[at];
        const last = at === steps.length - 1;
        card.replaceChildren(...[
            h('div', { class: 'tc-top' }, h('span', { class: 'tc-ic' }, icon(s.sym)), h('span', { class: 'tc-count' }, (at + 1) + ' of ' + steps.length),
              h('button', { class: 'sq', 'aria-label': 'Close', onclick: finish }, icon('x'))),
            h('h3', null, s.title),
            h('p', null, s.text),
            s.key ? h('div', { class: 'tc-key' }, h('kbd', null, s.key[0]), h('span', null, s.key[1])) : null,
            h('div', { class: 'tc-go' },
                h('div', { class: 'tc-dots' }, steps.map((_, n) => h('i', { class: n === at ? 'on' : n < at ? 'past' : '' }))),
                at > 0 ? h('button', { class: 'btn bare small', onclick: () => go(at - 1) }, 'Back') : null,
                h('button', { class: 'btn fill small', onclick: () => last ? finish() : go(at + 1) }, last ? 'Got it' : 'Next', last ? null : icon('right')))].filter(Boolean));
        card.classList.remove('turn');
        void card.offsetWidth;
        card.classList.add('turn');
        place();
        requestAnimationFrame(place);
        const next = card.querySelector('.btn.fill');
        if (next) next.focus();
    }
    window.addEventListener('resize', place);
    document.addEventListener('keydown', keys, true);
    box.addEventListener('mousedown', e => { if (!card.contains(e.target)) { e.preventDefault(); } });
    document.body.append(box);
    paint();
}

/* ── sending a file to an @username ─────────────────────────────────────

   To a Mac nearby, straight across the network you share. To anyone else,
   through kliner.app, encrypted on this Mac so that only theirs can open
   it. Either way the file goes exactly as it is on disk: not compressed,
   not converted, the same bytes. The other Mac says yes first, and what it
   gets lands in its Downloads under its own name. Every step here is one
   the app says happened; nothing is drawn as done before it is.          */

const SEND = { people: [], jobs: new Map(), queue: [], watching: false, offline: '',
               draft: { file: null, to: '' },   // the file and the name on the Send page
               known: new Map(),                 // what kliner.app said about a name
               recent: null };                   // who you sent to, from Kliner's settings

/** A username as it is typed: small letters, the @ taken off. */
const bareName = s => String(s || '').trim().replace(/^@+/, '').toLowerCase();

/** What is wrong with a name, or '' — the same rules the app checks. */
function nameTrouble(name) {
    if (!name) return '';
    if (name.length < 3) return 'At least 3 characters.';
    if (name.length > 20) return '20 characters at most.';
    if (/[^a-z0-9._]/.test(name)) return 'Small letters, numbers, . and _ only.';
    if (!/^[a-z]/.test(name)) return 'Start with a letter.';
    if (/\.\.|\.$/.test(name)) return 'A dot needs a letter on each side.';
    if (['kliner', 'admin', 'root', 'support', 'help', 'system', 'apple', 'everyone', 'nobody'].includes(name)) return 'That one is kept by Kliner.';
    return '';
}

/* ── one @username, everywhere ──────────────────────────────────────────

   Names live on kliner.app, so one name is one person on every Mac, near or
   far. When kliner.app cannot be reached, the Macs nearby are asked instead,
   as before, and the name is held on this Mac; Kliner claims it on
   kliner.app the first time it can, and says so if somebody got there first. */

async function nameLook(name) {
    const r = await ask('cloudCheck', { name });
    if (!r || r.offline || r.missing) return Object.assign({}, await ask('userCheck', { name }), { local: true });
    return r;
}

/** The name is yours. A Mac that has a name on kliner.app already changes
 *  it there (cloudRename): the same keys, the files on their way follow, and
 *  the old name is kept for you for a week. `code` is the one kliner.app
 *  showed for a name held there. */
async function nameClaim(name, code) {
    const had = bareName(K.meta.config.cloudUser);
    const r = await ask(had && had !== name ? 'cloudRename' : 'cloudClaim', { name, code: code || '' });
    if (!r || r.offline || r.missing) return Object.assign({}, await ask('userClaim', { name }), { local: true });
    if (r.ok && r.user) {
        K.meta.config.cloudUser = r.user;
        if (r.was) { K.meta.config.userWas = r.was; K.meta.config.userWasUntil = String(r.until || ''); }
    }
    return r;
}

/** The day a hold runs out, said the short way: "Oct 23". */
function untilDay(unix) {
    return new Date((+unix || 0) * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

/** A code from kliner.app as it was typed: its letters, upper case, as
 *  XXXXX-XXXXX once there are ten. */
function codeTyped(raw) {
    const s = String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 10);
    return s.length > 5 ? s.slice(0, 5) + '-' + s.slice(5) : s;
}

/** Where a name is held: on kliner.app, or on this Mac until it can be. */
function nameWhere() {
    const mine = bareName(handle());
    if (!mine) return '';
    return bareName(K.meta.config.cloudUser) === mine ? 'cloud' : 'here';
}

/** Everything the app says about files on their way, in or out. */
function sendEvent(ev) {
    if (!ev || typeof ev !== 'object') return;
    // a file held over the window, and let go of
    if (ev.kind === 'drag') { dragOver(!!ev.over); return; }
    if (ev.kind === 'dropped') { dropped(ev.file); return; }
    if (ev.kind === 'nearby') {
        SEND.people = (ev.people || []).map(p => p.user).filter(u => !nameTrouble(u));
        paintNearby();
        return;
    }
    if (ev.kind === 'offline') { SEND.offline = ev.text || ''; paintNearby(); return; }
    if (ev.kind === 'cloudClash') {
        toast('Somebody else has @' + ev.user + ' on kliner.app. Pick another username in Settings.', ['Settings', () => openSettings('profile')], 'x');
        return;
    }
    if (ev.kind === 'clash') {
        toast('Another Mac nearby claimed @' + ev.user + ' first. Pick another username in Settings.', ['Settings', () => openSettings('profile')], 'x');
        return;
    }
    if (ev.kind === 'incoming') {
        SEND.jobs.set(ev.id, { dir: 'in', id: ev.id, from: ev.from, name: ev.name, size: ev.size, state: 'asking', part: 0, at: new Date() });
        SEND.queue.push(ev.id);
        if (!$('.ksheet')) nextIncoming();
        paintTx(SEND.jobs.get(ev.id));
        return;
    }
    const job = SEND.jobs.get(ev.id);
    if (!job) return;
    if (ev.kind === 'progress') {
        job.part = ev.part;
        paintJob(job);
        paintTx(job);
        return;
    }
    if (ev.kind === 'state') {
        job.state = ev.state;
        if (ev.text) job.text = ev.text;
        if (ev.path) job.path = ev.path;
        if (ev.name) job.name = ev.name;
        if (ev.state === 'done') job.part = 1;
        // the island says how it ended for a moment, then closes
        if (ev.state === 'done' || ev.state === 'failed') job.doneAt = Date.now();
        paintJob(job);
        paintTx(job);
        if (ev.state === 'done' && job.dir === 'in') rememberName(job.from);
        if (ev.state === 'done' || ev.state === 'failed') {
            K.jobs.unshift({ page: SHARE(), title: job.dir === 'out' ? 'Sent to @' + job.to : 'From @' + job.from,
                             line: ev.state === 'done' ? job.name + ' · ' + size(job.size || 0) : (job.text || 'It did not work'),
                             good: ev.state === 'done', at: new Date() });
            K.jobs = K.jobs.slice(0, 30);
            K.unread = true;
            if (!K.welcome) setFrame();
        }
    }
}

/** A file on its way to you, in its sheet: where it is, what it is, and the
 *  buttons for that moment. */
function paintJob(job) {
    const sheet = $('.ksheet');
    if (!sheet || sheet.dataset.job !== job.id) return;
    const card = sheet.querySelector('.td');
    if (card) card.replaceChildren(...jobDetail(job));
    const acts = sheet.querySelector('.sh-acts');
    if (acts) acts.replaceChildren(...sheetButtons(job));
}

function sheetButtons(job) {
    const close = h('button', { class: 'btn line large', onclick: closeSheet }, 'Close');
    if (job.state === 'asking' && job.dir === 'in') {
        return [h('button', { class: 'btn line large', onclick: () => { tell('receive', { job: job.id, yes: false }); job.state = 'failed'; job.text = 'You said no.'; paintTx(job); closeSheet(); } }, 'Decline'),
                h('button', { class: 'btn fill large', onclick: () => { tell('receive', { job: job.id, yes: true }); job.state = 'waiting'; paintJob(job); paintTx(job); } }, icon('check'), 'Accept')];
    }
    if (['asking', 'waiting', 'sending', 'receiving'].includes(job.state)) {
        return [h('button', { class: 'btn line large', onclick: () => { tell('sendCancel', { job: job.id }); } }, 'Stop')];
    }
    if (job.state === 'done' && job.dir === 'in' && job.path) {
        return [close, h('button', { class: 'btn fill large', onclick: () => tell('showReceived', { path: job.path }) }, icon('finder'), 'Show in Finder')];
    }
    return [h('button', { class: 'btn fill large', onclick: closeSheet }, 'Done')];
}

/** The window over the window. One at a time. */
function openSheet(kids, cls) {
    closeSheet(true);
    const card = h('div', { class: 'sheet-card ' + (cls || '') }, kids);
    const box = h('div', { class: 'ksheet' }, card);
    box.addEventListener('mousedown', e => { if (e.target === box) closeSheet(); });
    box._keys = e => {
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeSheet(); }
    };
    document.addEventListener('keydown', box._keys, true);
    document.body.append(box);
    return box;
}
/** The sheet goes the way it came, unless another is taking its place
 *  (`now`), which is at once. Either way it stops being the open one at
 *  once: `.ksheet` is only ever the one you can use. */
function closeSheet(now) {
    const box = $('.ksheet');
    if (!box) return;
    document.removeEventListener('keydown', box._keys, true);
    if (box._close) box._close();
    if (now === true) box.remove();
    else leave(box, 'ksheet');
    if (SEND.queue.length) setTimeout(nextIncoming, 120);
}

/** The next file somebody is sending you, as its own question. */
function nextIncoming() {
    while (SEND.queue.length) {
        const id = SEND.queue.shift();
        const job = SEND.jobs.get(id);
        if (!job || job.state !== 'asking') continue;
        const box = openSheet([
            h('div', { class: 'sh-head' }, h('h2', null, '@' + job.from + ' is sending you a file'),
              h('button', { class: 'sq', 'aria-label': 'Close', onclick: closeSheet }, icon('x'))),
            h('div', { class: 'td' }),
            h('p', { class: 'sh-small' }, 'It goes into Downloads exactly as it was sent. Nothing opens by itself.'),
            h('div', { class: 'sh-acts' })], 'in');
        box.dataset.job = id;
        paintJob(job);
        return;
    }
}

/* ── one file on its way, the way his pull request is ──
   A line in its own colour that says where it is — green while it goes and
   once it is there, red when it did not, grey while somebody is asked —
   then its name, how far along it is, and what there is to know about it
   as names and values: who it is for or from, how big, how it travels,
   when it started. The same on the Send page and in the sheet that asks
   you about one coming to you. */

function jobState(job) {
    const pct = Math.round((job.part || 0) * 100) + '%';
    const out = job.dir === 'out';
    switch (job.state) {
        case 'asking': return { tone: '', text: out ? 'Waiting for @' + job.to + ' to say yes' : 'Asking you first' };
        case 'waiting': return job.text && out ? { tone: 'good', icon: 'check', text: 'Uploaded' } : { tone: '', text: 'Starting…' };
        case 'sending': return { tone: 'good', icon: 'up', text: 'Sending · ' + pct };
        case 'receiving': return { tone: 'good', icon: 'arrdown', text: 'Receiving · ' + pct };
        case 'done': return { tone: 'good', icon: 'check', text: out ? 'Delivered' : 'Received' };
        case 'failed': return { tone: 'bad', icon: 'x', text: out ? 'Not sent' : 'Not received' };
    }
    return { tone: '', text: '' };
}

/** Somebody, the way a person is shown here: their first letter in a
 *  circle, and their @username. */
function whoChip(name) {
    const u = bareName(name);
    return h('span', { class: 'lv-who' }, h('span', { class: 'pf' }, (u || '?').charAt(0).toUpperCase()), '@' + (u || '…'));
}

function jobDetail(job) {
    const st = jobState(job);
    const out = job.dir === 'out';
    const share = job.state === 'done' ? 1 : job.state === 'sending' || job.state === 'receiving' ? Math.max(0, Math.min(1, job.part || 0)) : 0;
    const rows = [[out ? 'To' : 'From', whoChip(out ? job.to : job.from)], ['Size', job.size != null ? size(job.size) : '…']];
    if (out && job.route) rows.push(['Route', job.route === 'near' ? 'Nearby, across your network' : 'Through kliner.app, encrypted']);
    if (!out) rows.push(['Lands in', 'Downloads, under its own name']);
    if (job.at) rows.push([out ? 'Started' : 'Asked', job.at.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })]);
    const why = job.text && (job.state === 'failed' || job.state === 'waiting') ? job.text : '';
    return [
        h('div', { class: 'td-st' + (st.tone ? ' ' + st.tone : '') }, st.icon ? icon(st.icon) : h('i', { class: 'spin' }), h('span', null, st.text)),
        h('div', { class: 'td-name', title: job.name }, job.name),
        h('div', { class: 'td-bar' + (st.tone === 'bad' ? ' bad' : '') + (job.state === 'sending' || job.state === 'receiving' ? ' go' : '') },
          h('i', { style: `width:${(share * 100).toFixed(1)}%;${sheenAt()}` })),
        h('dl', { class: 'lv' }, rows.map(([k, v]) => h('div', null, h('dt', null, k), h('dd', null, v)))),
        why ? h('p', { class: 'td-why' }, why) : null,
    ].filter(Boolean);
}

/* ── the Send page ──────────────────────────────────────────────────────
   The box you send from is at the foot of the pane on the right, on every
   page, the way his pane has the box you ask in: who it is for, the file
   and the people as round chips, one round button. A file on its way is
   the pane's top while it goes. This page is the people — the Macs nearby,
   live, then whoever you sent to before, each a row with Send — and every
   file on its way or arrived since Kliner opened. A file can be dropped
   anywhere on the window. Somebody sending you one still asks you first,
   over everything else. */

/** The people you have sent files to, newest first: kept in Kliner's own
 *  settings, so they are there the next time. Only names that are names. */
function recentNames() {
    if (!SEND.recent) {
        SEND.recent = String((K.meta && K.meta.config.sent) || '').split(',').map(bareName)
            .filter(u => u && !nameTrouble(u)).slice(0, 8);
    }
    return SEND.recent;
}
function rememberName(name) {
    const u = bareName(name);
    if (!u || nameTrouble(u)) return;
    SEND.recent = [u, ...recentNames().filter(x => x !== u)].slice(0, 8);
    if (K.meta) K.meta.config.sent = SEND.recent.join(',');
    tell('setConfig', { key: 'sent', value: SEND.recent.join(',') });
}

/** Looking for Macs nearby, only while the page that shows them is open. */
function watchNearby(on) {
    if (SEND.watching === on) return;
    SEND.watching = on;
    tell('nearby', { on });
}

function drawShare(out) {
    const me = bareName(handle());
    watchNearby(true);
    out.classList.add('dpage', 'col', 'sendp');
    out.append(
        h('header', { class: 'dh' }, h('div', { class: 'dh-w' }, h('h1', null, 'Send')),
            h('div', { class: 'dh-acts' }, h('button', { class: 'btn fill', onclick: () => openSend() }, icon('plus'), 'Send a file'))),
        panel('dpeople', dcap('user', 'People', h('span', { class: 'dc-n', id: 'sndNear' })), h('div', { class: 'tl', id: 'sndPeople' })),
        panel('dtx', dcap('list', 'Transfers'), h('div', { class: 'tl tx', id: 'txList' })));
    // with the pane beside the page, you and how a file travels are in it;
    // without it, they are here
    if (!inspBeside()) out.append(addressCard(me));
    paintPeople(out);
    paintTransfers(out);
}

/* ── the box you send from ── */

function paintComposer(root) {
    const scope = root || document;
    const box = scope.querySelector('#snd');
    if (!box) return;
    const d = SEND.draft;
    const field = h('input', { class: 'snd-field', id: 'sndTo', placeholder: 'Send to @username', spellcheck: 'false', autocapitalize: 'off',
                               autocomplete: 'off', maxlength: '21', 'aria-label': 'Send to' });
    field.value = d.to;
    field.addEventListener('input', () => {
        field.value = field.value.replace(/^@+/, '');
        d.to = bareName(field.value);
        paintWho();
    });
    field.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); sendNow(); } });
    box.replaceChildren(
        h('div', { class: 'sc-top' }, h('label', { class: 'sc-to', for: 'sndTo' }, h('span', { class: 'at' }, '@'), field)),
        h('div', { class: 'snd-who', id: 'sndWho' }),
        h('div', { class: 'sc-foot' },
            h('div', { class: 'sc-chips' }, h('span', { class: 'sc-file', id: 'sndFile' }), h('span', { class: 'sc-people', id: 'scPeople' })),
            h('button', { class: 'sc-go', id: 'sndGo', disabled: true, 'aria-label': 'Send', 'data-tip': 'Send', onclick: sendNow }, icon('up'))));
    paintFile(scope);
    paintChips(scope);
    paintWho(scope);
}

/** The file, as the first chip: the way to choose one, or the one chosen
 *  with the way to take it off again. */
function paintFile(root) {
    const el = (root || document).querySelector('#sndFile');
    if (!el) return;
    const f = SEND.draft.file;
    const drops = !!(K.meta && K.meta.drop);
    if (!f) {
        el.replaceChildren(h('button', { class: 'sc-chip', onclick: pickFile, title: drops ? 'Or drop one anywhere on this window' : null },
            icon('plus'), 'File'));
        return;
    }
    el.replaceChildren(h('span', { class: 'sc-chip file', title: f.name + ' · ' + size(f.size || 0) + ', exactly as it is' },
        h('button', { class: 'chip-in', onclick: pickFile, 'aria-label': 'Choose another file' },
            f.icon && goodPicture(f.icon) ? h('img', { src: f.icon, alt: '' }) : icon('file'),
            h('b', null, f.name), h('span', null, size(f.size || 0))),
        h('button', { class: 'chip-x', 'aria-label': 'Take the file off', onclick: () => { SEND.draft.file = null; paintFile(); paintWho(); } }, icon('x'))));
}

async function pickFile() {
    const r = await ask('sendPick');
    if (!r || r.cancelled || r.missing) return;
    if (!r.ok) { toast(r.text || 'That cannot be sent.', null, 'x'); return; }
    SEND.draft.file = r;
    paintFile();
    paintWho();
    const f = $('#sndTo');
    if (f) f.focus();
}

/** Who a name is — a Mac nearby, somebody on kliner.app, or nobody yet — and
 *  whether everything is there for Send. kliner.app is asked once a name
 *  has stood still for a moment; what it said is kept, except that it could
 *  not be reached, which is asked again a little later. */
let lookTimer = 0, lookTurn = 0;
function lookName(to) {
    clearTimeout(lookTimer);
    const turn = ++lookTurn;
    lookTimer = setTimeout(async () => {
        const r = await ask('cloudCheck', { name: to });
        const who = !r || r.offline || r.missing ? 'away' : r.taken ? 'there' : r.held ? 'moved'
            : r.ok && (r.free || r.claimed) ? 'nobody' : 'away';
        SEND.known.set(to, { who, at: Date.now() });
        if (turn === lookTurn) paintWho();
    }, 350);
}
function whoIs(to) {
    if (SEND.people.includes(to)) return 'near';
    const seen = SEND.known.get(to);
    if (!seen || (seen.who === 'away' && Date.now() - seen.at > 30000)) return '';
    return seen.who;
}

function paintWho(root) {
    const at = sel => (root || document).querySelector(sel);
    const d = SEND.draft, me = bareName(handle());
    const to = d.to;
    const trouble = nameTrouble(to);
    const who = to && !trouble && to !== me ? whoIs(to) : '';
    if (to && !trouble && to !== me && !who) lookName(to);
    const go = at('#sndGo');
    if (go) go.disabled = !(d.file && to && !trouble && to !== me && who && who !== 'nobody' && who !== 'moved' && me);
    const el = at('#sndWho');
    if (el) {
        let line, tone = '';
        if (!me) line = [icon('at'), 'Pick your @username first. ', h('button', { class: 'link', onclick: () => openSettings('profile') }, 'Settings')];
        else if (!to) line = null;
        else if (to === me) line = [icon('user'), 'That is you.'];
        else if (trouble) { line = [icon('x'), trouble]; tone = 'bad'; }
        else if (who === 'near') { line = [icon('wifi'), h('b', null, '@' + to), ' is nearby.']; tone = 'ok'; }
        else if (who === 'there') { line = [icon('globe'), h('b', null, '@' + to), ' is on kliner.app.']; tone = 'ok'; }
        else if (who === 'nobody') { line = [icon('x'), 'Nobody is called ', h('b', null, '@' + to), ' yet.']; tone = 'bad'; }
        else if (who === 'moved') { line = [icon('x'), h('b', null, '@' + to), ' changed their username. Ask them for the new one.']; tone = 'bad'; }
        else if (who === 'away') line = [icon('globe'), 'Offline. Macs nearby only.'];
        else line = [h('i', { class: 'spin' }), 'Looking for ', h('b', null, '@' + to), '…'];
        el.className = 'snd-who' + (tone ? ' ' + tone : '');
        // the picture, then the words as one run, so the gap between the
        // two never lands between words; nothing at all while there is
        // nothing to say
        el.replaceChildren(...(line ? [line[0], h('span', null, ...line.slice(1))] : []));
    }
    for (const b of document.querySelectorAll('.sp[data-user]')) b.classList.toggle('on', b.dataset.user === to);
}

/** The people, on the Send page: the Macs nearby, live, then whoever you
 *  sent to before, each a row with Send. */
function paintPeople(root) {
    const at = sel => (root || document).querySelector(sel);
    const me = bareName(handle());
    const nearby = SEND.people.filter(u => u !== me);
    const count = at('#sndNear');
    if (count) count.replaceChildren(...(nearby.length ? [h('i', { class: 'ldot' }), plural(nearby.length, 'Mac') + ' nearby'] : []));
    const el = at('#sndPeople');
    if (!el) return;
    const recent = recentNames().filter(u => u !== me && !nearby.includes(u));
    const rows = [...nearby.map(u => personRow(u, true)), ...recent.map(u => personRow(u, false))];
    el.replaceChildren(...(rows.length ? rows : [h('div', { class: 'd-none' }, SEND.offline || 'No one nearby right now.')]));
    for (const b of el.querySelectorAll('.sp')) b.classList.toggle('on', b.dataset.user === SEND.draft.to);
}

/** Somebody you can send to, as a row: their first letter, their name,
 *  nearby or sent to before, and Send. */
function personRow(u, near) {
    return h('div', { class: 'tl-row sp' + (near ? ' near' : ''), 'data-user': u },
        h('span', { class: 'tl-ic pf' }, u.charAt(0).toUpperCase()),
        h('span', { class: 'tl-w' }, h('b', null, '@' + u), h('span', null, near ? 'Nearby' : 'Sent before')),
        h('button', { class: 'btn line small tl-do', onclick: () => sendTo(u) }, 'Send'));
}

/** The people as chips in the box, the few nearest first: a click puts the
 *  name in. */
function paintChips(root) {
    const el = (root || document).querySelector('#scPeople');
    if (!el) return;
    const me = bareName(handle());
    const nearby = SEND.people.filter(u => u !== me);
    const recent = recentNames().filter(u => u !== me && !nearby.includes(u));
    const chip = (u, near) => h('button', { class: 'sc-chip sp' + (near ? ' near' : ''), 'data-user': u,
                                            title: near ? '@' + u + ' is on a Mac nearby' : 'You sent to @' + u + ' before', onclick: () => {
        SEND.draft.to = u;
        const f = $('#sndTo');
        if (f) { f.value = u; f.focus(); }
        paintWho();
    } }, h('span', { class: 'pf' }, u.charAt(0).toUpperCase()), '@' + u);
    const many = 2;
    el.replaceChildren(...[...nearby.map(u => chip(u, true)), ...recent.map(u => chip(u, false))].slice(0, many));
    for (const b of el.querySelectorAll('.sp')) b.classList.toggle('on', b.dataset.user === SEND.draft.to);
}

function paintNearby() {
    paintPeople();
    paintChips();
    paintWho();
    paintHomeTx();
    if (K.page === SHARE()) paintInsp();
}

/** Somebody's Send: their name in the box, and the file next — the Mac's
 *  own chooser, unless one is already in it. */
function sendTo(u) {
    SEND.draft.to = bareName(u);
    if (!INSP.open) toggleInsp(true);
    const f = $('#sndTo');
    if (f) f.value = SEND.draft.to;
    paintWho();
    if (!SEND.draft.file) pickFile();
    else if (f) f.focus();
}

async function sendNow() {
    const d = SEND.draft, to = d.to;
    const go = $('#sndGo');
    if (!d.file || !to || !go || go.disabled) return;
    go.disabled = true;
    // the way the app will send it: across the network to a Mac it can see,
    // and through kliner.app to anyone else once your name is there
    const route = SEND.people.includes(to) || nameWhere() !== 'cloud' ? 'near' : 'cloud';
    const r = await ask('send', { token: d.file.token, to });
    if (!r || !r.ok) {
        const el = $('#sndWho');
        if (el) { el.className = 'snd-who bad'; el.replaceChildren(icon('x'), h('span', null, (r && r.text) || 'That did not go.')); }
        go.disabled = false;
        return;
    }
    const job = { dir: 'out', id: r.id, to: bareName(r.to) || to, name: r.name || d.file.name, size: r.size != null ? r.size : d.file.size,
                  icon: d.file.icon, state: 'asking', part: 0, at: new Date(), route };
    SEND.jobs.set(r.id, job);
    rememberName(job.to);
    // the file goes on in the pane's top; the box is ready for the next one
    INSP.pick = { kind: 'job', id: r.id };
    SEND.draft = { file: null, to: '' };
    paintComposer();
    paintTransfers();
    paintPeople();
    paintHomeTx();
    if (!INSP.open) toggleInsp(true); else paintInsp();
}

/* ── every file on its way or arrived ── */

const ACTIVE = ['asking', 'waiting', 'sending', 'receiving'];

/** A bar that is filling has a light running along it. The bar is drawn
 *  again every time the file moves on, so each new one starts the light
 *  where the last one had it, and it runs on rather than starting over. */
const sheenAt = () => `animation-delay:-${Math.round(performance.now() % 1600)}ms`;

/** Where a file is, as a pill, or as a bar while it moves. */
function txStatus(j) {
    const pct = Math.round((j.part || 0) * 100);
    if (j.state === 'done') return h('span', { class: 'pill good' }, icon('check'), j.dir === 'out' ? 'Delivered' : 'Received');
    if (j.state === 'failed') {
        const why = j.text || '';
        const word = /said no|declined/i.test(why) ? 'Declined' : /^Stopped/.test(why) ? 'Stopped' : /nobody answered/i.test(why) ? 'Not answered' : 'Failed';
        return h('span', { class: 'pill' + (word === 'Failed' ? ' bad' : ''), title: why }, icon('x'), word);
    }
    if (j.state === 'sending' || j.state === 'receiving') {
        return h('span', { class: 'tx-prog' }, h('span', { class: 'tx-track go' }, h('i', { style: `width:${pct}%;${sheenAt()}` })), h('b', null, pct + '%'));
    }
    return h('span', { class: 'pill' }, h('i', { class: 'spin' }),
             j.state === 'asking' ? (j.dir === 'out' ? 'Waiting for yes' : 'Asking you') : j.text && j.dir === 'out' ? 'Uploaded' : 'Starting');
}

/** One transfer as a row, the way his pull requests are: a round picture,
 *  the file and who it is with, where it is, and what you can do now. A
 *  click shows it in the pane. */
function txRow(j, open) {
    const out = j.dir === 'out';
    const why = j.state === 'failed' && j.text ? j.text : '';
    const acts = [];
    if (j.dir === 'in' && j.state === 'asking') {
        acts.push(h('button', { class: 'btn line small', onclick: e => {
            e.stopPropagation();
            if (!SEND.queue.includes(j.id)) SEND.queue.unshift(j.id);
            if (!$('.ksheet')) nextIncoming();
        } }, 'Answer'));
    }
    if (ACTIVE.includes(j.state)) acts.push(h('button', { class: 'btn line small', onclick: e => { e.stopPropagation(); tell('sendCancel', { job: j.id }); } }, 'Stop'));
    if (j.state === 'done' && j.dir === 'in' && j.path) {
        acts.push(h('button', { class: 'btn line small', onclick: e => { e.stopPropagation(); tell('showReceived', { path: j.path }); } }, 'Show'));
    }
    const when = j.at ? j.at.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : '';
    const pick = open || (() => { INSP.pick = { kind: 'job', id: j.id }; if (!INSP.open) toggleInsp(true); else paintInsp(); });
    return h('div', { class: 'tl-row tx-row go', 'data-job': j.id, 'data-pick': 'job:' + j.id, role: 'button', tabindex: '0', onclick: pick,
                      onkeydown: e => { if ((e.key === 'Enter' || e.key === ' ') && e.target === e.currentTarget) { e.preventDefault(); pick(); } } },
        h('span', { class: 'tl-ic tx-ic ' + j.dir }, icon(out ? 'up' : 'arrdown')),
        h('span', { class: 'tl-w' }, h('b', { title: j.name }, j.name),
            h('span', { title: why || null }, why || [(out ? 'To @' + j.to : 'From @' + j.from), j.size != null ? size(j.size) : '', when].filter(Boolean).join(' · '))),
        h('span', { class: 'tx-st' }, txStatus(j)),
        acts.length ? h('span', { class: 'tx-act' }, acts) : null);
}

function paintTransfers(root) {
    const el = (root || document).querySelector('#txList');
    if (!el) return;
    const jobs = [...SEND.jobs.values()].reverse();
    if (!jobs.length) {
        el.replaceChildren(h('div', { class: 'd-none' }, 'Nothing yet.'));
        return;
    }
    el.replaceChildren(...jobs.map(txRow));
    const key = INSP.pick && INSP.pick.kind === 'job' ? 'job:' + INSP.pick.id : '';
    for (const r of el.querySelectorAll('[data-pick]')) r.classList.toggle('is-picked', INSP.open && r.dataset.pick === key);
}

/** One row again, when only it moved: a file's progress comes many times a
 *  second, and redrawing the whole list for each would be the list
 *  flickering. Once a frame at most, the pane with it when it is showing
 *  that file. */
const TX_OWED = new Set();
let txFrame = 0;
function paintTx(job) {
    TX_OWED.add(job.id);
    if (txFrame) return;
    txFrame = requestAnimationFrame(() => {
        txFrame = 0;
        const list = $('#txList');
        let pane = false;
        for (const id of TX_OWED) {
            const j = SEND.jobs.get(id);
            const row = list && list.querySelector(`.tx-row[data-job="${CSS.escape(id)}"]`);
            if (!j) continue;
            if (row) {
                const fresh = txRow(j);
                fresh.classList.toggle('is-picked', row.classList.contains('is-picked'));
                row.replaceWith(fresh);
            } else if (list) paintTransfers();
            if (INSP.pick && INSP.pick.kind === 'job' && INSP.pick.id === id) pane = true;
        }
        TX_OWED.clear();
        if (pane) paintInsp();
        paintHomeTx();
    });
    paintIsland();
}

/* ── v19: the island ─────────────────────────────────────────────────────
   transitions.dev and beui both have one: the pill at the top of an iPhone
   that grows into whatever is going on. Here it is a file on its way, in
   the middle of the bar on every page but Send (whose pane shows it
   already), and on Home only while its send card has scrolled the file
   out of sight: a ring filling as it goes, the file's name and how far; then a
   moment of Delivered or Received, and it closes. A click takes you to it —
   or, for a file somebody is sending you, to the question. It is drawn in
   place, so the ring and the width ease from one state to the next, and it
   is only ever as wide as the room between the bar's two sides. */

const ISLAND = { frame: 0, timer: 0, w: 0, told: 0 };
const ISL_C = 2 * Math.PI * 8;

function islandEl() {
    return h('button', { class: 'isl', id: 'island', 'data-hole': '', hidden: true, onclick: islandGo },
        h('span', { class: 'isl-in' },
            h('span', { class: 'isl-ring' },
                s('svg', { viewBox: '0 0 20 20', 'aria-hidden': 'true' },
                    s('circle', { class: 'tr', cx: 10, cy: 10, r: 8 }),
                    s('circle', { class: 'arc', cx: 10, cy: 10, r: 8, transform: 'rotate(-90 10 10)' })),
                icon('check', 'isl-ok'), icon('x', 'isl-no')),
            h('span', { class: 'isl-t' }),
            h('b', { class: 'isl-p' })));
}

function paintIsland() {
    if (ISLAND.frame) return;
    ISLAND.frame = requestAnimationFrame(() => { ISLAND.frame = 0; drawIsland(); });
}
window.addEventListener('resize', paintIsland);

/** The file the island is about: the newest one on its way, or else one
 *  that got there (or did not) in the last few seconds. */
function islandJob() {
    let live = null, more = 0, last = null;
    for (const j of SEND.jobs.values()) {
        if (ACTIVE.includes(j.state)) { if (live) more++; live = j; }
        else if (j.doneAt && Date.now() - j.doneAt < 3600) last = j;
    }
    return live ? { job: live, more } : last ? { job: last, more: 0 } : null;
}

/** Home's send card lists the last files: while the row of the one the
 *  island is about is in sight there, the island would say it twice. */
function homeSaysIt(job) {
    if (K.page !== 0 || !job) return false;
    const row = $(`#homeTx .tx-row[data-job="${CSS.escape(job.id)}"]`), sc = $('#scroll');
    if (!row || !sc) return false;
    const r = row.getBoundingClientRect(), v = sc.getBoundingClientRect();
    return r.height > 0 && r.bottom > v.top + 8 && r.top < v.bottom - 8;
}

function drawIsland() {
    const el = $('#island');
    if (!el) return;
    clearTimeout(ISLAND.timer);
    let pick = !K.meta || K.welcome || K.page === SHARE() ? null : islandJob();
    if (pick && homeSaysIt(pick.job)) pick = null;
    if (!pick) {
        if (!el.hidden && !el.classList.contains('closing')) {
            el.classList.add('closing');
            el.classList.remove('opening');
            ISLAND.timer = setTimeout(() => { el.hidden = true; el.classList.remove('closing'); el.style.width = ''; reportChrome(); }, calm() ? 0 : 260);
        }
        return;
    }
    const j = pick.job, out = j.dir === 'out';
    const who = '@' + (out ? j.to : j.from);
    const part = j.state === 'done' ? 1 : Math.max(0, Math.min(1, j.part || 0));
    const moving = j.state === 'sending' || j.state === 'receiving';
    const words = j.state === 'done' ? (out ? 'Delivered to ' + who : 'Received from ' + who)
        : j.state === 'failed' ? (out ? 'Not sent to ' + who : 'Not received')
        : j.state === 'asking' ? (out ? 'Waiting for ' + who : who + ' is sending you a file')
        : moving ? j.name : 'Starting ' + j.name;
    el.dataset.state = j.state;
    el.dataset.job = j.id;
    el.dataset.tip = j.dir === 'in' && j.state === 'asking' ? 'Answer ' + who
        : (out ? 'To ' : 'From ') + who + ' · ' + j.name + (pick.more ? ' · and ' + plural(pick.more, 'more file') : '');
    el.setAttribute('aria-label', words + (moving ? ', ' + Math.round(part * 100) + '%' : ''));
    el.querySelector('.arc').style.strokeDasharray = `${(part * ISL_C).toFixed(2)} ${ISL_C.toFixed(2)}`;
    el.querySelector('.isl-p').textContent = moving ? Math.round(part * 100) + '%' : '';
    const t = el.querySelector('.isl-t');
    if (t.textContent !== words) {
        t.textContent = words;
        // new words come in out of a little blur
        if (!calm()) { t.classList.remove('swap'); void t.offsetWidth; t.classList.add('swap'); }
    }
    // the room it has: the middle of the bar when it fits there, else the
    // middle of what is free between the bar's two sides; its words go
    // first when even that is too little, and the island itself last
    const bar = el.parentElement, br = bar.getBoundingClientRect(), mid = br.left + br.width / 2;
    let leftEnd = br.left + 12, rightStart = br.right - 12;
    for (const kid of ($('#where') || bar).children) { const r = kid.getBoundingClientRect(); if (r.width) leftEnd = Math.max(leftEnd, r.right); }
    const right = bar.querySelector('.right');
    for (const kid of right ? right.children : []) { const r = kid.getBoundingClientRect(); if (r.width) rightStart = Math.min(rightStart, r.left); }
    const free = rightStart - leftEnd - 24, round = 2 * Math.min(mid - leftEnd, rightStart - mid) - 24;
    const opening = el.hidden || el.classList.contains('closing');
    el.classList.remove('closing');
    el.hidden = false;
    const inner = el.querySelector('.isl-in');
    const measure = (words, most) => {
        el.classList.toggle('small', !words);
        t.style.maxWidth = most + 'px';
        return inner.offsetWidth + 20;
    };
    let want = measure(true, 300);
    if (want > free) want = measure(true, Math.max(0, free - 130));
    if (want > free || free < 190) want = measure(false, 0);
    if (want > free) { el.hidden = true; el.classList.remove('opening'); return; }
    const at = ((want <= round ? mid : (leftEnd + rightStart) / 2) - br.left).toFixed(1) + 'px';
    if (opening) {
        // it opens where it is to be, from a dot, and grows from there
        el.style.transition = 'none';
        el.style.left = at;
        el.style.width = '36px';
        void el.offsetWidth;
        el.style.transition = '';
        if (!calm()) { el.classList.remove('opening'); void el.offsetWidth; el.classList.add('opening'); }
        reportChrome();
    } else el.style.left = at;
    el.style.width = want + 'px';
    // the window is dragged by the bar, less what can be pressed in it: the
    // island is told to it again once it has grown to its new width
    if (ISLAND.w !== want) { ISLAND.w = want; clearTimeout(ISLAND.told); ISLAND.told = setTimeout(reportChrome, 620); }
    if (j.doneAt) ISLAND.timer = setTimeout(paintIsland, Math.max(0, 3600 - (Date.now() - j.doneAt)) + 40);
}

function islandGo() {
    const el = $('#island');
    const j = el && SEND.jobs.get(el.dataset.job);
    if (!j) return;
    if (j.dir === 'in' && j.state === 'asking') {
        if (!SEND.queue.includes(j.id)) SEND.queue.unshift(j.id);
        if (!$('.ksheet')) nextIncoming();
        return;
    }
    INSP.pick = { kind: 'job', id: j.id };
    show(SHARE());
    if (!INSP.open && inspFits()) toggleInsp(true);
}

/* ── your name ── */

/** You, as names and values: your @username, where it is held, and whether
 *  Macs nearby can send you files. On the page only while the pane, which
 *  says the same, is not beside it. */
function addressCard(me) {
    const where = nameWhere();
    const receive = K.meta.config.receive !== 'off';
    const note = h('span', { class: 'lv-sub' }, me ? 'They see @' + me + ' while this is on.' : 'Pick a username first.');
    const sw = h('button', { class: 'switch' + (receive && me ? ' on' : ''), disabled: !me, 'aria-label': 'Macs nearby can send you files',
                             onclick: async e => {
                                 const b = e.currentTarget;
                                 const r = await ask('receiving', { on: !b.classList.contains('on') });
                                 const on = !!(r && r.on);
                                 K.meta.config.receive = on ? 'on' : 'off';
                                 b.classList.toggle('on', on);
                             } });
    return panel('daddr', dcap('at', 'You'),
        h('dl', { class: 'lv' },
            h('div', null, h('dt', null, 'Username'),
                h('dd', null, me ? whoChip(me) : h('button', { class: 'btn line small', onclick: () => openSettings('profile') }, 'Pick a username'))),
            h('div', null, h('dt', null, 'Where'),
                h('dd', { class: 'ad-where' + (where === 'cloud' ? ' ok' : '') }, h('i', { class: 'dot' }),
                    where === 'cloud' ? 'On kliner.app. Anyone with Kliner can send you a file.'
                        : where === 'here' ? 'On this Mac. Kliner claims it on kliner.app as soon as it can.' : 'Nowhere yet.')),
            h('div', null, h('dt', null, 'Macs nearby'), h('dd', null, note, sw))));
}

/** The box, with a file in it: one picked from a folder on a page, or
 *  dropped on the window. Without one, the Mac's own chooser opens. The box
 *  is in the pane on every page, so nothing moves you anywhere. */
async function openSend(held) {
    if (!K.meta || K.welcome) return;
    if (held) SEND.draft.file = held;
    // Home has the box on it: the file goes in there, and Home stays
    if (K.page === 0 && $('#homeSnd #snd')) {
        paintComposer();
        const card = $('#homeSnd');
        if (card) card.scrollIntoView({ behavior: calm() ? 'auto' : 'smooth', block: 'nearest' });
        if (!held && !SEND.draft.file) pickFile();
        else requestAnimationFrame(() => { const f = $('#sndTo'); if (f && !SEND.draft.to) f.focus(); });
        return;
    }
    if (!paneHere()) show(SHARE());
    if (!INSP.open) toggleInsp(true);
    paintComposer();
    if (!held && !SEND.draft.file) pickFile();
    else requestAnimationFrame(() => { const f = $('#sndTo'); if (f && !SEND.draft.to) f.focus(); });
}

/* ── a file dragged onto the window ── */

/** While a file is held over the window, the window says what letting go
 *  of it will do. */
function dragOver(on) {
    if (!K.meta || K.welcome) return;
    let veil = $('#dropVeil');
    if (on && !veil) {
        veil = h('div', { class: 'drop-veil', id: 'dropVeil', 'aria-hidden': 'true' },
            h('div', { class: 'dv-card' }, h('span', { class: 'dv-ic' }, icon('upload')), h('b', null, 'Drop to send'),
              h('span', null, 'Exactly as it is, to any @username.')));
        document.body.append(veil);
        void veil.offsetWidth;
    }
    if (veil) veil.classList.toggle('show', on);
    document.body.classList.toggle('dropping', on);
}

function dropped(file) {
    dragOver(false);
    if (!K.meta || K.welcome) return;
    if (!file || !file.ok) { toast((file && file.text) || 'That cannot be sent.', null, 'x'); return; }
    if (file.many > 1) toast('One file at a time, so Kliner took ' + file.name + '.', null);
    openSend(file);
}

/** A file on your desktop, sent from where it is. */
async function sendThing(page, name) {
    const r = await ask('sendItem', { page, name });
    if (!r || !r.ok) { toast((r && r.text) || 'That cannot be sent.', null, 'x'); return; }
    openSend(r);
}

/* ── after Kliner tidies: what it did, where it went, and its name ──────

   Not a line that says "Tidy" and goes away. A small window: what moved,
   how many, the folder it went into — whose name you can change right
   there, the records of every move following it — and the ways on from
   it: see it in Finder, or put it all back.                             */

const PLACE_WORDS = { desktop: 'your Desktop', downloads: 'Downloads', documents: 'Documents' };

/** How many things nimo said it filed away, from its own words. */
function filedCount(reply) {
    const good = (parse(reply.text || '').find(p => p.k === 'good') || {}).text || '';
    const m = good.match(/(\d[\d,]*)\s+items?\b/);
    return m ? parseInt(m[1].replace(/,/g, ''), 10) : null;
}

/** The window after a tidy: one place or several. `results` are the app's
 *  own answers, one per page; only the ones that moved something are said. */
function tidyResult(results) {
    const moved = results.filter(r => r && r.ok && r.changed && ['desktop', 'downloads', 'documents', 'clean'].includes(kind(r.page)));
    if (!moved.length) return false;
    const folders = moved.filter(r => kind(r.page) !== 'clean');
    const freed = moved.find(r => kind(r.page) === 'clean');
    const total = folders.reduce((a, r) => a + (filedCount(r) || 0), 0);
    const one = folders.length === 1 && !freed ? folders[0] : null;
    const title = one ? 'Kliner tidied ' + PLACE_WORDS[kind(one.page)]
                      : freed && !folders.length ? 'Kliner freed up space' : 'Kliner cleaned your Mac';
    const sub_ = one ? (total ? plural(total, 'thing') + ', sorted by type. Nothing was deleted.' : 'Sorted by type. Nothing was deleted.')
                     : 'Every move was written down, so all of it can go back.';
    const rows = h('div', { class: 'tr-rows' });
    // one place: its Show is the Show in Finder at the bottom, not a second one
    for (const r of folders) rows.append(tidyRow(r, !one));
    if (freed) {
        const said = (parse(freed.text || '').find(p => p.k === 'good') || {}).text || 'Caches cleared';
        rows.append(h('div', { class: 'tr-row' }, h('span', { class: 'tr-ic' }, icon('sparkles')),
            h('div', { class: 'tr-what' }, h('b', null, 'App caches and the Trash'), h('span', null, said))));
    }
    const undoPage = pages().findIndex(p => p.kind === 'undo');
    const undo = one
        ? h('button', { class: 'btn bare large', onclick: () => { closeSheet(); const ex = pages()[one.page].extras.findIndex(x => /undo/i.test(x.title)); if (ex >= 0) extra(one.page, ex); } }, icon('undo'), 'Put it back')
        : undoPage >= 0 ? h('button', { class: 'btn bare large', onclick: () => { closeSheet(); show(undoPage); } }, icon('undo'), 'Undo…') : null;
    openSheet([
        h('div', { class: 'tr-top' }, h('span', { class: 'tr-art' }, folderArt('')),
          h('div', null, h('h2', null, title), h('p', null, sub_)),
          h('button', { class: 'sq', 'aria-label': 'Close', onclick: closeSheet }, icon('x'))),
        rows,
        h('div', { class: 'sh-acts spread' }, undo, h('span', { class: 'gap' }),
          one ? h('button', { class: 'btn line large', onclick: () => revealTidy(one.page) }, icon('finder'), 'Show in Finder') : null,
          h('button', { class: 'btn fill large', onclick: closeSheet }, 'Done'))], 'result');
    return true;
}

/** One folder things went into: where, how many, and its name, which is
 *  a field — Return keeps a new one, and nimo renames the folder. */
function tidyRow(r, withShow) {
    const i = r.page;
    let name = tidyName();
    const filed = filedCount(r);
    const field = h('input', { class: 'tr-name', value: name, spellcheck: 'false', autocomplete: 'off', maxlength: '60',
                               'aria-label': 'Name of the folder in ' + PLACE_WORDS[kind(i)] });
    field.value = name;
    const note = h('span', { class: 'tr-note' });
    const save = async () => {
        const to = field.value.trim();
        if (!to || to === name) { field.value = name; return; }
        const why = /[/:]/.test(to) ? 'A name cannot have “/” or “:” in it.' : to.startsWith('.') ? 'A name that starts with a dot would hide the folder.' : '';
        if (why) { note.textContent = why; note.className = 'tr-note bad'; field.focus(); return; }
        field.readOnly = true;
        note.textContent = 'Renaming…';
        note.className = 'tr-note';
        const reply = await ask('rename', { page: i, name, to });
        field.readOnly = false;
        if (reply && reply.ok) {
            const was = name;
            name = reply.name || to;
            field.value = name;
            // the next tidy goes into the folder by the name you gave it
            K.meta.config.tidy = name;
            tell('setConfig', { key: 'tidy', value: name });
            K.listing = {};
            note.textContent = 'Renamed from “' + was + '”';
            note.className = 'tr-note good';
        } else {
            const said = reply && reply.text ? parse(reply.text).find(x => x.k === 'warn' || x.k === 'err') : null;
            note.textContent = said ? capital(said.text) : 'Kliner could not rename it.';
            note.className = 'tr-note bad';
            field.value = name;
        }
    };
    field.addEventListener('keydown', e => {
        e.stopPropagation();
        if (e.key === 'Enter') { e.preventDefault(); field.blur(); }
        if (e.key === 'Escape') { e.preventDefault(); field.value = name; field.blur(); }
    });
    field.addEventListener('blur', save);
    // what went where: the kinds nimo said it sorted, each one the folder
    // it went into, shown in Finder when clicked
    const kinds = parse(r.text || '').filter(p => p.k === 'row' && /^\d[\d,]* items?$/.test(p.value) && !/^in there$/i.test(p.label));
    const where = kinds.length ? h('div', { class: 'tr-kinds' }, kinds.map(p =>
        h('button', { class: 'tr-kind', title: 'Show ' + p.label + ' in Finder',
                      onclick: () => tell('show', { path: [pages()[i].reveal, name, p.label] }) },
          p.label, h('span', null, whole(count(p.value)))))) : null;
    return h('div', { class: 'tr-row' },
        h('span', { class: 'tr-ic' }, icon(kind(i) === 'downloads' ? 'download' : kind(i) === 'documents' ? 'file' : 'desk')),
        h('div', { class: 'tr-what' },
            h('b', null, (filed != null ? plural(filed, 'thing') + ' from ' : 'From ') + PLACE_WORDS[kind(i)]),
            h('span', null, 'are in', h('span', { class: 'tr-path' }, pages()[i].reveal + ' /'), field, note),
            where),
        withShow ? h('button', { class: 'btn line small', onclick: () => revealTidy(i, name) }, 'Show') : null);
}

/** The folder things were sorted into, selected in Finder. */
function revealTidy(i, name) {
    tell('show', { path: [pages()[i].reveal, name || tidyName()] });
}

/* ── the keyboard ─────────────────────────────────────────────────────── */

document.addEventListener('keydown', e => {
    if (e.target.closest && e.target.closest('input, textarea, [contenteditable]') && !(K.welcome && e.key === 'Enter')) return;
    // \ shows the files on your desktop, and hides them again. Wherever you
    // are in the window, and never while you are typing in a field. On a
    // keyboard where \ takes ⌥, that is still \.
    if ((e.key === '\\' || (e.code === 'Backslash' && !e.altKey)) && !e.metaKey && !e.ctrlKey && !e.repeat
        && !$('.ksheet') && !$('.finder')) {
        e.preventDefault();
        if (K.welcome) { if (INTRO[K.welcome.step] === 'desk') introIcons(); return; }
        quickIcons();
        return;
    }
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'Escape') {
        if ($('.pop')) { closeActivity(); return; }
        if (K.walked.length) { walkUp(); return; }
    }
    if (K.welcome) {
        if (e.key === 'Enter' && K.welcome.primary && !K.welcome.primary.disabled) {
            // Enter on Back, Skip or an Allow presses that one, not the main button
            const on = e.target.closest && e.target.closest('button');
            if (on && on !== K.welcome.primary) return;
            e.preventDefault();
            K.welcome.primary.click();
        }
        return;
    }
    // ? is Help and the keys, the way it is in Linear and Raycast
    if (e.key === '?' && !$('.ksheet') && !$('.finder')) { e.preventDefault(); show(HELP()); return; }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        const order = [];
        for (const p of K.meta.places) order.push(...p.holds);
        order.push(HELP(), SETTINGS());
        if (!order.includes(ACTIVITY())) order.push(ACTIVITY());
        order.push(SHARE());
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
    // ⌘K with the window in front: the window's own search, not the panel
    find: () => { if (K.welcome) palKey(); else openFind(); },
    help: () => show(HELP()),
    setup: () => startWelcome(),
    send: ev => sendEvent(ev),
};

window.kliner = {
    reply(id, data) {
        const done = owed.get(id);
        if (done) done(data || {});
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
    // Glass only when the window behind the page is vibrant. An older copy
    // of the app sends no such word, and the page stays as it was.
    if (meta && meta.glass) document.documentElement.classList.add('glass');
    K.meta.config = K.meta.config || {};
    // What Home read last time the app was open, drawn straight away so the
    // window opens with figures on it. The real reading replaces it as soon
    // as nimo comes back.
    if (meta.lastLook && meta.lastLook.text) {
        const pieces = parse(meta.lastLook.text);
        K.kept[0] = { pieces, ok: true, at: meta.lastLook.at || Date.now(), old: true };
        K.lastRead = meta.lastLook.at || Date.now();
        readHome(pieces);
        // and what Home says from now on is measured from it: how much more
        // is free, how many fewer files are loose, since then
        if (K.home && meta.lastLook.at) K.base = { home: K.home, at: meta.lastLook.at };
    }
    // Activity is drawn here rather than run by nimo, so it joins the place
    // the machine's own readings are in, first
    const machine = (meta.places || []).find(p => p.holds.some(n => (meta.pages[n] || {}).kind === 'doctor' && n > 0));
    if (machine && !machine.holds.includes(meta.pages.length + 2)) machine.holds.unshift(meta.pages.length + 2);
    // the sidebar with its names is the window, the way Efferd's is; folded
    // to pictures only when you fold it (⌘B), and kept that way
    K.wide = K.meta.config.frame !== 'rail';
    K.preview = K.meta.config.preview === 'on';
    if (!meta.welcomed) { startWelcome(); return; }
    drawFrame();
    const first = K.pendingOpen != null ? K.pendingOpen : 0;
    K.pendingOpen = null;
    show(first, { remember: false });
    if (K.meta.config.tour !== 'done') mapLater(1200);
}

window.__kliner = K;   // for the tests, and nothing else
boot();

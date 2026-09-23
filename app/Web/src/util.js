/* ── small things everything else is built from ─────────────────────── */

const SVGNS = 'http://www.w3.org/2000/svg';

/** An element. Strings become text — never markup — so nothing nimo prints
 *  (a file name, a folder name) can ever be read as HTML. */
function h(tag, attrs, ...kids) {
    const node = document.createElement(tag);
    if (attrs) {
        for (const [key, value] of Object.entries(attrs)) {
            if (value == null || value === false) continue;
            if (key === 'class') node.className = value;
            else if (key === 'style') node.style.cssText = value;
            else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
            else node.setAttribute(key, value === true ? '' : value);
        }
    }
    for (const kid of kids.flat(Infinity)) {
        if (kid == null || kid === false) continue;
        node.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    }
    return node;
}

function s(tag, attrs, ...kids) {
    const node = document.createElementNS(SVGNS, tag);
    if (attrs) for (const [key, value] of Object.entries(attrs)) {
        if (value == null) continue;
        node.setAttribute(key, value);
    }
    for (const kid of kids.flat(Infinity)) if (kid) node.append(kid);
    return node;
}

/* one line of pictures, drawn the same way everywhere: 24 square, stroked */
const PATHS = {
    home:    ['M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z'],
    grid:    ['M3.5 3.5h7v7h-7z', 'M13.5 3.5h7v7h-7z', 'M3.5 13.5h7v7h-7z', 'M13.5 13.5h7v7h-7z'],
    desk:    ['M3 4.5h18a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1v-10a1 1 0 0 1 1-1z', 'M8 21h8', 'M12 16.5V21'],
    download:['M12 4v11', 'm7 10 5 5 5-5', 'M5 20h14'],
    photo:   ['M4 4h16a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z', 'M9 10.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z', 'm21 15-5-5L5 20'],
    power:   ['M12 3v9', 'M6.4 6.4a8 8 0 1 0 11.2 0'],
    bars:    ['M5 20v-8', 'M12 20V4', 'M19 20v-5', 'M3 20h18'],
    sparkles:['M12 3.5 13.7 8l4.5 1.7-4.5 1.8L12 16l-1.7-4.5L5.8 9.7 10.3 8z', 'M18.5 14.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z'],
    pulse:   ['M3 12h4l3-7 4 14 3-7h4'],
    undo:    ['M9 14 4 9l5-5', 'M4 9h11a5 5 0 0 1 0 10h-3'],
    gear:    ['M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z', 'M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z'],
    help:    ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3', 'M12 17h.01'],
    disk:    ['M22 12H2', 'M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z', 'M6 16h.01', 'M10 16h.01'],
    cpu:     ['M7 5h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z', 'M9.5 9.5h5v5h-5z', 'M9 2v3', 'M15 2v3', 'M9 19v3', 'M15 19v3', 'M2 9h3', 'M2 15h3', 'M19 9h3', 'M19 15h3'],
    tray:    ['M22 12h-6l-2 3h-4l-2-3H2', 'M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z'],
    right:   ['m9 18 6-6-6-6'],
    left:    ['m15 18-6-6 6-6'],
    down:    ['m6 9 6 6 6-6'],
    eye:     ['M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z', 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
    refresh: ['M20.5 12a8.5 8.5 0 1 1-2.5-6l2.5 2.5', 'M20.5 3.5v5h-5'],
    play:    ['M7 4.5v15l12.5-7.5z'],
    search:  ['M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z', 'm20 20-4-4'],
    bell:    ['M6 8.5a6 6 0 0 1 12 0c0 6.5 2.5 8.5 2.5 8.5h-17S6 15 6 8.5', 'M10.3 20.5a2 2 0 0 0 3.4 0'],
    sidebar: ['M4 3.5h16a.5.5 0 0 1 .5.5v16a.5.5 0 0 1-.5.5H4a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z', 'M9.5 3.5v17'],
    check:   ['M20 6 9 17l-5-5'],
    x:       ['M18 6 6 18', 'm6 6 12 12'],
    clock:   ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 7v5l3 2'],
    folder:  ['M4 20h16a2 2 0 0 0 2-2V8.5a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.7-.9l-.8-1.2A2 2 0 0 0 7.9 3.5H4a2 2 0 0 0-2 2V18a2 2 0 0 0 2 2z'],
    finder:  ['M15 3h6v6', 'M10 14 21 3', 'M18 13.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h5.5'],
    up:      ['M12 19V5', 'm5 12 7-7 7 7'],
    arrdown: ['M12 5v14', 'm19 12-7 7-7-7'],
    trash:   ['M3 6h18', 'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6', 'M8.5 6V4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v2'],
    plus:    ['M12 5v14', 'M5 12h14'],
    file:    ['M14 2.5H6.5a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V8z', 'M14 2.5V8h5.5'],
    bolt:    ['M13 2 4 14h8l-1 8 9-12h-8z'],
    terminal:['m4 17 6-5-6-5', 'M12 19h8'],
    lock:    ['M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z', 'M8 11V7a4 4 0 0 1 8 0v4'],
    shield:  ['M12 21.5s8-3.8 8-9.5V5.5l-8-3-8 3V12c0 5.7 8 9.5 8 9.5z'],
    slash:   ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'm5.7 5.7 12.6 12.6'],
    wait:    ['M5 22h14', 'M5 2h14', 'M17 22v-4.2a2 2 0 0 0-.6-1.4L12 12l-4.4 4.4a2 2 0 0 0-.6 1.4V22', 'M7 2v4.2a2 2 0 0 0 .6 1.4L12 12l4.4-4.4a2 2 0 0 0 .6-1.4V2'],
    camera:  ['M4 7.5h3l1.5-2.5h7L17 7.5h3a1 1 0 0 1 1 1V19a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8.5a1 1 0 0 1 1-1z', 'M12 16.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z'],
    film:    ['M4 3h16a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z', 'M7 3v18', 'M17 3v18', 'M3 7.5h4', 'M3 12h18', 'M3 16.5h4', 'M17 7.5h4', 'M17 16.5h4'],
    music:   ['M9 18V5l12-2v13', 'M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z', 'M18 19a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
    box:     ['M21 8v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8', 'M2 3h20v5H2z', 'M10 12h4'],
    code:    ['m16 18 6-6-6-6', 'm8 6-6 6 6 6'],
    cube:    ['M21 16V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l7-4a2 2 0 0 0 1-1.7z', 'M3.3 7 12 12l8.7-5', 'M12 22V12'],
    dot:     ['M12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z'],
    list:    ['M8 6h13', 'M8 12h13', 'M8 18h13', 'M3 6h.01', 'M3 12h.01', 'M3 18h.01'],
    moon:    ['M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9z'],
    copies:  ['M9 8h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z', 'M5 16V5a1 1 0 0 1 1-1h10'],
};

/* what macOS calls a picture, and what it is here */
const SYMBOLS = {
    'house': 'home', 'square.grid.2x2': 'grid', 'arrow.down.circle': 'download',
    'photo': 'photo', 'power': 'power', 'chart.bar': 'bars', 'sparkles': 'sparkles',
    'waveform.path.ecg': 'pulse', 'arrow.uturn.backward': 'undo', 'gearshape': 'gear',
    'questionmark.circle': 'help', 'display': 'desk', 'internaldrive': 'disk',
    'cpu': 'cpu', 'tray.and.arrow.down': 'tray', 'chevron.right': 'right',
    'chevron.left': 'left', 'eye': 'eye', 'arrow.clockwise': 'refresh', 'play': 'play',
    'menubar.dock.rectangle': 'desk', 'doc.text': 'file', 'bell': 'bell',
    'camera.viewfinder': 'camera', 'doc.on.doc': 'file',
};

function icon(name, cls) {
    const key = SYMBOLS[name] || name;
    const paths = PATHS[key] || PATHS.dot;
    return s('svg', { class: 'ic' + (cls ? ' ' + cls : ''), viewBox: '0 0 24 24', 'aria-hidden': 'true' },
             paths.map(d => s('path', { d })));
}

/* ── the face ─────────────────────────────────────────────────────────── */

/* The mark: the two eyes, traced from the film frame by frame, so what the
   window shows is the drawing itself and not a likeness of it. potrace's
   own coordinates, kept as they came out: tenths of a point, y upwards. */
const EYES = 'M1873 3566 c-198 -48 -367 -231 -430 -466 -26 -95 -23 -316 6 -477 104 -586 322 -1050 506 -1080 l34 -5 -25 88 c-61 218 -86 362 -91 539 -4 138 -2 182 11 235 52 203 147 279 426 340 158 35 183 45 220 85 23 25 25 34 24 118 -1 111 -29 220 -82 322 -47 89 -174 219 -252 258 -113 55 -235 70 -347 43z M3276 3549 c-95 -23 -220 -107 -288 -192 -50 -63 -111 -189 -135 -277 -67 -245 53 -860 242 -1245 92 -188 185 -294 274 -311 31 -7 34 -5 27 12 -20 50 -79 300 -96 408 -22 136 -27 343 -9 428 29 140 119 252 242 301 35 14 122 38 193 53 194 40 234 66 242 157 2 29 -1 86 -7 126 -36 230 -160 410 -347 502 -85 43 -90 44 -193 46 -58 1 -123 -2 -145 -8z';

function eyesMark(cls) {
    // room round them for the way they move: 40 left and right, 60 below.
    // Two groups, not one: `eyes` carries the glance traced off the film,
    // `lids` the blink. A blink on the same group would fight the glance for
    // the transform, and one of the two would win.
    const svg = s('svg', { class: 'eyes-mark ' + (cls || ''), viewBox: '102 134 334 285', 'aria-hidden': 'true' });
    const eyes = s('g', { class: 'eyes' });
    const lids = s('g', { class: 'lids' });
    lids.append(s('g', { transform: 'translate(0,512) scale(0.1,-0.1)' }, s('path', { class: 'eye', d: EYES })));
    eyes.append(lids);
    svg.append(eyes);
    return svg;
}

function mascot(cls) {
    const svg = s('svg', { class: cls || '', viewBox: '0 0 100 100', 'aria-hidden': 'true' });
    const whole = s('g', { class: 'whole' });
    whole.append(s('path', { class: 'body', d: MASCOT.body }));
    const eyes = s('g', { class: 'eyes' });
    eyes.append(s('path', { class: 'eye', d: MASCOT.left }), s('path', { class: 'eye', d: MASCOT.right }));
    whole.append(eyes);
    svg.append(whole);
    return svg;
}

/* ── numbers, the way nimo writes them ────────────────────────────────── */

/** "2.1 GB" → bytes. A bare number reads as bytes, the way nimo's own does. */
function bytes(text) {
    const m = /^\s*(-?[\d.]+)\s*([KMGT]?B)?\s*$/i.exec(String(text || ''));
    if (!m) return null;
    const value = parseFloat(m[1]);
    if (!isFinite(value)) return null;
    const unit = (m[2] || 'B').toUpperCase();
    const scale = { B: 1, KB: 1e3, MB: 1e6, GB: 1e9, TB: 1e12 }[unit] || 1;
    return value * scale;
}

/** Whether a figure carries a unit. `142` is a hundred and forty-two things. */
function hasUnit(text) {
    return /^\s*[\d.,]+\s*([KMGT]?B)\s*$/i.test(String(text || ''));
}

/** And back again, the way nimo would have said it. */
function size(value) {
    const units = [[1e12, 'TB'], [1e9, 'GB'], [1e6, 'MB'], [1e3, 'KB']];
    for (const [scale, name] of units) {
        if (value >= scale) {
            const n = value / scale;
            // one decimal under a hundred, the way nimo prints them
            return (n >= 100 ? Math.round(n).toString() : n.toFixed(1)) + ' ' + name;
        }
    }
    return Math.round(value) + ' B';
}

/** Split "29.5 GB" into the figure and its unit, so the unit can be small. */
function figure(text) {
    const m = /^\s*([\d.,]+)\s*(.*)$/.exec(String(text || ''));
    return m ? [m[1], m[2]] : [String(text || ''), ''];
}

/** The first whole number in a phrase: "34 items" → 34. */
function count(text) {
    const m = /(\d[\d,]*)/.exec(String(text || ''));
    return m ? parseInt(m[1].replace(/,/g, ''), 10) : 0;
}

function whole(n) {
    return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

function percent(part, of) {
    if (!(of > 0)) return '0%';
    const p = part / of * 100;
    if (p > 0 && p < 0.1) return '<0.1%';
    if (p < 10) return p.toFixed(1).replace(/\.0$/, '') + '%';
    return Math.round(p) + '%';
}

function plural(n, one, many) { return n + ' ' + (n === 1 ? one : (many || one + 's')); }

/* ── reading nimo back ────────────────────────────────────────────────── */

/* nimo draws a panel for a terminal: box corners, a heading, columns held
   apart by two or more spaces. This reads it back into what it meant —
   headings, rows, a total, sentences — the same way the Swift window always
   did, so the two can never disagree about what nimo said. */
const BOX = new Set('─╭╮╰╯│');
const ANSI = /\x1b\[[0-9;]*m/g;

function parse(raw) {
    const out = [];
    for (const line of String(raw || '').split('\n')) {
        const strong = line.includes('\x1b[1m');
        const bare = line.replace(ANSI, '');
        const t = bare.trim();
        if (!t) continue;
        if (t.startsWith('◍')) continue;              // the wordmark; the window has a title
        if (t.startsWith('╰')) continue;              // the bottom of a panel is a shape

        if (t.startsWith('╭')) {
            const title = t.replace(/^[─╭╮╰╯│\s]+/, '').replace(/[─╭╮╰╯│\s]+$/, '');
            if (title) out.push({ k: 'heading', text: title });
            continue;
        }
        if ([...t].every(c => BOX.has(c))) { out.push({ k: 'rule' }); continue; }
        // nimo's dashes, said as a window would: "Sorted — 34 items" is "Sorted: 34 items"
        if (t.startsWith('✓')) { out.push({ k: 'good', text: undash(t.slice(1).trim()) }); continue; }
        if (t.startsWith('✗') || t.startsWith('!')) { out.push({ k: 'warn', text: undash(t.slice(1).trim()) }); continue; }

        const indent = bare.length - bare.replace(/^ +/, '').length;
        const parts = t.split(/ {2,}/).filter(Boolean);
        const last = parts[parts.length - 1] || '';
        const isBar = parts.length > 1 && /^[█·]+$/.test(last);

        // A numbered line — the undo log, the wallpapers — is an entry, not
        // a label and a value. The Swift reader filed these as notes and
        // dropped them, which is why "Put it all back" never listed anything.
        if (!isBar && parts.length >= 2 && /^\d{1,3}$/.test(parts[0])) {
            out.push({ k: 'item', no: parseInt(parts[0], 10), parts: parts.slice(1), strong });
            continue;
        }

        if (indent >= 4 && parts.length >= 2) {
            const label = parts.shift();
            let bar = null;
            if (isBar) {
                const cells = [...parts.pop()];
                bar = cells.filter(c => c === '█').length / cells.length;
            }
            out.push({ k: 'row', label, value: parts[0] || '', note: parts.slice(1).join('  '), bar, strong });
            continue;
        }
        out.push(indent <= 3 ? { k: 'note', text: undash(t) } : { k: 'text', text: undash(t) });
    }
    return out;
}

/* nimo's lines, as the window says them: Kliner, not the engine under it,
   and a colon where a terminal would have used a dash */
function undash(text) {
    return String(text).replace(/\s+[—–]\s+/g, ': ').replace(/\bnimo (never|does|only|will|cannot|can|has|wrote|found|moved|sorted|looks|reads)\b/g, 'Kliner $1');
}

/** The rows of a reading, by label, for pages that read figures off it. */
function facts(pieces) {
    const map = {};
    for (const p of pieces) if (p.k === 'row' && !(p.label in map)) map[p.label] = p;
    return map;
}

/** A reading, cut at its headings: one section per panel nimo drew. */
function sections(pieces) {
    const out = [];
    let cur = { title: '', pieces: [] };
    for (const p of pieces) {
        if (p.k === 'heading') {
            if (cur.title || cur.pieces.length) out.push(cur);
            cur = { title: p.text, pieces: [] };
        } else cur.pieces.push(p);
    }
    if (cur.title || cur.pieces.length) out.push(cur);
    return out;
}

/** Words with nimo's commands in them, the commands set as code. Only
 *  nimo's own verbs count, so "8 min" stays a duration. */
const COMMAND = /(\bmin (?:desktop|downloads|screenshots|clean|preview|top|doctor|undo|startup|wallpaper|next|prev|tidy|clear|empty|duplicates|apps|setup|update|dock|hide|zen|dark|light|blank|menu|help)(?: (?:--?[a-z][a-z-]*|desktop|downloads|all|<[a-z]+>))*)/;
function prose(text) {
    const frag = document.createDocumentFragment();
    const bits = String(text).split(COMMAND);
    for (const bit of bits) {
        if (/^min /.test(bit)) frag.append(h('code', null, bit));
        else if (bit) frag.append(document.createTextNode(bit));
    }
    return frag;
}

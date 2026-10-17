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
    send:    ['m21.5 2.5-7 19-4-8.5-8.5-4z', 'M21.5 2.5 10.5 13'],
    at:      ['M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8z', 'M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-4 8'],
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
    board:   ['M4.5 4.5h15v15h-15z', 'M9.5 4.5v15', 'M14.5 4.5v15', 'M6.8 8h.8', 'M11.8 8h.8', 'M16.8 8h.8'],
    moon:    ['M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9z'],
    copies:  ['M9 8h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z', 'M5 16V5a1 1 0 0 1 1-1h10'],
    updown:  ['m7 15 5 5 5-5', 'm7 9 5-5 5 5'],
    user:    ['M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z', 'M4.5 20.5a7.5 7.5 0 0 1 15 0'],
    gauge:   ['M12 14l3.5-3.5', 'M3.5 18.5a10 10 0 1 1 17 0'],
    wifi:    ['M12 19.5h.01', 'M2.5 8.8a14.5 14.5 0 0 1 19 0', 'M5.5 12.3a10 10 0 0 1 13 0', 'M8.8 15.8a5 5 0 0 1 6.4 0'],
    globe:   ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 3a13.5 13.5 0 0 0 0 18 13.5 13.5 0 0 0 0-18z', 'M3 12h18'],
    inbox:   ['M21.5 12.5h-5.5l-2 3h-4l-2-3H2.5', 'M5.4 5.6 2.5 12.5V18a1.5 1.5 0 0 0 1.5 1.5h16a1.5 1.5 0 0 0 1.5-1.5v-5.5l-2.9-6.9A1.5 1.5 0 0 0 17.2 4.5H6.8a1.5 1.5 0 0 0-1.4 1.1z'],
    upload:  ['M12 15V4', 'm7 9 5-5 5 5', 'M4.5 15.5V18a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5v-2.5'],
    trend:   ['m21.5 7-8 8-4.5-4.5-6.5 6.5', 'M15.5 7h6v6'],
    eyeoff:  ['M3 3l18 18','M10.6 5.1A10.6 10.6 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-2.9 3.9', 'M6.6 6.6A17.6 17.6 0 0 0 2 12s3.5 7 10 7a9.8 9.8 0 0 0 5.4-1.6', 'M9.9 9.9a3 3 0 0 0 4.2 4.2'],
    enter:   ['M20 5v7a3 3 0 0 1-3 3H5', 'm9 11-4 4 4 4'],
    command: ['M9 6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3z'],
    expand:  ['M15 3h6v6', 'M9 21H3v-6', 'm21 3-7 7', 'm3 21 7-7'],
    more:    ['M5 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z', 'M12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z', 'M19 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z'],
    info:    ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 16v-4', 'M12 8h.01'],
    sliders: ['M20 7h-9', 'M14 17H5', 'M17 20a3 3 0 1 0 0-6 3 3 0 0 0 0 6z', 'M7 10a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
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

/* The word, the way Kliner writes it: traced from the drawing, with the eyes
   after it like the quote that closes what it says. The eyes are their own
   group, so they can look about while the word stays still. */
const WORD = { w: 594, h: 172,
    word: 'M373.4 170.2C367.3 169.8 363.5 169 358.2 167.2C357.1 166.8 355.6 166.3 355 166.1C354.3 165.9 353.7 165.6 353.5 165.4C353.3 165.2 353 165 352.8 165C352.5 165 352 164.8 351.7 164.5C351.3 164.2 350.9 164 350.7 164C350.5 164 350 163.8 349.7 163.5C349.3 163.2 348.9 163 348.8 163C348.7 163 348.4 162.8 348.1 162.5C347.9 162.2 347.6 162 347.4 162C347.1 162 344 159.7 344 159.5C344 159.4 343.8 159.2 343.5 159.1C342.2 158.7 335.5 151.4 332.8 147.5C331.6 145.7 331.3 145.2 330 142.8C329.7 142.3 329.4 141.8 329.2 141.6C329.1 141.5 329 141.2 329 141C329 140.8 328.8 140.3 328.5 140C328.2 139.7 328 139.2 328 139C328 138.8 327.8 138.2 327.5 137.7C326.7 135.9 326 134.1 326 133.7C326 133.5 325.8 132.8 325.5 132.1C323.4 126.5 322.1 118.4 321.9 109.6C321.7 103.4 322 96.4 322.5 93.8C322.6 93 322.9 91.5 323.1 90.4C323.8 86.5 324.7 83 325.9 79.9C326.2 78.9 326.6 77.8 326.8 77.4C327 76.6 327.5 75.5 328.6 73.3C332.7 64.5 340.8 55.1 348.2 50.6C348.9 50.2 349.6 49.8 349.8 49.6C350 49.4 350.9 48.9 351.8 48.4C352.7 48 353.6 47.5 353.9 47.3C357 45.6 364.2 43.5 370.1 42.6C374.2 42 384.8 42 388.1 42.6C389.4 42.8 390.7 43 391.1 43C391.6 43 392.6 43.2 393.5 43.5C395.2 43.9 396.3 44.3 398.7 44.9C399.4 45.1 400.2 45.3 400.3 45.5C400.5 45.6 401.1 45.8 401.7 46C402.6 46.2 404.8 47.2 405.8 47.7C406 47.8 406.9 48.3 407.8 48.8C410.1 49.9 410.9 50.3 411 50.5C411.1 50.6 411.7 51 412.4 51.4C413.1 51.9 413.8 52.3 413.9 52.5C414.1 52.6 414.8 53.2 415.6 53.9C417.9 55.7 420 57.8 421.5 59.6C422.3 60.6 423.2 61.7 423.5 62C424 62.5 424.6 63.4 425.8 65.4C426 65.6 426.3 66.2 426.6 66.5C426.8 66.9 427 67.4 427 67.5C427 67.7 427.2 68.2 427.5 68.5C427.8 68.8 428 69.3 428 69.5C428 69.6 428.2 70.1 428.5 70.5C428.7 70.8 429 71.3 429.1 71.6C429.2 71.9 429.5 72.9 429.9 73.9C431.5 78.3 432.6 83.4 433 88.8C433.5 95.1 433 108.8 432.2 110.5L431.9 111.1L385.5 111.2C351.3 111.2 339.1 111.3 339 111.5C338.3 112.7 339.9 125 341.4 129.8C341.6 130.4 341.9 131.4 342.1 132C342.6 133.8 343.1 134.8 343.6 135.6C343.8 135.9 344 136.4 344 136.5C344 138 350.9 145.9 353.9 147.9C356.6 149.7 357 150 357.4 150C357.5 150 358 150.2 358.3 150.5C358.7 150.8 359.2 151 359.4 151C359.7 151 360.2 151.2 360.7 151.5C361.1 151.8 361.7 152 361.9 152C362.2 152 362.8 152.2 363.4 152.4C370.5 155 388.3 155.1 395.8 152.6C396.4 152.4 397.3 152.1 397.8 152C398.4 151.8 399.1 151.6 399.3 151.4C399.6 151.2 400.1 151 400.3 151C400.6 151 401.1 150.8 401.5 150.6C401.8 150.3 402.3 150 402.5 149.9C405.1 148.3 407.2 146.5 408.9 144.4C410.2 142.7 412 140.1 412 139.8C412 139.6 412.2 139.2 412.4 138.9C413.4 137.3 414.8 131.2 414.7 128.8C414.6 126.6 414.2 126.8 423.5 126.8C430.6 126.8 431.7 126.8 432 127.1C432.4 127.6 432.2 134.5 431.7 136.1C431.6 136.7 431.3 137.8 431.1 138.6C430.9 139.5 430.6 140.5 430.4 140.9C430.2 141.3 430 141.8 430 142C430 142.2 429.8 142.7 429.5 143.2C429.2 143.6 429 144.1 429 144.3C429 144.5 428.8 144.9 428.5 145.2C428.2 145.6 428 146 428 146.2C428 146.5 426.1 149.4 424 152.3C423.2 153.5 417.8 158.7 416.4 159.6C414.2 161.2 411.7 162.7 410.9 163.1C410.5 163.3 409.9 163.6 409.7 163.7C408.6 164.4 408.3 164.5 407.8 164.8C407.4 164.9 406.7 165.3 406.1 165.5C405.6 165.8 405 166 404.9 166C404.8 166 404.2 166.2 403.6 166.5C402.1 167.2 400.2 167.8 399 168C398.4 168.1 397.4 168.4 396.9 168.6C396.3 168.8 395.6 169 395.2 169C394.9 169 393.9 169.2 393 169.4C389.1 170.3 379.6 170.7 373.4 170.2ZM0.2 167.8C0 167.6 -0.1 1.4 0.2 0.9C0.4 0.3 17.6 0.3 17.8 0.9C17.9 1.1 18 22.5 18 48.5C18 84.8 18.1 95.7 18.3 96C18.7 96.4 48.5 96.4 49 95.9C49.2 95.8 50.3 94.4 51.3 93C52.4 91.6 53.4 90.2 53.6 90C53.8 89.8 54.4 88.8 55.1 87.8C55.8 86.8 56.4 86 56.5 86C56.6 86 56.8 85.7 56.9 85.4C57.2 84.9 57.8 84 60.4 80.6C60.8 80 61.3 79.3 61.5 79C61.7 78.7 62.2 78 62.6 77.4C65.2 74 65.8 73.1 66.1 72.6C66.2 72.3 66.4 72 66.5 72C66.6 72 67.2 71.2 67.9 70.2C68.6 69.2 69.2 68.2 69.4 68C69.6 67.8 70.8 66.2 72 64.5C73.2 62.8 74.4 61.2 74.6 60.9C74.9 60.6 75.5 59.8 76 59C76.5 58.2 77.1 57.4 77.3 57.2C77.5 57 77.8 56.6 78 56.3C78.2 55.8 82 50.6 82.6 50C82.8 49.8 83.4 48.8 84.1 47.8C84.8 46.9 85.6 45.7 86 45.3L86.7 44.5L96.7 44.5C105 44.5 106.7 44.6 106.8 44.8C106.9 45.1 101.3 53 99.6 55C99.4 55.2 98.7 56.1 98.1 57C97.4 57.9 96.7 58.8 96.6 59C96.4 59.2 95.7 60 95.1 60.9C94.5 61.7 93.8 62.6 93.6 62.9C93.4 63.2 92.7 64.1 92.1 64.9C91.5 65.7 90.8 66.7 90.5 67C90.2 67.3 89.5 68.2 89 69C88.5 69.8 87.8 70.7 87.5 71C87.2 71.3 86.5 72.3 85.9 73.1C84.3 75.2 84.1 75.5 83.1 76.7C82.6 77.3 82.1 78.1 81.9 78.3C81.8 78.6 81.5 79 81.4 79.1C81.1 79.4 75.5 86.8 73.5 89.5C71.6 92.1 65.9 99.6 65.7 99.9C65.2 100.3 63.8 102.5 63.8 102.8C63.8 103.1 64.3 103.9 65.7 106.1C66.1 106.6 66.6 107.4 66.9 107.8C68.1 109.9 68.9 111.1 69.5 111.9C69.8 112.3 70.4 113.2 70.8 113.8C71.2 114.4 71.9 115.6 72.5 116.4C73.1 117.2 73.8 118.4 74.2 119C74.6 119.6 75.2 120.4 75.5 120.9C75.8 121.3 76.4 122.2 76.8 122.8C77.2 123.4 77.9 124.6 78.5 125.4C79.1 126.2 79.8 127.4 80.2 128C80.6 128.6 81.2 129.4 81.5 129.9C81.8 130.3 82.4 131.2 82.8 131.8C83.2 132.4 83.9 133.6 84.5 134.4C85.1 135.2 85.8 136.4 86.2 137C86.6 137.6 87.1 138.4 87.4 138.8C87.7 139.1 88 139.5 88 139.6C88 139.7 89.9 142.6 92.2 146.1C94.5 149.5 96.6 152.8 96.9 153.2C97.2 153.7 97.9 154.8 98.4 155.5C99 156.3 99.7 157.4 100.1 158C100.5 158.6 101 159.4 101.2 159.7C102 160.9 103.5 163.2 104.2 164.2C104.6 164.8 105.2 165.8 105.7 166.3C107 168 107.2 168 95.7 168L85.5 168L84.8 166.9C84.3 166.3 84 165.7 84 165.6C84 165.5 83.7 165.1 83.4 164.8C83.1 164.4 82.6 163.6 82.2 163C81.8 162.4 81.1 161.2 80.6 160.5C79.5 158.9 78.5 157.4 77.6 155.9C77.3 155.4 76.7 154.5 76.3 154C75.9 153.4 75.4 152.6 75.1 152.2C73.9 150.1 73.1 148.9 72.5 148.1C72.2 147.7 71.6 146.8 71.2 146.2C70.8 145.6 70.1 144.4 69.5 143.6C69 142.8 68.1 141.4 67.5 140.5C66.9 139.6 66 138.2 65.5 137.4C64.9 136.6 64.2 135.4 63.8 134.8C63.4 134.2 62.8 133.3 62.5 132.9C62.2 132.4 61.6 131.6 61.2 131C60.8 130.4 60.1 129.2 59.5 128.4C59 127.6 58.3 126.5 58 126C57.7 125.5 57.1 124.5 56.6 123.7C56 123 55.3 121.8 54.8 121.1C54.4 120.4 53.8 119.5 53.5 119.1C52.4 117.6 51.3 115.8 50.5 114.5C49 112 50.6 112.2 33.5 112.2C25.2 112.2 18.3 112.3 18.2 112.4C18.1 112.6 18 125.1 17.9 140.3L17.9 167.9L9.1 167.9C4.3 168 0.3 167.9 0.2 167.8ZM117.2 167.8C116.8 167.5 117 1.4 117.3 0.9C117.6 0.5 118.4 0.5 126.2 0.6L134.9 0.6L134.9 84.2L134.9 167.9L126.1 167.9C121.3 168 117.3 167.9 117.2 167.8ZM157.8 167.8C157.3 167.6 157.4 43.4 157.9 43.2C158.4 43 174.6 43 175.1 43.2C175.7 43.4 175.7 167.6 175.1 167.8C174.6 168 158.3 168 157.8 167.8ZM197.6 167.7C197 167.2 197.1 45.4 197.6 44.9C198.2 44.3 212.8 44.3 213.4 44.9C213.7 45.3 213.8 46.6 213.7 57.4C213.7 65.3 213.8 69.7 214 69.8C214.4 70.2 214.9 69.8 215.1 69C215.3 68.1 217.1 64.4 217.6 63.8C217.8 63.5 218 63.2 218.1 63C218.6 61.4 226.7 52.3 227.5 52.3C227.6 52.3 228.3 51.8 229 51.2C230.6 49.9 232.4 48.8 235.5 47.2C235.8 47.1 236.2 46.9 236.5 46.8C236.8 46.6 237.2 46.4 237.4 46.3C240.4 44.7 244.3 43.6 249.6 42.6C255.3 41.5 269.1 42.2 273.1 43.6C273.7 43.8 274.4 44 274.8 44C275.1 44 275.8 44.2 276.4 44.5C276.9 44.8 277.6 45 277.8 45C278.1 45 278.7 45.2 279.2 45.5C279.7 45.7 280.9 46.3 281.9 46.8C284.1 47.9 284.8 48.3 285 48.5C285.1 48.6 285.7 49 286.4 49.4C287.8 50.3 287.9 50.5 290.4 52.6C293 54.9 296.9 59.8 297.9 62C298 62.2 298.3 62.7 298.5 63C298.8 63.4 299 63.9 299 64C299 64.2 299.2 64.7 299.5 65C299.8 65.3 300 65.8 300 66.1C300 66.3 300.2 67 300.5 67.5C301.2 68.8 302 70.9 302 71.4C302 71.6 302.2 72.1 302.4 72.5C302.8 73.3 303.4 75.7 304.4 81.5C304.8 83.7 304.9 86.7 304.9 125.9L304.9 167.9L296 167.9L287.1 167.9L287 127.2C286.9 89.3 286.8 86.5 286.4 84.4C285.1 77.9 284.6 75.9 283.5 73.6C283.2 73.1 283 72.6 283 72.5C283 71.7 278.8 65.6 277.9 65.1C277.7 65 277.1 64.5 276.6 64.1C275.3 63 273.9 62.1 273.3 61.9C273 61.8 272.7 61.6 272.5 61.4C272.3 61.2 272 61 271.7 61C271.4 61 270.8 60.8 270.3 60.5C263.9 57.3 246.3 56.9 238 59.8C233.8 61.2 231.7 62.1 231.1 62.5C230.6 62.9 229.8 63.4 228.7 63.9C228.3 64.1 228 64.4 228 64.5C228 64.6 227.7 64.9 227.4 65.1C225.5 66 220 72.6 220 73.8C220 73.9 219.8 74.3 219.5 74.7C218.7 76 217.5 79.4 216.7 83.1C215.4 88.8 215.4 89.3 215.3 129.6C215.3 150.4 215.2 167.5 215.1 167.7C215 168.1 198 168.1 197.6 167.7ZM451.8 167.8C451.3 167.6 451.4 43.4 451.9 43.2C452.6 42.9 467.5 43 467.6 43.3C467.7 43.4 467.8 47.9 467.8 53.2C467.7 61.5 467.8 63 468.1 63.2C468.6 63.7 468.9 63.4 469.7 61.8C470.8 59.5 472.1 57.3 472.6 56.9C472.8 56.7 473.1 56.3 473.3 55.9C474.6 53.9 481 48.1 483.1 47C483.5 46.7 484.4 46.3 485 46C487.6 44.6 491.2 43.4 495.1 42.6C497.9 42.1 505.8 41.8 508.5 42.2C511.9 42.7 514.8 43.2 515.1 43.5C515.2 43.6 515.9 43.8 516.6 44C518.3 44.4 522.1 46.3 524.1 47.7C525.9 49 530 52.9 530.7 54C530.9 54.3 531.4 55 531.8 55.5C532.6 56.5 535 61.2 535 61.7C535 61.9 535.2 62.4 535.5 62.9C535.8 63.4 536 64 536 64.2C536 64.5 536.2 65.3 536.5 66.1C537.8 70.4 538.2 73.4 538.4 81.6C538.5 87.2 538.5 87.6 538.1 87.9C537.5 88.3 521.8 88.4 521 88C520.5 87.8 520.5 87.4 520.5 84.4C520.5 80.7 519.9 73.9 519.5 72.8C519.3 72.5 519.1 71.7 519 71.1C518.1 67.2 514.8 62.4 511.9 60.8C509.7 59.7 508.7 59.2 507.6 59C506.9 58.8 506.3 58.6 506.1 58.5C505.7 58.2 499.4 57.5 497 57.5C494.3 57.5 487.7 58.1 487.1 58.5C486.8 58.6 486 58.8 485.2 59C484.5 59.2 483.6 59.5 483.2 59.6C480 61.2 479 61.8 477.7 62.9C476.2 64.1 474.5 66 473.8 67.2C473 68.7 472 70.6 472 70.8C472 71 471.8 71.4 471.6 71.8C471.1 72.9 470.3 76.7 470 79C469.8 80.2 469.7 97.1 469.6 124.2C469.5 157.5 469.4 167.7 469.2 167.8C468.8 168 452.3 168 451.8 167.8ZM416.2 97.5C416.8 96.5 416.2 86 415.4 82.5C414.9 80.3 413.9 77.2 413.3 76.1C413.1 75.7 412.8 75.2 412.7 74.9C412.2 73.8 411.7 72.9 411.1 71.9C410 69.8 406.9 66.3 404.5 64.5C402.6 63.1 402.1 62.8 400.5 62C399.9 61.7 399.5 61.4 399.4 61.3C399.3 61.1 399 61 398.8 61C398.6 61 397.9 60.8 397.4 60.5C396.9 60.2 396.4 60 396.2 60C396 60 395.6 59.8 395.2 59.6C394.8 59.4 393.9 59.2 393.1 59C392.3 58.8 391.3 58.6 391 58.5C390.7 58.4 388.7 58 386.8 57.8C378.1 56.5 367.8 57.5 360.9 60.1C359.9 60.5 358.9 60.8 358.6 60.9C358.4 61 357.8 61.3 357.5 61.5C356.1 62.4 355.8 62.5 355.2 62.8C353.9 63.5 348.2 68.5 348.2 69C348.2 69.2 348 69.5 347.8 69.7C347.4 70.1 346.3 71.8 344.8 74.2C344.1 75.4 343.3 77.2 343.1 77.9C343 78.2 342.7 78.9 342.5 79.4C342.2 79.9 342 80.5 342 80.7C342 81 341.8 81.4 341.6 81.8C341.4 82.2 341.2 83.1 341 83.9C340.9 84.7 340.6 85.6 340.5 85.9C340.4 86.2 340.2 87.2 340 88.1C339.9 89.1 339.6 90.8 339.4 91.9C339 94.1 338.8 97.3 339.1 97.7C339.2 97.9 349.1 98 377.6 98C415.3 98 416 98 416.2 97.5ZM157.8 27.8C157.4 27.7 157.4 1.2 157.8 0.8C158.2 0.4 174.8 0.4 175.2 0.8C175.7 1.3 175.6 27.6 175.1 27.8C174.6 28 158.3 28 157.8 27.8Z',
    eyes: 'M551.5 66C550.6 65.6 548.3 63.1 547.4 61.4C546.9 60.5 546.4 59.7 546.2 59.6C546.1 59.5 546 59.2 546 59C546 58.7 545.8 58.1 545.5 57.5C544.9 56.3 544 54.1 544 53.7C544 53.5 543.8 52.8 543.5 52.1C542.8 50.2 542 47.4 542 46.7C542 46.4 541.8 45.2 541.5 44.1C540.6 40.5 540.9 36 542.3 33.5C544.1 30 545.7 28.4 548.1 27.3C553.2 24.9 558.3 25.8 562.1 29.7C563 30.6 565 33.6 565 34.1C565 34.2 565.2 35 565.5 35.8C566.1 37.4 566.2 40 565.7 40.5C564.9 41.5 564.1 41.8 561.7 42.4C560.3 42.7 558.9 43 558.6 43C556.4 43 553 45.4 551.7 47.9L550.9 49.4L550.9 53.1C550.9 57.1 551.3 59.2 552.7 63.7C553.5 66.2 553.2 66.7 551.5 66ZM579.5 66C578.6 65.6 576.3 63.1 575.4 61.4C574.9 60.5 574.4 59.7 574.2 59.6C574.1 59.5 574 59.2 574 59C574 58.7 573.8 58.1 573.5 57.5C572.9 56.3 572 54.1 572 53.7C572 53.5 571.8 52.8 571.5 52.1C570.8 50.2 570 47.4 570 46.7C570 46.4 569.8 45.2 569.5 44.1C568.6 40.5 568.9 36 570.3 33.5C572.5 29.3 573.9 28.1 578.1 26.5C579.8 25.8 583.7 25.9 585.2 26.6C585.7 26.8 586.4 27.1 586.8 27.2C589.3 28.3 593 32.7 593 34.5C593 34.7 593.2 35.2 593.5 35.6C594.1 36.3 594.3 40.8 593.7 40.8C593.5 40.8 593.1 41 592.8 41.3C592.2 41.9 591.3 42.1 587.4 42.8C583.5 43.6 581.2 45 579.8 47.8L578.9 49.4L578.9 53.1C578.9 57.1 579.3 59.2 580.7 63.7C581.5 66.2 581.2 66.7 579.5 66Z' };

function wordMark(cls) {
    const svg = s('svg', { class: 'word-mark' + (cls ? ' ' + cls : ''), viewBox: `0 0 ${WORD.w} ${WORD.h}`,
                           role: 'img', 'aria-label': 'Kliner' });
    svg.append(s('path', { class: 'wm-word', d: WORD.word, 'fill-rule': 'evenodd' }),
               s('g', { class: 'wm-eyes' }, s('path', { d: WORD.eyes, 'fill-rule': 'evenodd' })));
    return svg;
}

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

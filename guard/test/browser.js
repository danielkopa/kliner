// Loads the real extension into a real Chromium and fires the real shapes at
// it. The panel lives in a closed shadow root, which the page cannot reach —
// and neither can this test, on purpose. So it is tested by behaviour: did the
// wallet get asked, and when, and was what it received identical to what the
// site sent.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const shots = path.join(root, 'test', 'shots');
const EXECUTABLE = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const file = path.join(root, 'demo', url.pathname === '/' ? 'index.html' : url.pathname);
    if (url.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }
    if (!file.startsWith(path.join(root, 'demo')) || !fs.existsSync(file)) { res.writeHead(404); res.end('no'); return; }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'text/plain' });
    res.end(fs.readFileSync(file));
});
const port = await new Promise((r) => server.listen(0, () => r(server.address().port)));
const base = 'http://localhost:' + port + '/';

let pass = 0;
const failures = [];
const check = (name, ok, detail) => { if (ok) pass++; else failures.push({ name, detail }); };

fs.mkdirSync(shots, { recursive: true });
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'kg-'));
const extension = path.join(root, 'extension');

const context = await chromium.launchPersistentContext(profile, {
    executablePath: fs.existsSync(EXECUTABLE) ? EXECUTABLE : undefined,
    // Extensions do not load under the old headless mode, and Playwright adds
    // that flag unless it is told the browser is headed. So: headed here, and
    // the new headless mode asked for by hand.
    headless: false,
    args: [
        '--headless=new',
        '--no-sandbox',
        '--disable-extensions-except=' + extension,
        '--load-extension=' + extension,
    ],
    viewport: { width: 1000, height: 900 },
    deviceScaleFactor: 2,
});

const page = await context.newPage();
const problems = [];
page.on('pageerror', (e) => problems.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });

await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('button[data-shape]');
check('the demo page loads with every shape', (await page.$$('button[data-shape]')).length >= 20);

const asked = () => page.evaluate(() => window.__received.length);
const logText = () => page.textContent('#log');

async function fire(shape) {
    await page.click('button[data-shape="' + shape + '"]');
    await page.waitForTimeout(450);
}

/* ── it stops the wallet being asked at all ─────────────────────────────── */

const before = await asked();
await fire('unlimitedApprove');
check('the wallet is not asked while the panel is up', (await asked()) === before,
    'the request reached the wallet before anyone decided');

await page.screenshot({ path: path.join(shots, '1-unlimited-approve.png') });

// The safe button holds focus, so Enter is Stop.
await page.keyboard.press('Enter');
await page.waitForTimeout(400);
check('stopping means the wallet is never asked', (await asked()) === before);
check('and the site is told the person refused', (await logText()).includes('STOPPED'));
check('with the code a wallet uses for that', (await logText()).includes('stopped this one'));

/* ── and lets one through untouched ─────────────────────────────────────── */

await fire('boundedApprove');
await page.screenshot({ path: path.join(shots, '2-bounded-approve.png') });
await page.keyboard.press('Tab');
await page.keyboard.press('Enter');
await page.waitForTimeout(450);
check('signing passes it to the wallet', (await asked()) === before + 1);
check('and the site is told it was signed', (await logText()).includes('SIGNED'));
check('and the wallet got exactly what the site sent',
    await page.evaluate(() => window.__lastUnchanged === true),
    'the request was altered on the way through');

/* ── the signatures ─────────────────────────────────────────────────────── */

for (const shape of ['permitUnlimited', 'orderForNothing', 'permit2Batch', 'blindSign']) {
    const mark = await asked();
    await fire(shape);
    check(shape + ' is held before the wallet sees it', (await asked()) === mark);
    await page.screenshot({ path: path.join(shots, 'sig-' + shape + '.png') });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(350);
    check(shape + ' can be stopped', (await asked()) === mark);
}

/* ── an ordinary one is not made frightening ────────────────────────────── */

const mark = await asked();
await fire('loginMessage');
await page.screenshot({ path: path.join(shots, '3-login.png') });
await page.keyboard.press('Tab');
await page.keyboard.press('Enter');
await page.waitForTimeout(400);
check('a sign-in message can be signed', (await asked()) === mark + 1);

/* ── a page must not be able to remove the warning ──────────────────────── */

const mark2 = await asked();
await fire('approveAll');
await page.evaluate(() => {
    // what a hostile page would try
    document.querySelectorAll('div').forEach((d) => { if (!d.closest('.wrap')) d.remove(); });
});
await page.waitForTimeout(300);
check('the panel survives the page trying to delete it', (await asked()) === mark2);
await page.screenshot({ path: path.join(shots, '4-after-removal-attempt.png') });
await page.keyboard.press('Enter');
await page.waitForTimeout(350);
check('and still stops the request', (await asked()) === mark2);

/* ── and the page cannot reach into the panel ───────────────────────────── */

const reachable = await page.evaluate(() => {
    let open = 0;
    document.querySelectorAll('*').forEach((node) => { if (node.shadowRoot) open++; });
    return open;
});
check('the panel is not reachable from the page', reachable === 0,
    reachable + ' open shadow roots found — the page could click the buttons itself');

check('nothing threw in the browser', problems.length === 0, problems.join(' | '));

await context.close();
server.close();
fs.rmSync(profile, { recursive: true, force: true });

const total = pass + failures.length;
if (failures.length) {
    console.log('\nKliner Guard in a browser — ' + pass + '/' + total + '\n');
    for (const f of failures) console.log('  x ' + f.name + '\n      ' + (f.detail || ''));
    console.log('');
    process.exit(1);
}
console.log('\nKliner Guard in a browser — ' + pass + '/' + total + ' checks pass   (screenshots in test/shots)\n');

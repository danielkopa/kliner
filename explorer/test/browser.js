// Drives the real page in a real browser against the fake node. This is the
// only way to find out whether the page renders, because the page is the
// product and a passing unit test has never rendered anything.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { handle, LEDGER } from './fakenode.js';
import * as F from './fixtures.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const shots = path.join(root, 'test', 'shots');

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json' };

const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const file = path.join(root, url.pathname === '/' ? 'index.html' : url.pathname);
    if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end('no'); return;
    }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'text/plain' });
    res.end(fs.readFileSync(file));
});

const port = await new Promise((resolve) => {
    server.listen(0, () => resolve(server.address().port));
});

let pass = 0;
const failures = [];
const check = (name, condition, detail) => {
    if (condition) pass++; else failures.push({ name, detail });
};

fs.mkdirSync(shots, { recursive: true });

// The container ships one Chromium; use it rather than downloading another.
const EXECUTABLE = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const browser = await chromium.launch(
    fs.existsSync(EXECUTABLE) ? { executablePath: EXECUTABLE } : {}
);
const context = await browser.newContext({ viewport: { width: 900, height: 1200 }, deviceScaleFactor: 2 });

// Every outbound JSON-RPC call is answered locally.
await context.route('**/*', async (route) => {
    const request = route.request();
    if (request.method() !== 'POST') return route.continue();
    let body;
    try { body = JSON.parse(request.postData() || '{}'); } catch { return route.continue(); }
    return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(handle(body)),
    });
});

const page = await context.newPage();
const problems = [];
page.on('pageerror', (error) => problems.push(String(error)));
page.on('console', (message) => { if (message.type() === 'error') problems.push(message.text()); });

const base = 'http://localhost:' + port + '/';
const hashOf = (name) => LEDGER.find((e) => e.name === name).hash;

async function open(fragment, wait) {
    await page.goto(base + fragment, { waitUntil: 'load' });
    await page.waitForSelector(wait, { timeout: 15000 });
}

// ── the empty page ──────────────────────────────────────────────────────────

await open('', '.state');
check('the page loads', await page.title() === 'Kliner');
check('and says what it is for', (await page.textContent('.state')).includes('Paste a transaction'));
check('and offers every chain', (await page.$$('nav button')).length >= 6);
await page.screenshot({ path: path.join(shots, '1-empty.png'), fullPage: true });

// ── a transaction ───────────────────────────────────────────────────────────

await open('#/ethereum/' + hashOf('swap') + '/' + F.ME, '.verdict');
const verdict = await page.textContent('.verdict');
check('a swap reads as a swap', verdict.includes('You swapped'), verdict);
check('with both sides', verdict.includes('USDC') && verdict.includes('WETH'), verdict);
check('and the ledger has two rows', (await page.$$('.row')).length >= 2);
await page.screenshot({ path: path.join(shots, '2-swap.png'), fullPage: true });

await open('#/ethereum/' + hashOf('approveUnlimited') + '/' + F.ME, '.verdict');
check('an unlimited approval is named', (await page.textContent('.verdict')).includes('no limit'));
check('and flagged', (await page.$$('.flag.warn')).length === 1);
await page.screenshot({ path: path.join(shots, '3-approval.png'), fullPage: true });

await open('#/ethereum/' + hashOf('poison') + '/' + F.ME, '.verdict');
check('a poisoning attempt is named', (await page.textContent('.verdict')).includes('zero tokens'));
await page.screenshot({ path: path.join(shots, '4-poison.png'), fullPage: true });

await open('#/ethereum/' + hashOf('mint') + '/' + F.ME, '.verdict');
check('a mint reads as a mint', (await page.textContent('.verdict')).includes('You minted'));

// ── a wallet ────────────────────────────────────────────────────────────────

await open('#/ethereum/' + F.ME, '.verdict');
const walletVerdict = await page.textContent('.verdict');
check('a wallet is summarised by what can still spend from it',
    walletVerdict.includes('can still spend'), walletVerdict);
check('the standing approvals are listed', (await page.$$('.rows .row')).length >= 1);
check('recent activity is listed', (await page.$$('a.entry')).length >= 3);
const firstEntry = await page.textContent('a.entry .lead');
check('and each line is a sentence', /^(You|Nothing|\d)/.test(firstEntry.trim()), firstEntry);
await page.screenshot({ path: path.join(shots, '5-wallet.png'), fullPage: true });

// ── the small print ─────────────────────────────────────────────────────────

await open('#/ethereum/0xnonsense', '.state');
check('nonsense is refused kindly', (await page.textContent('.state')).includes('not something Kliner can read'));

await page.emulateMedia({ colorScheme: 'dark' });
await open('#/ethereum/' + hashOf('swap') + '/' + F.ME, '.verdict');
const ground = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
check('the dark ground is painted, not inherited', ground !== 'rgba(0, 0, 0, 0)' && ground !== 'transparent', ground);
await page.screenshot({ path: path.join(shots, '6-dark.png'), fullPage: true });

await page.setViewportSize({ width: 390, height: 900 });
await page.emulateMedia({ colorScheme: 'light' });
await open('#/ethereum/' + hashOf('swap') + '/' + F.ME, '.verdict');
const overflow = await page.evaluate(() =>
    document.documentElement.scrollWidth - document.documentElement.clientWidth);
check('nothing runs off the side of a phone', overflow <= 1, 'overflow ' + overflow + 'px');
await page.screenshot({ path: path.join(shots, '7-phone.png'), fullPage: true });

// The single-file build is what gets handed to someone to look at, so it has
// to work with no server at all.
const bundle = path.join(root, 'dist', 'kliner.html');
if (fs.existsSync(bundle)) {
    const single = await context.newPage();
    const alone = [];
    single.on('pageerror', (error) => alone.push(String(error)));
    await single.goto('file://' + bundle + '#/ethereum/' + hashOf('swap') + '/' + F.ME);
    await single.waitForSelector('.verdict', { timeout: 15000 });
    check('the one-file build renders without a server',
        (await single.textContent('.verdict')).includes('You swapped'));
    check('and throws nothing on its own', alone.length === 0, alone.join(' | '));
    await single.close();
} else {
    check('the one-file build exists', false, 'run node tools/bundle.js first');
}

check('nothing threw in the browser', problems.length === 0, problems.join(' | '));

await browser.close();
server.close();

const total = pass + failures.length;
if (failures.length) {
    console.log('\nKliner page — ' + pass + '/' + total + '\n');
    for (const f of failures) console.log('  x ' + f.name + '\n      ' + (f.detail || ''));
    console.log('');
    process.exit(1);
}
console.log('\nKliner page — ' + pass + '/' + total + ' checks pass   (screenshots in test/shots)\n');

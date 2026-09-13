// node test/run.js — it either says so, or tells you what broke.

import { keccak256 } from '../src/keccak.js';
import { SELECTOR, readCalldata, isUnlimited, isForever, MAX_UINT48 } from '../src/calldata.js';
import { readTypedData, readMessage, quantity } from '../src/typed.js';
import { read, shouldRead, WATCHED } from '../src/request.js';
import { explain } from '../src/warn.js';
import { format } from '../src/amount.js';
import { checksum } from '../src/hex.js';
import * as F from './fixtures.js';

let pass = 0;
const failures = [];
const show = (v) => (typeof v === 'bigint' ? v + 'n' : JSON.stringify(v));
const check = (name, ok, detail) => { if (ok) pass++; else failures.push({ name, detail }); };
const is = (name, got, want) => check(name, got === want, 'got ' + show(got) + ', wanted ' + show(want));
const has = (name, hay, needle) => check(name, String(hay).includes(needle), '"' + hay + '" has no "' + needle + '"');
const hasnt = (name, hay, needle) => check(name, !String(hay).includes(needle), '"' + hay + '" should not mention "' + needle + '"');

const seen = (name) => explain(read(F.REQUESTS[name], F.CONTEXT), F.CONTEXT);
const said = (name) => seen(name).title;
const flags = (name) => seen(name).risks.map((r) => r.code);

// ── the selectors are computed, and they match what the world publishes ─────

const PUBLISHED = {
    approve: '0x095ea7b3', setApprovalForAll: '0xa22cb465', increaseAllowance: '0x39509351',
    transfer: '0xa9059cbb', transferFrom: '0x23b872dd', safeTransferFrom721: '0x42842e0e',
    safeTransferFrom721Data: '0xb88d4fde', safeTransferFrom1155: '0xf242432a',
    permit2612: '0xd505accf', transferOwnership: '0xf2fde38b', multicall: '0xac9650d8',
};
for (const [name, id] of Object.entries(PUBLISHED)) is('selector for ' + name, SELECTOR[name], id);
is('keccak still agrees with the world',
    keccak256('Transfer(address,address,uint256)'),
    '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef');

// ── decimal strings: the bug that turned 250 USDC into 9,932 USDC ───────────

is('a decimal string reads as decimal', quantity('250000000'), 250000000n);
is('a hex string still reads as hex', quantity('0x10'), 16n);
is('a number reads', quantity(42), 42n);
is('nonsense reads as nothing', quantity('abc'), null);
has('a bounded permit says the real amount', said('permitBounded'), '250 USDC');
hasnt('and does not invent a bigger one', said('permitBounded'), '9,932');
check('and a half-hour deadline is not forever', flags('permitBounded').indexOf('forever') === -1);
has('an order in ether reads in ether', said('orderNormal'), '3 ETH');
has('a token id is not read as hex', said('orderForNothing'), '#88');
has('the chain currency is named', said('plainSend'), '2 ETH');

// ── allowances ─────────────────────────────────────────────────────────────

has('an unlimited approve says so in the sentence', said('unlimitedApprove'), 'all of it');
is('and stops', seen('unlimitedApprove').level, 'stop');
check('and flags the limit', flags('unlimitedApprove').includes('unlimited'));

has('a bounded approve states the amount', said('boundedApprove'), '100 USDC');
is('and does not stop', seen('boundedApprove').level, 'note');

is('setting an allowance to zero is clear', seen('revokeApprove').level, 'clear');
has('and reads as taking it back', said('revokeApprove'), 'takes back');

has('a collection approval says it covers everything', said('approveAll'), 'every item you own');
is('and stops', seen('approveAll').level, 'stop');
is('turning it off is clear', seen('revokeAll').level, 'clear');

check('Permit2 with max amount and max expiry stops',
    seen('permit2Approve').level === 'stop' && flags('permit2Approve').includes('forever'));

// ── the signatures ─────────────────────────────────────────────────────────

for (const name of ['permitUnlimited', 'permit2Single', 'permit2Batch', 'orderForNothing', 'blindSign', 'loginMessage']) {
    check(name + ' is marked as leaving no trace', flags(name).includes('offchain'));
}
has('a gasless permit is called a signature, not a transaction',
    seen('permitUnlimited').risks.find((r) => r.code === 'offchain').detail, 'costs no gas');

has('an unlimited permit names what it gives away', said('permitUnlimited'), 'every USDC you hold');
is('and stops', seen('permitUnlimited').level, 'stop');

has('Permit2 unlimited names the token', said('permit2Single'), 'every WETH you hold');
check('a batch permit counts them', said('permit2Batch').includes('3 different tokens'));
check('and flags that one has no ceiling', flags('permit2Batch').includes('unlimited'));

has('an order for nothing says nothing comes back', said('orderForNothing'), 'receiving nothing for it');
is('and stops', seen('orderForNothing').level, 'stop');
check('a wildcard order is flagged as unbounded', flags('orderWildcard').includes('wildcard'));
has('and says which collection it covers', said('orderWildcard'), 'any item you own');
is('an ordinary sale does not stop', seen('orderNormal').level, 'note');
check('but the marketplace fee is still shown',
    seen('orderNormal').facts.some((f) => f.includes('Also sends')));

check('a signature built for another chain is flagged',
    flags('wrongChainPermit').includes('wrong-chain'));

is('eth_sign stops', seen('blindSign').level, 'stop');
has('and says why', said('blindSign'), 'cannot explain');

is('a sign-in message is clear', seen('loginMessage').level, 'clear');
has('and is quoted back', seen('loginMessage').facts.join(' '), 'sign in with your Ethereum account');
check('JSON smuggled through the message door is flagged',
    flags('structuredMessage').includes('structured'));
check('bytes that are not text are flagged', flags('binaryMessage').includes('not-text'));

// ── honesty ────────────────────────────────────────────────────────────────

has('an unknown call is admitted, not guessed', said('unknownCall'), 'cannot read this one');
has('and says that is not the same as safe', seen('unknownCall').risks[0].title, 'not the same as safe');
check('a bundle is not pretended to be understood', flags('bundle').includes('bundle'));
check('no reading ever calls anything safe',
    Object.keys(F.REQUESTS).every((name) => {
        const out = seen(name);
        const words = (out.title + ' ' + out.risks.map((r) => r.title + r.detail).join(' ')).toLowerCase();
        return !/\bis safe\b|\blooks safe\b|\bsafe to sign\b/.test(words);
    }));

check('every request produces a sentence',
    Object.keys(F.REQUESTS).every((name) => {
        const t = said(name);
        return typeof t === 'string' && t.length > 12 && !/undefined|NaN|\[object/.test(t);
    }));

check('pulling from your own wallet is flagged', flags('pullFromYou').includes('pull'));
check('giving a contract away stops', seen('ownership').level === 'stop');

// ── the front door ─────────────────────────────────────────────────────────

check('the watched list is the dangerous ones',
    WATCHED.includes('eth_sendTransaction') && WATCHED.includes('eth_signTypedData_v4') &&
    WATCHED.includes('personal_sign') && WATCHED.includes('eth_sign'));
is('a harmless method is not watched', shouldRead('eth_blockNumber'), false);
is('and reads as ignored', read({ method: 'eth_chainId', params: [] }).kind, 'ignored');

is('a request with no data and no value is empty',
    readCalldata({ to: F.FRIEND, data: '0x', value: '0x0' }).call, 'nothing');
is('a truncated call is not guessed at',
    readCalldata({ to: F.USDC, data: '0x09' }).call, 'unreadable');
check('typed data that is not JSON is admitted',
    readTypedData('not json at all').kind === 'unreadable');
is('a message that is plain text passes through', readMessage('hello').text, 'hello');

is('unlimited means unlimited even one short of the maximum',
    isUnlimited((1n << 256n) - 2n), true);
is('and a real amount is not unlimited', isUnlimited(1000000n), false);
is('a Permit2 maximum expiry is forever', isForever(MAX_UINT48), true);

// nothing in here may alter the request it was handed
const original = JSON.stringify(F.REQUESTS.unlimitedApprove);
read(F.REQUESTS.unlimitedApprove, F.CONTEXT);
explain(read(F.REQUESTS.unlimitedApprove, F.CONTEXT), F.CONTEXT);
is('reading a request does not change it', JSON.stringify(F.REQUESTS.unlimitedApprove), original);

// ── the extension is only as loaded as its manifest is true ────────────────
//
// A manifest that names a file which is not there does not warn anybody: the
// browser refuses the whole extension in silence, and every other test here
// keeps passing while nothing at all is running. That happened once.

import fsX from 'node:fs';
import pathX from 'node:path';
import { fileURLToPath as f2u } from 'node:url';

const extDir = pathX.resolve(pathX.dirname(f2u(import.meta.url)), '..', 'extension');
const manifest = JSON.parse(fsX.readFileSync(pathX.join(extDir, 'manifest.json'), 'utf8'));

const named = [];
for (const script of manifest.content_scripts || []) for (const file of script.js || []) named.push(file);
for (const file of Object.values(manifest.icons || {})) named.push(file);
for (const file of Object.values(manifest.action?.default_icon || {})) named.push(file);

for (const file of named) {
    check('the manifest names ' + file + ' and it is there',
        fsX.existsSync(pathX.join(extDir, file)), 'missing — the browser would refuse the whole extension');
}
is('the manifest is version 3', manifest.manifest_version, 3);
check('it asks for no permissions',
    (manifest.permissions || []).length === 0 && (manifest.host_permissions || []).length === 0,
    'Kliner Guard should need none');
check('the reader runs where the page cannot reach it',
    (manifest.content_scripts || []).some((s) => s.world === 'ISOLATED' && s.js.includes('guard.js')));
check('and the wrapper runs where the wallet lives',
    (manifest.content_scripts || []).some((s) => s.world === 'MAIN' && s.js.includes('bridge.js')));

const bundled = fsX.readFileSync(pathX.join(extDir, 'guard.js'), 'utf8');
check('the built reader makes no network call',
    !/\b(fetch|XMLHttpRequest|WebSocket|sendBeacon)\s*\(/.test(bundled.replace(/^\s*\/\/.*$/gm, '')));
check('the built reader is current',
    bundled.includes('lvl-') && bundled.includes('quantity'), 'run node tools/bundle.js');

// ── report ─────────────────────────────────────────────────────────────────

const total = pass + failures.length;
if (failures.length) {
    console.log('\nKliner Guard — ' + pass + '/' + total + '\n');
    for (const f of failures) console.log('  x ' + f.name + '\n      ' + (f.detail || ''));
    console.log('');
    process.exit(1);
}
console.log('\nKliner Guard — ' + pass + '/' + total + ' checks pass\n');

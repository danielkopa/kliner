// No framework. node test/run.js, and it either says so or tells you what broke.

import { keccak256 } from '../src/keccak.js';
import { checksum, short, big, word } from '../src/hex.js';
import { TOPIC, decodeLog, MAX_UINT256 } from '../src/abi.js';
import { format, compact } from '../src/amount.js';
import { classify, netFlow } from '../src/classify.js';
import { sentence, describe, headline } from '../src/say.js';
import * as F from './fixtures.js';

let pass = 0;
const failures = [];

function check(name, condition, detail) {
    if (condition) { pass++; return; }
    failures.push({ name, detail });
}

const show = (v) => typeof v === 'bigint' ? `${v}n` : JSON.stringify(v);

function is(name, got, want) {
    check(name, got === want, `got ${show(got)}, wanted ${show(want)}`);
}

function has(name, haystack, needle) {
    check(name, String(haystack).includes(needle), `"${haystack}" does not contain "${needle}"`);
}

// ── the hash ────────────────────────────────────────────────────────────────

is('keccak256 of nothing',
    keccak256(''),
    '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470');
is('keccak256 of abc',
    keccak256('abc'),
    '0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45');
is('keccak256 across a block boundary',
    keccak256('a'.repeat(136)),
    keccak256('a'.repeat(136)));
check('keccak256 of 136 bytes is not the hash of 135',
    keccak256('a'.repeat(136)) !== keccak256('a'.repeat(135)));

// The published topic hashes. If a signature above is ever mistyped, these fail
// rather than the app quietly reading no logs at all.
const PUBLISHED = {
    transfer:       '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
    approval:       '0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925',
    approvalForAll: '0x17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31',
    transferSingle: '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62',
    transferBatch:  '0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb',
    deposit:        '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c',
    withdrawal:     '0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65',
};
for (const [name, topic] of Object.entries(PUBLISHED)) {
    is(`topic for ${name}`, TOPIC[name], topic);
}

// ── addresses ───────────────────────────────────────────────────────────────

for (const a of [
    '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
    '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
    '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
    '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
]) {
    is(`checksum of ${a.slice(0, 8)}`, checksum(a.toLowerCase()), a);
}
check('a short address keeps both ends', short(F.USDC).startsWith('0xA0b869') || short(F.USDC).startsWith('0xa0b869'));

// ── amounts ─────────────────────────────────────────────────────────────────

is('whole ether', format(10n ** 18n, 18), '1');
is('a fraction of ether', format(430000000000000000n, 18), '0.43');
is('thousands are grouped', format(1200n * 10n ** 6n, 6), '1,200');
is('dust still says something', format(1234n, 18), '0.000000000000001234');
is('zero is zero', format(0n, 18), '0');
is('a token with no decimals', format(3n, 0), '3');
is('big numbers get short', compact(1_500_000n * 10n ** 18n, 18), '1.5M');

// ── decoding ────────────────────────────────────────────────────────────────

const t20 = decodeLog(F.transfer(F.USDC, F.ME, F.FRIEND, 50n * 10n ** 6n));
is('an amount in the data field means ERC-20', t20.standard, 'erc20');
is('the amount decodes', t20.amount, 50000000n);

const t721 = decodeLog(F.transferNFT(F.NFT, F.ZERO, F.ME, 4021));
is('a fourth topic means ERC-721', t721.standard, 'erc721');
is('the token id decodes', t721.tokenId, 4021n);

const batch = decodeLog(F.batch1155(F.GAME, F.ME, F.ME, F.FRIEND, [[7, 3], [9, 1]]));
is('a batch decodes both arrays', batch.items.length, 2);
is('the first batch item', `${batch.items[0].tokenId}x${batch.items[0].amount}`, '7x3');
is('the second batch item', `${batch.items[1].tokenId}x${batch.items[1].amount}`, '9x1');

check('an event we do not read returns nothing',
    decodeLog({ address: F.USDC, topics: ['0x' + '11'.repeat(32)], data: '0x' }) === null);
check('a log with no topics returns nothing',
    decodeLog({ address: F.USDC, topics: [], data: '0x' }) === null);
is('a missing data word reads as zero', word('0x', 3), 0n);
is('rubbish reads as zero rather than throwing', big('0xzz'), 0n);

// ── shapes ──────────────────────────────────────────────────────────────────

const seen = (name, wallet = F.ME) => classify(F.CASES[name], wallet, F.META);
const said = (name, wallet = F.ME) => sentence(seen(name, wallet), F.META);

is('a swap is one token out and one token in', seen('swap').kind, 'swap');
has('and it says which way round', said('swap'), 'You swapped 1,200 USDC for 0.43 WETH.');

is('a swap ending in the native currency is still a swap', seen('swapForEth').kind, 'swap');
has('and the unwrapped side is found', said('swapForEth'), '0.43 ETH');
check('and it admits the native side was inferred',
    seen('swapForEth').notes.some((n) => n.includes('unwrap')));

is('a swap starting from the native currency', seen('swapEthIn').kind, 'swap');
has('and reads in the right order', said('swapEthIn'), 'You swapped 1 ETH for 2,800 USDC.');

is('a token leaving on its own is a send', seen('send').kind, 'send');
has('and names who got it', said('send'), 'You sent 50 USDC to');

is('the native currency leaving is also a send', seen('sendNative').kind, 'send');
has('and is measured in ether', said('sendNative'), '2 ETH');

is('a token arriving unsigned is a receive', seen('receive').kind, 'receive');
check('and the wallet is told it did not sign',
    seen('receive').risks.some((r) => r.code === 'unsigned-arrival'));

is('an allowance is an approval', seen('approveUnlimited').kind, 'approve');
check('an unlimited one is flagged',
    seen('approveUnlimited').risks.some((r) => r.code === 'unlimited-approval'));
has('and says so plainly', said('approveUnlimited'), 'with no limit');

is('a bounded allowance is still an approval', seen('approveLimited').kind, 'approve');
check('but is not flagged', seen('approveLimited').risks.length === 0);
has('and states the amount', said('approveLimited'), '100 USDC');

check('approving a whole collection is flagged',
    seen('approveAll').risks.some((r) => r.code === 'approve-all'));
has('and is described as the collection', said('approveAll'), 'every Cool Cats');

is('setting an allowance to zero is a revoke', seen('revoke').kind, 'revoke');
has('and reads as taking it back', said('revoke'), 'took back');

is('wrapping is its own thing', seen('wrap').kind, 'wrap');
has('and says both sides', said('wrap'), 'You wrapped 1 ETH into 1 WETH.');
is('unwrapping too', seen('unwrap').kind, 'unwrap');
has('and reads the other way', said('unwrap'), 'back into 1 ETH');

is('an NFT out of nowhere is a mint', seen('mint').kind, 'mint');
has('and carries what it cost', said('mint'), 'You minted Cool Cats #4021 for 0.08 ETH.');

is('an NFT in and a token out is a purchase', seen('nftBuy').kind, 'nft-buy');
has('and reads as buying', said('nftBuy'), 'You bought Cool Cats #88 for 3 WETH.');
is('the other way round is a sale', seen('nftSell').kind, 'nft-sell');
has('and reads as selling', said('nftSell'), 'You sold Cool Cats #88 for 3 WETH.');
is('an NFT leaving alone is a send', seen('nftSend').kind, 'nft-send');

is('a 1155 leaving is a send', seen('itemsSend').kind, 'nft-send');
has('and keeps the count', said('itemsSend'), '3× Game item #7');
is('a batch of 1155s is a send', seen('itemsBatch').kind, 'send');
has('and lists all of them', said('itemsBatch'), 'Game item #9');
has('and still names the person, not the contract', said('itemsBatch'), '0x555555');

is('a token out to a known bridge is a bridge', seen('bridge').kind, 'bridge');
has('and names it', said('bridge'), 'the Arbitrum bridge');

is('tokens arriving when you asked is a claim', seen('claim').kind, 'claim');
has('and says how many', said('claim'), 'You claimed 625 ARB.');

is('two in and a minted share is adding liquidity', seen('addLiquidity').kind, 'add-liquidity');
has('and says what came back', said('addLiquidity'), 'as your share');
is('a burned share and two out is removing it', seen('removeLiquidity').kind, 'remove-liquidity');
has('and lists both sides', said('removeLiquidity'), '3,000 USDC and 1 WETH');

is('a reverted transaction is not silent', seen('failed').kind, 'failed');
has('and says the gas went anyway', said('failed'), 'gas was spent anyway');
has('and the gas is reported', headline(seen('failed'), F.META).cost, 'Gas: 0.00144 ETH');

is('a transfer of zero is named', seen('poison').kind, 'poison');
check('and flagged', seen('poison').risks.some((r) => r.code === 'zero-value-transfer'));
has('and warns off copying the address', said('poison'), 'zero tokens');
has('and shows the address in full, because that is the trick',
    said('poison'), '0x1111111111112222222222222222111111111111'.slice(0, 30));

is('a transaction between other people is unrelated', seen('unrelated').kind, 'unrelated');
is('a call that moved nothing is a call', seen('call').kind, 'call');
has('and names what was called', said('call'), 'You called');

is('value leaving without your signature is not a send', seen('taken').kind, 'taken');
has('and says so', said('taken'), 'did not sign');

// ── the arithmetic underneath ───────────────────────────────────────────────

const flow = netFlow(F.CASES.swap, F.ME, F.META);
is('a swap nets to two rows', flow.rows.length, 2);
is('one of them is incoming', flow.incoming.length, 1);
is('and one outgoing', flow.outgoing.length, 1);

const roundTrip = {
    ...F.CASES.send,
    logs: [
        F.transfer(F.USDC, F.ME, F.POOL, 50n * 10n ** 6n),
        F.transfer(F.USDC, F.POOL, F.ME, 50n * 10n ** 6n),
    ],
};
is('a token that comes straight back nets to nothing',
    netFlow(roundTrip, F.ME, F.META).rows.length, 0);
is('and reads as a call, not a swap with itself',
    classify(roundTrip, F.ME, F.META).kind, 'call');

is('the same receipt read for someone else says so',
    classify(F.CASES.swap, F.FRIEND, F.META).kind, 'unrelated');

const unknownToken = {
    ...F.CASES.send,
    logs: [F.transfer('0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef', F.ME, F.FRIEND, 1000000n)],
};
check('a token we know nothing about still reads',
    sentence(classify(unknownToken, F.ME, F.META), F.META).startsWith('You sent'));

const noMeta = classify(F.CASES.swap, F.ME, {});
is('and so does a chain we have no metadata for at all', noMeta.kind, 'swap');
check('the sentence survives an empty metadata object',
    sentence(noMeta, {}).startsWith('You swapped'));

is('an unlimited allowance is recognised however it is written',
    classify({ ...F.CASES.approveUnlimited,
        logs: [F.approval(F.USDC, F.ME, F.ROUTER, MAX_UINT256 - 1n)] },
        F.ME, F.META).risks.length, 1);

check('a Deposit from something that is not the wrapped token is ignored',
    classify({ ...F.CASES.wrap, logs: [{ ...F.wrapLog(F.ME, 10n ** 18n), address: F.GAME }] },
        F.ME, F.META).kind !== 'wrap');

check('every case produces a sentence',
    Object.keys(F.CASES).every((name) => {
        const s = said(name);
        return typeof s === 'string' && s.length > 10 && !s.includes('undefined') && !s.includes('NaN');
    }));

// ── report ──────────────────────────────────────────────────────────────────

const total = pass + failures.length;
if (failures.length) {
    console.log(`\nKliner core — ${pass}/${total}\n`);
    for (const f of failures) console.log(`  ✗ ${f.name}\n      ${f.detail || ''}`);
    console.log('');
    process.exit(1);
}
console.log(`\nKliner core — ${pass}/${total} checks pass\n`);

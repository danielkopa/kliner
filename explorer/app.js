// The page. Everything it knows comes from src/; this file only arranges it.

import { CHAIN_LIST, chainByKey } from './src/chains.js';
import { makeRpc, readTransaction, scanWallet, transactionsIn, readMany,
         standingApprovals, balances } from './src/scan.js';
import { sentence, describe, costLine } from './src/say.js';
import { format } from './src/amount.js';
import { checksum, short, isAddress, lower, big } from './src/hex.js';
import { hasWallet, sendRevoke, describeRevoke } from './src/wallet.js';

const out = document.getElementById('out');
const field = document.getElementById('q');
const form = document.getElementById('form');
const nav = document.getElementById('chains');
const source = document.getElementById('source');

let chain = chainByKey('ethereum');
let rpc = makeRpc(chain);
let run = 0; // cancels a reading that has been superseded

// ── plumbing ────────────────────────────────────────────────────────────────

const el = (tag, attrs = {}, children = []) => {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
        if (v === null || v === undefined || v === false) continue;
        if (k === 'class') node.className = v;
        else if (k === 'text') node.textContent = v;
        else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
        else node.setAttribute(k, v === true ? '' : String(v));
    }
    for (const child of [].concat(children)) {
        if (child === null || child === undefined || child === false) continue;
        node.append(typeof child === 'string' ? document.createTextNode(child) : child);
    }
    return node;
};

const clear = () => { out.textContent = ''; };
const show = (...nodes) => { clear(); out.append(...nodes); };

function state(strongText, rest) {
    return el('p', { class: 'state' }, [el('strong', { text: strongText }), ' ', rest || '']);
}

function heading(text, trail) {
    const h = el('h2', {}, [text]);
    if (trail) h.append(el('span', { class: 'dim', style: 'letter-spacing:0;text-transform:none;font-weight:400', text: trail }));
    return h;
}

const asNumber = (hex) => Number(big(hex));

function timeAgo(seconds) {
    const delta = Math.max(0, Math.floor(Date.now() / 1000) - seconds);
    const steps = [[31536000, 'year'], [2592000, 'month'], [86400, 'day'], [3600, 'hour'], [60, 'minute']];
    for (const [size, word] of steps) {
        if (delta >= size) {
            const n = Math.floor(delta / size);
            return n + ' ' + word + (n === 1 ? '' : 's') + ' ago';
        }
    }
    return 'just now';
}

// ── chain tabs ──────────────────────────────────────────────────────────────

function paintChains() {
    nav.textContent = '';
    for (const c of CHAIN_LIST) {
        nav.append(el('button', {
            type: 'button',
            text: c.name,
            'aria-pressed': c.key === chain.key,
            onclick: () => {
                if (c.key === chain.key) return;
                chain = chainByKey(c.key);
                rpc = makeRpc(chain);
                paintChains();
                if (field.value.trim()) go(field.value.trim());
                else route();
            },
        }));
    }
}

// ── the empty page ──────────────────────────────────────────────────────────

function welcome() {
    show(
        el('p', { class: 'state' }, [
            el('strong', { text: 'Paste a transaction and read what happened.' }),
            ' Kliner works out the shape of it from what actually moved, so it can read a ' +
            'contract nobody has ever labelled. Paste a wallet address instead and it lists ' +
            'what that wallet still lets other contracts spend.',
        ]),
        el('p', { class: 'state', style: 'margin-top:18px' }, [
            'Nothing you type is sent anywhere except the public node for ' + chain.name +
            '. There is no account and no key.',
        ]),
    );
    source.textContent = '';
}

// ── one transaction ─────────────────────────────────────────────────────────

function ledgerRow(row, meta, side) {
    const where = side === 'out' ? row.to[0] : row.from[0];
    return el('div', { class: 'row' }, [
        el('span', { class: 'side', text: side === 'out' ? 'out' : 'in' }),
        el('span', { class: 'what' }, [
            describe(row, meta),
            row.inferred ? el('span', { class: 'dim', text: '  (read from the unwrap)' }) : null,
        ]),
        el('span', { class: 'aside', text: where ? (side === 'out' ? 'to ' : 'from ') + short(where) : '' }),
    ]);
}

function flagNode(risk) {
    return el('div', { class: 'flag ' + (risk.level === 'warn' ? 'warn' : 'note') }, [
        el('span', { class: 'glyph', text: risk.level === 'warn' ? '!' : '·' }),
        el('div', {}, [
            el('div', { class: 'title', text: risk.title }),
            el('div', { class: 'detail', text: risk.detail }),
        ]),
    ]);
}

function paintTransaction({ tx, meta, result }, wallet) {
    const nodes = [];

    nodes.push(el('p', { class: 'verdict', text: sentence(result, meta) }));

    const facts = [chain.name];
    if (tx.blockNumber) facts.push('block ' + asNumber(tx.blockNumber).toLocaleString('en-US'));
    const cost = costLine(result, meta);
    if (cost) facts.push(cost);
    const under = el('p', { class: 'under' }, facts.map((f) => el('span', { text: f })));
    under.append(el('a', {
        href: chain.explorer + '/tx/' + tx.hash,
        target: '_blank',
        rel: 'noreferrer noopener',
        text: 'raw',
    }));
    nodes.push(under);

    if (result.outgoing.length || result.incoming.length) {
        const rows = el('div', { class: 'rows' }, [
            ...result.outgoing.map((r) => ledgerRow(r, meta, 'out')),
            ...result.incoming.map((r) => ledgerRow(r, meta, 'in')),
        ]);
        nodes.push(el('section', {}, [heading('What moved'), rows]));
    }

    if (result.risks.length) {
        nodes.push(el('section', {}, [
            heading('Worth knowing'),
            el('div', {}, result.risks.map(flagNode)),
        ]));
    }

    if (result.notes.length) {
        nodes.push(el('section', {}, [
            heading('How this was read'),
            el('div', {}, result.notes.map((n) => el('p', { class: 'detail dim', style: 'margin:12px 0 0', text: n }))),
        ]));
    }

    const readAs = wallet && lower(wallet) !== lower(tx.from);
    nodes.push(el('section', {}, [
        heading('Seen from'),
        el('div', { class: 'line' }, [
            el('span', { class: 'lead mono', text: checksum(result.wallet) }),
            el('span', { class: 'trail', text: readAs ? 'not the signer' : 'the signer' }),
        ]),
        el('div', { class: 'line' }, [
            el('span', { class: 'lead dim', text: 'Read it as another wallet to see the same transaction from their side.' }),
            el('button', {
                class: 'act', type: 'button', text: 'Change',
                onclick: () => {
                    const other = prompt('Read this transaction as which address?', checksum(result.wallet));
                    if (other && isAddress(other.trim())) {
                        location.hash = '#/' + chain.key + '/' + tx.hash + '/' + lower(other.trim());
                    }
                },
            }),
        ]),
    ]));

    show(...nodes);
    source.textContent = 'read from ' + new URL(rpc.urls[0]).host;
}

// ── one wallet ──────────────────────────────────────────────────────────────

function approvalLine(approval, owner) {
    const what = approval.unlimited
        ? 'no limit'
        : format(approval.amount, approval.decimals, { significant: 4 }) + ' ' + (approval.symbol || '');

    const name = approval.symbol || approval.token_name;
    const button = el('button', {
        class: 'act', type: 'button',
        text: hasWallet() ? 'Revoke' : 'No wallet',
        disabled: !hasWallet(),
    });

    const status = el('span', { class: 'trail', text: what });

    button.addEventListener('click', async () => {
        const asked = confirm(describeRevoke(approval) + '\n\nYour wallet will ask you to confirm. Kliner cannot sign anything.');
        if (!asked) return;
        button.disabled = true;
        button.textContent = 'Waiting';
        try {
            const hash = await sendRevoke(approval, owner, chain);
            button.textContent = 'Sent';
            status.textContent = 'revoking';
            status.append(' ', el('a', {
                href: chain.explorer + '/tx/' + hash,
                target: '_blank', rel: 'noreferrer noopener', text: 'tx',
            }));
        } catch (error) {
            button.disabled = false;
            button.textContent = 'Revoke';
            status.textContent = error.message || 'the wallet refused';
        }
    });

    return el('div', { class: 'row' + (approval.unlimited ? ' warn' : '') }, [
        el('span', { class: 'side', text: approval.unlimited ? '!' : '' }),
        el('div', {}, [
            el('div', { class: 'what', text: name }),
            el('div', { class: 'sub mono', text: short(approval.spender) + ' can spend it' }),
        ]),
        el('div', { style: 'display:flex;gap:12px;align-items:baseline;justify-content:flex-end' }, [status, button]),
    ]);
}

function paintWallet(address, data) {
    const nodes = [];
    const live = data.approvals.filter((a) => a.unlimited || a.amount > 0n);

    nodes.push(el('p', { class: 'verdict' }, [
        live.length
            ? live.length + (live.length === 1 ? ' contract can still spend' : ' contracts can still spend') +
              ' from this wallet.'
            : 'Nothing is left standing that can spend from this wallet.',
    ]));

    nodes.push(el('p', { class: 'under' }, [
        el('span', { class: 'mono', text: checksum(address) }),
        el('span', { text: chain.name }),
        el('a', {
            href: chain.explorer + '/address/' + address,
            target: '_blank', rel: 'noreferrer noopener', text: 'raw',
        }),
    ]));

    if (live.length) {
        nodes.push(el('section', {}, [
            heading('Still allowed to spend', 'newest first'),
            el('div', { class: 'rows' }, live.map((a) => approvalLine(a, address))),
        ]));
    }

    if (data.holdings.length) {
        nodes.push(el('section', {}, [
            heading('Holds'),
            el('div', { class: 'rows' }, data.holdings.map((b) => el('div', { class: 'line' }, [
                el('span', { class: 'lead', text: format(b.amount, b.decimals, { significant: 5 }) + ' ' + (b.symbol || b.name) }),
                el('span', { class: 'trail mono', text: b.token === 'native' ? '' : short(b.token) }),
            ]))),
        ]));
    }

    if (data.history.length) {
        nodes.push(el('section', {}, [
            heading('Recently', data.window),
            el('div', { class: 'rows' }, data.history.map((entry) => el('a', {
                class: 'entry line',
                href: '#/' + chain.key + '/' + entry.tx.hash + '/' + lower(address),
            }, [
                el('span', { class: 'lead', text: sentence(entry.result, entry.meta) }),
                el('span', { class: 'trail', text: entry.when || '' }),
            ]))),
        ]));
    }

    if (!live.length && !data.history.length) {
        nodes.push(state('Nothing found in that window.', 'This wallet may simply be quiet, or older than the range a free public node will search.'));
    }

    show(...nodes);
    source.textContent = 'read from ' + new URL(rpc.urls[0]).host;
}

// ── doing the work ──────────────────────────────────────────────────────────

function progress(label) {
    const text = el('div', { class: 'progress', text: label });
    const fill = el('i');
    const node = el('div', {}, [text, el('div', { class: 'bar' }, [fill])]);
    show(el('div', { style: 'margin-top:48px' }, [node]));
    return {
        say(message, fraction) {
            text.textContent = message;
            if (typeof fraction === 'number') fill.style.width = Math.min(100, Math.max(0, fraction * 100)) + '%';
        },
    };
}

async function readOneTransaction(hash, wallet) {
    const mine = ++run;
    const bar = progress('Reading ' + short(hash, 10, 8) + ' on ' + chain.name + '…');
    try {
        const found = await readTransaction(rpc, chain, hash, wallet);
        if (mine !== run) return;
        paintTransaction(found, wallet);
    } catch (error) {
        if (mine !== run) return;
        show(state('That did not read.', error.message));
    }
}

async function readOneWallet(address) {
    const mine = ++run;
    const bar = progress('Looking at ' + short(address) + ' on ' + chain.name + '…');
    const cache = new Map();

    try {
        const head = Number(big(await rpc.blockNumber()));
        const depth = Math.round((180 * 24 * 3600) / chain.blockTime);
        const from = Math.max(0, head - depth);

        const { logs } = await scanWallet(rpc, chain, address, {
            head, from,
            onProgress: ({ block, found }) => {
                if (mine !== run) return;
                const done = (head - block) / Math.max(1, head - from);
                bar.say('Reading blocks… ' + (found || 0) + ' entries so far', done);
            },
        });
        if (mine !== run) return;

        bar.say('Checking what is still allowed…', 0.8);
        const approvals = await standingApprovals(rpc, chain, address, logs, cache);
        if (mine !== run) return;

        const txs = transactionsIn(logs).slice(0, 15);
        bar.say('Reading the last ' + txs.length + ' transactions…', 0.9);
        const history = await readMany(rpc, chain, txs.map((t) => t.hash), address, cache);
        if (mine !== run) return;

        const times = await blockTimes(txs.map((t) => t.block));
        for (const entry of history) {
            const when = times.get(asNumber(entry.tx.blockNumber));
            entry.when = when ? timeAgo(when) : '';
        }

        const tokens = new Set();
        for (const log of logs) tokens.add(lower(log.address));
        const holdings = await balances(rpc, chain, address, [...tokens].slice(0, 60), cache);
        if (mine !== run) return;

        paintWallet(address, {
            approvals,
            history,
            holdings,
            window: 'last ' + Math.round(depth * chain.blockTime / 86400) + ' days',
        });
    } catch (error) {
        if (mine !== run) return;
        show(state('That wallet did not read.', error.message +
            ' Free public nodes limit how far back they will search; try another chain, or a single transaction hash.'));
    }
}

async function blockTimes(blocks) {
    const wanted = [...new Set(blocks)].slice(0, 20);
    const map = new Map();
    if (!wanted.length) return map;
    try {
        const answers = await rpc.batch(wanted.map((b) => ({
            method: 'eth_getBlockByNumber',
            params: ['0x' + b.toString(16), false],
        })));
        wanted.forEach((b, i) => {
            const block = answers[i]?.result;
            if (block) map.set(b, asNumber(block.timestamp));
        });
    } catch { /* times are a nicety, not the point */ }
    return map;
}

// ── routing ─────────────────────────────────────────────────────────────────

function go(query) {
    const value = query.trim();
    if (/^0x[0-9a-fA-F]{64}$/.test(value)) {
        location.hash = '#/' + chain.key + '/' + value.toLowerCase();
    } else if (isAddress(value)) {
        location.hash = '#/' + chain.key + '/' + value.toLowerCase();
    } else {
        show(state('That is not something Kliner can read.',
            'A transaction hash is 66 characters starting 0x. A wallet address is 42.'));
    }
}

function route() {
    const parts = location.hash.replace(/^#\/?/, '').split('/').filter(Boolean);
    if (!parts.length) { field.value = ''; welcome(); return; }

    const named = chainByKey(parts[0]);
    if (named && named.key !== chain.key) {
        chain = named;
        rpc = makeRpc(chain);
        paintChains();
    }

    const subject = named ? parts[1] : parts[0];
    const wallet = named ? parts[2] : parts[1];
    if (!subject) { welcome(); return; }

    field.value = subject;
    if (/^0x[0-9a-fA-F]{64}$/.test(subject)) readOneTransaction(subject, wallet && isAddress(wallet) ? wallet : null);
    else if (isAddress(subject)) readOneWallet(lower(subject));
    else show(state('That is not something Kliner can read.', 'Paste a transaction hash or a wallet address.'));
}

form.addEventListener('submit', (event) => {
    event.preventDefault();
    go(field.value);
});

window.addEventListener('hashchange', route);
paintChains();
route();

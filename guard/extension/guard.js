// Kliner Guard — the reader.
//
// Built from src/ by tools/bundle.js. Every line of it is in this repository.
// It makes no network request of any kind: there is no fetch, no XHR, no
// WebSocket and no image beacon anywhere below, which is why the extension
// asks for no permissions and cannot report on you.
(function(){
"use strict";

/* src/keccak.js */
// keccak256 — the hash Ethereum uses for event topics and address checksums.
//
// This is Keccak, not NIST SHA-3. They differ in one byte of padding
// (0x01 here, 0x06 there), which is why node's crypto.sha3-256 cannot
// stand in for it. No dependency does this for us, so it lives here.
//
// Lanes are BigInt. That is slower than the usual 32-bit-pair trick, but
// it is short enough to read and check by eye, and we hash addresses and
// signatures, not megabytes.

const MASK = (1n << 64n) - 1n;

const RHO = [
     0n,  1n, 62n, 28n, 27n,
    36n, 44n,  6n, 55n, 20n,
     3n, 10n, 43n, 25n, 39n,
    41n, 45n, 15n, 21n,  8n,
    18n,  2n, 61n, 56n, 14n,
];

const RC = [
    0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an,
    0x8000000080008000n, 0x000000000000808bn, 0x0000000080000001n,
    0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an,
    0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
    0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n,
    0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
    0x000000000000800an, 0x800000008000000an, 0x8000000080008081n,
    0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];

const rotl = (v, n) => n === 0n ? v : ((v << n) | (v >> (64n - n))) & MASK;

function permute(A) {
    for (let round = 0; round < 24; round++) {
        // theta
        const C = new Array(5);
        for (let x = 0; x < 5; x++) {
            C[x] = A[x] ^ A[x + 5] ^ A[x + 10] ^ A[x + 15] ^ A[x + 20];
        }
        for (let x = 0; x < 5; x++) {
            const D = C[(x + 4) % 5] ^ rotl(C[(x + 1) % 5], 1n);
            for (let y = 0; y < 5; y++) A[x + 5 * y] ^= D;
        }

        // rho and pi
        const B = new Array(25).fill(0n);
        for (let x = 0; x < 5; x++) {
            for (let y = 0; y < 5; y++) {
                B[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(A[x + 5 * y], RHO[x + 5 * y]);
            }
        }

        // chi
        for (let y = 0; y < 5; y++) {
            for (let x = 0; x < 5; x++) {
                A[x + 5 * y] = B[x + 5 * y] ^
                    ((~B[(x + 1) % 5 + 5 * y] & MASK) & B[(x + 2) % 5 + 5 * y]);
            }
        }

        // iota
        A[0] ^= RC[round];
    }
}

const RATE = 136; // bytes absorbed per block for a 256-bit output

// Returns 32 bytes.
function keccak256Bytes(input) {
    const bytes = typeof input === 'string'
        ? new TextEncoder().encode(input)
        : Uint8Array.from(input);

    const padded = new Uint8Array(Math.floor(bytes.length / RATE) * RATE + RATE);
    padded.set(bytes);
    padded[bytes.length] = 0x01;
    padded[padded.length - 1] |= 0x80;

    const A = new Array(25).fill(0n);
    for (let off = 0; off < padded.length; off += RATE) {
        for (let lane = 0; lane < RATE / 8; lane++) {
            let v = 0n;
            for (let b = 7; b >= 0; b--) {
                v = (v << 8n) | BigInt(padded[off + lane * 8 + b]);
            }
            A[lane] ^= v;
        }
        permute(A);
    }

    const out = new Uint8Array(32);
    for (let lane = 0; lane < 4; lane++) {
        let v = A[lane];
        for (let b = 0; b < 8; b++) {
            out[lane * 8 + b] = Number(v & 0xffn);
            v >>= 8n;
        }
    }
    return out;
}

// Returns '0x' + 64 hex characters.
function keccak256(input) {
    let s = '0x';
    for (const b of keccak256Bytes(input)) s += b.toString(16).padStart(2, '0');
    return s;
}

/* src/hex.js */
// Small helpers for the shapes an RPC node hands back: 0x-strings.



const ZERO = '0x0000000000000000000000000000000000000000';
const DEAD = '0x000000000000000000000000000000000000dead';

function strip(hex) {
    return (hex || '').toLowerCase().replace(/^0x/, '');
}

// Any 0x-quantity to BigInt. Missing or malformed reads as 0n, because a
// receipt with a field we did not expect should not take the page down.
function big(hex) {
    if (typeof hex === 'bigint') return hex;
    if (typeof hex === 'number') return BigInt(hex);
    const s = strip(hex);
    if (!s || /[^0-9a-f]/.test(s)) return 0n;
    return BigInt('0x' + s);
}

// Addresses arrive in topics left-padded to 32 bytes.
function addressFromTopic(topic) {
    const s = strip(topic);
    return '0x' + s.slice(-40).padStart(40, '0');
}

function lower(address) {
    return (address || '').toLowerCase();
}

function sameAddress(a, b) {
    return !!a && !!b && a.toLowerCase() === b.toLowerCase();
}

function isZero(address) {
    return sameAddress(address, ZERO);
}

// Read the Nth 32-byte word out of a log's data field.
function word(data, index) {
    const s = strip(data);
    const at = index * 64;
    if (s.length < at + 64) return 0n;
    return BigInt('0x' + s.slice(at, at + 64));
}

function words(data) {
    const s = strip(data);
    const out = [];
    for (let i = 0; i + 64 <= s.length; i += 64) out.push(BigInt('0x' + s.slice(i, i + 64)));
    return out;
}

// EIP-55: the mixed-case form that catches a mistyped address.
function checksum(address) {
    const body = strip(address).padStart(40, '0');
    const hash = keccak256Bytes(body);
    let out = '0x';
    for (let i = 0; i < 40; i++) {
        const nibble = i % 2 === 0 ? hash[i >> 1] >> 4 : hash[i >> 1] & 0x0f;
        const c = body[i];
        out += nibble >= 8 ? c.toUpperCase() : c;
    }
    return out;
}

function isAddress(value) {
    return typeof value === 'string' && /^0x[0-9a-fA-F]{40}$/.test(value);
}

function short(address, head = 6, tail = 4) {
    const a = checksum(address);
    return a.slice(0, 2 + head) + '…' + a.slice(-tail);
}

/* src/amount.js */
// Turning a 256-bit integer into something a person reads without counting
// zeroes. All of it stays in BigInt: a token balance does not survive being
// a JavaScript number, and the one place that matters is the one place people
// look.

function format(amount, decimals = 18, options = {}) {
    const significant = options.significant ?? 6;
    const negative = amount < 0n;
    let v = negative ? -amount : amount;

    const d = BigInt(decimals);
    const unit = 10n ** d;
    const whole = v / unit;
    const rest = v % unit;

    let fraction = '';
    if (rest > 0n) {
        fraction = rest.toString().padStart(decimals, '0');
        // Keep enough digits to say something, counting from the first that is
        // not a zero, so 0.00001234 does not round away to nothing.
        const lead = fraction.length - fraction.replace(/^0+/, '').length;
        const keep = whole > 0n ? Math.min(significant, 6) : lead + significant;
        fraction = fraction.slice(0, Math.max(keep, 1)).replace(/0+$/, '');
    }

    const head = group(whole.toString());
    const text = fraction ? `${head}.${fraction}` : head;

    if (v > 0n && text.replace(/[0.,]/g, '') === '') {
        return (negative ? '-' : '') + `<0.${'0'.repeat(Math.max(significant - 1, 0))}1`;
    }
    return (negative ? '-' : '') + text;
}

function group(digits) {
    return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

// Compact form for a dense list: 1.2M rather than 1,200,000.
function compact(amount, decimals = 18) {
    const unit = 10n ** BigInt(decimals);
    const whole = (amount < 0n ? -amount : amount) / unit;
    const sign = amount < 0n ? '-' : '';
    const steps = [
        [1000000000000n, 'T'], [1000000000n, 'B'], [1000000n, 'M'], [1000n, 'k'],
    ];
    for (const [size, suffix] of steps) {
        if (whole >= size) {
            const scaled = Number(whole * 100n / size) / 100;
            return sign + String(scaled) + suffix;
        }
    }
    return format(amount, decimals, { significant: 4 });
}

/* src/known.js */
// A small table of tokens, so an amount can be written the way a person reads it.
//
// Kliner Guard never goes to the network — that is the whole point — so it
// cannot ask a token how many decimals it has. This table covers the tokens
// that drainers actually target. A token that is missing is not a failure: the
// amount is then shown in its raw units and said to be raw, which is honest,
// and "everything, forever" does not need decimals at all.

const TOKENS = {
    // Ethereum
    '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48': { symbol: 'USDC', decimals: 6 },
    '0xdac17f958d2ee523a2206206994597c13d831ec7': { symbol: 'USDT', decimals: 6 },
    '0x6b175474e89094c44da98b954eedeac495271d0f': { symbol: 'DAI', decimals: 18 },
    '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2': { symbol: 'WETH', decimals: 18 },
    '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599': { symbol: 'WBTC', decimals: 8 },
    '0xae7ab96520de3a18e5e111b5eaab095312d7fe84': { symbol: 'stETH', decimals: 18 },
    '0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0': { symbol: 'wstETH', decimals: 18 },
    '0x514910771af9ca656af840dff83e8264ecf986ca': { symbol: 'LINK', decimals: 18 },
    '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984': { symbol: 'UNI', decimals: 18 },
    '0x6982508145454ce325ddbe47a25d4ec3d2311933': { symbol: 'PEPE', decimals: 18 },
    '0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce': { symbol: 'SHIB', decimals: 18 },
    '0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9': { symbol: 'AAVE', decimals: 18 },
    '0x4d224452801aced8b2f0aebe155379bb5d594381': { symbol: 'APE', decimals: 18 },
    '0xd533a949740bb3306d119cc777fa900ba034cd52': { symbol: 'CRV', decimals: 18 },

    // Base
    '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913': { symbol: 'USDC', decimals: 6 },
    '0x4200000000000000000000000000000000000006': { symbol: 'WETH', decimals: 18 },

    // Arbitrum
    '0xaf88d065e77c8cc2239327c5edb3a432268e5831': { symbol: 'USDC', decimals: 6 },
    '0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9': { symbol: 'USDT', decimals: 6 },
    '0x82af49447d8a07e3bd95bd0d56f35241523fbab1': { symbol: 'WETH', decimals: 18 },
    '0x912ce59144191c1204e64559fe8253a0e49e6548': { symbol: 'ARB', decimals: 18 },

    // Polygon
    '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270': { symbol: 'WPOL', decimals: 18 },
    '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359': { symbol: 'USDC', decimals: 6 },
};

// Contracts worth naming when they show up as the thing being called.
const CONTRACTS = {
    '0x000000000022d473030f116ddee9f6b43ac78ba3': 'Permit2',
    '0x00000000006c3852cbef3e08e8df289169ede581': 'Seaport 1.1',
    '0x00000000000001ad428e4906ae43d8f9852d0dd6': 'Seaport 1.4',
    '0x0000000000000068f116a894984e2db1123eb395': 'Seaport 1.6',
    '0x3fc91a3afd70395cd496c647d5a6cc9d4b2b7fad': 'the Uniswap Universal Router',
    '0x7a250d5630b4cf539739df2c5dacb4c659f2488d': 'the Uniswap V2 Router',
    '0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45': 'the Uniswap V3 Router',
    '0x1111111254eeb25477b68fb85ed929f73a960582': 'the 1inch Router',
    '0x000000000000ad05ccc4f10045630fb830b95127': 'Blur',
};

// What the chain's own currency is called, so an amount with no token can
// still be written properly.
const CURRENCY = {
    1: 'ETH', 8453: 'ETH', 42161: 'ETH', 10: 'ETH', 324: 'ETH', 534352: 'ETH', 59144: 'ETH',
    137: 'POL', 56: 'BNB', 43114: 'AVAX', 100: 'xDAI', 250: 'FTM',
};

function currencyFor(chainId) {
    return CURRENCY[Number(chainId)] || 'the chain currency';
}

function tokenFor(address) {
    return TOKENS[(address || '').toLowerCase()] || null;
}

function contractName(address) {
    return CONTRACTS[(address || '').toLowerCase()] || null;
}

/* src/calldata.js */
// Reading a transaction before it exists.
//
// A wallet hands the page a `to` address and a blob of hex. Every other tool
// sends that blob to a server to be simulated. It does not need to be. The
// calls that drain wallets are a short list, their arguments are fixed-width
// words, and the whole thing decodes on your own machine with no network, no
// ABI lookup and no account.
//
// What cannot be read offline is said to be unreadable rather than guessed at.




const selector = (signature) => keccak256(signature).slice(0, 10);

const CALLS = {
    'approve(address,uint256)':                                   'approve',
    'increaseAllowance(address,uint256)':                          'increaseAllowance',
    'setApprovalForAll(address,bool)':                             'setApprovalForAll',
    'transfer(address,uint256)':                                   'transfer',
    'transferFrom(address,address,uint256)':                       'transferFrom',
    'safeTransferFrom(address,address,uint256)':                   'safeTransferFrom721',
    'safeTransferFrom(address,address,uint256,bytes)':             'safeTransferFrom721Data',
    'safeTransferFrom(address,address,uint256,uint256,bytes)':     'safeTransferFrom1155',
    'safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)': 'safeBatchTransferFrom1155',
    'permit(address,address,uint256,uint256,uint8,bytes32,bytes32)': 'permit2612',
    'approve(address,address,uint160,uint48)':                     'permit2Approve',
    'multicall(bytes[])':                                          'multicall',
    'multicall(uint256,bytes[])':                                  'multicallDeadline',
    'transferOwnership(address)':                                  'transferOwnership',
    'withdraw(uint256)':                                           'withdraw',
    'execute(bytes,bytes[])':                                      'universalRouter',
    'execute(bytes,bytes[],uint256)':                              'universalRouterDeadline',
};

const SELECTOR = {};
const BY_SELECTOR = {};
for (const [signature, name] of Object.entries(CALLS)) {
    const id = selector(signature);
    SELECTOR[name] = id;
    BY_SELECTOR[id] = { name, signature };
}

const MAX_UINT256 = (1n << 256n) - 1n;
const MAX_UINT160 = (1n << 160n) - 1n;   // Permit2 says "unlimited" with this
const MAX_UINT48  = (1n << 48n) - 1n;    // and "never expires" with this

// Anything this large is unlimited in practice, however it was written. A
// drainer that asks for one wei less than the maximum is still asking for
// everything you will ever hold.
const EFFECTIVELY_UNLIMITED = 1n << 255n;
const UNLIMITED_160 = (1n << 159n);

function isUnlimited(amount, width = 256) {
    if (width === 160) return amount >= UNLIMITED_160;
    return amount >= EFFECTIVELY_UNLIMITED;
}

// Beyond this a deadline is not a deadline.
const A_LIFETIME = 60 * 60 * 24 * 365 * 5;

// The nth 32-byte argument, counting past the four-byte selector.
function argAt(data, index) {
    const s = strip(data).slice(8);
    const at = index * 64;
    if (s.length < at + 64) return null;
    return BigInt('0x' + s.slice(at, at + 64));
}

function addressAt(data, index) {
    const v = argAt(data, index);
    if (v === null) return null;
    return addressFromTopic('0x' + v.toString(16).padStart(64, '0'));
}

// One transaction request in, one plain object out.
function readCalldata(tx) {
    const data = strip(tx.data || tx.input || '');
    const to = lower(tx.to || '');
    const value = big(tx.value);

    if (!data) {
        return value > 0n
            ? { call: 'send', to, value }
            : { call: 'nothing', to, value };
    }

    if (data.length < 8) return { call: 'unreadable', to, value, why: 'the data is too short to name a function' };

    const id = '0x' + data.slice(0, 8);
    const known = BY_SELECTOR[id];
    if (!known) {
        return { call: 'unknown', to, value, selector: id,
                 why: 'Kliner Guard reads this from the request alone, and this is not one of the calls it knows by shape.' };
    }

    const base = { call: known.name, signature: known.signature, to, value, selector: id };

    switch (known.name) {
        case 'approve': {
            const amount = argAt(tx.data || tx.input, 1);
            return { ...base, call: 'approve', spender: addressAt(tx.data || tx.input, 0),
                     token: to, amount, unlimited: amount !== null && isUnlimited(amount),
                     clearing: amount === 0n };
        }

        case 'increaseAllowance': {
            const amount = argAt(tx.data || tx.input, 1);
            return { ...base, call: 'approve', increase: true, spender: addressAt(tx.data || tx.input, 0),
                     token: to, amount, unlimited: amount !== null && isUnlimited(amount) };
        }

        case 'setApprovalForAll': {
            const on = argAt(tx.data || tx.input, 1) !== 0n;
            return { ...base, call: 'approveAll', spender: addressAt(tx.data || tx.input, 0),
                     token: to, approved: on, clearing: !on };
        }

        case 'transfer':
            return { ...base, call: 'transfer', token: to,
                     recipient: addressAt(tx.data || tx.input, 0), amount: argAt(tx.data || tx.input, 1) };

        case 'transferFrom':
        case 'safeTransferFrom721':
        case 'safeTransferFrom721Data':
            return { ...base, call: 'transferFrom', token: to,
                     owner: addressAt(tx.data || tx.input, 0),
                     recipient: addressAt(tx.data || tx.input, 1),
                     amount: argAt(tx.data || tx.input, 2) };

        case 'safeTransferFrom1155':
            return { ...base, call: 'transferFrom', token: to,
                     owner: addressAt(tx.data || tx.input, 0),
                     recipient: addressAt(tx.data || tx.input, 1),
                     tokenId: argAt(tx.data || tx.input, 2),
                     amount: argAt(tx.data || tx.input, 3) };

        case 'permit2612': {
            const amount = argAt(tx.data || tx.input, 2);
            const deadline = argAt(tx.data || tx.input, 3);
            return { ...base, call: 'permit', token: to,
                     owner: addressAt(tx.data || tx.input, 0),
                     spender: addressAt(tx.data || tx.input, 1),
                     amount, deadline,
                     unlimited: amount !== null && isUnlimited(amount),
                     forever: deadline !== null && isForever(deadline) };
        }

        case 'permit2Approve': {
            const amount = argAt(tx.data || tx.input, 2);
            const expiry = argAt(tx.data || tx.input, 3);
            return { ...base, call: 'approve', through: 'Permit2',
                     token: addressAt(tx.data || tx.input, 0),
                     spender: addressAt(tx.data || tx.input, 1),
                     amount, expiry,
                     unlimited: amount !== null && isUnlimited(amount, 160),
                     forever: expiry !== null && (expiry >= MAX_UINT48 || isForever(expiry)) };
        }

        case 'multicall':
        case 'multicallDeadline':
        case 'universalRouter':
        case 'universalRouterDeadline':
            return { ...base, call: 'bundle',
                     why: 'This packs several actions into one. Kliner Guard will not pretend to know what all of them are.' };

        case 'transferOwnership':
            return { ...base, call: 'transferOwnership', recipient: addressAt(tx.data || tx.input, 0) };

        default:
            return { ...base, call: 'unknown' };
    }
}

function isForever(deadline) {
    if (deadline === null) return false;
    if (deadline >= MAX_UINT48) return true;
    const now = BigInt(Math.floor(Date.now() / 1000));
    return deadline - now > BigInt(A_LIFETIME);
}

/* src/typed.js */
// Reading a signature that never becomes a transaction.
//
// This is where wallets are actually emptied now. An off-chain signature costs
// no gas, asks for no confirmation on any chain, and appears in no history —
// so there is nothing to notice afterwards and nothing to undo. The request is
// a plain JSON object, which means it can be read completely, offline, with
// more certainty than a simulation gives you.



// A typed-data payload is JSON, and JSON writes a uint256 as a DECIMAL string.
// hex.js's big() is for the chain's hex quantities and reads "250000000" as
// 0x250000000, which is how an amount of 250 USDC turns into 9,932 USDC and a
// half-hour deadline turns into the year 3699. Numbers in here go through this.
function quantity(value) {
    if (value === null || value === undefined) return null;
    if (typeof value === 'bigint') return value;
    if (typeof value === 'number') return Number.isFinite(value) ? BigInt(Math.trunc(value)) : null;
    if (typeof value !== 'string') return null;
    const text = value.trim();
    if (/^0x[0-9a-fA-F]+$/.test(text)) return BigInt(text);
    if (/^[0-9]+$/.test(text)) return BigInt(text);
    return null;
}

const q = (value) => quantity(value) ?? 0n;


// Seaport calls the kind of thing being offered by a number.
const ITEM = {
    0: { kind: 'native', what: 'the chain currency' },
    1: { kind: 'erc20', what: 'a token' },
    2: { kind: 'erc721', what: 'an NFT' },
    3: { kind: 'erc1155', what: 'an item' },
    4: { kind: 'erc721-any', what: 'ANY NFT from a collection' },
    5: { kind: 'erc1155-any', what: 'ANY item from a collection' },
};

function parseTypedData(raw) {
    if (raw && typeof raw === 'object') return raw;
    try { return JSON.parse(raw); } catch { return null; }
}

// One eth_signTypedData_v4 payload in, one plain object out.
function readTypedData(raw, context = {}) {
    const data = parseTypedData(raw);
    if (!data || !data.primaryType) {
        return { kind: 'unreadable', offchain: true,
                 why: 'The wallet was handed something that is not a typed-data request Kliner Guard can parse.' };
    }

    const type = data.primaryType;
    const message = data.message || {};
    const domain = data.domain || {};
    const base = {
        offchain: true,
        primaryType: type,
        domain: {
            name: domain.name || null,
            chainId: domain.chainId !== undefined ? Number(q(domain.chainId) ?? 0n) : null,
            verifyingContract: domain.verifyingContract ? lower(domain.verifyingContract) : null,
        },
        wrongChain: false,
    };

    if (context.chainId && base.domain.chainId && Number(context.chainId) !== base.domain.chainId) {
        base.wrongChain = true;
    }

    if (type === 'Permit') return readPermit(base, message);
    if (type === 'PermitSingle') return readPermitSingle(base, message);
    if (type === 'PermitBatch') return readPermitBatch(base, message);
    if (type === 'PermitTransferFrom' || type === 'PermitWitnessTransferFrom') {
        return readPermitTransfer(base, message);
    }
    if (type === 'OrderComponents' || type === 'OrderParameters') {
        return readSeaportOrder(base, message, context);
    }

    return { ...base, kind: 'other',
             fields: Object.keys(message),
             why: 'Kliner Guard has no shape for this one, so it will not tell you it is safe.' };
}

// ERC-2612: a spending allowance, signed instead of sent.
function readPermit(base, m) {
    const amount = q(m.value);
    const deadline = q(m.deadline);
    return {
        ...base,
        kind: 'permit',
        token: base.domain.verifyingContract,
        owner: m.owner ? lower(m.owner) : null,
        spender: m.spender ? lower(m.spender) : null,
        amount,
        deadline,
        unlimited: isUnlimited(amount),
        forever: isForever(deadline),
    };
}

// Permit2: the same idea, one layer further away, and the one drainers prefer
// because the amounts and expiries people sign here are almost always maximal.
function readPermitSingle(base, m) {
    const details = m.details || {};
    const amount = q(details.amount);
    const expiration = q(details.expiration);
    return {
        ...base,
        kind: 'permit',
        through: 'Permit2',
        token: details.token ? lower(details.token) : null,
        spender: m.spender ? lower(m.spender) : null,
        amount,
        deadline: expiration,
        unlimited: isUnlimited(amount, 160),
        forever: expiration >= MAX_UINT48 || isForever(expiration),
    };
}

function readPermitBatch(base, m) {
    const list = Array.isArray(m.details) ? m.details : [];
    const items = list.map((d) => ({
        token: d.token ? lower(d.token) : null,
        amount: q(d.amount),
        expiration: q(d.expiration),
        unlimited: isUnlimited(q(d.amount), 160),
    }));
    return {
        ...base,
        kind: 'permitBatch',
        through: 'Permit2',
        spender: m.spender ? lower(m.spender) : null,
        items,
        unlimited: items.some((i) => i.unlimited),
        forever: items.some((i) => i.expiration >= MAX_UINT48 || isForever(i.expiration)),
    };
}

function readPermitTransfer(base, m) {
    const permitted = m.permitted || {};
    return {
        ...base,
        kind: 'permitTransfer',
        through: 'Permit2',
        token: permitted.token ? lower(permitted.token) : null,
        amount: q(permitted.amount),
        spender: m.spender ? lower(m.spender) : null,
        deadline: q(m.deadline),
        unlimited: isUnlimited(q(permitted.amount), 160),
    };
}

// A marketplace order. You sign what you give and what you get; the other side
// submits it. If what you get is nothing, the signature is the whole theft.
function readSeaportOrder(base, m, context) {
    const you = lower(context.account || m.offerer || '');
    const offer = (m.offer || []).map(readItem);
    const consideration = (m.consideration || []).map(readItem);

    const yours = consideration.filter((c) => c.recipient && lower(c.recipient) === you);
    const backToYou = yours.reduce((sum, c) => sum + c.amount, 0n);
    const elsewhere = consideration.filter((c) => !c.recipient || lower(c.recipient) !== you);

    return {
        ...base,
        kind: 'order',
        marketplace: base.domain.name || 'a marketplace',
        offerer: m.offerer ? lower(m.offerer) : null,
        youAreTheSeller: !!you && lower(m.offerer || '') === you,
        offer,
        consideration,
        backToYou,
        backToYouToken: yours.length ? yours[0].token : null,
        goesElsewhere: elsewhere,
        forNothing: backToYou === 0n,
        wildcard: offer.some((o) => o.kind === 'erc721-any' || o.kind === 'erc1155-any'),
        endTime: q(m.endTime),
        forever: isForever(q(m.endTime)),
    };
}

function readItem(item) {
    const meta = ITEM[Number(item.itemType)] || { kind: 'unknown', what: 'something' };
    const start = q(item.startAmount);
    const end = q(item.endAmount);
    return {
        kind: meta.kind,
        what: meta.what,
        token: item.token ? lower(item.token) : null,
        tokenId: item.identifierOrCriteria !== undefined ? q(item.identifierOrCriteria) : null,
        amount: start > end ? start : end,
        recipient: item.recipient ? lower(item.recipient) : null,
    };
}

// personal_sign: a plain message. It cannot move a token by itself, but the
// text is worth reading, and a hex blob dressed up as a message is not a
// message.
function readMessage(raw) {
    const text = decodeMessage(raw);
    const looksStructured = /^[\s]*[{[]/.test(text || '');
    return {
        kind: 'message',
        offchain: true,
        text,
        looksStructured,
        unreadable: text === null,
    };
}

function decodeMessage(raw) {
    if (typeof raw !== 'string') return null;
    if (!/^0x[0-9a-fA-F]*$/.test(raw)) return raw;
    const hex = raw.slice(2);
    if (hex.length % 2 !== 0) return raw;
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
    try {
        return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    } catch {
        return null;
    }
}

/* src/request.js */
// The front door. A wallet request goes in; a reading comes out.
//
// Nothing in here touches the network, and nothing in here can alter the
// request. Kliner Guard reads a copy and hands the original on untouched.




const WATCHED = [
    'eth_sendTransaction',
    'eth_signTypedData',
    'eth_signTypedData_v3',
    'eth_signTypedData_v4',
    'personal_sign',
    'eth_sign',
];

function shouldRead(method) {
    return WATCHED.indexOf(method) !== -1;
}

function read(request, context = {}) {
    const method = request && request.method;
    const params = (request && request.params) || [];

    switch (method) {
        case 'eth_sendTransaction':
            return { method, ...readCalldata(params[0] || {}) };

        case 'eth_signTypedData':
        case 'eth_signTypedData_v3':
        case 'eth_signTypedData_v4': {
            // The address comes first and the payload second, except in the
            // oldest form where it is the other way round.
            const payload = typeof params[1] === 'undefined' ? params[0] : params[1];
            const account = context.account || (typeof params[0] === 'string' ? params[0] : null);
            return { method, ...readTypedData(payload, { ...context, account }) };
        }

        case 'personal_sign':
            return { method, ...readMessage(typeof params[0] === 'string' ? params[0] : '') };

        case 'eth_sign':
            // The wallet is asked to sign raw bytes it cannot explain. There is
            // no honest reason for a site to ask for this any more.
            return { method, kind: 'blind', offchain: true, payload: params[1] };

        default:
            return { method, kind: 'ignored' };
    }
}

/* src/warn.js */
// One sentence, and what is wrong with it.
//
// The levels are stop, warn, note and clear. Nothing here says "safe": Kliner
// Guard can say what a request does, and it can say when it cannot read one,
// but it is not in a position to promise you an outcome, and a tool that
// promises one is lying to you.






function nameOf(address, fallback) {
    if (!address) return fallback || 'an address Kliner Guard was not given';
    return contractName(address) || short(address);
}

function tokenName(address) {
    const known = tokenFor(address);
    if (known) return known.symbol;
    return address ? short(address) : 'a token';
}

const NO_TOKEN = '0x0000000000000000000000000000000000000000';

function amountText(amount, token, context) {
    if (amount === null || amount === undefined) return 'an amount that did not decode';
    // No token address means the chain's own currency, which is always 18 places.
    if (!token || token === NO_TOKEN) {
        return format(amount, 18, { significant: 6 }) + ' ' + currencyFor(context && context.chainId);
    }
    const known = tokenFor(token);
    if (known) return format(amount, known.decimals, { significant: 6 }) + ' ' + known.symbol;
    // Without the token's decimals there is no honest way to place the point.
    return format(amount, 0) + ' units of ' + tokenName(token) + ' (raw, Kliner Guard is offline and cannot ask the token how it counts)';
}

function when(deadline) {
    if (deadline === null || deadline === undefined) return null;
    if (deadline >= MAX_UINT48) return 'never';
    const ms = Number(deadline) * 1000;
    if (!Number.isFinite(ms) || ms <= 0) return null;
    const date = new Date(ms);
    if (Number.isNaN(date.getTime())) return null;
    return date.toISOString().slice(0, 10);
}

const GASLESS = 'This is a signature, not a transaction. It costs no gas, needs no confirmation on any chain, and will not appear in your history — so there will be nothing to notice afterwards.';

function explain(reading, context = {}) {
    const risks = [];
    const facts = [];
    let title = '';
    let level = 'note';

    const stop = (code, t, d) => risks.push({ level: 'stop', code, title: t, detail: d });
    const warn = (code, t, d) => risks.push({ level: 'warn', code, title: t, detail: d });
    const note = (code, t, d) => risks.push({ level: 'note', code, title: t, detail: d });

    if (reading.offchain) note('offchain', 'Nothing will show this happened', GASLESS);
    if (reading.wrongChain) {
        warn('wrong-chain', 'This was built for a different chain',
            'The request names chain ' + reading.domain.chainId + ' while your wallet is on ' + context.chainId +
            '. A signature made for one chain is sometimes replayable on another.');
    }

    switch (reading.kind || reading.call) {

        case 'approve': {
            const token = tokenName(reading.token);
            const who = nameOf(reading.spender);
            if (reading.clearing) {
                title = 'This takes back ' + who + "'s permission to spend your " + token + '.';
                level = 'clear';
                break;
            }
            if (reading.unlimited) {
                title = 'This lets ' + who + ' spend your ' + token + '. Not an amount — all of it.';
                stop('unlimited', 'An allowance with no limit',
                    who + ' will be able to move your ' + token + ' at any moment from now on, including ' +
                    'tokens you do not own yet. It stays until you revoke it.');
            } else {
                title = 'This lets ' + who + ' spend ' + amountText(reading.amount, reading.token, context) + ' of yours.';
                note('bounded', 'The amount is bounded', 'It can spend up to that and no more.');
            }
            if (reading.through === 'Permit2') {
                facts.push('Through Permit2, which holds the allowance on behalf of many apps.');
            }
            if (reading.forever) {
                warn('forever', 'It does not expire', 'The expiry on this is set so far out that it never arrives.');
            }
            if (reading.increase) {
                facts.push('This adds to an allowance you already gave, rather than replacing it.');
            }
            break;
        }

        case 'approveAll': {
            const who = nameOf(reading.spender);
            if (reading.clearing) {
                title = 'This takes back ' + who + "'s access to that collection.";
                level = 'clear';
                break;
            }
            title = 'This lets ' + who + ' move every item you own in that collection.';
            stop('approve-all', 'A whole collection, not one item',
                'It covers what you own now and anything you buy into that collection later, until you revoke it. ' +
                'A marketplace needs this. A mint page does not.');
            break;
        }

        case 'permit': {
            const token = tokenName(reading.token);
            const who = nameOf(reading.spender);
            const until = when(reading.deadline);
            title = reading.unlimited
                ? 'You are signing away every ' + token + ' you hold to ' + who + '.'
                : 'You are signing permission for ' + who + ' to spend ' + amountText(reading.amount, reading.token, context) + '.';
            if (reading.unlimited) {
                stop('unlimited', 'An allowance with no limit, signed rather than sent',
                    'There is no transaction to see and no gas to pay, and ' + who +
                    ' can move your ' + token + ' whenever it likes afterwards.');
            }
            if (reading.forever) {
                stop('forever', 'And it does not expire',
                    until === 'never' ? 'The expiry is set to the maximum the format allows.'
                                      : 'It runs until ' + until + ', which is not a deadline.');
            } else if (until) {
                facts.push('Runs until ' + until + '.');
            }
            if (reading.through) facts.push('Through ' + reading.through + '.');
            break;
        }

        case 'permitBatch': {
            const who = nameOf(reading.spender);
            title = 'You are signing permission for ' + who + ' to spend ' + reading.items.length + ' different tokens of yours.';
            if (reading.unlimited) {
                stop('unlimited', 'At least one of them has no limit',
                    'A batch permit is one signature that opens several doors at once. ' +
                    reading.items.filter((i) => i.unlimited).length + ' of these ' + reading.items.length + ' have no ceiling.');
            }
            if (reading.forever) stop('forever', 'And they do not expire', 'The expiry is set past any horizon that matters.');
            for (const item of reading.items) {
                facts.push(tokenName(item.token) + ' — ' + (item.unlimited ? 'no limit' : amountText(item.amount, item.token, context)));
            }
            break;
        }

        case 'permitTransfer': {
            const who = nameOf(reading.spender);
            title = 'You are signing permission for ' + who + ' to take ' + amountText(reading.amount, reading.token, context) + ' from you.';
            if (reading.unlimited) {
                stop('unlimited', 'With no ceiling on the amount', who + ' decides how much actually moves.');
            }
            break;
        }

        case 'order': {
            const giving = reading.offer.map((o) =>
                o.kind === 'erc721-any' || o.kind === 'erc1155-any'
                    ? 'any item you own from ' + tokenName(o.token)
                    : o.kind === 'erc20' || o.kind === 'native'
                        ? amountText(o.amount, o.token, context)
                        : tokenName(o.token) + ' #' + o.tokenId
            );

            if (reading.forNothing) {
                title = 'You are signing away ' + list(giving) + ' and receiving nothing for it.';
                stop('for-nothing', 'Nothing comes back to you',
                    'This is an order on ' + reading.marketplace + ' where everything leaves your side and the ' +
                    'consideration to you is zero. Whoever holds this signature can take it whenever they like.');
            } else {
                title = 'You are offering ' + list(giving) + ' for ' + amountText(reading.backToYou, reading.backToYouToken, context) + '.';
            }

            if (reading.wildcard) {
                stop('wildcard', 'It does not name which item',
                    'The order is written against a whole collection rather than one token id, so it applies to ' +
                    'whatever you hold from it — now or later.');
            }
            for (const other of reading.goesElsewhere) {
                facts.push('Also sends ' + amountText(other.amount, other.token, context) + ' to ' + nameOf(other.recipient) + '.');
            }
            if (reading.forever) warn('forever', 'The order does not expire', 'It can be filled at any point in the future.');
            break;
        }

        case 'send':
            title = 'You are sending ' + amountText(reading.value, null, context) + ' to ' + nameOf(reading.to) + '.';
            break;

        case 'transfer':
            title = 'You are sending ' + amountText(reading.amount, reading.token, context) + ' to ' + nameOf(reading.recipient) + '.';
            break;

        case 'transferFrom':
            title = 'This moves a token out of ' + nameOf(reading.owner) + ' and into ' + nameOf(reading.recipient) + '.';
            if (context.account && reading.owner && lower(reading.owner) === lower(context.account)) {
                warn('pull', 'It is taking from you', 'You are the wallet it is being pulled from.');
            }
            break;

        case 'transferOwnership':
            title = 'This hands ownership of that contract to ' + nameOf(reading.recipient) + '.';
            stop('ownership', 'Ownership is not recoverable', 'If that contract is yours, this gives it away for good.');
            break;

        case 'bundle':
            title = 'This packs several actions into one call.';
            warn('bundle', 'Kliner Guard will not guess what is inside',
                'Bundled calls are normal for routers and also how several actions get hidden behind one confirmation. ' +
                'It can be read only by simulating it, which would mean sending it to somebody else’s server.');
            break;

        case 'blind':
            title = 'The site is asking your wallet to sign raw data it cannot explain.';
            stop('eth-sign', 'This is a blind signature',
                'eth_sign hands over a signature on bytes nobody shows you, and it can be a transaction. ' +
                'Honest sites stopped asking for this years ago.');
            break;

        case 'message':
            if (reading.unreadable) {
                title = 'A message that is not text.';
                warn('not-text', 'It is dressed up as a message', 'A plain-text signature request should be plain text.');
            } else {
                title = 'A plain message, signed to prove the wallet is yours.';
                facts.push(reading.text);
                if (reading.looksStructured) {
                    warn('structured', 'It is not really prose',
                        'This is structured data being signed through the plain-message door, which is a way to get around the checks a typed-data request would face.');
                } else {
                    level = 'clear';
                    note('cannot-move', 'On its own it moves nothing',
                        'A signed message cannot transfer a token by itself. Read it anyway: it is also how a site gets you to agree to something.');
                }
            }
            break;

        case 'nothing':
            title = 'An empty call to ' + nameOf(reading.to) + '.';
            level = 'clear';
            break;

        case 'unknown':
        case 'unreadable':
        case 'other':
            title = 'Kliner Guard cannot read this one.';
            warn('unreadable', 'Not readable is not the same as safe',
                (reading.why || '') + ' Everything Kliner Guard knows, it knows from the request itself. ' +
                'When that is not enough, it says so instead of guessing.');
            break;

        default:
            title = 'Kliner Guard cannot read this one.';
            warn('unreadable', 'Not readable is not the same as safe', 'No shape matched this request.');
    }

    const worst = risks.some((r) => r.level === 'stop') ? 'stop'
                : risks.some((r) => r.level === 'warn') ? 'warn'
                : level;

    return { title, level: worst, risks, facts, reading };
}

function list(items) {
    if (!items.length) return 'nothing';
    if (items.length === 1) return items[0];
    if (items.length === 2) return items[0] + ' and ' + items[1];
    return items.slice(0, -1).join(', ') + ' and ' + items[items.length - 1];
}

/* src/overlay.js */
// Kliner Guard — the half that shows you the sentence.
//
// It lives in the extension's own world, so the page cannot read it, style it,
// or click its buttons. It renders into a closed shadow root for the same
// reason. It has no network access and asks for no permissions.

(function () {
    'use strict';

    var host = null;
    var root = null;
    var queue = [];
    var showing = false;

    window.addEventListener('message', function (event) {
        if (event.source !== window) return;
        var data = event.data;
        if (!data || data.channel !== 'kliner-guard' || data.direction !== 'request') return;
        queue.push(data);
        if (!showing) next();
    });

    function answer(id, allow) {
        window.postMessage({ channel: 'kliner-guard', direction: 'verdict', id: id, allow: allow }, '*');
    }

    function next() {
        var item = queue.shift();
        if (!item) { showing = false; hide(); return; }
        showing = true;

        var context = { account: item.account, chainId: item.chainId };
        var out;
        try {
            out = explain(read(item.request, context), context);
        } catch (error) {
            out = {
                title: 'Kliner Guard could not read this one.',
                level: 'warn',
                risks: [{ level: 'warn', code: 'crash', title: 'The reader failed on this request',
                          detail: 'That is a bug in Kliner Guard, not a verdict on the request. ' +
                                  'It is telling you rather than quietly letting it through.' }],
                facts: [],
                reading: {}
            };
        }

        render(out, item, function (allow) {
            answer(item.id, allow);
            next();
        });
    }

    /* ---------- the panel ---------- */

    // The id is different on every page load, and the panel puts itself back if
    // the page tries to remove it. A page that can delete the warning is a page
    // that can hide what it is asking for.
    var HOST_ID = 'kg-' + Math.random().toString(36).slice(2, 10);

    function build() {
        host = document.createElement('div');
        host.id = HOST_ID;
        host.style.cssText = 'all:initial;position:fixed;inset:0;z-index:2147483647;display:none';
        root = host.attachShadow({ mode: 'closed' });
        root.innerHTML =
            '<style>' + CSS + '</style>' +
            '<div class="veil"><div class="panel" role="dialog" aria-modal="true" aria-labelledby="kg-title">' +
            '<div class="top"><span class="mark">Kliner Guard</span><span class="lvl" id="kg-level"></span></div>' +
            '<p class="title" id="kg-title"></p>' +
            '<div class="risks" id="kg-risks"></div>' +
            '<div class="facts" id="kg-facts"></div>' +
            '<details class="raw"><summary>Show me exactly what the site sent</summary><pre id="kg-raw"></pre></details>' +
            '<div class="row"><button class="stop" id="kg-stop">Stop it</button>' +
            '<button class="go" id="kg-go">Sign it anyway</button></div>' +
            '<p class="foot">Kliner Guard read this on your machine. It sent nothing anywhere and cannot sign anything.</p>' +
            '</div></div>';
        (document.documentElement || document.body).appendChild(host);

        try {
            new MutationObserver(function () {
                if (showing && host && !host.isConnected) {
                    (document.documentElement || document.body).appendChild(host);
                }
            }).observe(document.documentElement, { childList: true, subtree: false });
        } catch (e) { /* an old engine still gets the panel, just not the guard on it */ }
    }

    function hide() { if (host) host.style.display = 'none'; }

    function render(out, item, done) {
        if (!host) build();
        host.style.display = 'block';

        var level = root.getElementById('kg-level');
        level.textContent = out.level === 'stop' ? 'Stop' :
                            out.level === 'warn' ? 'Careful' :
                            out.level === 'clear' ? 'Ordinary' : 'Read it';
        level.className = 'lvl lvl-' + out.level;

        root.getElementById('kg-title').textContent = out.title;

        var risks = root.getElementById('kg-risks');
        risks.textContent = '';
        out.risks.forEach(function (risk) {
            var box = document.createElement('div');
            box.className = 'risk lvl-' + risk.level;
            var head = document.createElement('div');
            head.className = 'rt';
            head.textContent = risk.title;
            var body = document.createElement('div');
            body.className = 'rd';
            body.textContent = risk.detail;
            box.appendChild(head); box.appendChild(body);
            risks.appendChild(box);
        });

        var facts = root.getElementById('kg-facts');
        facts.textContent = '';
        out.facts.forEach(function (fact) {
            var line = document.createElement('div');
            line.className = 'fact';
            line.textContent = fact;
            facts.appendChild(line);
        });

        try {
            root.getElementById('kg-raw').textContent = JSON.stringify(item.request, null, 2);
        } catch (e) {
            root.getElementById('kg-raw').textContent = 'unprintable';
        }

        var stop = root.getElementById('kg-stop');
        var go = root.getElementById('kg-go');
        go.textContent = out.level === 'stop' ? 'Sign it anyway' : 'Sign it';
        go.className = 'go' + (out.level === 'stop' ? ' quiet' : '');

        stop.onclick = function () { done(false); };
        go.onclick = function () { done(true); };

        // The safe choice is the one your finger is already on.
        setTimeout(function () { try { stop.focus(); } catch (e) {} }, 0);
    }

    var CSS = [
        ':host{all:initial}',
        '*{box-sizing:border-box;font-family:ui-sans-serif,-apple-system,"Segoe UI",Roboto,Arial,sans-serif}',
        '.veil{position:fixed;inset:0;background:rgba(10,10,9,.55);display:flex;align-items:center;',
        '  justify-content:center;padding:20px;overflow:auto}',
        '.panel{background:#fdfdfc;color:#161614;width:min(520px,100%);border-radius:3px;',
        '  padding:22px 24px 18px;box-shadow:0 24px 70px rgba(0,0,0,.34);font-size:14px;line-height:1.55}',
        '@media (prefers-color-scheme:dark){.panel{background:#141413;color:#f0f0ec}}',
        '.top{display:flex;justify-content:space-between;align-items:baseline;',
        '  border-bottom:1px solid rgba(128,128,120,.28);padding-bottom:10px}',
        '.mark{font-size:11px;letter-spacing:.18em;text-transform:uppercase;font-weight:600}',
        '.lvl{font-size:11px;letter-spacing:.14em;text-transform:uppercase;opacity:.55}',
        '.lvl.lvl-stop{opacity:1;font-weight:600;box-shadow:inset 0 -2px 0 currentColor}',
        '.title{font-size:19px;line-height:1.32;margin:18px 0 0;text-wrap:balance}',
        '.risk{margin-top:14px;padding-left:12px;box-shadow:inset 2px 0 0 currentColor}',
        '.risk.lvl-note{box-shadow:none;padding-left:0;opacity:.72}',
        '.rt{font-weight:600;font-size:13px}',
        '.risk.lvl-note .rt{font-weight:400}',
        '.rd{font-size:13px;opacity:.75;margin-top:2px}',
        '.facts{margin-top:12px;font-size:13px;opacity:.7}',
        '.fact{padding-block:3px;border-bottom:1px solid rgba(128,128,120,.18)}',
        '.raw{margin-top:16px;font-size:12px;opacity:.6}',
        '.raw summary{cursor:pointer}',
        '.raw pre{max-height:190px;overflow:auto;font-family:ui-monospace,Menlo,Consolas,monospace;',
        '  font-size:11px;line-height:1.5;white-space:pre-wrap;word-break:break-all;margin-top:8px}',
        '.row{display:flex;gap:10px;margin-top:20px}',
        'button{appearance:none;font:inherit;font-size:14px;padding:11px 16px;border-radius:2px;cursor:pointer;flex:1 1 0}',
        '.stop{background:#161614;color:#fdfdfc;border:1px solid #161614}',
        '@media (prefers-color-scheme:dark){.stop{background:#f0f0ec;color:#141413;border-color:#f0f0ec}}',
        '.go{background:none;color:inherit;border:1px solid rgba(128,128,120,.5)}',
        '.go.quiet{opacity:.55;font-size:13px;flex:0 0 auto}',
        '.foot{font-size:11px;opacity:.5;margin:14px 0 0}'
    ].join('');
})();
})();

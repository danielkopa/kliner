// Reading a signature that never becomes a transaction.
//
// This is where wallets are actually emptied now. An off-chain signature costs
// no gas, asks for no confirmation on any chain, and appears in no history —
// so there is nothing to notice afterwards and nothing to undo. The request is
// a plain JSON object, which means it can be read completely, offline, with
// more certainty than a simulation gives you.

import { big, lower, isZero, checksum } from './hex.js';

// A typed-data payload is JSON, and JSON writes a uint256 as a DECIMAL string.
// hex.js's big() is for the chain's hex quantities and reads "250000000" as
// 0x250000000, which is how an amount of 250 USDC turns into 9,932 USDC and a
// half-hour deadline turns into the year 3699. Numbers in here go through this.
export function quantity(value) {
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
import { isForever, MAX_UINT48, isUnlimited } from './calldata.js';

// Seaport calls the kind of thing being offered by a number.
const ITEM = {
    0: { kind: 'native', what: 'the chain currency' },
    1: { kind: 'erc20', what: 'a token' },
    2: { kind: 'erc721', what: 'an NFT' },
    3: { kind: 'erc1155', what: 'an item' },
    4: { kind: 'erc721-any', what: 'ANY NFT from a collection' },
    5: { kind: 'erc1155-any', what: 'ANY item from a collection' },
};

export function parseTypedData(raw) {
    if (raw && typeof raw === 'object') return raw;
    try { return JSON.parse(raw); } catch { return null; }
}

// One eth_signTypedData_v4 payload in, one plain object out.
export function readTypedData(raw, context = {}) {
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
export function readMessage(raw) {
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

export { checksum, isZero };

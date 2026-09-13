// What a token calls itself.
//
// Read off the contract, not off a list someone has to maintain. Old tokens
// answer symbol() with a fixed 32-byte word instead of a string, so both
// shapes are handled; a token that answers neither still gets read, it just
// gets called by its address.

import { keccak256 } from './keccak.js';
import { strip, lower } from './hex.js';

const selector = (signature) => keccak256(signature).slice(0, 10);

export const SELECTOR = {
    name: selector('name()'),
    symbol: selector('symbol()'),
    decimals: selector('decimals()'),
    balanceOf: selector('balanceOf(address)'),
    allowance: selector('allowance(address,address)'),
    tokenURI: selector('tokenURI(uint256)'),
    approve: selector('approve(address,uint256)'),
    setApprovalForAll: selector('setApprovalForAll(address,bool)'),
};

const TRAILING_ZERO_BYTES = /(?:00)+$/;
const PRINTABLE = /^[\x20-\x7e]+$/;
const PADDING = new RegExp(String.fromCharCode(0), 'g');

// A string return is offset, length, bytes. A bytes32 return is 32 bytes with
// the text at the front and zero padding after it.
export function readString(hex) {
    const s = strip(hex);
    if (!s) return null;
    if (s.length === 64) {
        const text = decode(s.replace(TRAILING_ZERO_BYTES, ''));
        return text && PRINTABLE.test(text) ? text : null;
    }
    if (s.length < 128) return null;
    const length = Number(BigInt('0x' + s.slice(64, 128)));
    if (!Number.isFinite(length) || length === 0 || length > 256) return null;
    return decode(s.slice(128, 128 + length * 2));
}

function decode(hex) {
    if (!hex) return null;
    const bytes = new Uint8Array(Math.floor(hex.length / 2));
    for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
    try {
        const text = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
        return text.replace(PADDING, '').trim() || null;
    } catch {
        return null;
    }
}

export function readNumber(hex) {
    const s = strip(hex);
    if (!s) return null;
    const v = BigInt('0x' + s);
    return v <= 255n ? Number(v) : null;
}

// One batched round trip for as many tokens as you like.
export async function loadTokens(rpc, addresses, cache = new Map()) {
    const wanted = [...new Set(addresses.map(lower))]
        .filter((a) => a && a !== 'native' && !cache.has(a));
    if (!wanted.length) return cache;

    const calls = [];
    for (const address of wanted) {
        calls.push({ method: 'eth_call', params: [{ to: address, data: SELECTOR.symbol }, 'latest'] });
        calls.push({ method: 'eth_call', params: [{ to: address, data: SELECTOR.decimals }, 'latest'] });
        calls.push({ method: 'eth_call', params: [{ to: address, data: SELECTOR.name }, 'latest'] });
    }

    const answers = await rpc.batch(calls);
    wanted.forEach((address, i) => {
        const [symbol, decimals, name] = answers.slice(i * 3, i * 3 + 3);
        cache.set(address, {
            address,
            symbol: symbol && !symbol.error ? readString(symbol.result) : null,
            decimals: decimals && !decimals.error ? readNumber(decimals.result) : null,
            name: name && !name.error ? readString(name.result) : null,
        });
    });

    return cache;
}

// Turn the cache into the plain object the classifier and the words expect.
export function asMeta(cache) {
    const tokens = {};
    for (const [address, info] of cache) {
        if (!info) continue;
        tokens[address] = {
            symbol: info.symbol || undefined,
            decimals: info.decimals ?? undefined,
            name: info.name || info.symbol || undefined,
        };
    }
    return tokens;
}

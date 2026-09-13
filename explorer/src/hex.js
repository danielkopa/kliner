// Small helpers for the shapes an RPC node hands back: 0x-strings.

import { keccak256Bytes } from './keccak.js';

export const ZERO = '0x0000000000000000000000000000000000000000';
export const DEAD = '0x000000000000000000000000000000000000dead';

export function strip(hex) {
    return (hex || '').toLowerCase().replace(/^0x/, '');
}

// Any 0x-quantity to BigInt. Missing or malformed reads as 0n, because a
// receipt with a field we did not expect should not take the page down.
export function big(hex) {
    if (typeof hex === 'bigint') return hex;
    if (typeof hex === 'number') return BigInt(hex);
    const s = strip(hex);
    if (!s || /[^0-9a-f]/.test(s)) return 0n;
    return BigInt('0x' + s);
}

// Addresses arrive in topics left-padded to 32 bytes.
export function addressFromTopic(topic) {
    const s = strip(topic);
    return '0x' + s.slice(-40).padStart(40, '0');
}

export function lower(address) {
    return (address || '').toLowerCase();
}

export function sameAddress(a, b) {
    return !!a && !!b && a.toLowerCase() === b.toLowerCase();
}

export function isZero(address) {
    return sameAddress(address, ZERO);
}

// Read the Nth 32-byte word out of a log's data field.
export function word(data, index) {
    const s = strip(data);
    const at = index * 64;
    if (s.length < at + 64) return 0n;
    return BigInt('0x' + s.slice(at, at + 64));
}

export function words(data) {
    const s = strip(data);
    const out = [];
    for (let i = 0; i + 64 <= s.length; i += 64) out.push(BigInt('0x' + s.slice(i, i + 64)));
    return out;
}

// EIP-55: the mixed-case form that catches a mistyped address.
export function checksum(address) {
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

export function isAddress(value) {
    return typeof value === 'string' && /^0x[0-9a-fA-F]{40}$/.test(value);
}

export function short(address, head = 6, tail = 4) {
    const a = checksum(address);
    return a.slice(0, 2 + head) + '…' + a.slice(-tail);
}

// Reading a transaction before it exists.
//
// A wallet hands the page a `to` address and a blob of hex. Every other tool
// sends that blob to a server to be simulated. It does not need to be. The
// calls that drain wallets are a short list, their arguments are fixed-width
// words, and the whole thing decodes on your own machine with no network, no
// ABI lookup and no account.
//
// What cannot be read offline is said to be unreadable rather than guessed at.

import { keccak256 } from './keccak.js';
import { big, strip, lower, addressFromTopic, isZero, checksum } from './hex.js';

const selector = (signature) => keccak256(signature).slice(0, 10);

export const CALLS = {
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

export const SELECTOR = {};
export const BY_SELECTOR = {};
for (const [signature, name] of Object.entries(CALLS)) {
    const id = selector(signature);
    SELECTOR[name] = id;
    BY_SELECTOR[id] = { name, signature };
}

export const MAX_UINT256 = (1n << 256n) - 1n;
export const MAX_UINT160 = (1n << 160n) - 1n;   // Permit2 says "unlimited" with this
export const MAX_UINT48  = (1n << 48n) - 1n;    // and "never expires" with this

// Anything this large is unlimited in practice, however it was written. A
// drainer that asks for one wei less than the maximum is still asking for
// everything you will ever hold.
export const EFFECTIVELY_UNLIMITED = 1n << 255n;
export const UNLIMITED_160 = (1n << 159n);

export function isUnlimited(amount, width = 256) {
    if (width === 160) return amount >= UNLIMITED_160;
    return amount >= EFFECTIVELY_UNLIMITED;
}

// Beyond this a deadline is not a deadline.
export const A_LIFETIME = 60 * 60 * 24 * 365 * 5;

// The nth 32-byte argument, counting past the four-byte selector.
export function argAt(data, index) {
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
export function readCalldata(tx) {
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

export function isForever(deadline) {
    if (deadline === null) return false;
    if (deadline >= MAX_UINT48) return true;
    const now = BigInt(Math.floor(Date.now() / 1000));
    return deadline - now > BigInt(A_LIFETIME);
}

export { checksum, isZero };

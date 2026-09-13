// The five events that carry almost every movement of value on an EVM chain.
//
// We do not decode calldata and we do not know any protocol by name. A swap
// router, a lending pool and a game all emit the same Transfer log, and that
// log is the only thing we read. The topic hashes below are computed from the
// signatures at load time rather than pasted in, so a typo cannot survive.

import { keccak256 } from './keccak.js';
import { addressFromTopic, big, word, words, strip } from './hex.js';

export const SIGNATURES = {
    transfer:        'Transfer(address,address,uint256)',
    approval:        'Approval(address,address,uint256)',
    approvalForAll:  'ApprovalForAll(address,address,bool)',
    transferSingle:  'TransferSingle(address,address,address,uint256,uint256)',
    transferBatch:   'TransferBatch(address,address,address,uint256[],uint256[])',
    deposit:         'Deposit(address,uint256)',    // WETH-style wrap
    withdrawal:      'Withdrawal(address,uint256)', // WETH-style unwrap
};

export const TOPIC = Object.fromEntries(
    Object.entries(SIGNATURES).map(([name, sig]) => [name, keccak256(sig)])
);

export const BY_TOPIC = Object.fromEntries(
    Object.entries(TOPIC).map(([name, topic]) => [topic, name])
);

// The amount an "unlimited" approval usually asks for.
export const MAX_UINT256 = (1n << 256n) - 1n;

// Anything this large is unlimited in practice, however it was written.
export const EFFECTIVELY_UNLIMITED = (1n << 255n);

// One log in, one plain object out, or null when it is not an event we read.
//
// The shape of Transfer is what tells ERC-20 apart from ERC-721: the token id
// of an NFT is indexed and so becomes a fourth topic, while an amount stays in
// the data field. No registry, no guessing.
export function decodeLog(log) {
    const topics = log.topics || [];
    if (!topics.length) return null;

    const name = BY_TOPIC[(topics[0] || '').toLowerCase()];
    if (!name) return null;

    const token = (log.address || '').toLowerCase();

    switch (name) {
        case 'transfer': {
            if (topics.length === 4) {
                return {
                    event: 'transfer',
                    standard: 'erc721',
                    token,
                    from: addressFromTopic(topics[1]),
                    to: addressFromTopic(topics[2]),
                    tokenId: big(topics[3]),
                    amount: 1n,
                };
            }
            if (topics.length === 3) {
                return {
                    event: 'transfer',
                    standard: 'erc20',
                    token,
                    from: addressFromTopic(topics[1]),
                    to: addressFromTopic(topics[2]),
                    amount: word(log.data, 0),
                };
            }
            return null; // some other Transfer; not ours to read
        }

        case 'approval': {
            if (topics.length === 4) {
                return {
                    event: 'approval',
                    standard: 'erc721',
                    token,
                    owner: addressFromTopic(topics[1]),
                    spender: addressFromTopic(topics[2]),
                    tokenId: big(topics[3]),
                };
            }
            return {
                event: 'approval',
                standard: 'erc20',
                token,
                owner: addressFromTopic(topics[1]),
                spender: addressFromTopic(topics[2]),
                amount: word(log.data, 0),
            };
        }

        case 'approvalForAll':
            return {
                event: 'approvalForAll',
                standard: 'erc721',
                token,
                owner: addressFromTopic(topics[1]),
                spender: addressFromTopic(topics[2]),
                approved: word(log.data, 0) !== 0n,
            };

        case 'transferSingle':
            return {
                event: 'transfer',
                standard: 'erc1155',
                token,
                operator: addressFromTopic(topics[1]),
                from: addressFromTopic(topics[2]),
                to: addressFromTopic(topics[3]),
                tokenId: word(log.data, 0),
                amount: word(log.data, 1),
            };

        case 'transferBatch': {
            // data is two dynamic arrays: offset, offset, then len+items twice.
            const w = words(log.data);
            const ids = readArray(w, 0);
            const amounts = readArray(w, 1);
            const from = addressFromTopic(topics[2]);
            const to = addressFromTopic(topics[3]);
            return {
                event: 'transferBatch',
                standard: 'erc1155',
                token,
                operator: addressFromTopic(topics[1]),
                from,
                to,
                items: ids.map((id, i) => ({ tokenId: id, amount: amounts[i] ?? 0n })),
            };
        }

        case 'deposit':
            // WETH9 emits no Transfer when you wrap, so this is the only trace.
            return {
                event: 'wrap',
                standard: 'erc20',
                token,
                to: addressFromTopic(topics[1]),
                amount: topics.length > 2 ? big(topics[2]) : word(log.data, 0),
            };

        case 'withdrawal':
            return {
                event: 'unwrap',
                standard: 'erc20',
                token,
                from: addressFromTopic(topics[1]),
                amount: topics.length > 2 ? big(topics[2]) : word(log.data, 0),
            };

        default:
            return null;
    }
}

function readArray(w, slot) {
    const offset = w[slot];
    if (offset === undefined) return [];
    const at = Number(offset) / 32;
    const length = Number(w[at] ?? 0n);
    return w.slice(at + 1, at + 1 + length);
}

// Some contracts named Deposit or Withdrawal are not wrapped native currency.
// Only trust those two events when they come from the chain's wrapped token.
export function isWrappedNative(address, wrapped) {
    return !!wrapped && (address || '').toLowerCase() === wrapped.toLowerCase();
}

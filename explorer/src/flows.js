// What moved, for one address.
//
// This is the whole trick. Instead of asking "which protocol is this and what
// does its calldata mean", we ask the only question a person actually has:
// what left my wallet and what arrived. Every log is read the same way, the
// sums are netted per token, and the leftovers are the answer.

import { decodeLog, isWrappedNative, EFFECTIVELY_UNLIMITED } from './abi.js';
import { big, lower, sameAddress, isZero, ZERO, DEAD } from './hex.js';

const keyFor = (m) =>
    m.standard === 'erc721' || m.standard === 'erc1155'
        ? `${m.token}#${m.tokenId}`
        : m.token;

// Returns every decoded movement in the receipt, flattened.
export function movements(tx, meta = {}) {
    const out = [];
    const wrapped = meta.wrapped ? lower(meta.wrapped) : null;

    for (const log of tx.logs || []) {
        const decoded = decodeLog(log);
        if (!decoded) continue;

        if (decoded.event === 'wrap' || decoded.event === 'unwrap') {
            // Deposit and Withdrawal are common event names. Only the chain's
            // own wrapped token is allowed to mean wrapping.
            if (!isWrappedNative(decoded.token, wrapped)) continue;
            out.push(decoded);
            continue;
        }

        if (decoded.event === 'transferBatch') {
            for (const item of decoded.items) {
                out.push({
                    event: 'transfer',
                    standard: 'erc1155',
                    token: decoded.token,
                    operator: decoded.operator,
                    from: decoded.from,
                    to: decoded.to,
                    tokenId: item.tokenId,
                    amount: item.amount,
                });
            }
            continue;
        }

        out.push(decoded);
    }

    return out;
}

// Net every movement against one address.
export function netFlow(tx, wallet, meta = {}) {
    const me = lower(wallet);
    const wrapped = meta.wrapped ? lower(meta.wrapped) : null;
    const moves = movements(tx, meta);

    const ledger = new Map();
    const approvals = [];
    const notes = [];

    const entry = (m) => {
        const key = keyFor(m);
        if (!ledger.has(key)) {
            ledger.set(key, {
                key,
                token: m.token,
                standard: m.standard,
                tokenId: m.tokenId ?? null,
                in: 0n,
                out: 0n,
                minted: false,
                burned: false,
                inferred: false,
                from: [],
                to: [],
            });
        }
        return ledger.get(key);
    };

    // The native currency never emits a log; it lives on the transaction.
    const value = big(tx.value);
    if (value > 0n) {
        const native = entry({ standard: 'native', token: 'native' });
        native.token = 'native';
        native.standard = 'native';
        if (sameAddress(tx.from, me)) {
            native.out += value;
            if (tx.to) native.to.push(lower(tx.to));
        }
        if (sameAddress(tx.to, me)) {
            native.in += value;
            if (tx.from) native.from.push(lower(tx.from));
        }
    }

    let unwrapped = 0n;
    let sawUnwrap = false;

    for (const m of moves) {
        if (m.event === 'approval' || m.event === 'approvalForAll') {
            if (!sameAddress(m.owner, me)) continue;
            const unlimited = m.event === 'approvalForAll'
                ? m.approved
                : (m.amount ?? 0n) >= EFFECTIVELY_UNLIMITED;
            const cleared = m.event === 'approvalForAll'
                ? !m.approved
                : (m.amount ?? 0n) === 0n;
            approvals.push({
                token: m.token,
                standard: m.standard,
                spender: m.spender,
                tokenId: m.tokenId ?? null,
                amount: m.amount ?? null,
                everything: m.event === 'approvalForAll',
                unlimited,
                cleared,
            });
            continue;
        }

        if (m.event === 'wrap') {
            // Native turned into wrapped native. The native side is tx.value,
            // already counted above when the wallet paid it itself.
            if (!sameAddress(m.to, me)) continue;
            const e = entry({ standard: 'erc20', token: m.token });
            e.in += m.amount;
            e.minted = true;
            e.from.push(ZERO);
            continue;
        }

        if (m.event === 'unwrap') {
            sawUnwrap = true;
            unwrapped += m.amount;
            if (!sameAddress(m.from, me)) continue;
            const e = entry({ standard: 'erc20', token: m.token });
            e.out += m.amount;
            e.burned = true;
            e.to.push(ZERO);
            const native = entry({ standard: 'native', token: 'native' });
            native.in += m.amount;
            native.from.push(lower(m.token));
            continue;
        }

        if (m.event !== 'transfer') continue;
        if (sameAddress(m.from, m.to)) continue;

        const touchesMe = sameAddress(m.from, me) || sameAddress(m.to, me);
        if (!touchesMe) continue;

        const e = entry(m);
        if (sameAddress(m.to, me)) {
            e.in += m.amount;
            e.from.push(lower(m.from));
            if (isZero(m.from)) e.minted = true;
        }
        if (sameAddress(m.from, me)) {
            e.out += m.amount;
            e.to.push(lower(m.to));
            if (isZero(m.to) || sameAddress(m.to, DEAD)) e.burned = true;
        }
    }

    // A router can unwrap on your behalf and hand you the native currency in a
    // call that leaves no log at all. When that is the only way the numbers add
    // up, say so rather than reporting that you received nothing.
    const native = ledger.get('native');
    if (sawUnwrap && sameAddress(tx.from, me) && (!native || native.in === 0n)) {
        const anyOut = [...ledger.values()].some((e) => e.out > e.in);
        if (anyOut && unwrapped > 0n) {
            const n = entry({ standard: 'native', token: 'native' });
            n.in += unwrapped;
            n.inferred = true;
            notes.push('The native amount was unwrapped inside the transaction and forwarded without a log, so it is read from the unwrap.');
        }
    }

    const rows = [];
    for (const e of ledger.values()) {
        const net = e.in - e.out;
        if (net === 0n && !(e.standard === 'erc721' && e.in > 0n && e.out > 0n)) continue;
        rows.push({ ...e, net, direction: net > 0n ? 'in' : 'out', amount: net > 0n ? net : -net });
    }

    const incoming = rows.filter((r) => r.direction === 'in');
    const outgoing = rows.filter((r) => r.direction === 'out');

    return {
        wallet: me,
        wrapped,
        moves,
        rows,
        incoming,
        outgoing,
        approvals,
        notes,
        touched: rows.length > 0 || approvals.length > 0,
    };
}

// From "what moved" to "what happened".
//
// Every rule below reads the shape of the net flow and nothing else. There is
// no list of router addresses to keep up to date, no ABI to fetch, no protocol
// to support. A swap on a chain that launches tomorrow is one token out and one
// token in, the same as a swap on Uniswap, and so it reads the same here.

import { netFlow } from './flows.js';
import { big, lower, sameAddress, isZero, ZERO } from './hex.js';

const isNFT = (row) => row.standard === 'erc721' || row.standard === 'erc1155';
const isNative = (row) => row.standard === 'native';

const only = (list) => (list.length === 1 ? list[0] : null);

// When everything went to the same place, that place is the counterparty,
// however many tokens were involved. Otherwise there is no single answer and
// we say nothing rather than naming the contract that happened to be called.
function sameEnd(rows, side) {
    const all = new Set();
    for (const r of rows) for (const a of r[side]) if (!isZero(a)) all.add(a);
    return all.size === 1 ? [...all][0] : null;
}

function failed(tx) {
    const s = tx.status;
    if (s === undefined || s === null) return false;
    if (typeof s === 'boolean') return s === false;
    return big(s) === 0n;
}

export function classify(tx, wallet, meta = {}) {
    const me = lower(wallet);
    const flow = netFlow(tx, me, meta);
    const iSigned = sameAddress(tx.from, me);

    const fee = big(tx.gasUsed) * big(tx.effectiveGasPrice ?? tx.gasPrice);

    const base = {
        hash: tx.hash,
        wallet: me,
        chain: meta.chain || null,
        signedByMe: iSigned,
        fee: iSigned ? fee : 0n,
        incoming: flow.incoming,
        outgoing: flow.outgoing,
        approvals: flow.approvals,
        notes: [...flow.notes],
        risks: risksOf(tx, flow, me, iSigned),
    };

    if (failed(tx)) {
        return { ...base, kind: 'failed', confidence: 'high', counterparty: lower(tx.to) };
    }

    const { incoming: ins, outgoing: outs, approvals } = flow;
    const inOne = only(ins);
    const outOne = only(outs);

    // Wrapping is a swap between the native currency and its own token. It is
    // worth its own name because calling it a swap reads as a mistake.
    if (flow.wrapped) {
        if (inOne && outOne && isNative(outOne) && inOne.token === flow.wrapped && inOne.minted) {
            return { ...base, kind: 'wrap', confidence: 'high', gave: outOne, got: inOne };
        }
        if (inOne && outOne && isNative(inOne) && outOne.token === flow.wrapped && outOne.burned) {
            return { ...base, kind: 'unwrap', confidence: 'high', gave: outOne, got: inOne };
        }
    }

    const nftIn = ins.filter(isNFT);
    const nftOut = outs.filter(isNFT);

    if (nftIn.length === 1 && nftOut.length === 0) {
        const nft = nftIn[0];
        const paid = outs.find((r) => !isNFT(r));
        if (nft.minted) {
            return { ...base, kind: 'mint', confidence: 'high', got: nft, gave: paid || null };
        }
        if (paid) {
            return { ...base, kind: 'nft-buy', confidence: 'high', got: nft, gave: paid };
        }
        if (!iSigned) {
            return { ...base, kind: 'nft-receive', confidence: 'high', got: nft, counterparty: nft.from[0] };
        }
        return { ...base, kind: 'nft-claim', confidence: 'medium', got: nft };
    }

    if (nftOut.length === 1 && nftIn.length === 0) {
        const nft = nftOut[0];
        const got = ins.find((r) => !isNFT(r));
        if (got) return { ...base, kind: 'nft-sell', confidence: 'high', gave: nft, got };
        if (nft.burned) return { ...base, kind: 'burn', confidence: 'high', gave: nft };
        return { ...base, kind: 'nft-send', confidence: 'high', gave: nft, counterparty: nft.to[0] };
    }

    // A pool hands you a share token minted out of nothing when you put value
    // in, and burns it when you take value out. That mint or burn is the whole
    // signal; the pool itself stays anonymous.
    if (outs.length >= 2 && inOne && inOne.minted) {
        return { ...base, kind: 'add-liquidity', confidence: 'medium', gave: outs, got: inOne };
    }
    if (ins.length >= 2 && outOne && outOne.burned) {
        return { ...base, kind: 'remove-liquidity', confidence: 'medium', gave: outOne, got: ins };
    }

    if (ins.length >= 1 && outs.length >= 1) {
        const clean = ins.length === 1 && outs.length === 1;
        return {
            ...base,
            kind: 'swap',
            confidence: clean ? 'high' : 'medium',
            gave: clean ? outOne : outs,
            got: clean ? inOne : ins,
            legs: { in: ins.length, out: outs.length },
        };
    }

    if (outs.length >= 1 && ins.length === 0) {
        const target = sameEnd(outs, 'to') || lower(tx.to);
        const bridgeName = bridgeLabel(meta, target) || bridgeLabel(meta, lower(tx.to));
        if (bridgeName) {
            return {
                ...base,
                kind: 'bridge',
                confidence: 'medium',
                gave: outOne || outs,
                counterparty: target,
                bridge: bridgeName,
            };
        }
        if (!iSigned) {
            return { ...base, kind: 'taken', confidence: 'medium', gave: outOne || outs, counterparty: target };
        }
        return { ...base, kind: 'send', confidence: 'high', gave: outOne || outs, counterparty: target };
    }

    if (ins.length >= 1 && outs.length === 0) {
        const source = sameEnd(ins, 'from') || lower(tx.from);
        if (!iSigned) {
            return { ...base, kind: 'receive', confidence: 'high', got: inOne || ins, counterparty: source };
        }
        return { ...base, kind: 'claim', confidence: 'medium', got: inOne || ins, counterparty: source };
    }

    if (approvals.length) {
        const cleared = approvals.every((a) => a.cleared);
        return {
            ...base,
            kind: cleared ? 'revoke' : 'approve',
            confidence: 'high',
            counterparty: approvals[0].spender,
        };
    }

    // A transfer of zero tokens moves nothing, which is exactly the point of
    // it. Name it rather than reporting an empty transaction.
    if (base.risks.some((k) => k.code === 'zero-value-transfer')) {
        const poison = base.risks.find((k) => k.code === 'zero-value-transfer');
        return { ...base, kind: 'poison', confidence: 'high', counterparty: poison.counterparty };
    }

    if (!flow.touched && !iSigned) {
        return { ...base, kind: 'unrelated', confidence: 'high' };
    }

    return { ...base, kind: 'call', confidence: 'low', counterparty: lower(tx.to) };
}

function bridgeLabel(meta, address) {
    if (!address || !meta.bridges) return null;
    const hit = meta.bridges[address] ?? meta.bridges[address?.toLowerCase()];
    return hit === true ? 'a bridge' : (hit || null);
}

// The cleaning half. Everything here is read off the same logs; none of it
// needs a blocklist, which is why none of it goes stale.
function risksOf(tx, flow, me, iSigned) {
    const risks = [];

    for (const a of flow.approvals) {
        if (a.everything && !a.cleared) {
            risks.push({
                level: 'warn',
                code: 'approve-all',
                title: 'You gave away a whole collection',
                detail: 'This address can move every item you own in that collection, now and later.',
                spender: a.spender,
                token: a.token,
            });
        } else if (a.unlimited) {
            risks.push({
                level: 'warn',
                code: 'unlimited-approval',
                title: 'You granted an unlimited allowance',
                detail: 'This address can spend as much of that token as you ever hold, until you revoke it.',
                spender: a.spender,
                token: a.token,
            });
        }
    }

    // Address poisoning: a zero-amount transfer crafted so a near-identical
    // address appears in your history, hoping you copy it next time.
    for (const m of flow.moves) {
        if (m.event !== 'transfer') continue;
        if (m.amount !== 0n) continue;
        if (!sameAddress(m.from, me) && !sameAddress(m.to, me)) continue;
        risks.push({
            level: 'warn',
            code: 'zero-value-transfer',
            title: 'A transfer of nothing',
            detail: 'Someone moved zero tokens to put an address that looks like one of yours into your history. Do not copy addresses out of it.',
            counterparty: sameAddress(m.to, me) ? m.from : m.to,
            token: m.token,
        });
        break;
    }

    if (!iSigned && flow.incoming.length && !flow.outgoing.length) {
        risks.push({
            level: 'note',
            code: 'unsigned-arrival',
            title: 'You did not sign this',
            detail: 'It arrived on its own. Tokens that show up unasked are often bait for a site that wants a signature.',
        });
    }

    return risks;
}

export { netFlow };

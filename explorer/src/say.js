// One sentence, in the words a person would use.
//
// The classifier returns a shape; this turns the shape into English. Keeping
// them apart means the wording can be argued about without touching anything
// that decides what a transaction was.

import { format } from './amount.js';
import { short, checksum, lower } from './hex.js';

function tokenInfo(row, meta) {
    if (!row) return null;
    if (row.standard === 'native') {
        return {
            symbol: meta.chain?.symbol || 'ETH',
            decimals: 18,
            name: meta.chain?.currency || meta.chain?.symbol || 'ETH',
        };
    }
    const known = (meta.tokens || {})[lower(row.token)] || {};
    return {
        symbol: known.symbol || short(row.token, 4, 4),
        decimals: known.decimals ?? (row.standard === 'erc20' ? 18 : 0),
        name: known.name || known.symbol || short(row.token, 4, 4),
        unknown: !known.symbol,
    };
}

// "1,200 USDC" or "Cool Cats #4021"
export function describe(row, meta = {}) {
    if (!row) return '';
    const info = tokenInfo(row, meta);
    if (row.standard === 'erc721') {
        return `${info.name} #${row.tokenId}`;
    }
    if (row.standard === 'erc1155') {
        const n = row.amount === 1n ? '' : `${format(row.amount, 0)}× `;
        return `${n}${info.name} #${row.tokenId}`;
    }
    return `${format(row.amount, info.decimals)} ${info.symbol}`;
}

function list(rows, meta) {
    const parts = (Array.isArray(rows) ? rows : [rows]).map((r) => describe(r, meta));
    if (parts.length <= 1) return parts[0] || '';
    if (parts.length === 2) return `${parts[0]} and ${parts[1]}`;
    return parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1];
}

function who(address, meta) {
    if (!address) return 'somewhere else';
    const label = (meta.labels || {})[lower(address)];
    return label || short(address);
}

export function sentence(result, meta = {}) {
    const r = result;
    const gave = () => list(r.gave, meta);
    const got = () => list(r.got, meta);

    switch (r.kind) {
        case 'swap':
            return `You swapped ${gave()} for ${got()}.`;
        case 'wrap':
            return `You wrapped ${gave()} into ${got()}.`;
        case 'unwrap':
            return `You unwrapped ${gave()} back into ${got()}.`;
        case 'send':
            return `You sent ${gave()} to ${who(r.counterparty, meta)}.`;
        case 'receive':
            return `${got()} arrived from ${who(r.counterparty, meta)}.`;
        case 'taken':
            return `${gave()} left your wallet in a transaction you did not sign.`;
        case 'claim':
            return `You claimed ${got()}.`;
        case 'bridge':
            return `You sent ${gave()} into ${r.bridge === 'a bridge' ? 'a bridge' : r.bridge}, on its way to another chain.`;
        case 'mint':
            return r.gave
                ? `You minted ${got()} for ${gave()}.`
                : `You minted ${got()}.`;
        case 'nft-buy':
            return `You bought ${got()} for ${gave()}.`;
        case 'nft-sell':
            return `You sold ${gave()} for ${got()}.`;
        case 'nft-send':
            return `You sent ${gave()} to ${who(r.counterparty, meta)}.`;
        case 'nft-receive':
            return `${got()} arrived from ${who(r.counterparty, meta)}.`;
        case 'nft-claim':
            return `You received ${got()} from a contract you called.`;
        case 'burn':
            return `You burned ${gave()}.`;
        case 'add-liquidity':
            return `You put ${gave()} into a pool and got ${got()} back as your share.`;
        case 'remove-liquidity':
            return `You returned ${gave()} to a pool and took out ${got()}.`;
        case 'approve': {
            const a = r.approvals[0];
            const info = tokenInfo({ standard: a?.standard === 'erc20' ? 'erc20' : 'erc721', token: a?.token }, meta);
            if (a?.everything) {
                return `You let ${who(a.spender, meta)} move every ${info.name} you own.`;
            }
            if (a?.unlimited) {
                return `You let ${who(a.spender, meta)} spend your ${info.symbol}, with no limit.`;
            }
            return `You let ${who(a?.spender, meta)} spend ${format(a?.amount ?? 0n, info.decimals)} ${info.symbol}.`;
        }
        case 'revoke': {
            const a = r.approvals[0];
            const info = tokenInfo({ standard: 'erc20', token: a?.token }, meta);
            return `You took back ${who(a?.spender, meta)}'s permission to touch your ${info.symbol}.`;
        }
        case 'failed':
            return `This one failed. Nothing moved, and the gas was spent anyway.`;
        case 'call':
            return `You called ${who(r.counterparty, meta)}. Nothing left or entered your wallet.`;
        case 'poison':
            // The whole attack is that the address looks like one of yours, so
            // this is the one place a shortened address would be a lie.
            return `Nothing really moved. ${checksum(r.counterparty)} sent you zero tokens so that its address would sit in your history, close enough to yours to be copied by mistake.`;
        case 'unrelated':
            return `Nothing in this transaction touched your wallet.`;
        default:
            return `Something happened that Kliner could not name.`;
    }
}

// The line under the sentence: what it cost you.
export function costLine(result, meta = {}) {
    if (!result.signedByMe || result.fee === 0n) return '';
    const symbol = meta.chain?.symbol || 'ETH';
    return `Gas: ${format(result.fee, 18, { significant: 5 })} ${symbol}`;
}

export function headline(result, meta = {}) {
    return {
        title: sentence(result, meta),
        cost: costLine(result, meta),
        kind: result.kind,
        confidence: result.confidence,
        risks: result.risks,
        notes: result.notes,
    };
}

// A JSON-RPC node made out of the fixtures, so the whole page can be driven
// end to end without the chain. It answers the same shapes a real node does.

import { keccak256 } from '../src/keccak.js';
import { SELECTOR } from '../src/tokens.js';
import { strip } from '../src/hex.js';
import * as F from './fixtures.js';

const u256 = (n) => BigInt(n).toString(16).padStart(64, '0');

const encodeString = (text) => {
    const hex = Buffer.from(text, 'utf8').toString('hex');
    const padded = hex.padEnd(Math.ceil(hex.length / 64) * 64, '0');
    return '0x' + u256(32) + u256(text.length) + padded;
};

const HEAD = 20_000_000;

// Each fixture gets a stable hash and a block, newest last.
export const LEDGER = Object.entries(F.CASES).map(([name, tx], i) => ({
    name,
    hash: keccak256(name),
    block: HEAD - (Object.keys(F.CASES).length - i) * 1000,
    tx,
}));

const byHash = new Map(LEDGER.map((e) => [e.hash, e]));

const receiptOf = (entry) => ({
    transactionHash: entry.hash,
    blockNumber: '0x' + entry.block.toString(16),
    status: entry.tx.status,
    gasUsed: entry.tx.gasUsed,
    effectiveGasPrice: entry.tx.effectiveGasPrice,
    contractAddress: null,
    logs: (entry.tx.logs || []).map((log, index) => ({
        ...log,
        transactionHash: entry.hash,
        blockNumber: '0x' + entry.block.toString(16),
        logIndex: '0x' + index.toString(16),
    })),
});

const sentOf = (entry) => ({
    hash: entry.hash,
    from: entry.tx.from,
    to: entry.tx.to,
    value: entry.tx.value,
    input: '0x',
    nonce: '0x1',
    gasPrice: entry.tx.effectiveGasPrice,
});

const walletTopic = '0x' + strip(F.ME).padStart(64, '0');

export function answer(request) {
    const { method, params = [], id } = request;
    const ok = (result) => ({ jsonrpc: '2.0', id, result });

    switch (method) {
        case 'eth_blockNumber':
            return ok('0x' + HEAD.toString(16));

        case 'eth_getTransactionByHash': {
            const entry = byHash.get((params[0] || '').toLowerCase());
            return ok(entry ? sentOf(entry) : null);
        }

        case 'eth_getTransactionReceipt': {
            const entry = byHash.get((params[0] || '').toLowerCase());
            return ok(entry ? receiptOf(entry) : null);
        }

        case 'eth_getBlockByNumber':
            return ok({
                number: params[0],
                timestamp: '0x' + Math.floor(Date.now() / 1000 - 86400 * 3).toString(16),
            });

        case 'eth_getBalance':
            return ok('0x' + (2400000000000000000n).toString(16));

        case 'eth_getLogs': {
            const filter = params[0] || {};
            const from = Number(BigInt(filter.fromBlock || '0x0'));
            const to = Number(BigInt(filter.toBlock || '0x0'));
            const topics = filter.topics || [];
            const position = topics.findIndex((t) => t === walletTopic);
            const hits = [];
            for (const entry of LEDGER) {
                if (entry.block < from || entry.block > to) continue;
                for (const log of receiptOf(entry).logs) {
                    if (position >= 0 && (log.topics[position] || '').toLowerCase() !== walletTopic) continue;
                    hits.push({ ...log, address: log.address });
                }
            }
            return ok(hits);
        }

        case 'eth_call': {
            const to = (params[0]?.to || '').toLowerCase();
            const data = (params[0]?.data || '').toLowerCase();
            const info = F.META.tokens[to];
            if (data.startsWith(SELECTOR.symbol)) return ok(info ? encodeString(info.symbol) : '0x');
            if (data.startsWith(SELECTOR.name)) return ok(info ? encodeString(info.name) : '0x');
            if (data.startsWith(SELECTOR.decimals)) return ok(info ? '0x' + u256(info.decimals) : '0x');
            if (data.startsWith(SELECTOR.balanceOf)) {
                const amount = info ? BigInt(1200) * 10n ** BigInt(info.decimals || 0) : 0n;
                return ok('0x' + u256(amount));
            }
            if (data.startsWith(SELECTOR.allowance)) {
                return ok('0x' + u256((1n << 256n) - 1n));
            }
            return ok('0x');
        }

        default:
            return { jsonrpc: '2.0', id, error: { message: 'unhandled ' + method } };
    }
}

export function handle(body) {
    const list = Array.isArray(body) ? body : [body];
    const answers = list.map(answer);
    return Array.isArray(body) ? answers : answers[0];
}

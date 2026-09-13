// Reading the chain for one wallet.
//
// Two jobs. Read one transaction in full, and sweep a wallet's history for the
// things it left behind. Both run against a plain public endpoint with no key,
// so the ranges are chunked and shrink themselves when an endpoint says no.

import { Rpc, hexBlock } from './rpc.js';
import { TOPIC, MAX_UINT256, EFFECTIVELY_UNLIMITED } from './abi.js';
import { loadTokens, asMeta, SELECTOR } from './tokens.js';
import { classify } from './classify.js';
import { movements } from './flows.js';
import { big, lower, strip, checksum } from './hex.js';
import { BRIDGES } from './chains.js';

const topicFor = (address) => '0x' + strip(address).padStart(64, '0');

export function makeRpc(chain, options = {}) {
    return new Rpc(chain.rpc, options);
}

function metaFor(chain, tokenCache) {
    return {
        chain: { name: chain.name, symbol: chain.symbol, currency: chain.currency },
        wrapped: chain.wrapped,
        bridges: BRIDGES,
        labels: {},
        tokens: asMeta(tokenCache),
    };
}

// A transaction and its receipt are two calls; asking for both at once is the
// difference between one round trip and two.
export async function readTransaction(rpc, chain, hash, wallet, tokenCache = new Map()) {
    const [txAnswer, receiptAnswer] = await rpc.batch([
        { method: 'eth_getTransactionByHash', params: [hash] },
        { method: 'eth_getTransactionReceipt', params: [hash] },
    ]);

    const sent = txAnswer.result;
    const receipt = receiptAnswer.result;
    if (!sent) throw new Error('No transaction with that hash on ' + chain.name + '.');
    if (!receipt) throw new Error('That transaction has not been included in a block yet.');

    const tx = {
        hash: sent.hash,
        from: lower(sent.from),
        to: lower(sent.to || receipt.contractAddress || ''),
        value: sent.value,
        input: sent.input,
        nonce: sent.nonce,
        blockNumber: receipt.blockNumber,
        status: receipt.status,
        gasUsed: receipt.gasUsed,
        effectiveGasPrice: receipt.effectiveGasPrice || sent.gasPrice,
        logs: receipt.logs || [],
        createdContract: receipt.contractAddress ? lower(receipt.contractAddress) : null,
    };

    const who = wallet || tx.from;
    await loadTokens(rpc, tokensIn(tx, chain), tokenCache);
    const meta = metaFor(chain, tokenCache);

    return { tx, meta, result: classify(tx, who, meta) };
}

function tokensIn(tx, chain) {
    const seen = new Set();
    for (const m of movements(tx, { wrapped: chain.wrapped })) if (m.token) seen.add(m.token);
    return [...seen];
}

// Every log that names this wallet in any indexed position. Three filters cover
// Transfer either way, Approval either way, and the 1155 events, without
// naming a single token contract.
const WALLET_FILTERS = (walletTopic) => [
    [null, walletTopic],
    [null, null, walletTopic],
    [null, null, null, walletTopic],
];

export async function scanWallet(rpc, chain, wallet, options = {}) {
    const onProgress = options.onProgress ?? (() => {});
    const head = options.head ?? Number(big(await rpc.blockNumber()));
    const depth = options.depth ?? Math.round((90 * 24 * 3600) / chain.blockTime);
    const from = Math.max(0, options.from ?? head - depth);
    const walletTopic = topicFor(wallet);

    let chunk = options.chunk ?? 50000;
    const logs = [];
    let cursor = head;

    while (cursor >= from) {
        const start = Math.max(from, cursor - chunk + 1);
        let got;
        try {
            const answers = await rpc.batch(
                WALLET_FILTERS(walletTopic).map((topics) => ({
                    method: 'eth_getLogs',
                    params: [{ fromBlock: hexBlock(start), toBlock: hexBlock(cursor), topics }],
                }))
            );
            const failed = answers.find((a) => a.error);
            if (failed) throw new Error(failed.error.message || 'the endpoint refused that range');
            got = answers.flatMap((a) => a.result || []);
        } catch (error) {
            // Public endpoints all cap the range, and none of them agree on
            // what the cap is. Halve and try again rather than giving up.
            if (chunk > 500) {
                chunk = Math.max(500, Math.floor(chunk / 4));
                onProgress({ block: cursor, head, from, note: 'narrowing the range' });
                continue;
            }
            throw error;
        }

        logs.push(...got);
        cursor = start - 1;
        onProgress({ block: Math.max(start, from), head, from, found: logs.length });
        if (options.limit && logs.length >= options.limit) break;
    }

    return { logs, from, head, scannedTo: cursor + 1 };
}

// Distinct transactions, newest first.
export function transactionsIn(logs) {
    const order = new Map();
    for (const log of logs) {
        const hash = log.transactionHash;
        if (!hash) continue;
        const block = Number(big(log.blockNumber));
        const index = Number(big(log.logIndex ?? '0x0'));
        const seen = order.get(hash);
        if (!seen || block > seen.block) order.set(hash, { hash, block, index });
    }
    return [...order.values()].sort((a, b) => b.block - a.block);
}

export async function readMany(rpc, chain, hashes, wallet, tokenCache = new Map(), options = {}) {
    const onProgress = options.onProgress ?? (() => {});
    const size = options.batch ?? 10;
    const out = [];

    for (let i = 0; i < hashes.length; i += size) {
        const slice = hashes.slice(i, i + size);
        const calls = slice.flatMap((hash) => ([
            { method: 'eth_getTransactionByHash', params: [hash] },
            { method: 'eth_getTransactionReceipt', params: [hash] },
        ]));
        const answers = await rpc.batch(calls);

        const built = [];
        for (let j = 0; j < slice.length; j++) {
            const sent = answers[j * 2]?.result;
            const receipt = answers[j * 2 + 1]?.result;
            if (!sent || !receipt) continue;
            built.push({
                hash: sent.hash,
                from: lower(sent.from),
                to: lower(sent.to || receipt.contractAddress || ''),
                value: sent.value,
                blockNumber: receipt.blockNumber,
                status: receipt.status,
                gasUsed: receipt.gasUsed,
                effectiveGasPrice: receipt.effectiveGasPrice || sent.gasPrice,
                logs: receipt.logs || [],
            });
        }

        const tokens = new Set();
        for (const tx of built) for (const a of tokensIn(tx, chain)) tokens.add(a);
        await loadTokens(rpc, [...tokens], tokenCache);
        const meta = metaFor(chain, tokenCache);

        for (const tx of built) out.push({ tx, meta, result: classify(tx, wallet, meta) });
        onProgress({ done: out.length, total: hashes.length });
    }

    return out;
}

// The standing permissions a wallet has handed out and never taken back.
//
// The logs say what was granted; the contract says what is still true. Both
// are needed, because a spent allowance and a live one look identical in the
// history and only one of them is worth acting on.
export async function standingApprovals(rpc, chain, wallet, logs, tokenCache = new Map()) {
    const owner = lower(wallet);
    const latest = new Map();

    for (const log of logs) {
        const topic = (log.topics?.[0] || '').toLowerCase();
        const isErc20 = topic === TOPIC.approval && log.topics.length === 3;
        const isAll = topic === TOPIC.approvalForAll;
        if (!isErc20 && !isAll) continue;
        if (lower('0x' + strip(log.topics[1]).slice(-40)) !== owner) continue;

        const spender = lower('0x' + strip(log.topics[2]).slice(-40));
        const key = lower(log.address) + ':' + spender + (isAll ? ':all' : '');
        const block = Number(big(log.blockNumber));
        const previous = latest.get(key);
        if (previous && previous.block > block) continue;

        latest.set(key, {
            token: lower(log.address),
            spender,
            block,
            everything: isAll,
            amount: big(log.data),
            hash: log.transactionHash,
        });
    }

    const live = [...latest.values()].filter((a) => a.amount > 0n || a.everything);
    if (!live.length) return [];

    await loadTokens(rpc, live.map((a) => a.token), tokenCache);

    // Ask the contracts what is actually still allowed right now.
    const erc20 = live.filter((a) => !a.everything);
    if (erc20.length) {
        const answers = await rpc.batch(erc20.map((a) => ({
            method: 'eth_call',
            params: [{
                to: a.token,
                data: SELECTOR.allowance + strip(topicFor(owner)) + strip(topicFor(a.spender)),
            }, 'latest'],
        })));
        erc20.forEach((a, i) => {
            const answer = answers[i];
            a.current = answer && !answer.error ? big(answer.result) : null;
        });
    }

    const tokens = asMeta(tokenCache);
    return live
        .filter((a) => a.everything || a.current === null || a.current > 0n)
        .map((a) => ({
            ...a,
            token_name: tokens[a.token]?.name || checksum(a.token),
            symbol: tokens[a.token]?.symbol || null,
            decimals: tokens[a.token]?.decimals ?? 18,
            unlimited: a.everything || (a.current ?? a.amount) >= EFFECTIVELY_UNLIMITED,
            amount: a.current ?? a.amount,
        }))
        .sort((a, b) => (Number(b.unlimited) - Number(a.unlimited)) || (b.block - a.block));
}

// What the wallet holds now, for every token it has ever touched.
export async function balances(rpc, chain, wallet, tokenAddresses, tokenCache = new Map()) {
    const owner = lower(wallet);
    const list = [...new Set(tokenAddresses.map(lower))].filter(Boolean);

    const calls = [{ method: 'eth_getBalance', params: [owner, 'latest'] }];
    for (const token of list) {
        calls.push({
            method: 'eth_call',
            params: [{ to: token, data: SELECTOR.balanceOf + strip(topicFor(owner)) }, 'latest'],
        });
    }

    const answers = await rpc.batch(calls);
    await loadTokens(rpc, list, tokenCache);
    const tokens = asMeta(tokenCache);

    const out = [{
        token: 'native',
        standard: 'native',
        symbol: chain.symbol,
        name: chain.currency,
        decimals: 18,
        amount: answers[0] && !answers[0].error ? big(answers[0].result) : 0n,
    }];

    list.forEach((token, i) => {
        const answer = answers[i + 1];
        if (!answer || answer.error) return;
        const amount = big(answer.result);
        if (amount === 0n) return;
        out.push({
            token,
            standard: 'erc20',
            symbol: tokens[token]?.symbol || null,
            name: tokens[token]?.name || checksum(token),
            decimals: tokens[token]?.decimals ?? 18,
            amount,
        });
    });

    return out.filter((row) => row.amount > 0n);
}

export { MAX_UINT256 };

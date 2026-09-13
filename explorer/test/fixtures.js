// Receipts shaped the way a node returns them: topics as 32-byte words, data
// as a hex blob, amounts as integers in the token's own units. The topic
// hashes come from src/abi.js so a fixture cannot drift away from the reader.

import { TOPIC, MAX_UINT256 } from '../src/abi.js';

export const ME      = '0x1111111111111111111111111111111111111111';
export const FRIEND  = '0x5555555555555555555555555555555555555555';
export const ROUTER  = '0x2222222222222222222222222222222222222222';
export const POOL    = '0x6666666666666666666666666666666666666666';
export const BRIDGE  = '0x4444444444444444444444444444444444444444';
export const SELLER  = '0x8888888888888888888888888888888888888888';
export const POISON  = '0x1111111111112222222222222222111111111111';
export const ZERO    = '0x0000000000000000000000000000000000000000';

export const USDC = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
export const WETH = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
export const ARB  = '0x912ce59144191c1204e64559fe8253a0e49e6548';
export const NFT  = '0x3333333333333333333333333333333333333333';
export const GAME = '0x9999999999999999999999999999999999999999';
export const LP   = '0x7777777777777777777777777777777777777777';

export const META = {
    chain: { name: 'Ethereum', symbol: 'ETH', currency: 'ether' },
    wrapped: WETH,
    tokens: {
        [USDC]: { symbol: 'USDC', decimals: 6, name: 'USD Coin' },
        [WETH]: { symbol: 'WETH', decimals: 18, name: 'Wrapped Ether' },
        [ARB]:  { symbol: 'ARB', decimals: 18, name: 'Arbitrum' },
        [LP]:   { symbol: 'UNI-V2', decimals: 18, name: 'Pool share' },
        [NFT]:  { symbol: 'COOL', decimals: 0, name: 'Cool Cats' },
        [GAME]: { symbol: 'ITEM', decimals: 0, name: 'Game item' },
    },
    labels: {
        [BRIDGE]: 'the Arbitrum bridge',
        [ROUTER]: 'Uniswap',
    },
    bridges: { [BRIDGE]: 'the Arbitrum bridge' },
};

const pad = (address) => '0x' + address.toLowerCase().replace(/^0x/, '').padStart(64, '0');
const u256 = (n) => BigInt(n).toString(16).padStart(64, '0');
const data = (...items) => '0x' + items.map(u256).join('');

export const transfer = (token, from, to, amount) => ({
    address: token,
    topics: [TOPIC.transfer, pad(from), pad(to)],
    data: data(amount),
});

export const transferNFT = (token, from, to, tokenId) => ({
    address: token,
    topics: [TOPIC.transfer, pad(from), pad(to), pad(BigInt(tokenId).toString(16))],
    data: '0x',
});

export const transfer1155 = (token, operator, from, to, tokenId, amount) => ({
    address: token,
    topics: [TOPIC.transferSingle, pad(operator), pad(from), pad(to)],
    data: data(tokenId, amount),
});

export const batch1155 = (token, operator, from, to, items) => {
    const ids = items.map((i) => i[0]);
    const amounts = items.map((i) => i[1]);
    // two dynamic arrays: head is two offsets, then each array's length + body
    const headWords = 2;
    const idsAt = headWords * 32;
    const amountsAt = idsAt + 32 + ids.length * 32;
    return {
        address: token,
        topics: [TOPIC.transferBatch, pad(operator), pad(from), pad(to)],
        data: '0x' + u256(idsAt) + u256(amountsAt)
            + u256(ids.length) + ids.map(u256).join('')
            + u256(amounts.length) + amounts.map(u256).join(''),
    };
};

export const approval = (token, owner, spender, amount) => ({
    address: token,
    topics: [TOPIC.approval, pad(owner), pad(spender)],
    data: data(amount),
});

export const approvalForAll = (token, owner, spender, approved) => ({
    address: token,
    topics: [TOPIC.approvalForAll, pad(owner), pad(spender)],
    data: data(approved ? 1 : 0),
});

export const wrapLog = (to, amount) => ({
    address: WETH,
    topics: [TOPIC.deposit, pad(to)],
    data: data(amount),
});

export const unwrapLog = (from, amount) => ({
    address: WETH,
    topics: [TOPIC.withdrawal, pad(from)],
    data: data(amount),
});

const tx = (fields) => ({
    hash: '0x' + 'ab'.repeat(32),
    from: ME,
    to: ROUTER,
    value: '0x0',
    status: '0x1',
    gasUsed: '0x' + (120000).toString(16),
    effectiveGasPrice: '0x' + (12_000_000_000).toString(16),
    logs: [],
    ...fields,
});

const e = (n) => BigInt(n) * 10n ** 18n;
const usdc = (n) => BigInt(n) * 10n ** 6n;

export const CASES = {
    swap: tx({
        logs: [
            transfer(USDC, ME, POOL, usdc(1200)),
            transfer(WETH, POOL, ME, 430000000000000000n),
        ],
    }),

    swapForEth: tx({
        logs: [
            transfer(USDC, ME, POOL, usdc(1200)),
            transfer(WETH, POOL, ROUTER, 430000000000000000n),
            unwrapLog(ROUTER, 430000000000000000n),
        ],
    }),

    swapEthIn: tx({
        to: ROUTER,
        value: '0x' + e(1).toString(16),
        logs: [
            wrapLog(ROUTER, e(1)),
            transfer(WETH, ROUTER, POOL, e(1)),
            transfer(USDC, POOL, ME, usdc(2800)),
        ],
    }),

    send: tx({
        to: USDC,
        logs: [transfer(USDC, ME, FRIEND, usdc(50))],
    }),

    sendNative: tx({
        to: FRIEND,
        value: '0x' + e(2).toString(16),
        logs: [],
    }),

    receive: tx({
        from: FRIEND,
        to: USDC,
        logs: [transfer(USDC, FRIEND, ME, usdc(50))],
    }),

    approveUnlimited: tx({
        to: USDC,
        logs: [approval(USDC, ME, ROUTER, MAX_UINT256)],
    }),

    approveLimited: tx({
        to: USDC,
        logs: [approval(USDC, ME, ROUTER, usdc(100))],
    }),

    approveAll: tx({
        to: NFT,
        logs: [approvalForAll(NFT, ME, ROUTER, true)],
    }),

    revoke: tx({
        to: USDC,
        logs: [approval(USDC, ME, ROUTER, 0n)],
    }),

    wrap: tx({
        to: WETH,
        value: '0x' + e(1).toString(16),
        logs: [wrapLog(ME, e(1))],
    }),

    unwrap: tx({
        to: WETH,
        logs: [unwrapLog(ME, e(1))],
    }),

    mint: tx({
        to: NFT,
        value: '0x' + (80000000000000000n).toString(16),
        logs: [transferNFT(NFT, ZERO, ME, 4021)],
    }),

    nftBuy: tx({
        logs: [
            transferNFT(NFT, SELLER, ME, 88),
            transfer(WETH, ME, SELLER, e(3)),
        ],
    }),

    nftSell: tx({
        logs: [
            transferNFT(NFT, ME, SELLER, 88),
            transfer(WETH, SELLER, ME, e(3)),
        ],
    }),

    nftSend: tx({
        to: NFT,
        logs: [transferNFT(NFT, ME, FRIEND, 88)],
    }),

    itemsSend: tx({
        to: GAME,
        logs: [transfer1155(GAME, ME, ME, FRIEND, 7, 3)],
    }),

    itemsBatch: tx({
        to: GAME,
        logs: [batch1155(GAME, ME, ME, FRIEND, [[7, 3], [9, 1]])],
    }),

    bridge: tx({
        to: BRIDGE,
        logs: [transfer(USDC, ME, BRIDGE, usdc(500))],
    }),

    claim: tx({
        to: ARB,
        logs: [transfer(ARB, ZERO, ME, e(625))],
    }),

    addLiquidity: tx({
        logs: [
            transfer(USDC, ME, POOL, usdc(3000)),
            transfer(WETH, ME, POOL, e(1)),
            transfer(LP, ZERO, ME, 54772255750516611345n),
        ],
    }),

    removeLiquidity: tx({
        logs: [
            transfer(LP, ME, ZERO, 54772255750516611345n),
            transfer(USDC, POOL, ME, usdc(3000)),
            transfer(WETH, POOL, ME, e(1)),
        ],
    }),

    failed: tx({
        status: '0x0',
        logs: [],
    }),

    poison: tx({
        from: POISON,
        to: USDC,
        logs: [transfer(USDC, POISON, ME, 0n)],
    }),

    unrelated: tx({
        from: FRIEND,
        to: USDC,
        logs: [transfer(USDC, FRIEND, SELLER, usdc(10))],
    }),

    call: tx({
        to: GAME,
        logs: [],
    }),

    taken: tx({
        from: ROUTER,
        to: USDC,
        logs: [transfer(USDC, ME, ROUTER, usdc(900))],
    }),
};

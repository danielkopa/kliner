// The shapes drainers actually use, built the way a site would build them.

import { keccak256 } from '../src/keccak.js';

export const YOU      = '0x1111111111111111111111111111111111111111';
export const DRAINER  = '0xbadc0ffee0ddf00d1234567890abcdef12345678';
export const FRIEND   = '0x5555555555555555555555555555555555555555';
export const USDC     = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
export const WETH     = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
export const NFT      = '0x3333333333333333333333333333333333333333';
export const UNISWAP  = '0x7a250d5630b4cf539739df2c5dacb4c659f2488d';
export const PERMIT2  = '0x000000000022d473030f116ddee9f6b43ac78ba3';
export const SEAPORT  = '0x0000000000000068f116a894984e2db1123eb395';

export const MAX256 = (1n << 256n) - 1n;
export const MAX160 = (1n << 160n) - 1n;
export const MAX48  = (1n << 48n) - 1n;

const sel = (signature) => keccak256(signature).slice(0, 10);
const pad = (v) => {
    if (typeof v === 'boolean') return (v ? 1n : 0n).toString(16).padStart(64, '0');
    if (typeof v === 'string') return v.toLowerCase().replace(/^0x/, '').padStart(64, '0');
    return BigInt(v).toString(16).padStart(64, '0');
};
export const call = (signature, ...args) => sel(signature) + args.map(pad).join('');

const tx = (fields) => ({ from: YOU, value: '0x0', ...fields });

export const REQUESTS = {

    unlimitedApprove: {
        method: 'eth_sendTransaction',
        params: [tx({ to: USDC, data: call('approve(address,uint256)', DRAINER, MAX256) })],
    },

    boundedApprove: {
        method: 'eth_sendTransaction',
        params: [tx({ to: USDC, data: call('approve(address,uint256)', UNISWAP, 100n * 10n ** 6n) })],
    },

    revokeApprove: {
        method: 'eth_sendTransaction',
        params: [tx({ to: USDC, data: call('approve(address,uint256)', UNISWAP, 0n) })],
    },

    approveAll: {
        method: 'eth_sendTransaction',
        params: [tx({ to: NFT, data: call('setApprovalForAll(address,bool)', DRAINER, true) })],
    },

    revokeAll: {
        method: 'eth_sendTransaction',
        params: [tx({ to: NFT, data: call('setApprovalForAll(address,bool)', UNISWAP, false) })],
    },

    permit2Approve: {
        method: 'eth_sendTransaction',
        params: [tx({ to: PERMIT2, data: call('approve(address,address,uint160,uint48)', USDC, DRAINER, MAX160, MAX48) })],
    },

    plainSend: {
        method: 'eth_sendTransaction',
        params: [tx({ to: FRIEND, value: '0x' + (2n * 10n ** 18n).toString(16) })],
    },

    transfer: {
        method: 'eth_sendTransaction',
        params: [tx({ to: USDC, data: call('transfer(address,uint256)', FRIEND, 50n * 10n ** 6n) })],
    },

    pullFromYou: {
        method: 'eth_sendTransaction',
        params: [tx({ to: USDC, data: call('transferFrom(address,address,uint256)', YOU, DRAINER, 900n * 10n ** 6n) })],
    },

    bundle: {
        method: 'eth_sendTransaction',
        params: [tx({ to: UNISWAP, data: call('multicall(bytes[])', 32n) })],
    },

    unknownCall: {
        method: 'eth_sendTransaction',
        params: [tx({ to: DRAINER, data: '0xdeadbeef' + '00'.repeat(32) })],
    },

    ownership: {
        method: 'eth_sendTransaction',
        params: [tx({ to: NFT, data: call('transferOwnership(address)', DRAINER) })],
    },

    // ── the signatures, which is where it actually happens ─────────────────

    permitUnlimited: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'Permit',
            domain: { name: 'USD Coin', version: '2', chainId: 1, verifyingContract: USDC },
            types: { Permit: [
                { name: 'owner', type: 'address' }, { name: 'spender', type: 'address' },
                { name: 'value', type: 'uint256' }, { name: 'nonce', type: 'uint256' },
                { name: 'deadline', type: 'uint256' }] },
            message: { owner: YOU, spender: DRAINER, value: MAX256.toString(), nonce: '3',
                       deadline: '99999999999' },
        })],
    },

    permitBounded: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'Permit',
            domain: { name: 'USD Coin', version: '2', chainId: 1, verifyingContract: USDC },
            types: { Permit: [] },
            message: { owner: YOU, spender: UNISWAP, value: (250n * 10n ** 6n).toString(),
                       nonce: '1', deadline: String(Math.floor(Date.now() / 1000) + 1800) },
        })],
    },

    permit2Single: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'PermitSingle',
            domain: { name: 'Permit2', chainId: 1, verifyingContract: PERMIT2 },
            types: { PermitSingle: [] },
            message: {
                details: { token: WETH, amount: MAX160.toString(), expiration: MAX48.toString(), nonce: '0' },
                spender: DRAINER,
                sigDeadline: MAX48.toString(),
            },
        })],
    },

    permit2Batch: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'PermitBatch',
            domain: { name: 'Permit2', chainId: 1, verifyingContract: PERMIT2 },
            types: { PermitBatch: [] },
            message: {
                details: [
                    { token: USDC, amount: MAX160.toString(), expiration: MAX48.toString(), nonce: '0' },
                    { token: WETH, amount: MAX160.toString(), expiration: MAX48.toString(), nonce: '0' },
                    { token: NFT,  amount: '1000',            expiration: '1900000000',     nonce: '0' },
                ],
                spender: DRAINER,
                sigDeadline: MAX48.toString(),
            },
        })],
    },

    orderForNothing: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'OrderComponents',
            domain: { name: 'Seaport', version: '1.6', chainId: 1, verifyingContract: SEAPORT },
            types: { OrderComponents: [] },
            message: {
                offerer: YOU,
                offer: [{ itemType: 2, token: NFT, identifierOrCriteria: '88', startAmount: '1', endAmount: '1' }],
                consideration: [{ itemType: 0, token: '0x0000000000000000000000000000000000000000',
                                  identifierOrCriteria: '0', startAmount: '0', endAmount: '0', recipient: YOU }],
                endTime: '99999999999',
            },
        })],
    },

    orderWildcard: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'OrderComponents',
            domain: { name: 'Seaport', version: '1.6', chainId: 1, verifyingContract: SEAPORT },
            types: { OrderComponents: [] },
            message: {
                offerer: YOU,
                offer: [{ itemType: 4, token: NFT, identifierOrCriteria: '0', startAmount: '1', endAmount: '1' }],
                consideration: [{ itemType: 0, token: '0x0000000000000000000000000000000000000000',
                                  identifierOrCriteria: '0', startAmount: '1', endAmount: '1', recipient: YOU }],
                endTime: '99999999999',
            },
        })],
    },

    orderNormal: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'OrderComponents',
            domain: { name: 'Seaport', version: '1.6', chainId: 1, verifyingContract: SEAPORT },
            types: { OrderComponents: [] },
            message: {
                offerer: YOU,
                offer: [{ itemType: 2, token: NFT, identifierOrCriteria: '88', startAmount: '1', endAmount: '1' }],
                consideration: [
                    { itemType: 0, token: '0x0000000000000000000000000000000000000000',
                      identifierOrCriteria: '0', startAmount: (3n * 10n ** 18n).toString(),
                      endAmount: (3n * 10n ** 18n).toString(), recipient: YOU },
                    { itemType: 0, token: '0x0000000000000000000000000000000000000000',
                      identifierOrCriteria: '0', startAmount: (75n * 10n ** 15n).toString(),
                      endAmount: (75n * 10n ** 15n).toString(), recipient: UNISWAP },
                ],
                endTime: String(Math.floor(Date.now() / 1000) + 86400),
            },
        })],
    },

    wrongChainPermit: {
        method: 'eth_signTypedData_v4',
        params: [YOU, JSON.stringify({
            primaryType: 'Permit',
            domain: { name: 'USD Coin', chainId: 137, verifyingContract: USDC },
            types: { Permit: [] },
            message: { owner: YOU, spender: DRAINER, value: MAX256.toString(), nonce: '0', deadline: '99999999999' },
        })],
    },

    blindSign: {
        method: 'eth_sign',
        params: [YOU, '0x' + 'ab'.repeat(32)],
    },

    loginMessage: {
        method: 'personal_sign',
        params: ['0x' + Buffer.from('example.com wants you to sign in with your Ethereum account.').toString('hex'), YOU],
    },

    structuredMessage: {
        method: 'personal_sign',
        params: ['0x' + Buffer.from('{"spender":"' + DRAINER + '","value":"unlimited"}').toString('hex'), YOU],
    },

    binaryMessage: {
        method: 'personal_sign',
        params: ['0xfffefdfc', YOU],
    },
};

export const CONTEXT = { account: YOU, chainId: 1 };

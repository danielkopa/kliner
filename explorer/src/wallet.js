// The only part of Kliner that asks anything of your wallet.
//
// It builds one kind of transaction and one only: setting an allowance back to
// nothing. Your wallet signs it, your wallet shows you it first, and Kliner
// never sees a key. Nothing here can move a token, only stop something else
// from being able to.

import { SELECTOR } from './tokens.js';
import { strip, lower, checksum, isAddress } from './hex.js';

const pad = (value) => strip(value).padStart(64, '0');

export function encodeRevoke(approval) {
    if (!isAddress(approval.token)) throw new Error('That is not a token address.');
    if (!isAddress(approval.spender)) throw new Error('That is not a spender address.');

    if (approval.everything) {
        // setApprovalForAll(spender, false)
        return SELECTOR.setApprovalForAll + pad(approval.spender) + pad('0');
    }
    // approve(spender, 0)
    return SELECTOR.approve + pad(approval.spender) + pad('0');
}

// A sentence describing exactly what the wallet is about to be asked to sign,
// shown before the wallet is touched. If this does not match what the wallet
// then shows you, do not sign it.
export function describeRevoke(approval) {
    const what = approval.symbol || approval.token_name || checksum(approval.token);
    return approval.everything
        ? 'Tell ' + what + ' that ' + checksum(approval.spender) + ' may no longer move your items.'
        : 'Set ' + checksum(approval.spender) + ' allowance on ' + what + ' to zero.';
}

export function hasWallet() {
    return typeof globalThis.ethereum !== 'undefined';
}

export async function connect() {
    if (!hasWallet()) throw new Error('No wallet extension found in this browser.');
    const accounts = await globalThis.ethereum.request({ method: 'eth_requestAccounts' });
    if (!accounts?.length) throw new Error('The wallet did not offer an account.');
    return lower(accounts[0]);
}

export async function currentChainId() {
    if (!hasWallet()) return null;
    const id = await globalThis.ethereum.request({ method: 'eth_chainId' });
    return Number(BigInt(id));
}

export async function switchChain(chain) {
    const target = '0x' + chain.id.toString(16);
    try {
        await globalThis.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: target }],
        });
        return true;
    } catch (error) {
        throw new Error('Switch your wallet to ' + chain.name + ' and try again.');
    }
}

// Hands the wallet one transaction. The wallet asks you. Kliner does not.
export async function sendRevoke(approval, owner, chain) {
    if (!hasWallet()) throw new Error('No wallet extension found in this browser.');

    const account = lower(owner);
    const connected = await connect();
    if (connected !== account) {
        throw new Error('Your wallet is on ' + checksum(connected) + ', not ' + checksum(account) + '.');
    }

    const id = await currentChainId();
    if (id !== chain.id) await switchChain(chain);

    return globalThis.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{ from: account, to: approval.token, data: encodeRevoke(approval), value: '0x0' }],
    });
}

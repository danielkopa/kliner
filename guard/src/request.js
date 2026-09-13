// The front door. A wallet request goes in; a reading comes out.
//
// Nothing in here touches the network, and nothing in here can alter the
// request. Kliner Guard reads a copy and hands the original on untouched.

import { readCalldata } from './calldata.js';
import { readTypedData, readMessage } from './typed.js';

export const WATCHED = [
    'eth_sendTransaction',
    'eth_signTypedData',
    'eth_signTypedData_v3',
    'eth_signTypedData_v4',
    'personal_sign',
    'eth_sign',
];

export function shouldRead(method) {
    return WATCHED.indexOf(method) !== -1;
}

export function read(request, context = {}) {
    const method = request && request.method;
    const params = (request && request.params) || [];

    switch (method) {
        case 'eth_sendTransaction':
            return { method, ...readCalldata(params[0] || {}) };

        case 'eth_signTypedData':
        case 'eth_signTypedData_v3':
        case 'eth_signTypedData_v4': {
            // The address comes first and the payload second, except in the
            // oldest form where it is the other way round.
            const payload = typeof params[1] === 'undefined' ? params[0] : params[1];
            const account = context.account || (typeof params[0] === 'string' ? params[0] : null);
            return { method, ...readTypedData(payload, { ...context, account }) };
        }

        case 'personal_sign':
            return { method, ...readMessage(typeof params[0] === 'string' ? params[0] : '') };

        case 'eth_sign':
            // The wallet is asked to sign raw bytes it cannot explain. There is
            // no honest reason for a site to ask for this any more.
            return { method, kind: 'blind', offchain: true, payload: params[1] };

        default:
            return { method, kind: 'ignored' };
    }
}

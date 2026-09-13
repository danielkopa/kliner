// One sentence, and what is wrong with it.
//
// The levels are stop, warn, note and clear. Nothing here says "safe": Kliner
// Guard can say what a request does, and it can say when it cannot read one,
// but it is not in a position to promise you an outcome, and a tool that
// promises one is lying to you.

import { format } from './amount.js';
import { checksum, short, isZero, lower } from './hex.js';
import { tokenFor, contractName, currencyFor } from './known.js';
import { MAX_UINT48 } from './calldata.js';

function nameOf(address, fallback) {
    if (!address) return fallback || 'an address Kliner Guard was not given';
    return contractName(address) || short(address);
}

function tokenName(address) {
    const known = tokenFor(address);
    if (known) return known.symbol;
    return address ? short(address) : 'a token';
}

const NO_TOKEN = '0x0000000000000000000000000000000000000000';

function amountText(amount, token, context) {
    if (amount === null || amount === undefined) return 'an amount that did not decode';
    // No token address means the chain's own currency, which is always 18 places.
    if (!token || token === NO_TOKEN) {
        return format(amount, 18, { significant: 6 }) + ' ' + currencyFor(context && context.chainId);
    }
    const known = tokenFor(token);
    if (known) return format(amount, known.decimals, { significant: 6 }) + ' ' + known.symbol;
    // Without the token's decimals there is no honest way to place the point.
    return format(amount, 0) + ' units of ' + tokenName(token) + ' (raw, Kliner Guard is offline and cannot ask the token how it counts)';
}

function when(deadline) {
    if (deadline === null || deadline === undefined) return null;
    if (deadline >= MAX_UINT48) return 'never';
    const ms = Number(deadline) * 1000;
    if (!Number.isFinite(ms) || ms <= 0) return null;
    const date = new Date(ms);
    if (Number.isNaN(date.getTime())) return null;
    return date.toISOString().slice(0, 10);
}

const GASLESS = 'This is a signature, not a transaction. It costs no gas, needs no confirmation on any chain, and will not appear in your history — so there will be nothing to notice afterwards.';

export function explain(reading, context = {}) {
    const risks = [];
    const facts = [];
    let title = '';
    let level = 'note';

    const stop = (code, t, d) => risks.push({ level: 'stop', code, title: t, detail: d });
    const warn = (code, t, d) => risks.push({ level: 'warn', code, title: t, detail: d });
    const note = (code, t, d) => risks.push({ level: 'note', code, title: t, detail: d });

    if (reading.offchain) note('offchain', 'Nothing will show this happened', GASLESS);
    if (reading.wrongChain) {
        warn('wrong-chain', 'This was built for a different chain',
            'The request names chain ' + reading.domain.chainId + ' while your wallet is on ' + context.chainId +
            '. A signature made for one chain is sometimes replayable on another.');
    }

    switch (reading.kind || reading.call) {

        case 'approve': {
            const token = tokenName(reading.token);
            const who = nameOf(reading.spender);
            if (reading.clearing) {
                title = 'This takes back ' + who + "'s permission to spend your " + token + '.';
                level = 'clear';
                break;
            }
            if (reading.unlimited) {
                title = 'This lets ' + who + ' spend your ' + token + '. Not an amount — all of it.';
                stop('unlimited', 'An allowance with no limit',
                    who + ' will be able to move your ' + token + ' at any moment from now on, including ' +
                    'tokens you do not own yet. It stays until you revoke it.');
            } else {
                title = 'This lets ' + who + ' spend ' + amountText(reading.amount, reading.token, context) + ' of yours.';
                note('bounded', 'The amount is bounded', 'It can spend up to that and no more.');
            }
            if (reading.through === 'Permit2') {
                facts.push('Through Permit2, which holds the allowance on behalf of many apps.');
            }
            if (reading.forever) {
                warn('forever', 'It does not expire', 'The expiry on this is set so far out that it never arrives.');
            }
            if (reading.increase) {
                facts.push('This adds to an allowance you already gave, rather than replacing it.');
            }
            break;
        }

        case 'approveAll': {
            const who = nameOf(reading.spender);
            if (reading.clearing) {
                title = 'This takes back ' + who + "'s access to that collection.";
                level = 'clear';
                break;
            }
            title = 'This lets ' + who + ' move every item you own in that collection.';
            stop('approve-all', 'A whole collection, not one item',
                'It covers what you own now and anything you buy into that collection later, until you revoke it. ' +
                'A marketplace needs this. A mint page does not.');
            break;
        }

        case 'permit': {
            const token = tokenName(reading.token);
            const who = nameOf(reading.spender);
            const until = when(reading.deadline);
            title = reading.unlimited
                ? 'You are signing away every ' + token + ' you hold to ' + who + '.'
                : 'You are signing permission for ' + who + ' to spend ' + amountText(reading.amount, reading.token, context) + '.';
            if (reading.unlimited) {
                stop('unlimited', 'An allowance with no limit, signed rather than sent',
                    'There is no transaction to see and no gas to pay, and ' + who +
                    ' can move your ' + token + ' whenever it likes afterwards.');
            }
            if (reading.forever) {
                stop('forever', 'And it does not expire',
                    until === 'never' ? 'The expiry is set to the maximum the format allows.'
                                      : 'It runs until ' + until + ', which is not a deadline.');
            } else if (until) {
                facts.push('Runs until ' + until + '.');
            }
            if (reading.through) facts.push('Through ' + reading.through + '.');
            break;
        }

        case 'permitBatch': {
            const who = nameOf(reading.spender);
            title = 'You are signing permission for ' + who + ' to spend ' + reading.items.length + ' different tokens of yours.';
            if (reading.unlimited) {
                stop('unlimited', 'At least one of them has no limit',
                    'A batch permit is one signature that opens several doors at once. ' +
                    reading.items.filter((i) => i.unlimited).length + ' of these ' + reading.items.length + ' have no ceiling.');
            }
            if (reading.forever) stop('forever', 'And they do not expire', 'The expiry is set past any horizon that matters.');
            for (const item of reading.items) {
                facts.push(tokenName(item.token) + ' — ' + (item.unlimited ? 'no limit' : amountText(item.amount, item.token, context)));
            }
            break;
        }

        case 'permitTransfer': {
            const who = nameOf(reading.spender);
            title = 'You are signing permission for ' + who + ' to take ' + amountText(reading.amount, reading.token, context) + ' from you.';
            if (reading.unlimited) {
                stop('unlimited', 'With no ceiling on the amount', who + ' decides how much actually moves.');
            }
            break;
        }

        case 'order': {
            const giving = reading.offer.map((o) =>
                o.kind === 'erc721-any' || o.kind === 'erc1155-any'
                    ? 'any item you own from ' + tokenName(o.token)
                    : o.kind === 'erc20' || o.kind === 'native'
                        ? amountText(o.amount, o.token, context)
                        : tokenName(o.token) + ' #' + o.tokenId
            );

            if (reading.forNothing) {
                title = 'You are signing away ' + list(giving) + ' and receiving nothing for it.';
                stop('for-nothing', 'Nothing comes back to you',
                    'This is an order on ' + reading.marketplace + ' where everything leaves your side and the ' +
                    'consideration to you is zero. Whoever holds this signature can take it whenever they like.');
            } else {
                title = 'You are offering ' + list(giving) + ' for ' + amountText(reading.backToYou, reading.backToYouToken, context) + '.';
            }

            if (reading.wildcard) {
                stop('wildcard', 'It does not name which item',
                    'The order is written against a whole collection rather than one token id, so it applies to ' +
                    'whatever you hold from it — now or later.');
            }
            for (const other of reading.goesElsewhere) {
                facts.push('Also sends ' + amountText(other.amount, other.token, context) + ' to ' + nameOf(other.recipient) + '.');
            }
            if (reading.forever) warn('forever', 'The order does not expire', 'It can be filled at any point in the future.');
            break;
        }

        case 'send':
            title = 'You are sending ' + amountText(reading.value, null, context) + ' to ' + nameOf(reading.to) + '.';
            break;

        case 'transfer':
            title = 'You are sending ' + amountText(reading.amount, reading.token, context) + ' to ' + nameOf(reading.recipient) + '.';
            break;

        case 'transferFrom':
            title = 'This moves a token out of ' + nameOf(reading.owner) + ' and into ' + nameOf(reading.recipient) + '.';
            if (context.account && reading.owner && lower(reading.owner) === lower(context.account)) {
                warn('pull', 'It is taking from you', 'You are the wallet it is being pulled from.');
            }
            break;

        case 'transferOwnership':
            title = 'This hands ownership of that contract to ' + nameOf(reading.recipient) + '.';
            stop('ownership', 'Ownership is not recoverable', 'If that contract is yours, this gives it away for good.');
            break;

        case 'bundle':
            title = 'This packs several actions into one call.';
            warn('bundle', 'Kliner Guard will not guess what is inside',
                'Bundled calls are normal for routers and also how several actions get hidden behind one confirmation. ' +
                'It can be read only by simulating it, which would mean sending it to somebody else’s server.');
            break;

        case 'blind':
            title = 'The site is asking your wallet to sign raw data it cannot explain.';
            stop('eth-sign', 'This is a blind signature',
                'eth_sign hands over a signature on bytes nobody shows you, and it can be a transaction. ' +
                'Honest sites stopped asking for this years ago.');
            break;

        case 'message':
            if (reading.unreadable) {
                title = 'A message that is not text.';
                warn('not-text', 'It is dressed up as a message', 'A plain-text signature request should be plain text.');
            } else {
                title = 'A plain message, signed to prove the wallet is yours.';
                facts.push(reading.text);
                if (reading.looksStructured) {
                    warn('structured', 'It is not really prose',
                        'This is structured data being signed through the plain-message door, which is a way to get around the checks a typed-data request would face.');
                } else {
                    level = 'clear';
                    note('cannot-move', 'On its own it moves nothing',
                        'A signed message cannot transfer a token by itself. Read it anyway: it is also how a site gets you to agree to something.');
                }
            }
            break;

        case 'nothing':
            title = 'An empty call to ' + nameOf(reading.to) + '.';
            level = 'clear';
            break;

        case 'unknown':
        case 'unreadable':
        case 'other':
            title = 'Kliner Guard cannot read this one.';
            warn('unreadable', 'Not readable is not the same as safe',
                (reading.why || '') + ' Everything Kliner Guard knows, it knows from the request itself. ' +
                'When that is not enough, it says so instead of guessing.');
            break;

        default:
            title = 'Kliner Guard cannot read this one.';
            warn('unreadable', 'Not readable is not the same as safe', 'No shape matched this request.');
    }

    const worst = risks.some((r) => r.level === 'stop') ? 'stop'
                : risks.some((r) => r.level === 'warn') ? 'warn'
                : level;

    return { title, level: worst, risks, facts, reading };
}

function list(items) {
    if (!items.length) return 'nothing';
    if (items.length === 1) return items[0];
    if (items.length === 2) return items[0] + ' and ' + items[1];
    return items.slice(0, -1).join(', ') + ' and ' + items[items.length - 1];
}

export { short, checksum };

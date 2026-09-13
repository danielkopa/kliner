// What you bought, what you sold, and which purchase paid for which sale.
//
// The tax office does not want a number. It wants to see that the number came
// from somewhere. So every disposal here carries the list of acquisitions it
// consumed, with the date and cost of each — that record is the product, and
// the total is just its last line.

import { parse, rescale, scaleBy, divide, COIN, EUR, ONE_COIN } from './decimal.js';

export const FIAT = new Set(['EUR', 'USD', 'CZK', 'GBP', 'PLN', 'CHF']);

const isFiat = (asset) => FIAT.has(String(asset || '').toUpperCase());

// Acquisitions waiting to be matched against a disposal.
class Pool {
    constructor(asset, method) {
        this.asset = asset;
        this.method = method;
        this.lots = [];
    }

    add(lot) {
        this.lots.push(lot);
        if (this.method === 'fifo') this.lots.sort((a, b) => a.when.localeCompare(b.when));
    }

    get held() {
        return this.lots.reduce((sum, lot) => sum + lot.amount, 0n);
    }

    get cost() {
        return this.lots.reduce((sum, lot) => sum + lot.cost, 0n);
    }

    // Consume `amount` of the asset and report exactly what was used.
    take(amount) {
        return this.method === 'average' ? this.takeAverage(amount) : this.takeInOrder(amount);
    }

    takeInOrder(amount) {
        const used = [];
        let left = amount;
        let cost = 0n;

        while (left > 0n && this.lots.length) {
            const lot = this.lots[0];
            const part = lot.amount <= left ? lot.amount : left;
            // cost of the part, in proportion to what is left in the lot
            const partCost = part === lot.amount ? lot.cost : scaleBy(lot.cost, part, lot.amount);

            used.push({ when: lot.when, amount: part, cost: partCost, ref: lot.ref, source: lot.source });
            cost += partCost;
            left -= part;
            lot.amount -= part;
            lot.cost -= partCost;
            if (lot.amount === 0n) this.lots.shift();
        }

        return { cost, used, short: left };
    }

    takeAverage(amount) {
        const held = this.held;
        if (held === 0n) return { cost: 0n, used: [], short: amount };

        const take = amount <= held ? amount : held;
        const cost = scaleBy(this.cost, take, held);
        const perUnit = divide(this.cost * ONE_COIN, held);

        const used = [{
            when: 'weighted average of ' + this.lots.length + ' acquisitions',
            amount: take,
            cost,
            perUnit,
            source: 'average',
        }];

        // Draw the average down proportionally across every lot.
        let drawn = 0n;
        for (const lot of this.lots) {
            const share = scaleBy(lot.amount, take, held);
            lot.cost -= scaleBy(lot.cost, share, lot.amount === 0n ? 1n : lot.amount);
            lot.amount -= share;
            drawn += share;
        }
        if (drawn < take && this.lots.length) this.lots[0].amount -= (take - drawn);
        this.lots = this.lots.filter((lot) => lot.amount > 0n);

        return { cost, used, short: amount - take };
    }
}

function eurOf(value) {
    return value === null || value === undefined ? null : parse(value, EUR);
}

function side(value) {
    if (!value) return null;
    return { asset: String(value.asset).toUpperCase(), amount: parse(value.amount, COIN) };
}

// The whole year, in order, turned into acquisitions and disposals.
export function walk(events, options = {}) {
    const method = options.method === 'average' ? 'average' : 'fifo';
    const pools = new Map();
    const disposals = [];
    const acquisitions = [];
    const problems = [];

    const poolFor = (asset) => {
        if (!pools.has(asset)) pools.set(asset, new Pool(asset, method));
        return pools.get(asset);
    };

    const ordered = [...events].sort((a, b) => String(a.when).localeCompare(String(b.when)));

    for (const [index, event] of ordered.entries()) {
        const give = side(event.give);
        const take = side(event.take);
        const at = { index, when: event.when, ref: event.ref, where: event.where, kind: event.kind, note: event.note };

        const givenEur = eurOf(event.eur?.give);
        const takenEur = eurOf(event.eur?.take);

        // Moving your own coins between your own wallets is not a sale, but the
        // fee paid to do it is a disposal of the coin used to pay it.
        if (event.kind === 'transfer') {
            chargeFee(event, at, poolFor, disposals, problems);
            continue;
        }

        // What left you
        let proceeds = null;
        if (give && !isFiat(give.asset) && give.amount > 0n) {
            // The value of a disposal is what you got for it; when only the
            // cost of the incoming side is known, that is the same number.
            proceeds = givenEur !== null ? givenEur : takenEur;

            if (proceeds === null) {
                problems.push({ ...at, why: 'No euro value for ' + give.asset + ' at this moment, so this disposal cannot be counted yet.' });
            } else {
                const pool = poolFor(give.asset);
                const { cost, used, short } = pool.take(give.amount);
                if (short > 0n) {
                    problems.push({ ...at, why: 'You disposed of more ' + give.asset + ' than Kliner has seen you acquire. Something earlier is missing.' });
                }
                disposals.push({
                    ...at,
                    asset: give.asset,
                    amount: give.amount,
                    proceeds,
                    cost,
                    gain: proceeds - cost,
                    used,
                    unmatched: short,
                    because: reasonFor(event, take),
                });
            }
        }

        // What arrived
        if (take && !isFiat(take.asset) && take.amount > 0n) {
            const cost = event.kind === 'reward'
                ? 0n                               // nothing was paid for it
                : (takenEur !== null ? takenEur : (proceeds !== null ? proceeds : givenEur));

            if (cost === null) {
                problems.push({ ...at, why: 'No euro value for ' + take.asset + ', so its cost is unknown and a later sale cannot be worked out.' });
            } else {
                const lot = { when: String(event.when), amount: take.amount, cost, ref: event.ref, source: event.kind };
                poolFor(take.asset).add(lot);
                acquisitions.push({ ...at, asset: take.asset, amount: take.amount, cost });
            }
        }

        chargeFee(event, at, poolFor, disposals, problems);
    }

    const holdings = [...pools.entries()]
        .map(([asset, pool]) => ({ asset, amount: pool.held, cost: pool.cost }))
        .filter((row) => row.amount > 0n)
        .sort((a, b) => a.asset.localeCompare(b.asset));

    return { method, disposals, acquisitions, holdings, problems };
}

function chargeFee(event, at, poolFor, disposals, problems) {
    if (!event.fee || !event.fee.asset) return;
    const asset = String(event.fee.asset).toUpperCase();
    const amount = parse(event.fee.amount, COIN);
    if (amount <= 0n) return;

    if (isFiat(asset)) return;  // a euro fee is just a cost, not a disposal

    const value = eurOf(event.fee.eur);
    if (value === null) {
        problems.push({ ...at, why: 'The fee was paid in ' + asset + ' with no euro value, so it cannot be counted.' });
        return;
    }

    const pool = poolFor(asset);
    const { cost, used, short } = pool.take(amount);
    disposals.push({
        ...at,
        asset,
        amount,
        proceeds: value,
        cost,
        gain: value - cost,
        used,
        unmatched: short,
        because: 'Paying a fee in ' + asset + ' spends it, and spending is a disposal.',
        isFee: true,
    });
}

function reasonFor(event, take) {
    if (event.kind === 'sell') return 'Sold for fiat.';
    if (event.kind === 'spend') return 'Spent on goods or services, which counts as a sale.';
    if (take && !isFiat(take.asset)) {
        return 'Swapped for ' + take.asset + '. In Slovakia a crypto-for-crypto swap is a sale, even though no euro reached your bank.';
    }
    return 'Disposed of.';
}

export { isFiat };

// node test/run.js

import { parse, format, euros, divide, COIN, EUR } from '../src/decimal.js';
import { walk } from '../src/ledger.js';
import { compute } from '../src/compute.js';
import { RULES, incomeTax, healthLevy } from '../src/rules/sk-2026.js';
import { YEAR, LAST_YEAR } from './fixtures.js';

let pass = 0;
const failures = [];
const show = (v) => (typeof v === 'bigint' ? v.toString() + 'n' : JSON.stringify(v));
const check = (name, ok, detail) => { if (ok) pass++; else failures.push({ name, detail }); };
const is = (name, got, want) => check(name, got === want, 'got ' + show(got) + ', wanted ' + show(want));
const eur = (text) => parse(text, EUR);

// ── the arithmetic, because money in floats is how returns go wrong ─────────

is('a tenth plus two tenths is three tenths', parse('0.1', EUR) + parse('0.2', EUR), parse('0.3', EUR));
is('a coin keeps eighteen places', format(parse('0.000000000000000001'), COIN), '0,000000000000000001');
is('past eighteen places it truncates rather than rounds up',
    format(parse('0.0000000000000000019'), COIN), '0,000000000000000001');
is('a comma is a decimal point', parse('1,5', EUR), parse('1.5', EUR));
is('a thousands separator is not', parse('1,500.25', EUR), parse('1500.25', EUR));
is('scientific notation survives', parse('1.2e-7', COIN), parse('0.00000012', COIN));
is('half a cent rounds away from zero', divide(5n, 2n), 3n);
is('and so does minus half a cent', divide(-5n, 2n), -3n);
is('euros print as euros', euros(eur('1234.5')), '1 234,50 €');

// ── the brackets, worked out by hand ────────────────────────────────────────

{
    // 20 000 € of gain sitting on top of 40 000 € of other income:
    //   40 000 → 43 975 is  3 975 at 19% =   755,25
    //   43 975 → 60 000 is 16 025 at 25% = 4 006,25
    const { tax } = incomeTax(eur('20000'), eur('40000'));
    is('tax across two brackets', tax, eur('4761.50'));
    is('the health levy is 16% of the base', healthLevy(eur('20000')), eur('3200'));
}
{
    // 100 000 € with no other income touches all four brackets.
    const { tax, steps } = incomeTax(eur('100000'), 0n);
    is('tax across all four brackets', tax, eur('25592.25'));
    is('and it reports four steps', steps.length, 4);
    is('the top rate is 35', steps[3].rate, 35);
}
is('no gain, no tax', incomeTax(0n, eur('40000')).tax, 0n);
is('a loss is not taxed', incomeTax(eur('-500'), eur('40000')).tax, 0n);
is('and pays no levy either', healthLevy(eur('-500')), 0n);

// ── the rules that are particular to Slovakia ──────────────────────────────

const fifo = compute(YEAR, { method: 'fifo', otherIncome: '40000' });
const avg = compute(YEAR, { method: 'average', otherIncome: '40000' });

const find = (out, ref) => out.disposals.find((d) => d.ref === ref);

check('a crypto-for-crypto swap is a disposal', !!find(fifo, '0xswap'));
check('and says why, since this is the rule people miss',
    find(fifo, '0xswap').because.includes('no euro reached your bank'));
is('the swap is priced at what was given', find(fifo, '0xswap').proceeds, eur('12000'));

check('spending coin on goods is a disposal', !!find(fifo, 'laptop'));
check('trading into a stablecoin is a disposal', !!find(fifo, 'u1'));

check('moving between your own wallets is not a disposal',
    !fifo.disposals.some((d) => d.ref === 't1' && !d.isFee));
check('but the fee paid in coin to do it is',
    !!fifo.disposals.find((d) => d.ref === 't1' && d.isFee));

{
    const reward = find(fifo, 's2');
    is('a staking reward carries no cost', reward.cost, 0n);
    is('so the whole sale is gain', reward.gain, reward.proceeds);
}

check('buying with euros is never a disposal',
    !fifo.disposals.some((d) => d.ref === 'b1' || d.ref === 'b2'));

// ── cost basis ─────────────────────────────────────────────────────────────

is('FIFO takes the oldest bitcoin first', find(fifo, '0xswap').cost, eur('8000'));
is('the average takes the average', find(avg, '0xswap').cost, eur('9000'));
check('the two methods do not agree, which is the point', fifo.owed !== avg.owed);
is('and the answer always says which was used', fifo.method, 'fifo');

check('a disposal lists the acquisitions it consumed', find(fifo, '0xswap').used.length >= 1);
is('and names the day each was bought', find(fifo, '0xswap').used[0].when.slice(0, 10), '2026-01-14');

// ── the year, added up ─────────────────────────────────────────────────────

is('the year total', fifo.net, eur('1512'));
is('income tax on it', fifo.incomeTax, eur('287.28'));
is('the health levy on it', fifo.healthLevy, eur('241.92'));
is('what is owed', fifo.owed, eur('529.20'));
is('losses reduced the gains', fifo.net, fifo.totalGain + fifo.totalLoss);

{
    const strict = compute(YEAR, {
        method: 'fifo', otherIncome: '40000',
        rules: { ...RULES, lossesOffsetGainsWithinYear: false },
    });
    check('and if an adviser says they may not, that is one line',
        strict.base === strict.totalGain && strict.owed > fifo.owed);
}

// ── the things that must never be quietly swallowed ────────────────────────

check('an unpriced trade is reported, not dropped', fifo.problems.length >= 1);
check('and names the day it happened',
    fifo.problems.some((p) => String(p.when).startsWith('2026-12-20')));
check('an unpriced disposal is not counted as a zero gain',
    !fifo.disposals.some((d) => d.ref === 'nope'));

{
    const impossible = walk([
        { when: '2026-04-01T00:00:00Z', kind: 'sell', give: { asset: 'BTC', amount: '1' },
          take: { asset: 'EUR', amount: '50000' }, eur: { give: '50000' }, ref: 'ghost' },
    ], { method: 'fifo' });
    check('selling what was never bought is flagged',
        impossible.problems.some((p) => p.why.includes('more BTC')));
}

// ── housekeeping ───────────────────────────────────────────────────────────

is('last year stays in last year', compute([...YEAR, ...LAST_YEAR], { year: 2026 }).counts.disposals,
    fifo.counts.disposals);
is('and can be asked for on its own', compute([...YEAR, ...LAST_YEAR], { year: 2025 }).counts.disposals, 1);

is('the same year computes the same twice',
    JSON.stringify(compute(YEAR, { method: 'fifo' }), (k, v) => typeof v === 'bigint' ? v.toString() : v),
    JSON.stringify(compute(YEAR, { method: 'fifo' }), (k, v) => typeof v === 'bigint' ? v.toString() : v));

check('events out of order are sorted before anything is matched',
    compute([...YEAR].reverse(), { method: 'fifo', otherIncome: '40000' }).owed === fifo.owed);

check('what is still held is reported with what it cost',
    fifo.holdings.some((h) => h.asset === 'BTC' && h.cost > 0n));
is('and the bitcoin left is right', format(fifo.holdings.find((h) => h.asset === 'BTC').amount, COIN), '0,7899');

// ── the rules are checkable, which is the product ──────────────────────────

check('every rule says where it came from', RULES.sources.length >= 3);
check('and every source has a link', RULES.sources.every((s) => s.url.startsWith('https://')));
check('the rules say plainly that this is not advice', RULES.warning.includes('not a tax adviser'));
is('the year the rules are for', RULES.year, 2026);
check('the one-year exemption is not applied to coins held directly',
    RULES.holdingExemptionMonths === null);
check('both methods are offered rather than one being assumed',
    RULES.costBasisMethods.length === 2);

// ── report ─────────────────────────────────────────────────────────────────

const total = pass + failures.length;
if (failures.length) {
    console.log('\nKliner Tax — ' + pass + '/' + total + '\n');
    for (const f of failures) console.log('  x ' + f.name + '\n      ' + (f.detail || ''));
    console.log('');
    process.exit(1);
}
console.log('\nKliner Tax — ' + pass + '/' + total + ' checks pass\n');

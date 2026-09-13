// The year, added up.

import { walk } from './ledger.js';
import { RULES, incomeTax, healthLevy } from './rules/sk-2026.js';
import { parse, EUR } from './decimal.js';

export function compute(events, options = {}) {
    const rules = options.rules || RULES;
    const method = options.method || rules.defaultMethod;
    const year = options.year || rules.year;
    const otherIncome = parse(options.otherIncome || 0, EUR);

    const book = walk(events, { method });

    const inYear = book.disposals.filter((d) => String(d.when).slice(0, 4) === String(year));
    const gains = inYear.filter((d) => d.gain > 0n);
    const losses = inYear.filter((d) => d.gain < 0n);

    const totalGain = gains.reduce((sum, d) => sum + d.gain, 0n);
    const totalLoss = losses.reduce((sum, d) => sum + d.gain, 0n); // negative
    const proceeds = inYear.reduce((sum, d) => sum + d.proceeds, 0n);
    const cost = inYear.reduce((sum, d) => sum + d.cost, 0n);

    // Whether a loss is allowed to reduce a gain is a rule, not a given.
    const net = rules.lossesOffsetGainsWithinYear ? totalGain + totalLoss : totalGain;
    const base = net > 0n ? net : 0n;

    const tax = incomeTax(base, otherIncome, rules);
    const levy = healthLevy(base, rules);

    return {
        country: rules.country,
        year,
        method,
        rules,
        disposals: inYear,
        problems: book.problems,
        holdings: book.holdings,
        counts: { disposals: inYear.length, gains: gains.length, losses: losses.length },
        proceeds,
        cost,
        totalGain,
        totalLoss,
        net,
        base,
        otherIncome,
        incomeTax: tax.tax,
        brackets: tax.steps,
        healthLevy: levy,
        owed: tax.tax + levy,
        effectiveRate: base > 0n ? Number((tax.tax + levy) * 10000n / base) / 100 : 0,
        deadline: rules.filingDeadline,
    };
}

export { RULES };

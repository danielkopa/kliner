// Slovakia, tax year 2026 — the rules as data, with where each came from.
//
// Kliner is not a tax adviser and this file is not advice. It is a written-down
// reading of published rules, kept in one place so that it can be checked, and
// versioned so that last year's return still computes the way it was filed. If
// a line here is wrong, the calculation is wrong in a way you can see and fix,
// which is the whole reason it is not buried in the code.
//
// Read it with your accountant before you file anything.

import { parse, EUR } from '../decimal.js';

export const RULES = {
    country: 'Slovakia',
    year: 2026,
    currency: 'EUR',
    revised: '2026-09-13',

    // Income tax on other income (§8), applied to the net gain on top of the
    // rest of your income for the year.
    brackets: [
        { upTo: '43975',  rate: 19 },
        { upTo: '60388',  rate: 25 },
        { upTo: '74997',  rate: 30 },
        { upTo: null,     rate: 35 },
    ],

    // Health insurance contribution on the same base.
    healthLevy: 16,

    // What creates a taxable disposal.
    taxable: {
        sellForFiat: true,
        swapCryptoForCrypto: true,   // the rule that catches everyone here
        spendOnGoods: true,
        payAFeeInCrypto: true,
        moveBetweenYourOwnWallets: false,
        buyWithFiat: false,
        justHolding: false,
    },

    // Staking and mining rewards are not taxed as they arrive; they are taxed
    // when the coin is later sold or exchanged. Kliner therefore books a reward
    // at a cost of zero, so the whole proceeds are taxed on disposal.
    rewardsTaxedOnArrival: false,
    rewardCostBasis: 'zero',

    // Losses reduce gains inside the same year. Carrying a net loss forward to
    // another year is NOT assumed here; if your adviser says otherwise, it is
    // one line to change.
    lossesOffsetGainsWithinYear: true,
    lossesCarryForward: false,

    // The one-year exemption people quote applies to crypto ETFs, not to
    // holding the coin itself. Kliner does not apply it to direct disposals.
    holdingExemptionMonths: null,

    filingDeadline: '2027-03-31',

    // Neither method is mandated in the sources Kliner has read, so it offers
    // both and always says which one produced the number.
    costBasisMethods: ['fifo', 'average'],
    defaultMethod: 'fifo',

    sources: [
        { what: 'rates, health levy, and that a crypto-to-crypto swap is a sale',
          url: 'https://kryptomagazin.sk/dane-z-krypta-na-slovensku-1-pravidlo-ktore-meni-cely-vypocet/' },
        { what: 'rates, the 16% health levy, rewards taxed on sale rather than on arrival',
          url: 'https://cryptotaxlaw.sk/kryptoaktiva-a-dane-v-roku-2026/' },
        { what: 'FIFO and weighted average both in use; losses reducing gains within the year',
          url: 'https://www.legalion.sk/2025/01/31/ako-spravne-zdanit-kryptomeny-a-vyhnut-sa-problemom-s-financnou-spravou/' },
    ],

    warning: 'Kliner is not a tax adviser. This is a calculation with its working shown, for you and your accountant to check.',
};

// Progressive tax on a base that sits on top of income you already have.
export function incomeTax(base, otherIncome = 0n, rules = RULES) {
    if (base <= 0n) return { tax: 0n, steps: [] };

    const steps = [];
    let taxed = 0n;
    let floor = otherIncome;
    let top = otherIncome + base;

    let previous = 0n;
    for (const bracket of rules.brackets) {
        const ceiling = bracket.upTo === null ? null : parse(bracket.upTo, EUR);
        const from = previous > floor ? previous : floor;
        const to = ceiling === null ? top : (ceiling < top ? ceiling : top);

        if (to > from) {
            const slice = to - from;
            const tax = slice * BigInt(bracket.rate) / 100n;
            steps.push({ from, to, slice, rate: bracket.rate, tax });
            taxed += tax;
        }

        if (ceiling === null || ceiling >= top) break;
        previous = ceiling;
    }

    return { tax: taxed, steps };
}

export function healthLevy(base, rules = RULES) {
    if (base <= 0n) return 0n;
    return base * BigInt(rules.healthLevy) / 100n;
}

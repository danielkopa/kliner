// A year that contains every shape the Slovak rules treat differently.

export const YEAR = [
    { when: '2026-01-14T10:00:00Z', kind: 'buy',
      give: { asset: 'EUR', amount: '20000' }, take: { asset: 'BTC', amount: '0.5' },
      eur: { give: '20000', take: '20000' }, where: 'Binance', ref: 'b1' },

    { when: '2026-03-02T09:30:00Z', kind: 'buy',
      give: { asset: 'EUR', amount: '25000' }, take: { asset: 'BTC', amount: '0.5' },
      eur: { give: '25000', take: '25000' }, where: 'Binance', ref: 'b2' },

    // The rule that catches people: no euro ever reaches the bank, and it is
    // still a sale of 0.2 BTC.
    { when: '2026-06-11T18:45:00Z', kind: 'trade',
      give: { asset: 'BTC', amount: '0.2' }, take: { asset: 'ETH', amount: '3' },
      eur: { give: '12000', take: '12000' }, where: 'Uniswap', ref: '0xswap' },

    { when: '2026-08-03T12:00:00Z', kind: 'sell',
      give: { asset: 'ETH', amount: '1' }, take: { asset: 'EUR', amount: '3500' },
      eur: { give: '3500', take: '3500' }, where: 'Kraken', ref: 's1' },

    // Buying a laptop with coin is a sale too.
    { when: '2026-09-19T16:20:00Z', kind: 'spend',
      give: { asset: 'BTC', amount: '0.01' },
      eur: { give: '700' }, where: 'a shop', ref: 'laptop', note: 'laptop' },

    // A staking reward: nothing was paid for it, so the whole of a later sale
    // is gain.
    { when: '2026-09-25T00:00:00Z', kind: 'reward',
      take: { asset: 'ADA', amount: '500' }, eur: { take: '250' }, where: 'staking', ref: 'r1' },

    { when: '2026-11-02T11:00:00Z', kind: 'sell',
      give: { asset: 'ADA', amount: '500' }, take: { asset: 'EUR', amount: '210' },
      eur: { give: '210', take: '210' }, where: 'Kraken', ref: 's2' },

    // Moving your own coin is not a sale — but the fee paid in coin is.
    { when: '2026-10-05T08:00:00Z', kind: 'transfer',
      give: { asset: 'BTC', amount: '0.1' }, take: { asset: 'BTC', amount: '0.0999' },
      fee: { asset: 'BTC', amount: '0.0001', eur: '6' }, where: 'to cold wallet', ref: 't1' },

    // A stablecoin is not a currency here; this is a sale of ETH.
    { when: '2026-11-20T14:10:00Z', kind: 'trade',
      give: { asset: 'ETH', amount: '1' }, take: { asset: 'USDT', amount: '2900' },
      eur: { give: '2900', take: '2900' }, where: 'Binance', ref: 'u1' },

    // A loss, to see whether it is allowed to reduce the gains.
    { when: '2026-12-01T09:00:00Z', kind: 'sell',
      give: { asset: 'ETH', amount: '1' }, take: { asset: 'EUR', amount: '2600' },
      eur: { give: '2600', take: '2600' }, where: 'Kraken', ref: 's3' },

    // Something an exchange export forgot to price.
    { when: '2026-12-20T21:00:00Z', kind: 'trade',
      give: { asset: 'USDT', amount: '400' }, take: { asset: 'SOL', amount: '2' },
      where: 'a DEX', ref: 'nope' },
];

// Last year, to prove the year filter works.
export const LAST_YEAR = [
    { when: '2025-05-05T10:00:00Z', kind: 'buy',
      give: { asset: 'EUR', amount: '1000' }, take: { asset: 'SOL', amount: '10' },
      eur: { give: '1000', take: '1000' }, ref: 'old1' },
    { when: '2025-09-09T10:00:00Z', kind: 'sell',
      give: { asset: 'SOL', amount: '10' }, take: { asset: 'EUR', amount: '1800' },
      eur: { give: '1800', take: '1800' }, ref: 'old2' },
];

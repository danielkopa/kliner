# Kliner Tax — Slovakia

Works out what a year of crypto owes, and shows the working.

```
2026-06-11   0,2 BTC     got 12 000,00 €   cost  8 000,00 €   +4 000,00 €
   Swapped for ETH. In Slovakia a crypto-for-crypto swap is a sale,
   even though no euro reached your bank.
   used: 0,2 BTC bought on 2026-01-14 at 40 000,00 €/BTC

gains 4 512,00 €   losses -3 000,00 €   net 1 512,00 €
income tax 287,28 €   health levy 16% 241,92 €
OWED 529,20 €
```

## Why this exists

Slovakia taxes crypto in the way that hurts most: **every crypto-for-crypto
swap is a sale**, priced in euros at that moment. Stablecoins included. An
active year is hundreds of taxable events without a single euro reaching a bank
account. On top of that sit progressive rates of 19 / 25 / 30 / 35 % **and a
16 % health insurance levy** — an effective rate that can approach half.

The global tools do not model any of this, and the local advice is a blog post.

## What makes this one different

Every other calculator hands you **a number you cannot check**. If the tax
office asks where it came from, you have a screenshot.

Kliner hands you the number **and the working**: which purchases were consumed
by which sale, on what date, at what price, under which rule and why that rule
applies. The rules live in one readable file with a link to the source for each
one, so a disagreement with your accountant is a line to change rather than an
argument with a black box.

## What it is not

**Kliner is not a tax adviser, and this is not tax advice.** It is arithmetic
with its working shown, for you and your accountant to check. Read
`src/rules/sk-2026.js` before you rely on a single figure in it.

## What it gets right on purpose

- **No floating point anywhere.** Coins are integers at 18 places, euros at 6
  while the sums run, rounded to whole cents once, at the end. `0.1 + 0.2` is
  exactly `0.3` here, and a half cent rounds away from zero rather than in
  whoever's favour the hardware felt like.
- **Both cost-basis methods.** Neither FIFO nor weighted average is mandated in
  the sources read so far, so Kliner offers both and always states which
  produced the answer. On the test year they differ by more than three times the
  tax owed — which is exactly why a tool must say which one it used.
- **Nothing is silently dropped.** A trade an exchange exported without a price
  is listed as needing attention, not counted as a zero.
- **Moving your own coins is not a sale** — but the fee you paid in coin to move
  them is, and it is charged.
- **A staking reward carries no cost**, so the whole of a later sale is gain,
  because Slovakia taxes the reward on disposal rather than on arrival.

## Running it

```sh
npm test     # 55 checks, including the bracket maths worked out by hand
npm run show # prints a sample year under both methods
```

## Layout

```
src/decimal.js       money and coin amounts as integers; no floats
src/ledger.js        lots, FIFO and weighted average, and what each sale used
src/rules/sk-2026.js Slovakia 2026 as data, with a source for every line
src/compute.js       the year, added up
```

## Not built yet

- Reading exchange exports (Binance, Kraken, Coinbase CSV) and on-chain history
- Euro prices at a timestamp, which is the one thing that needs an outside
  source
- The filled-in tax return itself

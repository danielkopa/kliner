# Kliner

Paste a transaction. Read what happened, in one sentence.

```
You swapped 1,200 USDC for 0.43 ETH.
You let 0x1111…2222 spend your USDC, with no limit.
Nothing really moved. 0x1111…1111 sent you zero tokens so that its address
would sit in your history, close enough to yours to be copied by mistake.
```

## The idea

Every explorer shows you the same thing: a method name, a list of logs, and a
wall of hex. To know what a transaction *did* you have to already know the
protocol it touched.

Kliner does not read protocols. It reads **what moved**.

```
for every Transfer log:
    if it arrived at your address   → in
    if it left your address         → out

one token out, one token in         → a swap
out, nothing in                     → you sent it
nothing moved, an allowance set     → you granted permission
two out, one minted share in        → you added liquidity
an NFT in, minted out of nothing    → you minted it
a transfer of zero                  → someone is baiting your address book
```

That is the whole classifier. It has no list of routers, no ABI to fetch, and
no protocol it "supports". A swap on a DEX that launches tomorrow is still one
token out and one token in, so it still reads as a swap.

## What it does that an explorer does not

- **Says it in a sentence.** Not a method name — a sentence, from your side.
- **Reads the same transaction as anyone.** Change the address and the story
  changes with it, because the story was only ever about one address.
- **Finds what you left switched on.** Every allowance a wallet has granted and
  never taken back, checked against the contract so a spent one does not pad
  the list — and a button that revokes it. Your wallet signs; Kliner cannot.
- **Names the tricks by shape.** Zero-value transfers, unlimited allowances,
  tokens that arrive without your signature. None of it needs a blocklist, so
  none of it goes stale.

## Running it

```sh
npm test          # 105 checks on the reading, 20 on the page
npm run build     # folds everything into dist/kliner.html
npm run serve     # then open http://localhost:8787
npm run show      # prints how every fixture reads, as text
```

`dist/kliner.html` is one file with no dependencies. Open it by
double-clicking it; it works with no server at all.

## Layout

```
src/keccak.js    keccak-256, because Ethereum's hash is not SHA-3
src/hex.js       the shapes a node returns, and EIP-55 checksums
src/abi.js       the five events that carry value; topics computed, not pasted
src/flows.js     what moved, for one address
src/classify.js  from what moved, to what happened
src/say.js       from what happened, to a sentence
src/amount.js    256-bit integers a person can read
src/chains.js    the chains, their public endpoints, their wrapped token
src/rpc.js       a JSON-RPC client that batches and survives a bad endpoint
src/tokens.js    what a token calls itself, read off the contract
src/scan.js      one transaction, or a wallet's history and its allowances
src/wallet.js    the only thing Kliner asks a wallet to sign: a revoke
```

Every module is plain ESM with no dependencies. The only package in the
project is Playwright, and only so the tests can drive a real browser.

## Where it is honest about its limits

- **Free public endpoints cap how far back they will search.** The wallet view
  asks for a window, narrows its range when an endpoint refuses, and tells you
  what window it read. A wallet older than the window is not fully covered.
- **A router can hand you the native currency with no log at all.** When the
  numbers only add up that way, Kliner says the amount was read from the
  unwrap rather than pretending it saw it.
- **The event topics are computed from their signatures at load time** and the
  test suite checks them against the published values. They have not yet been
  checked against a live node — do that once on day one.
- **The 0.25% swap fee described in the plan is not built yet.** This is the
  reading half.

## What it never does

No account. No key. No server of ours. Nothing you paste leaves the page
except to the public node it reads from, and you can see which one at the
bottom of it.

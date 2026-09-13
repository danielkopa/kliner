# Kliner Guard

Reads what you are about to sign, before you sign it.

```
You are signing away every USDC you hold to 0xbaDc0F…5678.

  Nothing will show this happened
  This is a signature, not a transaction. It costs no gas, needs no
  confirmation on any chain, and will not appear in your history — so
  there will be nothing to notice afterwards.

! An allowance with no limit, signed rather than sent
! And it does not expire

            [ Stop it ]        [ Sign it anyway ]
```

## Why this is not the same as the others

Every other tool in this space sends your request to **their server**, simulates
it there, and returns a verdict — "risky", "suspicious", a colour. You cannot
check a verdict, and you have to trust the server with a record of everything
you were about to do.

Kliner Guard does not have a server.

The calls that empty wallets are a short list, their arguments are fixed-width
words, and every one of them decodes **on your own machine, offline**, with
certainty rather than opinion. So this extension asks for **no permissions**,
makes **no network request of any kind** — the build refuses if one appears —
and never says "safe": it says what a request does, or it says it cannot read
it, which is not the same thing.

## What it reads

**Transactions** — `approve`, `increaseAllowance`, `setApprovalForAll`,
`transfer`, `transferFrom`, the ERC-721 and ERC-1155 transfers, ERC-2612
`permit`, Permit2 `approve`, `transferOwnership`, and bundles it refuses to
guess at.

**Signatures, which is where wallets are actually emptied now** — ERC-2612
`Permit`, Permit2 `PermitSingle`, `PermitBatch` and `PermitTransferFrom`,
Seaport orders (including the ones that hand over an item for nothing, and the
ones written against a whole collection rather than one token), `personal_sign`
messages, and `eth_sign`, which no honest site has asked for in years.

It flags by **shape**, never by a list of bad addresses: no limit on an
allowance, no expiry on a permit, nothing coming back to you on an order, a
domain built for a different chain, structured data smuggled through the
plain-message door. A blocklist goes stale the day it ships. A shape does not.

## What it will not do

- It never alters a request. What the wallet receives is the object the site
  sent, unchanged — there is a test that fires a request through a real browser
  and compares the bytes.
- It never sees a key, a seed or a signature. Your wallet still does all of it.
- It sets no global and leaves no mark on the page. A drainer that can detect
  the guard is a drainer that behaves itself until the guard is gone.
- It does not tell you anything is safe.

## Running it

```sh
npm run build     # bundles the reader and draws the icons
npm test          # 88 checks on the reading, 21 driving the real extension in a real browser
npm run show      # prints how every known attack shape reads, as text
npm run demo      # serves the demo page on http://localhost:8788
```

**To install it:** open `chrome://extensions`, turn on Developer mode, choose
*Load unpacked*, and pick the `extension/` folder. Then open the demo page and
fire one.

## Layout

```
src/keccak.js     keccak-256; every selector below is computed from its
                  signature with it, never pasted from memory
src/calldata.js   the dangerous calls, read straight out of the hex
src/typed.js      EIP-712 requests: permits, Permit2, marketplace orders
src/request.js    the front door — a wallet request in, a reading out
src/warn.js       the sentence, and what is wrong with it
src/known.js      a small offline table of tokens, so amounts read properly
src/overlay.js    the panel, in a closed shadow root
extension/bridge.js  the wrapper, in the page, that alters nothing
```

## Known limits, stated rather than hidden

- **A bundled call cannot be read this way.** `multicall` and router `execute`
  pack several actions behind one confirmation, and reading them means
  simulating them, which means a server. Kliner Guard says it cannot read them
  instead of implying they are fine.
- **Decimals for unknown tokens.** Offline, it cannot ask a token how it counts,
  so an amount in a token outside `known.js` is shown in raw units and labelled
  as raw. "Everything, forever" needs no decimals, which is the case that
  matters.
- **The install prompt is frightening.** An extension that must sit between
  every site and your wallet has to be allowed to run on every site, and Chrome
  describes that as reading and changing all your data. That is why all of this
  is open: the reader is 50 kB, it is built from the files in `src/`, and the
  build fails if a network call appears in it.
- **Not yet audited by anyone but its own tests.**

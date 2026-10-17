# Kliner Cloud — contract between the Mac app and the server

Kliner (a macOS app) lets people claim a global `@username`, send a file to
another `@username` anywhere on the internet (end-to-end encrypted, original
bytes, no compression), and publish an opt-in public profile at
`https://kliner.app/@name`. The server also holds the beta waitlist and the
20 beta activation codes.

Server: one Cloudflare Worker (ES modules, plain JavaScript, no framework,
no npm runtime dependencies) with a D1 database (binding `DB`) and an R2
bucket (binding `FILES`). It answers on two hosts:

- `api.kliner.app` — the JSON API under `/v1/...`
- `kliner.app/@*` — the public profile pages (HTML)

On `*.workers.dev` (before the domain is wired) both work on the one host:
`/v1/...` and `/@name`.

Vars (wrangler.toml `[vars]`): `PUBLIC_URL = "https://kliner.app"`,
`MAX_BYTES = "5368709120"` (5 GiB of ciphertext per transfer),
`TRANSFER_DAYS = "7"`, `MAX_PENDING = "20"` (ready/uploading transfers a
sender may have at once).

All JSON is UTF-8. Every error is an HTTP status with
`{"error": "<code>", "message": "<one plain sentence a person can act on>"}`.
Every response carries `Cache-Control: no-store` except profile pages
(`public, max-age=60`). The app is native and needs no CORS. The three
addresses kliner.app's own page calls — `GET /v1/names/<name>`,
`POST /v1/claims` and `GET /v1/release` — answer any page: every answer
there, errors included, carries `Access-Control-Allow-Origin: *`, and an
`OPTIONS` preflight gets 204 with `Access-Control-Allow-Methods: GET, POST,
OPTIONS`, `Access-Control-Allow-Headers: Content-Type` and
`Access-Control-Max-Age: 86400`.

## Names

Lowercase. 3–20 characters, `[a-z0-9._]`, starts with a letter, no `..`,
does not end with `.`. Reserved: `kliner admin root support help system apple
everyone nobody api www about privacy terms beta waitlist profile settings
login signup me mail team staff`. Compared and stored lowercase.

One name a key: a Mac changes its name (`POST /v1/users/me/name`) rather
than registering a second one. A name can be **held** for a while, and is
then neither free nor anybody's:

- `held` — its owner changed it a moment ago. It is kept for that same key
  for 7 days (they can change back to it), then anyone may take it. One old
  name is kept a key at a time.
- `claimed` — somebody held it on kliner.app (`POST /v1/claims`), for 30
  days, for whoever has the code the site showed them.

## Keys (made on the Mac, never sent anywhere except the public halves)

- Signing: Ed25519 (CryptoKit `Curve25519.Signing`). Public key: raw 32 bytes.
- Box: X25519 (CryptoKit `Curve25519.KeyAgreement`). Public key: raw 32 bytes.

Binary values in JSON and headers are **base64url without padding**
("b64u" below). Hashes are lowercase hex.

## Every answer

Every response from the Worker, errors and profile pages included, carries
`X-Kliner: 1`. The app counts a response without it as no answer at all
(status 0, "Kliner cannot reach kliner.app right now"): the domain can point
somewhere else for a while, a parking page before the Worker is wired to it,
and that is not kliner.app saying no.

## Signed requests

Every endpoint marked (signed) needs three headers:

```
X-Kliner-User: <name>
X-Kliner-Time: <unix seconds, integer>
X-Kliner-Sig:  <b64u Ed25519 signature>
```

The signature is over the UTF-8 bytes of:

```
KLINER1\n<METHOD>\n<PATH>\n<TIME>\n<hex sha256 of the raw request body>
```

`METHOD` uppercase, `PATH` the URL path only (no host, no query), e.g.
`/v1/transfers/abc/parts/3`. An empty body hashes to
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

The server rejects (401 `bad_signature` / `stale`): unknown user, a time more
than 300 s from its clock, or a signature that does not verify with that
user's stored signing key. `POST /v1/users` is signed with the key being
registered (proof the caller holds it); the user does not exist yet.

## Endpoints

### Health
`GET /v1/health` → `{"ok": true, "version": "1"}`

### Names
`GET /v1/names/<name>` → `{"name": "dan", "free": true}` or
`{"name": "dan", "free": false, "reason": "taken" | "reserved" | "invalid", "message": "..."}`,
or for a held name `{"name": "dan", "free": false, "reason": "held" | "claimed",
"message": "...", "until": <unix>}`. Rate limited per IP (60/min).

### Holding a name on kliner.app (not signed)
`POST /v1/claims` body `{"name": "dan"}` (an `@` in front is forgiven), from
the site's page → 201 `{"name": "dan", "code": "K7M2Q-XPA4N", "expires": <unix>}`:
the name is held for 30 days for whoever has the code. The code is ten of
`ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/O, 1/I/L) as `XXXXX-XXXXX`; only its
sha256 is kept (of the code upper-cased, spaces and dashes left out, which
is how it is compared too), and it is shown once. 409 `taken` / `held` /
`claimed`, 400 `invalid` / `reserved`. Rate limited per IP: 10/min, and 3
holds an hour and 6 a day (429 `rate_limited` with `Retry-After`). The code is
given when registering the name (`claim` in `POST /v1/users`) or when a Mac
that has a name changes to it (`claim` in `POST /v1/users/me/name`). The
same hold is made from the name's own page, `kliner.app/@name`, with no
script (`POST /@name`, under "Profile page" below).

### Users
`POST /v1/users` (signed by the new key) body:
`{"name": "dan", "sign": "<b64u 32>", "box": "<b64u 32>", "device": "<≤64 chars>", "claim": "<code, only for a name held on kliner.app>"}`
- 201 `{"name": "dan", "created": 1790000000}`
- 200 same, when that name already belongs to this same signing key (idempotent)
- 409 `taken`, 400 `invalid` / `reserved`
- 409 `has_name` when this key already has another name (change it instead)
- 409 `held` (somebody's old name), 409 `claimed` (held on kliner.app, no
  code given), 403 `wrong_code`

`GET /v1/users/<name>` → `{"name", "sign", "box", "created"}`, or 404
`no_user`, or 404 `renamed` ("@dan changed their username. Ask them for the
new one.") while the name is kept for an owner who changed it. The new name
is not said.

`POST /v1/users/me/name` (signed) body `{"name": "daniel", "claim": "<code, for a name held on kliner.app>"}`
→ 200 `{"name": "daniel", "was": "dan", "until": <unix>}`. The same keys, a
new name: the profile and every transfer to or from the old name move to
it (so whoever sent a file waiting for it sees the new name in their
outbox); the old name is held for this key until `until` (7 days), and the
name held for it before, if any, is let go. Changing back to that old name
within the week is the same call. 400 `same` / `invalid` / `reserved`, 409
`taken` / `held` / `claimed`, 403 `wrong_code`, 429 `rate_limited` after 3
changes a day. From the 200 on, the Mac signs as the new name.

`DELETE /v1/users/me` (signed) → deletes the user, the profile, and every
transfer to or from them (R2 parts too); a name it was keeping is free at
once → `{"ok": true}`.

### Profile
`PUT /v1/profile` (signed) body (≤ 800 KB), every field optional:

```json
{
  "visible": true,
  "display": "Daniel",              // ≤ 60
  "bio": "Designer in Bratislava",  // ≤ 280
  "role": "Building Kliner",        // ≤ 60, what they do
  "place": "Bratislava",            // ≤ 60
  "work": [{"name": "Kliner", "when": "2026", "note": "A Mac that stays tidy",
            "url": "https://kliner.app"}],
                                    // ≤ 14; name ≤ 60, when ≤ 20, note ≤ 90,
                                    // url https only ≤ 200
  "links": [{"title": "Site", "url": "https://..."}],  // ≤ 5, https only, title ≤ 40, url ≤ 200
  "avatar": "data:image/jpeg;base64,...",   // ≤ 150 KB, jpeg or png only
  "mac": {"model": "MacBook Air", "chip": "Apple M2", "memory": "8 GB", "macos": "macOS 26.1", "storage": "228 GB"},
  "setup": {
    "wallpaper": "Sequoia Sunrise",
    "wallpaperThumb": "data:image/jpeg;base64,...",  // ≤ 330 KB, the
                                     // wallpaper as the Mac hands it over
                                     // (1400 across), not a thumbnail
    "trash": "data:image/png;base64,...",            // ≤ 28 KB, the bin
    "appearance": "dark",            // dark | light | auto
    "accent": "multicolor",          // ≤ 20
    "dock": ["Safari", {"name": "Figma", "icon": "data:image/png;base64,..."}],
                                     // ≤ 40 apps; a name (≤ 40), or a name with
                                     // the app's own icon (≤ 28 KB, jpeg or
                                     // png; 128 across, the size macOS gives)
    "dockAutohide": true,
    "desktop": "clear",              // clear | icons hidden | busy   (≤ 20)
    "apps": 142,                     // integer
    "walls": [{"name": "Pro Black", "thumb": "data:image/jpeg;base64,...",
               "on": true}]           // ≤ 8, name ≤ 80, thumb ≤ 60 KB,
                                      // `on` marks the one in use
  },
  "done": [{"what": "Sorted your downloads", "when": "Oct 9, 11:40"}],
                                     // ≤ 10, what ≤ 80, when ≤ 40 — the
                                     // lines `min undo --list` printed
  "stats": {"freedBytes": 1932735283, "tidied": 214, "cleanSince": "2026-09-01"},
  "since": "2026-09-30"
}
```

Strings are trimmed and length-checked; unknown fields are dropped; wrong
types are a 400 `invalid` naming the field. Stored as JSON. →
`{"ok": true, "url": "https://kliner.app/@dan"}` (from `PUBLIC_URL`).

`GET /v1/users/<name>/profile` → the stored profile JSON plus `"name"`,
only when `visible` is true; otherwise 404 `no_profile`.

`GET /@<name>` → an HTML page for that profile (404 page when missing or not
visible). Server-rendered, every user string HTML-escaped, `data:` images
only in `<img src>` after checking they are `data:image/(jpeg|png);base64,`
followed by base64 characters only. Response header
`Content-Security-Policy: default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`.
Design: one 715px column held between two rules that run the whole height
of the page, on near-black `#080808` with `#fafafa` ink, or `#fbfbfa` with
`#0a0a0a` ink when the system is light. Set in Geist, Kliner's own face,
subset to Latin plus Slovak and Czech and carried in the page as a `data:`
URL (the CSP allows no fetched font and no script at all).
Three rules make the frame, and each crosses the **whole window**, not only
the column: the hairline under the top strip, a 24px band of diagonal hatch
between one section and the next, and the hairline under a section's name.
The type is one scale, taken off that page: section names and the display
name 30px/36 (400 and 500), the line across the dots 20px/24 at -0.5px,
every label and value 14px/20, the small print 11px and 12px, body 16px/24.
Four greys and no more: `#fafafa` ink, `#d4d4d4` for a value, `#a3a3a3` for
a label, `#737373` for the quietest.
The top strip is the `kliner”` wordmark linking to `PUBLIC_URL`, their
`@name` beside it, and a "Get Kliner" button on the right. Then a field of
dots across the column with their bio in the middle of it; then the person
— their picture as a 120px square in a 1px frame, the display name,
`@name`, and the month they joined.
Then, each only when it has data, and each opening with its name over its
hairline — **the person first and the machine after**, which is the order
every page this one is drawn after reads in:
"Work" — what they have made, one row each: the name with an arrow when it
goes somewhere, what it is under it, and the year off to the right.
"Links" — the same row, the host where the year sits.
"Setup" — their screen, drawn to the same figures as the one Kliner's own
Home page draws (the page's `cqw` is that page's `em`: a hundredth of the
screen's width), so the bezel, the menu bar, the Dock and the icons come
out the size they are in the app: their wallpaper, a menu bar of shapes,
and along the bottom their Dock from the apps' own icons (at most 12, the
rest named only; square and whole, never re-cut; an app with no icon gets
the app's own letter tile), closed — when `setup.trash` came with it — by
the line macOS draws there and the bin. Without a wallpaper the screen is
drawn in the app's own default blue, and the Dock still stands on it.
The pictures are the real ones, at the size the page draws them on a Retina
screen: that is what the 800 KB is for, and why `wallpaperThumb` is no
longer a thumbnail.
Under it the facts as cells: a mark, what it is at 14px/400 in
`#a3a3a3`, and what it says under it at 14px/500 in `#d4d4d4`. "This Mac" — model, chip, memory, storage and system in the same
cells. "Wallpapers" — the ones they keep, four across, the picture itself with
its name under it and the one in use ringed. "With Kliner" — freed, tidied
and clean since, the number said out loud. "Done with Kliner" — what Kliner
has done here, newest first, in `min`'s own words with when beside each.

The cells are laid out as a row that wraps, each one 200px at least and free
to grow, so the last row fills the width and no cell is ever left standing
beside an empty box. A footer line "Made with Kliner". Works at phone width,
where the rules at the column's edges are dropped, and light and dark both
come from `prefers-color-scheme`.

A name with no public profile gets a page about the name instead, in the
same frame, with the name itself big where a person's picture and name
would be, `Cache-Control: no-store` and `<meta name="robots"
content="noindex">`:

- **free** (nobody has it and nothing holds it) → 200: "@name is free.",
  what holding it means, and one form, `POST /@name`, with a hidden `n`: a
  fresh random nonce (22 base64url characters) every time the page is
  drawn. This page alone is served with `form-action 'self'` in its CSP
  instead of `'none'`.
- **somebody's, page not public** → 404: "@name is on Kliner. Their page is
  not public.", how to send them a file, and where the owner turns the page
  on. Nothing of the hidden profile is on it.
- **held** on kliner.app → 200: until when, and that the code goes into
  Kliner. **renamed** → 404: "@name changed their username. Ask them for
  the new one." The new name is never shown.
- **reserved or not a name** → 404 "No profile here", with why.

`POST /@name` (`application/x-www-form-urlencoded`, `n=<nonce>`, 4 KB at
most) holds a free name from its page, under the same rules, counters and
answers as `POST /v1/claims`, and answers with a page, never JSON. Only from
a page on this host: `Sec-Fetch-Site: same-origin`, or with no
`Sec-Fetch-Site` an `Origin` that is this host or `PUBLIC_URL`; anything
else (another site, or a request that says nothing) is a 403 page that
holds nothing. The code is drawn from the nonce — SHA-256 of
`kliner-hold\n<round>\n<nonce>\n<name>`, bytes 248 and over skipped,
the rest mod 31 into the code alphabet, ten of them as XXXXX-XXXXX — so the
same form sent twice (a double click, a reload) asks for the same code and
is shown it again, without being counted again; a different form for a
name already held is a 409 page and no code. Like every code, only its
SHA-256 is kept. → 200 page: "@name is held for you.", the code once, and
the three steps (get Kliner, type the name, type the code). A missing or
malformed nonce is a 400 page ("That form is out of date"); taken, held,
claimed or counted out meanwhile is the name's page again with the reason,
at the status the JSON answer would have had.

### Transfers (store and forward, end-to-end encrypted)

The server never sees names, sizes of the plaintext or contents: it stores
opaque parts and an opaque header.

`POST /v1/transfers` (signed, sender) body
`{"to": "alice", "parts": 3, "bytes": 25165872, "header": "<b64u, ≤ 4096 chars>"}`
- `parts` 1…10000, `bytes` 1…MAX_BYTES (total ciphertext bytes of all parts)
- 404 `no_user` (recipient), 404 `renamed` (the recipient changed their
  name, see Users), 400 `self` (to yourself), 413 `too_big`,
  429 `too_many` (sender already has MAX_PENDING uploading/ready)
- 201 `{"id": "<22 char random b64u>", "expires": <unix>}` (status `uploading`)

`PUT /v1/transfers/<id>/parts/<n>` (signed, sender) body: raw bytes, 1 byte …
16 MiB + 64. n in 0…parts-1. Stored in R2 at `t/<id>/<n>`. Re-putting a
part replaces it. → `{"ok": true}`. 404 when the transfer is not the
sender's or not `uploading`.

`POST /v1/transfers/<id>/ready` (signed, sender) → checks every part is in R2
and the sizes add up to `bytes` (409 `incomplete` otherwise) → status `ready`
→ `{"ok": true}`.

`GET /v1/inbox` (signed) → `{"transfers": [{"id", "from", "parts", "bytes", "header", "created", "expires"}]}`
— status `ready`, recipient = caller, not expired, oldest first.

`GET /v1/outbox` (signed) → `{"transfers": [{"id", "to", "status", "parts", "bytes", "created", "done"}]}`
— the caller's sends of the last TRANSFER_DAYS days, newest first. Status is
one of `uploading ready received declined cancelled expired`.

`GET /v1/transfers/<id>/parts/<n>` (signed, recipient, status `ready`) →
the raw bytes (`application/octet-stream`, `Content-Length`).

`POST /v1/transfers/<id>/received` (signed, recipient) → status `received`,
`done` = now, R2 parts deleted → `{"ok": true}`.

`POST /v1/transfers/<id>/decline` (signed, recipient) → status `declined`,
parts deleted.

`DELETE /v1/transfers/<id>` (signed, sender) → status `cancelled`, parts deleted.

Cron (hourly, `[triggers] crons = ["17 * * * *"]`): every transfer past
`expires` that is `uploading` or `ready` → parts deleted, status `expired`;
rows older than 30 days → deleted; holds past `expires` → deleted; rate-limit
rows older than a day → deleted (a counter can cover a day).

### Beta and waitlist (not signed)

`POST /v1/beta/activate` body `{"code": "KLNR-7F3K-Q9WX", "device": "<≤64>"}`.
The code is normalised (uppercase, spaces and dashes removed) and its
sha256 hex looked up in `beta_codes`.
- unknown → 404 `unknown_code`
- unused → marked used by that device → `{"ok": true}`
- used by the same device → `{"ok": true}`
- used by another device → 409 `used_code`
Rate limited per IP (10/min).

`POST /v1/waitlist` body `{"email": "a@b.co"}` (≤ 120, a plausible address)
→ `{"ok": true, "position": 42}`; the same address again returns its
original position. Rate limited per IP (10/min).

### The app (not signed)

What people download is the disk image: open it, drag Kliner onto
Applications. `deploy.sh` puts up three R2 objects from the owner's Mac:
`releases/Kliner.dmg` (the image `app/build.sh` made), `releases/latest.json`
(`{"version": "0.62.0", "dmg": {"bytes": 6301234, "sha256": "<64 hex>"},
"published": "2026-10-16T12:00:00Z"}`, the version as `VERSION` writes it)
and `releases/Kliner.app.zip` (the zip it used to be, kept for the links
already out there). Nothing about who downloads them is kept.

`GET /download` → 302 to `/download/Kliner-<version>.dmg` when the image and
its note are up, else to `/download/Kliner.app.zip`.

`GET /download/Kliner-<version>.dmg` (any version that looks like one, or
`/download/Kliner.dmg`) → always the newest image, as
`application/x-apple-diskimage` with
`Content-Disposition: attachment; filename="Kliner-<version>.dmg"` (the
version that is up), `Cache-Control: public, max-age=300` and its ETag; 404
`not_found` until one has been put up, and for any other name under
`/download/`.

`GET /download/Kliner.app.zip` → the zip, as `application/zip` with
`Content-Disposition: attachment; filename="Kliner.app.zip"`, the same caching;
404 `not_found` until one has been put up. HEAD answers both the same without
the body.

`GET /v1/release` → `{"version": "0.62.0", "dmg": {"url":
"/download/Kliner-0.62.0.dmg", "bytes": 6301234, "sha256": "<64 hex>"},
"zip": {"url": "/download/Kliner.app.zip", "bytes": 5200000}, "published":
"2026-10-16T12:00:00Z"}`, any part `null` when it is not up, with
`Access-Control-Allow-Origin: *` (the site is on another host) and
`Cache-Control: public, max-age=60`.

## File encryption (the Mac does this; the Node test client does the same)

- File key `K`: 32 random bytes.
- Chunk size: 8 MiB of plaintext (8388608). `parts = max(1, ceil(size/chunk))`.
- Part `n` = ChaCha20-Poly1305 of chunk `n` with key `K` and nonce
  `00 00 00 00 || uint64 big-endian n` (12 bytes), sent as CryptoKit's
  `combined` layout: `nonce(12) || ciphertext || tag(16)`. The receiver checks
  the nonce equals the expected one for `n` before opening.
- Header (the `header` field): b64u of the UTF-8 JSON
  `{"v":1,"epk":"<b64u ephemeral X25519 public>","box":"<b64u combined>"}` where
  - `shared = X25519(ephemeral private, recipient box public)`
  - `wrap = HKDF-SHA256(ikm = shared, salt = ephemeral public || recipient box public (64 bytes), info = "kliner-file-v1", length 32)`
  - `box = ChaCha20-Poly1305(wrap, random 12-byte nonce)` of the UTF-8 JSON
    `{"k":"<b64u K>","name":"poster.mov","size":1234,"sha256":"<hex of plaintext>","chunk":8388608,"from":"dan"}`,
    in the `combined` layout.
- The receiver writes the plaintext to Downloads under its own name (never
  a path), checks the size and the sha256, then calls `received`.

## D1 schema

```sql
CREATE TABLE IF NOT EXISTS users (name TEXT PRIMARY KEY, sign TEXT NOT NULL, box TEXT NOT NULL, device TEXT, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS profiles (name TEXT PRIMARY KEY, json TEXT NOT NULL, visible INTEGER NOT NULL DEFAULT 0, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS transfers (id TEXT PRIMARY KEY, sender TEXT NOT NULL, recipient TEXT NOT NULL, parts INTEGER NOT NULL, bytes INTEGER NOT NULL, header TEXT NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL, expires INTEGER NOT NULL, done INTEGER);
CREATE INDEX IF NOT EXISTS transfers_to ON transfers(recipient, status);
CREATE INDEX IF NOT EXISTS transfers_from ON transfers(sender, created);
CREATE TABLE IF NOT EXISTS beta_codes (hash TEXT PRIMARY KEY, device TEXT, used INTEGER);
CREATE TABLE IF NOT EXISTS waitlist (email TEXT PRIMARY KEY, position INTEGER NOT NULL, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS hits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, window INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS users_sign ON users(sign);
CREATE TABLE IF NOT EXISTS holds (name TEXT PRIMARY KEY, kind TEXT NOT NULL, sign TEXT, code TEXT, created INTEGER NOT NULL, expires INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS holds_sign ON holds(sign);
```

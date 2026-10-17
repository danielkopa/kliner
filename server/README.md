# Kliner Cloud

The server behind Kliner's online features: one Cloudflare Worker (plain
JavaScript, no dependencies) with a D1 database and an R2 bucket. It gives
the Mac app

- global `@names`, with the public keys the app signs requests with and
  receives files with — changed in place (the old one kept for its owner a
  week), or held from the site for 30 days with a code,
- end-to-end encrypted file transfers between `@names` (store and forward,
  kept up to 7 days),
- opt-in public profiles at `https://kliner.app/@name`; a name nobody has can
  be held from that same address for 30 days, with a code Kliner then asks for.

The app no longer asks for a beta code. The beta endpoints, `gen-codes.mjs`
and the `beta_codes` and `waitlist` tables are still here, unused, and
`deploy.sh` no longer loads codes.

`SPEC.md` is the contract with the Mac app (endpoints, signing, file format).

## What it stores

| Where | What |
| --- | --- |
| `users` | name, public signing key, public box key, a device label, date |
| `profiles` | the profile the person chose to publish, as JSON |
| `transfers` | sender, recipient, part count, total encrypted size, the sealed header, status, times |
| R2 `t/<id>/<n>` | the encrypted parts, deleted once a transfer is received, declined, cancelled or expired |
| `beta_codes` | the sha256 of each code, and which device used it |
| `waitlist` | email address, position, date |
| `hits` | request counters for rate limits (per IP, or per key for name changes), deleted after a day |
| `holds` | a name kept for a while: an old one for its owner's key for 7 days, or one held on kliner.app for 30 days with the sha256 of its code |

**File contents and file names are end-to-end encrypted on the Mac and are
never readable by the server.** Each file gets its own random key; the parts
are sealed with ChaCha20-Poly1305 and the key, name, size and checksum travel
in a header sealed to the recipient's X25519 key. Private keys never leave
the Mac. The server only sees who sends to whom, when, and the total
encrypted size. Transfer rows are deleted 30 days after they were created.

## Deploy

You need a Cloudflare account (the free plan is enough; turn on R2 once in
the dashboard under R2 Object Storage) and Node.js 18 or newer.

```sh
bash ~/nimo/server/deploy.sh   # the first time, the browser opens to log in
```

`deploy.sh` logs in with wrangler's own browser login when it has to,
creates the D1 database `kliner` (and writes its id into
`wrangler.toml`), creates the R2 bucket `kliner-transfers`, applies
`schema.sql`, deploys, wires kliner.app when the account
has that zone, checks `/v1/health`, and writes `cloud = <base URL>` into
`~/.nimo/config` and into `server/cloud.url`, so the Mac app finds the server.
`app/build.sh` writes that address into the app it builds, so a copy opened on
any other Mac talks to the same server. When the build has made
`app/build/Kliner-<version>.dmg` and `app/build/Kliner.app.zip` (build first
with `bash ~/nimo/app/install-app.sh`), `deploy.sh` puts them up too, with a
note of the version (`releases/latest.json`): anyone can download the disk
image from `<base URL>/download`, saved as `Kliner-<version>.dmg`, and
`<base URL>/v1/release` says which version it is. It only uses wrangler's own
login and is safe to run again. Several Cloudflare
accounts: it asks which one (or set `CLOUDFLARE_ACCOUNT_ID`).

Logs: `npx wrangler tail kliner-api`. Settings are the `[vars]` in
`wrangler.toml`: `PUBLIC_URL`, `MAX_BYTES`, `TRANSFER_DAYS`, `MAX_PENDING`.

## Beta codes (unused)

`node gen-codes.mjs` writes 20 codes to **`beta-codes.local.txt`** and their
hashes to `beta-codes.sql`; `deploy.sh` no longer loads them. Keep both files
private: they are in `.gitignore`, and the short codes can be recovered from
their unsalted hashes.

## Waitlist

```sh
npx wrangler d1 execute kliner --remote --command "SELECT * FROM waitlist ORDER BY position"
```

## Wiring kliner.app

The two routes, `api.kliner.app` (custom domain, the API) and `kliner.app/@*`
(profile pages on the main site), sit **commented out** at the bottom of
`wrangler.toml`, between `# >>> domain routes` and `# <<< domain routes`. A
Cloudflare account without the kliner.app zone cannot deploy routes, so they
are off by default and the Worker runs on `kliner-api.<you>.workers.dev`,
where `/v1/...` and `/@name` both work.

When `kliner.app`'s nameservers point to Cloudflare, `deploy.sh` also writes
`wrangler.domain.toml` (a copy of `wrangler.toml` with that block switched on)
and deploys it, so `wrangler.toml` stays the only file you edit. To wire it:

1. Add `kliner.app` to the same Cloudflare account and switch its nameservers.
2. Leave `api.kliner.app` without a DNS record (the custom domain creates one;
   wrangler asks before replacing an existing one). `kliner.app` itself needs
   its usual proxied (orange cloud) record for the website.
3. Run `./deploy.sh` again (`--domain` skips the nameserver check,
   `--no-domain` never touches the routes).

The app then uses `https://api.kliner.app` and profiles live at
`https://kliner.app/@name`.

## Tests

```sh
npm install
npm test               # node test/e2e.mjs
```

The e2e test starts `wrangler dev` itself with local D1 and R2 in a temp
dir, runs every endpoint and a full 20 MiB encrypted transfer between two
users, and exits non-zero on any failure. `test/client.mjs` is a reference
client (Node built-in crypto only) with the exact signing and file encryption
the Mac app uses.

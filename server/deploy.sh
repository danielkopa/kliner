#!/usr/bin/env bash
# Kliner Cloud deploy, for the owner's Mac. One command, from anywhere:
#
#     bash ~/nimo/server/deploy.sh
#
# What it does, each step checking first so it is safe to run again:
#   1. checks node/npx and that you are logged in to Cloudflare. If not, it
#      opens the browser to log in (wrangler's own login: this script never
#      sees a password or a token)
#   2. creates the D1 database "kliner" if missing and writes its id into wrangler.toml
#   3. creates the R2 bucket "kliner-transfers" if missing
#   4. applies schema.sql
#   5. deploys the Worker (and, when the account has the kliner.app zone, the
#      api.kliner.app + kliner.app/@* routes via wrangler.domain.toml)
#   6. finds the base URL that answers and writes `cloud = <url>` into ~/.nimo/config
#   7. puts the disk image app/build/Kliner-<version>.dmg up for anyone to
#      download at <url>/download, with the zip beside it and a note of the
#      version for /v1/release, when the app has been built
#      (bash ~/nimo/app/install-app.sh)
#
# Options:  --domain     try the kliner.app routes even if the DNS check says no
#           --no-domain  never touch the kliner.app routes
# Several Cloudflare accounts? It asks which one, or set CLOUDFLARE_ACCOUNT_ID.

set -euo pipefail

cd "$(dirname "$0")"

DB_NAME="kliner"
BUCKET="kliner-transfers"
ZONE="kliner.app"
API_HOST="api.kliner.app"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok() { printf '    \033[32mok\033[0m  %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() {
  printf '\n\033[31mStopped:\033[0m %s\n' "$*" >&2
  exit 1
}

DOMAIN_MODE="auto"
for arg in "$@"; do
  case "$arg" in
    --domain) DOMAIN_MODE="yes" ;;
    --no-domain) DOMAIN_MODE="no" ;;
    -h | --help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *) die "Unknown option \"$arg\". Use --domain, --no-domain or --help." ;;
  esac
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kliner-deploy.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# No usage metrics from this script's wrangler runs.
export WRANGLER_SEND_METRICS=false

# wrangler 3, fetched by npx on first use (the config and commands here are written for it).
wr() { npx --yes wrangler@3 "$@"; }

# ---------------------------------------------------------------------------
step "Checking tools"
command -v node >/dev/null 2>&1 || die "Node.js is not installed. Install the LTS version from https://nodejs.org, then run ./deploy.sh again."
command -v npx >/dev/null 2>&1 || die "npx is missing (it comes with Node.js). Reinstall Node.js from https://nodejs.org."
command -v curl >/dev/null 2>&1 || die "curl is missing. Install the Xcode command line tools: xcode-select --install"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 18 ] || die "Node.js $(node --version) is too old; wrangler needs 18 or newer. Update it from https://nodejs.org."
ok "node $(node --version), npx $(npx --version)"
note "The first run downloads wrangler 3 through npx; that can take a minute."

# ---------------------------------------------------------------------------
step "Checking your Cloudflare login"
WHO="$(wr whoami 2>&1)" && WHO_OK=1 || WHO_OK=0
if grep -qi "not authenticated" <<<"$WHO"; then
  [ -t 0 ] || die "You are not logged in to Cloudflare. Run this in Terminal: it opens the browser to log in."
  note "Not logged in yet. The browser opens now: log in to Cloudflare (a free account is enough) and allow wrangler."
  wr login || die "The Cloudflare login did not finish. Run this again to try once more."
  WHO="$(wr whoami 2>&1)" && WHO_OK=1 || WHO_OK=0
  if grep -qi "not authenticated" <<<"$WHO"; then
    die "Still not logged in to Cloudflare. Run this again to try once more."
  fi
fi
if [ "$WHO_OK" != 1 ]; then
  printf '%s\n' "$WHO"
  die "\"wrangler whoami\" failed (see above). Check your internet connection and try again."
fi
ACCOUNTS="$(grep -Eo '[0-9a-f]{32}' <<<"$WHO" | sort -u || true)"
ACCOUNT_COUNT="$(grep -c . <<<"$ACCOUNTS" || true)"
if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ "$ACCOUNT_COUNT" -gt 1 ]; then
  printf '%s\n' "$WHO" | sed -n '/Account Name/,/┘/p'
  [ -t 0 ] || die "This login has several Cloudflare accounts. Run again with CLOUDFLARE_ACCOUNT_ID=<one of the ids above> ./deploy.sh"
  CHOSEN=""
  read -r -p "    Several accounts. Paste the Account ID to deploy to: " CHOSEN || true
  grep -qx "$CHOSEN" <<<"$ACCOUNTS" || die "\"$CHOSEN\" is not one of the account ids listed above."
  export CLOUDFLARE_ACCOUNT_ID="$CHOSEN"
fi
ok "$(grep -o 'logged in with .*' <<<"$WHO" | head -n1 || echo "logged in")"

# ---------------------------------------------------------------------------
step "D1 database \"$DB_NAME\""
# Prints the uuid of the database called $DB_NAME from `wrangler d1 list --json`, or nothing.
d1_id() {
  local list
  list="$(wr d1 list --json 2>"$TMP/d1-list.err")" || {
    cat "$TMP/d1-list.err" >&2
    die "Could not list your D1 databases (see above)."
  }
  node -e '
    let text = require("fs").readFileSync(0, "utf8");
    const start = text.indexOf("[");
    if (start < 0) process.exit(0);
    const db = JSON.parse(text.slice(start)).find((d) => d.name === process.argv[1]);
    if (db) process.stdout.write(String(db.uuid || db.id || ""));
  ' "$DB_NAME" <<<"$list"
}
DB_ID="$(d1_id)"
if [ -z "$DB_ID" ]; then
  note "Not found, creating it..."
  wr d1 create "$DB_NAME"
  DB_ID="$(d1_id)"
  [ -n "$DB_ID" ] || die "Created the database but could not read its id. Run ./deploy.sh again."
  ok "created $DB_NAME ($DB_ID)"
else
  ok "exists ($DB_ID)"
fi
# Write the id into wrangler.toml (replaces the placeholder or an older id; keeps the rest).
# shellcheck disable=SC2016 # ${head} is JavaScript, not shell
node -e '
  const fs = require("fs");
  const [file, id] = process.argv.slice(1);
  const before = fs.readFileSync(file, "utf8");
  const after = before.replace(/^(database_id\s*=\s*)"[^"]*"/m, (_, head) => `${head}"${id}"`);
  if (after !== before) fs.writeFileSync(file, after);
' wrangler.toml "$DB_ID"
grep -q "database_id = \"$DB_ID\"" wrangler.toml || die "Could not write the database id into wrangler.toml."
ok "wrangler.toml has database_id = \"$DB_ID\""

# ---------------------------------------------------------------------------
step "R2 bucket \"$BUCKET\""
if wr r2 bucket info "$BUCKET" >/dev/null 2>&1; then
  ok "exists"
else
  note "Not found, creating it..."
  if ! wr r2 bucket create "$BUCKET" >"$TMP/r2.out" 2>&1; then
    cat "$TMP/r2.out"
    grep -qi "already exists" "$TMP/r2.out" ||
      die "Could not create the R2 bucket. If R2 is not enabled on this account yet, open dash.cloudflare.com > R2 Object Storage, finish the one-time setup, then run ./deploy.sh again."
  fi
  ok "created $BUCKET"
fi

# ---------------------------------------------------------------------------
step "Tables"
wr d1 execute "$DB_NAME" --remote --yes --file schema.sql
ok "schema.sql applied"

# ---------------------------------------------------------------------------
step "Deploying the Worker"
# wrangler stays attached to the terminal so it can ask things (a workers.dev
# subdomain on a new account, DNS conflicts for custom domains). Its log file
# holds the same output, so the workers.dev address is read from there.
wr_logged() {
  local log="$1"
  shift
  WRANGLER_LOG_PATH="$log" wr "$@"
}
wr_logged "$TMP/deploy.log" deploy
WORKERS_URL="$(grep -Eo 'https://[A-Za-z0-9.-]+\.workers\.dev' "$TMP/deploy.log" | head -n1 || true)"
if [ -n "$WORKERS_URL" ]; then
  ok "deployed: $WORKERS_URL"
else
  note "Deployed, but the workers.dev address was not in wrangler's output."
fi

# ---------------------------------------------------------------------------
# kliner.app routes: only when the zone is on Cloudflare (its nameservers say
# so), or when asked with --domain. A fresh account without the zone skips this.
zone_on_cloudflare() {
  local ns=""
  if command -v dig >/dev/null 2>&1; then
    ns="$(dig +short NS "$ZONE" 2>/dev/null || true)"
  elif command -v nslookup >/dev/null 2>&1; then
    ns="$(nslookup -type=NS "$ZONE" 2>/dev/null || true)"
  fi
  grep -qi 'ns\.cloudflare\.com' <<<"$ns"
}

DOMAIN_OK="no"
if [ "$DOMAIN_MODE" = "yes" ] || { [ "$DOMAIN_MODE" = "auto" ] && zone_on_cloudflare; }; then
  step "Wiring $ZONE: $API_HOST and $ZONE/@*"
  # wrangler.toml with the commented routes block switched on.
  {
    echo "# Generated by deploy.sh from wrangler.toml (routes switched on). Edit wrangler.toml, not this file."
    awk '
      /^# >>> domain routes/ { inside = 1; next }
      /^# <<< domain routes/ { inside = 0; next }
      inside { sub(/^# ?/, ""); print; next }
      { print }
    ' wrangler.toml
  } >wrangler.domain.toml
  if wr_logged "$TMP/domain.log" deploy -c wrangler.domain.toml; then
    if grep -q "$API_HOST" "$TMP/domain.log"; then
      DOMAIN_OK="yes"
      ok "routes attached"
    else
      note "wrangler skipped the custom domain (see above); the workers.dev address still works."
    fi
    [ -n "$WORKERS_URL" ] || WORKERS_URL="$(grep -Eo 'https://[A-Za-z0-9.-]+\.workers\.dev' "$TMP/domain.log" | head -n1 || true)"
  else
    note "Could not attach the $ZONE routes (is $ZONE on this Cloudflare account, and is $API_HOST free of other DNS records?)."
    note "Nothing is broken: the Worker runs on workers.dev. Fix that, then run ./deploy.sh again."
  fi
elif [ "$DOMAIN_MODE" = "no" ]; then
  note "Skipped the $ZONE routes (--no-domain)."
else
  note "$ZONE is not on Cloudflare yet, so its routes were skipped. See README.md, \"Wiring kliner.app\"."
fi

# ---------------------------------------------------------------------------
step "Finding the address that answers"
# Waits up to $2 seconds for $1/v1/health to answer {"ok":true,...}.
answers() {
  local url="$1" waited=0
  while [ "$waited" -le "$2" ]; do
    if curl -fsS --max-time 10 "$url/v1/health" 2>/dev/null | grep -q '"ok":true'; then
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  return 1
}
BASE=""
if [ "$DOMAIN_OK" = "yes" ]; then
  note "Trying https://$API_HOST (a new custom domain can take a few minutes)..."
  if answers "https://$API_HOST" 90; then BASE="https://$API_HOST"; fi
fi
# Only when there is no custom domain. Once there is one, the workers.dev
# address stops answering the moment the domain takes over — and an app that
# was handed that address keeps calling a host that no longer exists and can
# reach nothing at all. So a configured domain is always the address written
# down, answering yet or not: it is where the Worker will be in a minute.
if [ -z "$BASE" ] && [ -n "$WORKERS_URL" ] && [ "$DOMAIN_OK" != "yes" ]; then
  note "Trying $WORKERS_URL (a brand-new workers.dev subdomain can take a few minutes)..."
  if answers "$WORKERS_URL" 120; then BASE="$WORKERS_URL"; fi
fi
if [ -z "$BASE" ]; then
  if [ "$DOMAIN_OK" = "yes" ]; then
    BASE="https://$API_HOST"
  elif [ -n "$WORKERS_URL" ]; then
    BASE="$WORKERS_URL"
  elif [ -t 0 ]; then
    read -r -p "    Paste the Worker's address (https://kliner-api.<you>.workers.dev): " BASE || true
  fi
  [ -n "$BASE" ] || die "Could not find the Worker's address. Look it up in dash.cloudflare.com > Workers, then put it in ~/.nimo/config as: cloud = <address>"
  note "$BASE did not answer yet. It is deployed; give it a few minutes (check: curl $BASE/v1/health)."
  [ "$DOMAIN_OK" = "yes" ] && note "This is the address Kliner is given on purpose: workers.dev stops answering once the domain takes over."
else
  ok "$BASE/v1/health answers"
fi
BASE="${BASE%/}"

# ---------------------------------------------------------------------------
step "Pointing the Mac app at it (~/.nimo/config)"
CONFIG_DIR="$HOME/.nimo"
CONFIG="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG" ] || : >"$CONFIG"
# Replace the first `cloud =` line (drop any repeats), keep every other line as is.
awk -v url="$BASE" '
  /^[[:space:]]*cloud[[:space:]]*=/ { if (!done) print "cloud = " url; done = 1; next }
  { print }
  END { if (!done) print "cloud = " url }
' "$CONFIG" >"$TMP/config"
cat "$TMP/config" >"$CONFIG" # rewrite in place, so the file keeps its permissions
ok "$CONFIG: cloud = $BASE"
# and beside this script, for the app's build: every copy of Kliner built
# from here, on this Mac or on GitHub's, talks to this same Worker
printf '%s\n' "$BASE" > cloud.url
ok "server/cloud.url: $BASE"

# ---------------------------------------------------------------------------
# What the app's build made, for anyone: the disk image people download
# (served at $BASE/download, saved as Kliner-<version>.dmg), the zip it used to
# be (kept for the links already out there), and a note of which version they
# are, which /v1/release reads. Built after this script has written `cloud =`,
# the app inside them talks to this same Worker on any Mac it is opened on.
step "Putting Kliner up for download"
VERSION="$(tr -d ' \n' < ../VERSION)"
DMG="../app/build/Kliner-$VERSION.dmg"
ZIP="../app/build/Kliner.app.zip"
DOWNLOAD=""
if [ -f "$ZIP" ]; then
  if wr r2 object put "$BUCKET/releases/Kliner.app.zip" --file "$ZIP" --content-type application/zip >"$TMP/zip.log" 2>&1; then
    DOWNLOAD="$BASE/download"
    ok "$BASE/download/Kliner.app.zip ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
  else
    cat "$TMP/zip.log" >&2
    note "The zip did not go up (see above). Everything else is deployed; run this again to retry."
  fi
else
  note "No app/build/Kliner.app.zip yet. Build the app (bash ~/nimo/app/install-app.sh), then run this again."
fi
if [ -f "$DMG" ]; then
  # the image first, then the note that points at it, so /download never
  # names a version whose image is not up yet
  if wr r2 object put "$BUCKET/releases/Kliner.dmg" --file "$DMG" --content-type application/x-apple-diskimage >"$TMP/dmg.log" 2>&1; then
    BYTES="$(wc -c < "$DMG" | tr -d ' ')"
    SHA="$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"
    printf '{"version": "%s", "dmg": {"bytes": %s, "sha256": "%s"}, "published": "%s"}\n' \
      "$VERSION" "$BYTES" "$SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMP/latest.json"
    if wr r2 object put "$BUCKET/releases/latest.json" --file "$TMP/latest.json" --content-type application/json >"$TMP/latest.log" 2>&1; then
      DOWNLOAD="$BASE/download"
      ok "$DOWNLOAD → Kliner-$VERSION.dmg ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
    else
      cat "$TMP/latest.log" >&2
      note "The disk image is up but the note of its version is not (see above), so /download still hands out the zip. Run this again to retry."
    fi
  else
    cat "$TMP/dmg.log" >&2
    note "The disk image did not go up (see above). Everything else is deployed; run this again to retry."
  fi
else
  note "No app/build/Kliner-$VERSION.dmg yet. Build the app (bash ~/nimo/app/install-app.sh), then run this again."
fi

# ---------------------------------------------------------------------------
PAGES="$BASE"
[ "$DOMAIN_OK" = "yes" ] && PAGES="https://$ZONE"
cat <<EOF

Done. Kliner Cloud is live.
  API          $BASE/v1/health
  Profiles     $PAGES/@<name>
  Download     ${DOWNLOAD:-not up yet (build the app, then run this again)}
  Logs         npx wrangler tail kliner-api
EOF

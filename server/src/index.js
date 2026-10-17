// Kliner Cloud: one Cloudflare Worker for
//   - the JSON API under /v1/... (names and the holds on them, users,
//     profiles, encrypted transfers, beta codes, waitlist), and
//   - the public profile pages at /@name.
// Both answer on any host, so *.workers.dev works before the domain is wired.
//
// Plain JavaScript, WebCrypto only, no dependencies. SPEC.md is the
// contract with the Mac app: do not change paths, headers, the signing string
// or JSON shapes here without changing it there too.
//
import { GEIST } from "./geist.js";

// Bindings: DB (D1), FILES (R2). Vars: PUBLIC_URL, MAX_BYTES, TRANSFER_DAYS,
// MAX_PENDING (all strings, from wrangler.toml).

const API_VERSION = "1";
const CLOCK_SKEW = 300; // seconds X-Kliner-Time may differ from our clock
const MAX_JSON_BODY = 64 * 1024; // any ordinary JSON request
const MAX_PROFILE_BODY = 800 * 1024; // PUT /v1/profile
const MAX_PART_BYTES = 16 * 1024 * 1024 + 64; // one encrypted part
const MAX_PARTS = 10000;
const MAX_HEADER_CHARS = 4096;
const KEEP_ROWS_DAYS = 30; // the cron deletes finished transfer rows older than this
const LIST_LIMIT = 500; // most rows inbox/outbox return in one response
const CRON_BATCH = 50; // expired transfers handled per round (stays under D1's 100 bound values)
const CRON_ROUNDS = 4; // rounds per cron run; the rest waits for the next hour
const RENAME_HOLD_DAYS = 7; // a name you leave stays yours this long
const CLAIM_HOLD_DAYS = 30; // a name held on kliner.app waits this long for its code
const RENAMES_PER_DAY = 3;
const CLAIMS_PER_HOUR = 3; // per network address
const CLAIMS_PER_DAY = 6;
// The code kliner.app shows for a held name: ten of these, no 0/O, 1/I/L.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

const RESERVED = new Set(
  ("kliner admin root support help system apple everyone nobody api www about privacy " +
    "terms beta waitlist profile settings login signup me mail team staff").split(" "),
);

const PROFILE_CSP =
  "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; " +
  "base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
// A free name's page: the same, and its one form may post to this host.
const HOLD_CSP = PROFILE_CSP.replace("form-action 'none'", "form-action 'self'");

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

export default {
  async fetch(request, env, ctx) {
    let response;
    try {
      response = await handle(request, env, ctx);
    } catch (err) {
      if (err instanceof HttpError) {
        response = errorResponse(err.status, err.code, err.message, err.headers);
      } else {
        console.error("unhandled error:", err && err.stack ? err.stack : err);
        response = errorResponse(500, "server_error", "Something went wrong on our side. Please try again in a minute.");
      }
    }
    // HEAD gets the same status and headers, without the body.
    if (request.method === "HEAD") response = new Response(null, response);
    // Every answer says it is Kliner's. The app counts an answer without this
    // as no answer at all: the name can point somewhere else for a while (a
    // parking page, before the Worker is wired to it), and that is not
    // kliner.app saying no.
    response = new Response(response.body, response);
    response.headers.set("X-Kliner", "1");
    // The site (kliner.app) checks and holds names from another host than
    // the API's, errors included, so a page can read why it was turned away.
    if (openToPages(new URL(request.url).pathname)) response.headers.set("Access-Control-Allow-Origin", "*");
    return response;
  },

  // Hourly (see [triggers] in wrangler.toml). Awaited rather than waitUntil,
  // so the run counts as finished only when the cleanup is really done.
  async scheduled(controller, env, ctx) {
    await cleanup(env);
  },
};

class HttpError extends Error {
  constructor(status, code, message, headers) {
    super(message);
    this.status = status;
    this.code = code;
    this.headers = headers;
  }
}

function fail(status, code, message, headers) {
  throw new HttpError(status, code, message, headers);
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

const ROUTES = [
  ["GET", "/v1/health", health],
  ["GET", "/v1/names/:name", checkName],
  ["POST", "/v1/users", registerUser],
  ["DELETE", "/v1/users/me", deleteMe],
  ["POST", "/v1/users/me/name", renameMe],
  ["POST", "/v1/claims", claimName],
  ["GET", "/v1/users/:name", getUser],
  ["GET", "/v1/users/:name/profile", getProfile],
  ["PUT", "/v1/profile", putProfile],
  ["POST", "/v1/transfers", createTransfer],
  ["DELETE", "/v1/transfers/:id", cancelTransfer],
  ["PUT", "/v1/transfers/:id/parts/:n", putPart],
  ["GET", "/v1/transfers/:id/parts/:n", getPart],
  ["POST", "/v1/transfers/:id/ready", markReady],
  ["POST", "/v1/transfers/:id/received", markReceived],
  ["POST", "/v1/transfers/:id/decline", declineTransfer],
  ["GET", "/v1/inbox", inbox],
  ["GET", "/v1/outbox", outbox],
  ["POST", "/v1/beta/activate", betaActivate],
  ["POST", "/v1/waitlist", joinWaitlist],
  ["GET", "/v1/release", release],
  ["GET", "/download", downloadApp],
  ["GET", "/download/Kliner.app.zip", downloadApp],
  ["GET", "/download/:file", downloadImage],
].map(([method, pattern, handler]) => ({ method, parts: pattern.split("/"), handler }));

async function handle(request, env, ctx) {
  const url = new URL(request.url);
  const path = url.pathname;
  // HEAD is answered like GET (the body is dropped in fetch above).
  const method = request.method === "HEAD" ? "GET" : request.method;

  // A page on kliner.app asking whether it may send a JSON body here.
  if (method === "OPTIONS" && openToPages(path)) {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Max-Age": "86400",
      },
    });
  }

  // Public profile pages: /@name on any host. A name nobody has can be held
  // from its page, with the form on it (POST).
  if (path.startsWith("/@")) {
    const raw = path.slice(2).replace(/\/$/, "");
    if (method === "POST") return holdPage({ request, env, ctx, url }, raw);
    if (method !== "GET") fail(405, "method_not_allowed", "A name's page can be read, or a free name held from it.", { Allow: "GET, HEAD, POST" });
    return profilePage({ request, env, ctx, url }, raw);
  }

  const segments = path.split("/");
  const allowed = [];
  for (const route of ROUTES) {
    const params = matchPath(route.parts, segments);
    if (!params) continue;
    if (route.method === method) return route.handler({ request, env, ctx, url, params });
    allowed.push(route.method);
  }
  if (allowed.length) {
    fail(405, "method_not_allowed", `Use ${allowed.join(" or ")} for this address.`, { Allow: allowed.join(", ") });
  }
  fail(404, "not_found", "There is nothing at this address. Check the URL.");
}

// The few addresses any web page may call: whether a name is free, holding
// one, and which Kliner is up. None of them is signed or reads anything private.
function openToPages(path) {
  return path === "/v1/claims" || path === "/v1/release" || path.startsWith("/v1/names/");
}

function matchPath(patternParts, segments) {
  if (patternParts.length !== segments.length) return null;
  const params = {};
  for (let i = 0; i < patternParts.length; i++) {
    const want = patternParts[i];
    if (want.startsWith(":")) {
      if (!segments[i]) return null;
      params[want.slice(1)] = safeDecode(segments[i]);
    } else if (want !== segments[i]) {
      return null;
    }
  }
  return params;
}

function safeDecode(segment) {
  try {
    return decodeURIComponent(segment);
  } catch {
    return segment; // malformed %-escapes simply fail validation later
  }
}

// ---------------------------------------------------------------------------
// The app, for anyone
// ---------------------------------------------------------------------------

// deploy.sh puts up what the owner's Mac built: the disk image people
// download (Kliner.dmg: open it, drag Kliner onto Applications), the zip it
// used to be (Kliner.app.zip, kept for the links already out there), and a
// note of which version they are (latest.json). This hands them out exactly
// as they are. Nothing about who downloads them is written down.
const APP_KEY = "releases/Kliner.app.zip";
const DMG_KEY = "releases/Kliner.dmg";
const RELEASE_KEY = "releases/latest.json";
const VERSION_RE = /^\d{1,4}\.\d{1,4}\.\d{1,4}$/;

/** The note deploy.sh left about what is up, or null when there is none
 *  (or it does not say a version the way VERSION does). */
async function latest(env) {
  const obj = await env.FILES.get(RELEASE_KEY);
  if (!obj) return null;
  try {
    const r = JSON.parse(await obj.text());
    return r && VERSION_RE.test(String(r.version || "")) ? r : null;
  } catch {
    return null;
  }
}

async function downloadApp(c) {
  if (c.url.pathname === "/download") {
    // the disk image when there is one, named for its version; the zip when not
    const r = await latest(c.env);
    const dmg = r ? await c.env.FILES.head(DMG_KEY) : null;
    const to = dmg ? `/download/Kliner-${r.version}.dmg` : "/download/Kliner.app.zip";
    return new Response(null, { status: 302, headers: { Location: to, "Cache-Control": "no-store" } });
  }
  return serveRelease(c, APP_KEY, "application/zip", "Kliner.app.zip");
}

// /download/Kliner-0.62.0.dmg (or /download/Kliner.dmg): always the newest
// disk image, saved under the name of the version it is, so an old link
// still gets you the Kliner that is up now.
async function downloadImage(c) {
  if (!/^Kliner(-\d{1,4}\.\d{1,4}\.\d{1,4})?\.dmg$/.test(c.params.file || "")) {
    fail(404, "not_found", "There is nothing at this address. Check the URL.");
  }
  const r = await latest(c.env);
  return serveRelease(c, DMG_KEY, "application/x-apple-diskimage", r ? `Kliner-${r.version}.dmg` : "Kliner.dmg");
}

async function serveRelease(c, key, type, filename) {
  const head = c.request.method === "HEAD";
  const obj = head ? await c.env.FILES.head(key) : await c.env.FILES.get(key);
  if (!obj) fail(404, "not_found", "Kliner is not up for download yet. Try again soon.");
  const headers = new Headers({
    "Content-Type": type,
    "Content-Disposition": `attachment; filename="${filename}"`,
    "Content-Length": String(obj.size),
    "Cache-Control": "public, max-age=300",
  });
  if (obj.httpEtag) headers.set("ETag", obj.httpEtag);
  if (obj.uploaded) headers.set("Last-Modified", obj.uploaded.toUTCString());
  return new Response(head ? null : obj.body, { status: 200, headers });
}

// GET /v1/release: which Kliner is up, for the site's Download button. Any
// page may read it (CORS), since kliner.app is not api.kliner.app.
async function release(c) {
  const r = await latest(c.env);
  const dmg = r ? await c.env.FILES.head(DMG_KEY) : null;
  const zip = await c.env.FILES.head(APP_KEY);
  const sha = r && r.dmg && /^[0-9a-f]{64}$/.test(String(r.dmg.sha256 || "")) ? r.dmg.sha256 : null;
  return json({
    version: r ? r.version : null,
    dmg: dmg ? { url: `/download/Kliner-${r.version}.dmg`, bytes: dmg.size, sha256: sha } : null,
    zip: zip ? { url: "/download/Kliner.app.zip", bytes: zip.size } : null,
    published: r && typeof r.published === "string" ? r.published.slice(0, 40) : null,
  }, 200, { "Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=60" });
}

// ---------------------------------------------------------------------------
// Health and names
// ---------------------------------------------------------------------------

function health() {
  return json({ ok: true, version: API_VERSION });
}

async function checkName(c) {
  await rateLimit(c, "names", 60);
  const name = normName(c.params.name);
  const problem = nameProblem(name);
  if (problem) return json({ name, free: false, reason: problem.reason, message: problem.message });
  const row = await c.env.DB.prepare("SELECT 1 AS x FROM users WHERE name = ?").bind(name).first();
  if (row) return json({ name, free: false, reason: "taken", message: "That name is already taken. Try another one." });
  const hold = await activeHold(c.env.DB, name);
  if (hold) return json({ name, free: false, reason: holdReason(hold), message: holdMessage(hold), until: hold.expires });
  return json({ name, free: true });
}

// ---------------------------------------------------------------------------
// Holds: a name kept for somebody for a while
// ---------------------------------------------------------------------------

// A name somebody gave up is kept for them for a week (they can change back,
// and nobody can pose as them under it while their friends still send to
// it); a name held on kliner.app waits a month for the code the site showed.
async function activeHold(db, name, at = now()) {
  return db.prepare("SELECT name, kind, sign, code, expires FROM holds WHERE name = ? AND expires > ?").bind(name, at).first();
}

function holdReason(hold) {
  return hold.kind === "claimed" ? "claimed" : "held";
}

function holdMessage(hold) {
  const until = longDate(hold.expires);
  return hold.kind === "claimed"
    ? `Somebody is holding this name on kliner.app until ${until}. If that is you, enter the code you got there.`
    : `Its owner changed their name a moment ago, so it is kept for them until ${until}.`;
}

function renamedMessage(name) {
  return `@${name} changed their username. Ask them for the new one.`;
}

function longDate(unix) {
  const d = new Date(unix * 1000);
  return `${LONG_MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

// The code as people type it: upper case, spaces and dashes left out.
function normCode(value) {
  return typeof value === "string" ? value.toUpperCase().replace(/[\s\-\u2010-\u2015\u2212]/g, "") : "";
}

// Ten letters and digits from CODE_ALPHABET, drawn without bias, as XXXXX-XXXXX.
function newCode() {
  let out = "";
  while (out.length < 10) {
    for (const b of crypto.getRandomValues(new Uint8Array(16))) {
      if (b >= 248 || out.length >= 10) continue; // 248 = 8 * 31: the rest would favour the first letters
      out += CODE_ALPHABET[b % CODE_ALPHABET.length];
    }
  }
  return `${out.slice(0, 5)}-${out.slice(5)}`;
}

// POST /v1/claims, from a page: a name held for 30 days, for whoever has
// the code it hands back. Nothing about who asked is kept but the counters.
async function claimName(c) {
  await rateLimit(c, "claims", 10);
  const input = parseJsonObject(await readBody(c.request, MAX_JSON_BODY));
  if (typeof input.name !== "string") fail(400, "invalid", "name is required.");
  const name = normName(input.name).replace(/^@+/, "");
  const held = await holdName(c, name, newCode());
  return json({ name: held.name, code: held.code, expires: held.expires }, 201);
}

// Holds `name` for 30 days for whoever has `code`: the rules, the name being
// nobody's, the counters, and the one insert that counts. Only the code's
// SHA-256 is kept. The same code asking again for a name it already holds
// (the same form sent twice) is told the same thing again, and not counted.
async function holdName(c, name, code) {
  const problem = nameProblem(name);
  if (problem) fail(400, problem.reason, problem.message);
  const db = c.env.DB;
  if (await db.prepare("SELECT 1 AS x FROM users WHERE name = ?").bind(name).first()) {
    fail(409, "taken", "That name is already taken. Try another one.");
  }
  const t = now();
  const hash = await sha256Hex(utf8(normCode(code)));
  const hold = await activeHold(db, name, t);
  if (hold && hold.kind === "claimed" && hold.code === hash) return { name, code, expires: hold.expires, again: true };
  if (hold) fail(409, holdReason(hold), holdMessage(hold));
  const ip = clientAddress(c.request);
  await countIn(c, `claims:${ip}`, CLAIMS_PER_HOUR, 3600,
    (wait) => `You have held ${CLAIMS_PER_HOUR} names in the last hour. Try again in ${Math.ceil(wait / 60)} minutes.`);
  await countIn(c, `claimsday:${ip}`, CLAIMS_PER_DAY, 86400,
    (wait) => `You have held ${CLAIMS_PER_DAY} names today. Try again in ${Math.ceil(wait / 3600)} hours.`);
  const expires = t + CLAIM_HOLD_DAYS * 86400;
  // a hold that ran out goes first, so the insert is the only one that counts
  const done = await db.batch([
    db.prepare("DELETE FROM holds WHERE name = ? AND expires <= ?").bind(name, t),
    db.prepare("INSERT OR IGNORE INTO holds (name, kind, sign, code, created, expires) VALUES (?, 'claimed', NULL, ?, ?, ?)")
      .bind(name, hash, t, expires),
  ]);
  if (done[1].meta.changes !== 1) {
    const won = await activeHold(db, name, t);
    if (won && won.kind === "claimed" && won.code === hash) return { name, code, expires: won.expires, again: true };
    fail(409, "claimed", "Somebody held that name a moment ago. Try another one.");
  }
  return { name, code, expires };
}

// The code a form on a name's page stands for. The page hands out a fresh
// random nonce with every form; the code is drawn from it, without bias, so
// the same form sent again (a double click, a reload after a slow answer)
// asks for the same code and gets the same answer, instead of a name held
// with a code nobody saw. Like every code, only its SHA-256 is kept.
async function codeFrom(nonce, name) {
  let out = "";
  for (let round = 0; out.length < 10; round++) {
    const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", utf8(`kliner-hold\n${round}\n${nonce}\n${name}`)));
    for (const b of bytes) {
      if (b >= 248 || out.length >= 10) continue; // 248 = 8 * 31, as in newCode
      out += CODE_ALPHABET[b % CODE_ALPHABET.length];
    }
  }
  return `${out.slice(0, 5)}-${out.slice(5)}`;
}

// Names are compared and stored lowercase. Surrounding spaces are forgiven.
function normName(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

// null when the name is valid and not reserved, else { reason, message }.
// Reserved comes first, so every word on the list (even the short "me") says so.
function nameProblem(name) {
  const invalid = (message) => ({ reason: "invalid", message });
  if (RESERVED.has(name)) return { reason: "reserved", message: "That name is reserved. Pick another one." };
  if (name.length < 3 || name.length > 20) return invalid("A name is 3 to 20 characters long.");
  if (!/^[a-z]/.test(name)) return invalid("A name starts with a letter.");
  if (!/^[a-z0-9._]+$/.test(name)) return invalid("A name uses only lowercase letters, digits, dots and underscores.");
  if (name.includes("..")) return invalid("A name cannot have two dots in a row.");
  if (name.endsWith(".")) return invalid("A name cannot end with a dot.");
  return null;
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

async function registerUser(c) {
  // Not in the spec's list of limits: a light brake on bulk name grabbing.
  await rateLimit(c, "users", 10);
  const body = await readBody(c.request, MAX_JSON_BODY);
  const input = parseJsonObject(body);

  if (typeof input.name !== "string") fail(400, "invalid", "name is required.");
  const name = normName(input.name);
  const problem = nameProblem(name);
  if (problem) fail(400, problem.reason, problem.message);
  const sign = canonicalKey(input.sign);
  if (!sign) fail(400, "invalid", "sign must be the raw 32-byte Ed25519 public key, base64url without padding.");
  const box = canonicalKey(input.box);
  if (!box) fail(400, "invalid", "box must be the raw 32-byte X25519 public key, base64url without padding.");
  const device = cleanText(input.device, "device", 64) ?? null;

  // The request is signed with the key being registered: proof the caller holds it.
  await authenticate(c, body, sign);

  const db = c.env.DB;
  const created = now();
  let existing = await db.prepare("SELECT sign, created FROM users WHERE name = ?").bind(name).first();
  if (!existing) {
    // One name a key: a Mac that has one changes it (POST /v1/users/me/name),
    // so the old name does not stay behind as a second inbox nobody reads.
    const other = await db.prepare("SELECT name FROM users WHERE sign = ?").bind(sign).first();
    if (other) fail(409, "has_name", `This Mac is @${other.name} on kliner.app already. Change the name in Settings instead.`);
    const hold = await activeHold(db, name, created);
    if (hold && hold.kind === "claimed") {
      const code = normCode(input.claim);
      if (!code) fail(409, "claimed", holdMessage(hold));
      if ((await sha256Hex(utf8(code))) !== hold.code) fail(403, "wrong_code", "That code does not hold this name. Check it and try again.");
    } else if (hold) {
      fail(409, "held", holdMessage(hold));
    }
    const result = await db
      .prepare("INSERT OR IGNORE INTO users (name, sign, box, device, created) VALUES (?, ?, ?, ?, ?)")
      .bind(name, sign, box, device, created)
      .run();
    if (result.meta.changes === 1) {
      // the code was right and the name is taken: its hold has done its job
      if (hold) await db.prepare("DELETE FROM holds WHERE name = ?").bind(name).run();
      return json({ name, created }, 201);
    }
    // Someone registered the same name a moment ago; decide against their row.
    existing = await db.prepare("SELECT sign, created FROM users WHERE name = ?").bind(name).first();
  }
  if (!existing || existing.sign !== sign) fail(409, "taken", "That name is already taken. Pick another one.");
  // Same signing key: the owner again. Keep the name and date; refresh the box
  // key, and the device label when one is sent.
  await db.prepare("UPDATE users SET box = ?, device = COALESCE(?, device) WHERE name = ?").bind(box, device, name).run();
  return json({ name, created: existing.created }, 200);
}

async function getUser(c) {
  const name = normName(c.params.name);
  const row = nameProblem(name)
    ? null
    : await c.env.DB.prepare("SELECT name, sign, box, created FROM users WHERE name = ?").bind(name).first();
  if (!row) {
    const hold = nameProblem(name) ? null : await activeHold(c.env.DB, name);
    if (hold && hold.kind === "renamed") fail(404, "renamed", renamedMessage(name));
    fail(404, "no_user", "There is no Kliner user with that name.");
  }
  return json({ name: row.name, sign: row.sign, box: row.box, created: row.created });
}

// POST /v1/users/me/name (signed): the same Mac, the same keys, a new name.
// Its files on their way go with it; the old name is kept for it for a week,
// then anyone may take it. One old name is kept at a time, and changing back
// to it within the week is the same call.
async function renameMe(c) {
  const body = await readBody(c.request, MAX_JSON_BODY);
  const me = await authenticate(c, body);
  const input = parseJsonObject(body);
  if (typeof input.name !== "string") fail(400, "invalid", "name is required.");
  const name = normName(input.name).replace(/^@+/, "");
  const problem = nameProblem(name);
  if (problem) fail(400, problem.reason, problem.message);
  if (name === me) fail(400, "same", "That is your name already.");
  const db = c.env.DB;
  const t = now();
  const mine = await db.prepare("SELECT sign FROM users WHERE name = ?").bind(me).first();
  if (await db.prepare("SELECT 1 AS x FROM users WHERE name = ?").bind(name).first()) {
    fail(409, "taken", "That name is already taken. Pick another one.");
  }
  const hold = await activeHold(db, name, t);
  if (hold && hold.kind === "claimed") {
    // held on kliner.app: the code the site showed makes it this Mac's
    const code = normCode(input.claim);
    if (!code) fail(409, "claimed", holdMessage(hold));
    if ((await sha256Hex(utf8(code))) !== hold.code) fail(403, "wrong_code", "That code does not hold this name. Check it and try again.");
  } else if (hold && hold.sign !== mine.sign) {
    fail(409, holdReason(hold), holdMessage(hold));
  }
  await countIn(c, `rename:${mine.sign}`, RENAMES_PER_DAY, 86400,
    (wait) => `You changed your name ${RENAMES_PER_DAY} times today. Try again in ${Math.ceil(wait / 3600)} hours.`);
  const until = t + RENAME_HOLD_DAYS * 86400;
  try {
    await db.batch([
      // the name held for this Mac before is let go, or taken back; and the
      // new one's own hold, run out or held with the code just given
      db.prepare("DELETE FROM holds WHERE sign = ? AND kind = 'renamed'").bind(mine.sign),
      db.prepare("DELETE FROM holds WHERE name = ? AND (expires <= ? OR kind = 'claimed')").bind(name, t),
      db.prepare("UPDATE users SET name = ?1 WHERE name = ?2").bind(name, me),
      db.prepare("UPDATE profiles SET name = ?1 WHERE name = ?2").bind(name, me),
      db.prepare("UPDATE transfers SET sender = ?1 WHERE sender = ?2").bind(name, me),
      db.prepare("UPDATE transfers SET recipient = ?1 WHERE recipient = ?2").bind(name, me),
      db.prepare("INSERT OR REPLACE INTO holds (name, kind, sign, code, created, expires) VALUES (?, 'renamed', ?, NULL, ?, ?)")
        .bind(me, mine.sign, t, until),
    ]);
  } catch {
    // somebody took the name between the look above and the change
    fail(409, "taken", "That name is already taken. Pick another one.");
  }
  return json({ name, was: me, until });
}

async function deleteMe(c) {
  const me = await authenticate(c, await readBody(c.request, MAX_JSON_BODY));
  const db = c.env.DB;
  const mine = await db.prepare("SELECT sign FROM users WHERE name = ?").bind(me).first();
  // Only uploading/ready transfers still have parts in R2.
  const { results } = await db
    .prepare("SELECT id, parts FROM transfers WHERE (sender = ?1 OR recipient = ?1) AND status IN ('uploading', 'ready')")
    .bind(me)
    .all();
  await deleteParts(c.env, results);
  await db.batch([
    db.prepare("DELETE FROM transfers WHERE sender = ?1 OR recipient = ?1").bind(me),
    db.prepare("DELETE FROM profiles WHERE name = ?").bind(me),
    db.prepare("DELETE FROM users WHERE name = ?").bind(me),
    // a name it gave up is free at once: there is nobody left to keep it for
    db.prepare("DELETE FROM holds WHERE sign = ?").bind(mine.sign),
  ]);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Signed requests
// ---------------------------------------------------------------------------

// Checks X-Kliner-Time and X-Kliner-Sig over
//   KLINER1\n<METHOD>\n<PATH>\n<TIME>\n<hex sha256 of body>
// and returns the caller's name. With `registerKey` (POST /v1/users) the
// signature is checked against that new key instead of a stored user.
async function authenticate(c, body, registerKey) {
  const { request, env, url } = c;
  const headers = request.headers;
  const time = headers.get("X-Kliner-Time");
  const sig = headers.get("X-Kliner-Sig");
  const name = registerKey ? null : normName(headers.get("X-Kliner-User"));
  if ((!registerKey && !name) || !time || !sig) {
    fail(401, "bad_signature", "Sign this request with the X-Kliner-User, X-Kliner-Time and X-Kliner-Sig headers.");
  }
  if (!/^\d{1,15}$/.test(time)) fail(401, "bad_signature", "X-Kliner-Time must be the current time in whole unix seconds.");
  if (Math.abs(now() - Number(time)) > CLOCK_SKEW) {
    fail(401, "stale", "The request time is more than 5 minutes off. Set the Mac's clock automatically, then try again.");
  }
  const signature = b64uDecode(sig);
  if (!signature || signature.length !== 64) fail(401, "bad_signature", "X-Kliner-Sig must be a base64url Ed25519 signature.");

  let key = registerKey;
  if (!key) {
    const user = await env.DB.prepare("SELECT sign FROM users WHERE name = ?").bind(name).first();
    if (!user) fail(401, "bad_signature", "There is no user with that name. Register it first.");
    key = user.sign;
  }
  const message = `KLINER1\n${request.method.toUpperCase()}\n${url.pathname}\n${time}\n${await sha256Hex(body)}`;
  if (!(await verifyEd25519(key, signature, utf8(message)))) {
    fail(401, "bad_signature", "The signature does not match. Sign the method, path, time and body hash with this user's key.");
  }
  return name;
}

async function verifyEd25519(publicKeyB64u, signature, message) {
  const raw = b64uDecode(publicKeyB64u);
  if (!raw || raw.length !== 32) return false;
  try {
    const key = await crypto.subtle.importKey("raw", raw, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "Ed25519" }, key, signature, message);
  } catch {
    return false; // not a usable key: treat exactly like a wrong signature
  }
}

// A raw 32-byte public key in canonical base64url (no padding), or null.
// Re-encoding means two spellings of the same key compare equal.
function canonicalKey(value) {
  const bytes = typeof value === "string" ? b64uDecode(value) : null;
  return bytes && bytes.length === 32 ? b64uEncode(bytes) : null;
}

// ---------------------------------------------------------------------------
// Profiles
// ---------------------------------------------------------------------------

async function putProfile(c) {
  const body = await readBody(c.request, MAX_PROFILE_BODY, "The profile is larger than 800 KB. Use smaller images.");
  const me = await authenticate(c, body);
  const profile = cleanProfile(parseJsonObject(body));
  await c.env.DB.prepare(
    "INSERT INTO profiles (name, json, visible, updated) VALUES (?1, ?2, ?3, ?4) " +
      "ON CONFLICT(name) DO UPDATE SET json = excluded.json, visible = excluded.visible, updated = excluded.updated",
  )
    .bind(me, JSON.stringify(profile), profile.visible ? 1 : 0, now())
    .run();
  return json({ ok: true, url: `${profileBase(c)}/@${me}` });
}

// Where profile pages are: kliner.app, or — before the domain is wired, when
// the request came to the Worker's workers.dev address — that address, which
// serves /@name itself.
function profileBase(c) {
  const host = new URL(c.request.url).host;
  return host.endsWith(".workers.dev") ? `https://${host}` : settings(c.env).publicUrl;
}

async function getProfile(c) {
  const name = normName(c.params.name);
  const profile = await loadVisibleProfile(c.env, name);
  if (!profile) fail(404, "no_profile", "This person has no public profile.");
  return json({ name, ...profile });
}

async function loadVisibleProfile(env, name) {
  if (nameProblem(name)) return null;
  const row = await env.DB.prepare("SELECT json FROM profiles WHERE name = ? AND visible = 1").bind(name).first();
  if (!row) return null;
  try {
    return JSON.parse(row.json);
  } catch {
    return null;
  }
}

// PUT replaces the whole profile. Unknown fields are dropped, strings are
// trimmed and length-checked (in Unicode characters), empty values are left
// out, and a wrong type is a 400 naming the field.
const PROFILE_FIELDS = {
  visible: flag,
  display: text(60),
  bio: text(280, { multiline: true }),
  role: text(60),
  place: text(60),
  work: workList(14),
  links: linkList,
  avatar: dataImage(150),
  mac: object({ model: text(80), chip: text(80), memory: text(80), macos: text(80), storage: text(80) }),
  setup: object({
    wallpaper: text(80),
    wallpaperThumb: dataImage(330),
    trash: dataImage(28),
    appearance: oneOf("dark", "light", "auto"),
    accent: text(20),
    dock: dockList(40, 40),
    dockAutohide: flag,
    desktop: text(20),
    apps: whole,
    walls: wallList(8, 80),
  }),
  done: doneList(10),
  stats: object({ freedBytes: whole, tidied: whole, cleanSince: text(40) }),
  since: text(40),
};

function cleanProfile(input) {
  const { visible = false, ...rest } = object(PROFILE_FIELDS)(input, "") ?? {};
  return { visible, ...rest };
}

// Field checkers: (value, path) -> cleaned value, or undefined to leave it out.
// null and missing values are simply left out.

function object(fields) {
  return (value, path) => {
    if (value == null) return undefined;
    if (typeof value !== "object" || Array.isArray(value)) invalidField(path, "must be an object");
    const out = {};
    for (const [key, check] of Object.entries(fields)) {
      const cleaned = check(value[key], path ? `${path}.${key}` : key);
      if (cleaned !== undefined) out[key] = cleaned;
    }
    return Object.keys(out).length ? out : undefined;
  };
}

function text(max, { multiline = false } = {}) {
  return (value, path) => cleanText(value, path, max, multiline);
}

function cleanText(value, path, max, multiline = false) {
  if (value == null) return undefined;
  if (typeof value !== "string") invalidField(path, `must be text of at most ${max} characters`);
  let s = value.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "");
  s = multiline ? s.replace(/\n{3,}/g, "\n\n") : s.replace(/\s+/g, " ");
  s = s.trim();
  if ([...s].length > max) invalidField(path, `must be at most ${max} characters`);
  return s || undefined;
}

function flag(value, path) {
  if (value == null) return undefined;
  if (typeof value !== "boolean") invalidField(path, "must be true or false");
  return value;
}

function whole(value, path) {
  if (value == null) return undefined;
  if (!Number.isSafeInteger(value) || value < 0) invalidField(path, "must be a whole number, 0 or more");
  return value;
}

function oneOf(...choices) {
  return (value, path) => {
    if (value == null) return undefined;
    const s = typeof value === "string" ? value.trim().toLowerCase() : null;
    if (!choices.includes(s)) invalidField(path, `must be ${choices.slice(0, -1).join(", ")} or ${choices.at(-1)}`);
    return s;
  };
}

// The things they have made or done, each with a year and, when there is
// one, somewhere to go. This is the shape every page Dan picked is built
// from: a short line, a year beside it, and a link under the name.
function workList(maxItems) {
  return (value, path) => {
    if (value == null) return undefined;
    if (!Array.isArray(value) || value.length > maxItems) invalidField(path, `must be a list of at most ${maxItems} things`);
    const out = [];
    for (let i = 0; i < value.length; i++) {
      const at = `${path}[${i}]`;
      const item = value[i];
      if (item == null || typeof item !== "object" || Array.isArray(item)) invalidField(at, "must be a thing with a name");
      const name = cleanText(item.name, `${at}.name`, 60);
      if (!name) continue;
      const one = { name };
      const when = cleanText(item.when, `${at}.when`, 20);
      if (when) one.when = when;
      const note = cleanText(item.note, `${at}.note`, 90);
      if (note) one.note = note;
      if (item.url != null && item.url !== "") {
        const url = cleanText(item.url, `${at}.url`, 200);
        if (url && !isHttpsUrl(url)) invalidField(`${at}.url`, "must be an https:// address");
        if (url) one.url = url;
      }
      out.push(one);
    }
    return out.length ? out : undefined;
  };
}

// The wallpapers they keep, each a name and — while there is room for it —
// the picture itself. A name on its own is still worth drawing.
function wallList(maxItems, maxLength) {
  const thumb = dataImage(60);
  return (value, path) => {
    if (value == null) return undefined;
    if (!Array.isArray(value) || value.length > maxItems) invalidField(path, `must be a list of at most ${maxItems} wallpapers`);
    const out = [];
    for (let i = 0; i < value.length; i++) {
      const at = `${path}[${i}]`;
      const item = value[i];
      if (item == null || typeof item !== "object" || Array.isArray(item)) invalidField(at, "must be a wallpaper with a name");
      const name = cleanText(item.name, `${at}.name`, maxLength);
      if (!name) continue;
      const art = thumb(item.thumb, `${at}.thumb`);
      out.push(art ? { name, thumb: art, on: item.on === true || undefined } : { name, on: item.on === true || undefined });
    }
    return out.length ? out : undefined;
  };
}

// What Kliner has done on this Mac: whatever `min undo --list` printed, as
// it printed it. Nothing here is worked out by the page.
function doneList(maxItems) {
  return (value, path) => {
    if (value == null) return undefined;
    if (!Array.isArray(value) || value.length > maxItems) invalidField(path, `must be a list of at most ${maxItems} things`);
    const out = [];
    for (let i = 0; i < value.length; i++) {
      const at = `${path}[${i}]`;
      const item = value[i];
      if (item == null || typeof item !== "object" || Array.isArray(item)) invalidField(at, "must be a thing with a name");
      const what = cleanText(item.what, `${at}.what`, 80);
      if (!what) continue;
      out.push({ what, when: cleanText(item.when, `${at}.when`, 40) || undefined });
    }
    return out.length ? out : undefined;
  };
}

// The Dock: a list of app names, or of names with the app's own icon. A
// plain string stays a plain string, so a copy of the app from before the
// icons keeps publishing exactly as it did. An icon that is not a real small
// picture is a 400 naming the app, never a silently dropped one.
function dockList(maxItems, maxLength) {
  const icon = dataImage(28);
  return (value, path) => {
    if (value == null) return undefined;
    if (!Array.isArray(value) || value.length > maxItems) invalidField(path, `must be a list of at most ${maxItems} apps`);
    const out = [];
    for (let i = 0; i < value.length; i++) {
      const at = `${path}[${i}]`;
      const item = value[i];
      if (item != null && typeof item === "object" && !Array.isArray(item)) {
        const name = cleanText(item.name, `${at}.name`, maxLength);
        if (!name) continue;
        const art = icon(item.icon, `${at}.icon`);
        out.push(art ? { name, icon: art } : { name });
        continue;
      }
      const name = cleanText(item, at, maxLength);
      if (name) out.push(name);
    }
    return out.length ? out : undefined;
  };
}

function linkList(value, path) {
  if (value == null) return undefined;
  if (!Array.isArray(value) || value.length > 5) invalidField(path, "must be a list of at most 5 links");
  const out = [];
  value.forEach((item, i) => {
    const at = `${path}[${i}]`;
    if (!item || typeof item !== "object" || Array.isArray(item)) invalidField(at, "must be an object with title and url");
    const url = cleanText(item.url, `${at}.url`, 200);
    const title = cleanText(item.title, `${at}.title`, 40);
    if (!url) return; // a link without an address shows nothing: drop it
    if (!isHttpsUrl(url)) invalidField(`${at}.url`, "must be an https:// address");
    out.push(title ? { title, url } : { url });
  });
  return out.length ? out : undefined;
}

function isHttpsUrl(s) {
  if (typeof s !== "string" || !/^https:\/\//i.test(s) || /[\s<>"\\]/.test(s)) return false;
  try {
    const u = new URL(s);
    return u.protocol === "https:" && Boolean(u.hostname) && !u.username && !u.password;
  } catch {
    return false;
  }
}

// data:image/(jpeg|png);base64,<base64 only>. The limit is on the decoded
// image, which also covers a client that measures the base64 text instead.
const DATA_IMAGE = /^data:image\/(jpeg|png);base64,([A-Za-z0-9+/]+={0,2})$/;

function dataImage(maxKB) {
  return (value, path) => {
    if (value == null) return undefined;
    if (typeof value !== "string") invalidField(path, "must be a data:image/jpeg or data:image/png URL");
    const s = value.trim();
    if (!s) return undefined;
    if (!isDataImage(s)) invalidField(path, "must be a data:image/jpeg;base64 or data:image/png;base64 URL of a real image");
    if (base64Bytes(DATA_IMAGE.exec(s)[2]) > maxKB * 1024) invalidField(path, `must be at most ${maxKB} KB`);
    return s;
  };
}

// Also used when rendering, so a bad row can never reach an <img src>.
function isDataImage(s) {
  const m = typeof s === "string" ? DATA_IMAGE.exec(s) : null;
  if (!m || m[2].length % 4 === 1 || m[2].length < 12) return false;
  // Check the file signature, so the declared type is what the bytes are.
  let head;
  try {
    head = atob(m[2].slice(0, 12));
  } catch {
    return false;
  }
  const bytes = [...head].map((ch) => ch.charCodeAt(0));
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  return m[1] === "jpeg"
    ? bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
    : png.every((b, i) => bytes[i] === b);
}

function base64Bytes(b64) {
  const data = b64.replace(/=+$/, "");
  return Math.floor((data.length * 3) / 4);
}

function invalidField(path, problem) {
  fail(400, "invalid", `${path || "The body"} ${problem}.`);
}

// ---------------------------------------------------------------------------
// Profile page (HTML)
// ---------------------------------------------------------------------------

async function profilePage(c, rawName) {
  const name = normName(safeDecode(rawName));
  const cfg = settings(c.env);
  const profile = await loadVisibleProfile(c.env, name);
  if (!profile) return namePage(c, name, cfg);
  return htmlResponse(renderProfile(name, profile, cfg), 200, "public, max-age=60");
}

// A name with no page to show says what it is instead: nobody's, and it can
// be held from here; somebody's, whose page is not public; given up a moment
// ago, or held on kliner.app, and until when; or no name at all. Dan opened
// kliner.app/@a-free-name, found "No profile here" and nothing to do, and
// this is where kliner.app's own name lives, so it is where a name is held.
async function namePage(c, name, cfg, bad = "", status = 0) {
  const problem = nameProblem(name);
  if (!name || problem) return htmlResponse(renderMissing(name, cfg, problem), status || 404, "no-store");
  const db = c.env.DB;
  if (await db.prepare("SELECT 1 AS x FROM users WHERE name = ?").bind(name).first()) {
    return htmlResponse(renderUnlisted(name, cfg, bad), status || 404, "no-store");
  }
  const hold = await activeHold(db, name);
  if (hold) return htmlResponse(renderHeld(name, hold, cfg, bad), status || (hold.kind === "claimed" ? 200 : 404), "no-store");
  return htmlResponse(renderFree(name, cfg, randomId(), bad), status || 200, "no-store", HOLD_CSP);
}

// POST /@name: the form on a free name's page. Only from that page — a form
// on another site cannot hold names in its visitors' names — with the nonce
// that page handed out. Every answer is a page: the code, or the name's page
// again saying why not.
async function holdPage(c, rawName) {
  const name = normName(safeDecode(rawName));
  const cfg = settings(c.env);
  try {
    if (!fromItsPage(c.request, cfg)) {
      return namePage(c, name, cfg, `Hold it from its page: ${hostOf(cfg.publicUrl)}/@${name}.`, 403);
    }
    await rateLimit(c, "claims", 10);
    const form = await readForm(c.request);
    const nonce = form.get("n") || "";
    if (!/^[A-Za-z0-9_-]{22}$/.test(nonce)) return namePage(c, name, cfg, "That form is out of date. Try again.", 400);
    const held = await holdName(c, name, await codeFrom(nonce, name));
    return htmlResponse(renderHeldForYou(held, cfg), 200, "no-store");
  } catch (err) {
    if (!(err instanceof HttpError)) throw err;
    // taken, held or counted out in the meantime: what the name is now, and why
    return namePage(c, name, cfg, err.message, err.status);
  }
}

// A form sent from a page on this host. Browsers say where a request came
// from (Sec-Fetch-Site, then Origin); one that says neither is turned away.
function fromItsPage(request, cfg) {
  const site = request.headers.get("Sec-Fetch-Site");
  if (site) return site === "same-origin";
  const origin = request.headers.get("Origin");
  if (!origin) return false;
  return origin === new URL(request.url).origin || origin === new URL(cfg.publicUrl).origin;
}

async function readForm(request) {
  const type = (request.headers.get("Content-Type") || "").toLowerCase();
  if (!type.startsWith("application/x-www-form-urlencoded")) return new URLSearchParams();
  return new URLSearchParams(new TextDecoder().decode(await readBody(request, 4096)));
}

function htmlResponse(body, status, cacheControl, csp = PROFILE_CSP) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": cacheControl,
      "Content-Security-Policy": csp,
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function esc(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);
}

// The page a person's @username opens: who they are, the Mac they keep, and
// what Kliner has done for it.
//
// The frame is the one Dan picked: one 715-point column held between two
// rules that run the whole height of the page, every section opening with
// its name over a hairline that crosses the entire window, and the sections
// parted by a band of diagonal hatch that crosses it too. Facts sit in cells
// of three — a mark, what it is, and what it says — with a gap between them,
// so a row that does not fill simply ends.
//
// No script (the CSP allows none) and one font: Geist, carried in the page
// as a data: URL. Every string a person typed goes through esc(); every
// picture passes isDataImage() before it reaches an <img>. A section is
// drawn only when the profile has something for it, and nothing is made up.
function renderProfile(name, p, cfg) {
  const handle = `@${name}`;
  const display = str(p.display);
  const bio = str(p.bio);
  // The person, then what they have made, then where to find them — and
  // only then the Mac. Every page Dan picked reads in that order; a page
  // that opens on a spec sheet is a report about a computer.
  const sections = [workSection(p), linksSection(p), setupSection(p.setup), macSection(p.mac),
                    wallsSection(p.setup), statsSection(p), doneSection(p)].filter(Boolean);
  return page({
    title: display ? `${display} (${handle}) · Kliner` : `${handle} · Kliner`,
    description: bio || `${handle} on Kliner`,
    canonical: `${cfg.publicUrl}/@${name}`,
    cfg,
    handle,
    body: heroSection(name, display, bio, p) + sections.join("\n"),
  });
}

// The person: what they wrote across the top on a field of dots, then their
// picture in its frame, their name, their @username and the month they have
// had Kliner.
function heroSection(name, display, bio, p) {
  const handle = `@${name}`;
  const face = isDataImage(p.avatar)
    ? `<span class="face"><img src="${esc(p.avatar)}" alt="" width="120" height="120"></span>`
    : `<span class="face initial" aria-hidden="true">${esc(firstLetter(display || name))}</span>`;
  const since = str(p.since) ? formatMonth(str(p.since)) : "";
  return `<div class="dots">${bio ? `<p>${esc(bio)}</p>` : `<p class="quiet">${esc(handle)} on Kliner</p>`}</div>
<section class="hero">
${face}
<div class="hero-w">
<h1>${esc(display || handle)}</h1>
${str(p.role) ? `<p class="at">${esc(str(p.role))}</p>` : `<p class="at">${esc(handle)}</p>`}
<p class="since">${[str(p.role) ? esc(handle) : "", str(p.place) ? esc(str(p.place)) : "", since ? `On Kliner since ${esc(since)}` : ""].filter(Boolean).join(" · ")}</p>
</div>
</section>`;
}

// A section: the hatch band that parts it from the one before, its name over
// a rule that crosses the window, then whatever it holds.
function section(title, inner) {
  return `<i class="band" aria-hidden="true"></i>
<div class="head"><h2>${esc(title)}</h2></div>
<section class="sec">${inner}</section>`;
}

// Facts in cells of three: a mark, what it is above, and what it says below.
function cells(items, cls) {
  const list = items.filter(([, , value]) => value);
  if (!list.length) return "";
  return `<div class="cells${cls ? " " + cls : ""}">${list
    .map(([mark, label, value, extra]) =>
      `<div class="cell"><span class="cm">${mark}</span>` +
      `<span class="ct"><span class="cl">${esc(label)}</span>` +
      `<span class="cv">${extra || ""}${esc(value)}</span></span></div>`)
    .join("")}</div>`;
}

// Setup: their screen, with their wallpaper on it and their own Dock along
// the bottom. No wallpaper and the screen is drawn plain — it is a frame for
// their Dock, and says nothing the profile did not.
const DOCK_SHOWN = 12;

function setupSection(s) {
  if (!s || typeof s !== "object") return "";
  const thumb = isDataImage(s.wallpaperThumb) ? s.wallpaperThumb : "";
  const wallpaper = str(s.wallpaper);
  const apps = (Array.isArray(s.dock) ? s.dock : [])
    .map((app) => {
      if (typeof app === "string") return { name: app.trim() };
      if (!app || typeof app !== "object") return null;
      const name = str(app.name);
      return name ? { name, icon: isDataImage(app.icon) ? app.icon : "" } : null;
    })
    .filter((app) => app && app.name);
  const shown = apps.slice(0, DOCK_SHOWN);
  // The Trash closes a real Dock, behind the line macOS draws there, so the
  // page ends it the same way when the Mac sent its picture.
  const bin = isDataImage(s.trash)
    ? `<span class="dsep" aria-hidden="true"></span><span class="app" role="listitem">` +
      `<img src="${esc(s.trash)}" alt="Trash" loading="lazy"></span>`
    : "";
  const dock = shown.length
    ? `<div class="dock" role="list" aria-label="In the Dock">${shown
      .map((app) => `<span class="app" role="listitem">` +
        (app.icon
          ? `<img src="${esc(app.icon)}" alt="${esc(app.name)}" loading="lazy">`
          : `<i aria-hidden="true">${esc(firstLetter(app.name))}</i><span class="vh">${esc(app.name)}</span>`) +
        `</span>`)
      .join("")}${bin}</div>`
    : "";
  const screen = thumb || dock
    ? `<figure class="shot"><div class="screen${thumb ? "" : " plain"}">` +
      (thumb ? `<img class="wall" src="${esc(thumb)}" alt="">` : "") +
      MENU_BAR + dock + `</div>` +
      (wallpaper ? `<figcaption>${glyph("wallpaper")}<span>${esc(wallpaper)}</span></figcaption>` : "") +
      `</figure>`
    : "";

  const appearance = str(s.appearance);
  const accent = str(s.accent);
  const desktop = str(s.desktop);
  const hides = typeof s.dockAutohide === "boolean" ? (s.dockAutohide ? "Hides automatically" : "Always shown") : "";
  const grid = cells([
    [glyph("wallpaper"), "Wallpaper", !thumb && wallpaper ? wallpaper : ""],
    [glyph(appearanceGlyph(appearance)), "Appearance", appearance ? capitalize(appearance) : ""],
    [glyph("desktop"), "Desktop", desktop ? capitalize(desktop) : ""],
    [glyph("dock"), "Dock", hides],
    [glyph("apps"), "Apps installed", Number.isSafeInteger(s.apps) ? groupDigits(s.apps) : ""],
    [glyph("accent"), "Accent", accent ? capitalize(accent) : "", accent ? swatch(accent) : ""],
  ]);
  if (!screen && !grid) return "";
  return section("Setup", screen + grid);
}

// What they have made: a name, a line about it, a year off to the right,
// and the whole row going somewhere when it has an address.
function workSection(p) {
  const work = (Array.isArray(p.work) ? p.work : []).filter((w) => w && str(w.name));
  if (!work.length) return "";
  const rows = work
    .map((w) => {
      const url = str(w.url) && isHttpsUrl(str(w.url)) ? str(w.url) : "";
      const inner =
        `<span class="iw"><span class="in">${esc(str(w.name))}${url ? ARROW : ""}</span>` +
        (str(w.note) ? `<span class="io">${esc(str(w.note))}</span>` : "") + `</span>` +
        (str(w.when) ? `<span class="iy">${esc(str(w.when))}</span>` : "");
      return url
        ? `<li><a href="${esc(url)}" rel="nofollow noopener noreferrer ugc" target="_blank">${inner}</a></li>`
        : `<li><span class="row">${inner}</span></li>`;
    })
    .join("");
  return section("Work", `<ul class="items">${rows}</ul>`);
}

// The wallpapers they keep: the pictures themselves, four across, the name
// under each, and the one that is on now said so. A wallpaper that came
// without its picture is still named.
function wallsSection(s) {
  if (!s || typeof s !== "object") return "";
  const walls = (Array.isArray(s.walls) ? s.walls : []).filter((w) => w && str(w.name));
  if (!walls.length) return "";
  const grid = `<div class="walls">${walls
    .map((w) => {
      const art = isDataImage(w.thumb)
        ? `<img src="${esc(w.thumb)}" alt="" loading="lazy">`
        : `<i aria-hidden="true"></i>`;
      return `<figure class="wp${w.on ? " on" : ""}">${art}` +
        `<figcaption>${esc(str(w.name))}${w.on ? `<b>on now</b>` : ""}</figcaption></figure>`;
    })
    .join("")}</div>`;
  return section(walls.length === 1 ? "Wallpaper" : "Wallpapers", grid);
}

// What Kliner has done here, in its own words, newest first.
function doneSection(p) {
  const done = (Array.isArray(p.done) ? p.done : []).filter((d) => d && str(d.what));
  if (!done.length) return "";
  const list = `<ul class="log">${done
    .map((d) => `<li><span class="lw">${esc(str(d.what))}</span>` +
      (str(d.when) ? `<span class="ln">${esc(str(d.when))}</span>` : "") + `</li>`)
    .join("")}</ul>`;
  return section("Done with Kliner", list);
}

// This Mac, in the same cells.
function macSection(mac) {
  if (!mac || typeof mac !== "object") return "";
  const model = str(mac.model);
  const grid = cells([
    [glyph(modelGlyph(model)), "Model", model],
    [glyph("chip"), "Chip", str(mac.chip)],
    [glyph("memory"), "Memory", str(mac.memory)],
    [glyph("disk"), "Storage", str(mac.storage)],
    [glyph("macos"), "System", str(mac.macos)],
  ]);
  return grid ? section("This Mac", grid) : "";
}

// With Kliner: the same cells, with the number said out loud.
function statsSection(p) {
  const st = p.stats && typeof p.stats === "object" ? p.stats : {};
  const figures = [
    [glyph("broom"), "Freed", Number.isSafeInteger(st.freedBytes) ? formatBytes(st.freedBytes) : ""],
    [glyph("files"), st.tidied === 1 ? "File tidied" : "Files tidied", Number.isSafeInteger(st.tidied) ? groupDigits(st.tidied) : ""],
    [glyph("clock"), "Clean since", str(st.cleanSince) ? formatShortMonth(str(st.cleanSince)) : ""],
  ].filter(([, , value]) => value);
  if (!figures.length) return "";
  const grid = `<div class="cells figs">${figures
    .map(([mark, label, value]) => {
      const [n, unit] = splitFigure(value);
      return `<div class="cell"><span class="cm">${mark}</span><span class="ct">` +
        `<span class="cl">${esc(label)}</span>` +
        `<b class="cf">${esc(n)}${unit ? `<small>${esc(unit)}</small>` : ""}</b></span></div>`;
    })
    .join("")}</div>`;
  return section("With Kliner", grid);
}

// Their links: the same cells, going somewhere, each ending in an arrow.
function linksSection(p) {
  const links = (Array.isArray(p.links) ? p.links : []).filter((l) => l && isHttpsUrl(l.url));
  if (!links.length) return "";
  const rows = links
    .map((l) =>
      `<li><a href="${esc(l.url)}" rel="nofollow noopener noreferrer ugc" target="_blank">` +
      `<span class="iw"><span class="in">${esc(str(l.title) || hostOf(l.url))}${ARROW}</span></span>` +
      `<span class="iy">${esc(hostOf(l.url))}</span></a></li>`)
    .join("");
  return section("Links", `<ul class="items">${rows}</ul>`);
}

function renderMissing(name, cfg, problem) {
  const shown = name && name.length <= 40 ? `@${name}` : "This person";
  return page({
    title: "Not found · Kliner",
    description: "",
    canonical: "",
    cfg,
    handle: "",
    hidden: true,
    body: `<div class="dots"><p class="quiet">${esc(shown)} has no public Kliner profile.</p></div>
<section class="hero">
<span class="face initial" aria-hidden="true">?</span>
<div class="hero-w"><h1>No profile here</h1>
<p class="at">${problem ? esc(problem.message) : esc(shown)}</p></div>
</section>`,
  });
}

// The top of every page about a name with no profile on it: the name, big,
// where a person's picture and name would be.
function nameHero(name, at, more) {
  return `<section class="hero">
<span class="face initial" aria-hidden="true">@</span>
<div class="hero-w"><h1>@${esc(name)}</h1>
<p class="at">${at}</p>${more ? `\n<p class="since">${more}</p>` : ""}</div>
</section>`;
}

function saidBad(bad) {
  return bad ? `<p class="say bad" role="alert">${esc(bad)}</p>` : "";
}

// Nobody's: what holding it means, and the one button that does it.
function renderFree(name, cfg, nonce, bad) {
  const handle = `@${name}`;
  return page({
    title: `${handle} is free · Kliner`,
    description: `${handle} is free on Kliner. Hold it for 30 days.`,
    canonical: "",
    cfg,
    handle: "",
    hidden: true,
    body: `<div class="dots"><p>${esc(handle)} is free.</p></div>
${nameHero(name, "Nobody has this name yet.", `${esc(hostOf(cfg.publicUrl))}/${esc(handle)}`)}
<i class="band" aria-hidden="true"></i>
<div class="head"><h2>Hold it</h2></div>
<section class="sec hold">
<p class="lede">${esc(hostOf(cfg.publicUrl))} keeps <b>${esc(handle)}</b> for you for ${CLAIM_HOLD_DAYS} days and gives you a code. Type ${esc(handle)} into Kliner as your username, then the code, and the name is yours.</p>
<form class="hold-f" method="post" action="/@${encodeURIComponent(name)}">
<input type="hidden" name="n" value="${esc(nonce)}">
<button type="submit">Hold ${esc(handle)} for ${CLAIM_HOLD_DAYS} days</button>
</form>
${saidBad(bad)}
<p class="fine">No email and no account.</p>
</section>`,
  });
}

// Held, for whoever just held it: the code, once, and what to do with it.
function renderHeldForYou(held, cfg) {
  const handle = `@${held.name}`;
  return page({
    title: `${handle} is held for you · Kliner`,
    description: "",
    canonical: "",
    cfg,
    handle: "",
    hidden: true,
    body: `<div class="dots"><p>${esc(handle)} is held for you.</p></div>
${nameHero(held.name, `Held until ${esc(longDate(held.expires))}.`)}
<i class="band" aria-hidden="true"></i>
<div class="head"><h2>Your code</h2></div>
<section class="sec hold">
<p class="code">${esc(held.code)}</p>
<p class="fine">Copy it now. ${esc(hostOf(cfg.publicUrl))} keeps only its fingerprint, so this page is the one place it is written down.</p>
<ol class="steps">
<li><span class="n">1</span><span>Get Kliner on your Mac.</span></li>
<li><span class="n">2</span><span>Type <b>${esc(handle)}</b> as your username.</span></li>
<li><span class="n">3</span><span>Type this code.</span></li>
</ol>
</section>`,
  });
}

// Somebody's, and their page is not public.
function renderUnlisted(name, cfg, bad) {
  const handle = `@${name}`;
  return page({
    title: `${handle} · Kliner`,
    description: "",
    canonical: "",
    cfg,
    handle: "",
    hidden: true,
    body: `<div class="dots"><p class="quiet">${esc(handle)} is on Kliner.</p></div>
${nameHero(name, "Their page is not public.")}
<i class="band" aria-hidden="true"></i>
<div class="head"><h2>Send ${esc(handle)} a file</h2></div>
<section class="sec hold">
${saidBad(bad)}
<p class="lede">With Kliner on your Mac, type ${esc(handle)} and choose a file. It is locked on your Mac before it leaves, and only ${esc(handle)} can open it.</p>
<p class="fine">Yours? In Kliner, open Settings, then Public page, and turn on Show my page.</p>
</section>`,
  });
}

// Kept for somebody: given up a moment ago, or held on kliner.app.
function renderHeld(name, hold, cfg, bad) {
  const handle = `@${name}`;
  const claimed = hold.kind === "claimed";
  return page({
    title: `${handle} · Kliner`,
    description: "",
    canonical: "",
    cfg,
    handle: "",
    hidden: true,
    body: `<div class="dots"><p class="quiet">${esc(handle)} ${claimed ? "is held" : "changed their username"}.</p></div>
${nameHero(name, claimed ? `Held on ${esc(hostOf(cfg.publicUrl))} until ${esc(longDate(hold.expires))}.` : "Ask them for the new one.")}
${claimed || bad ? `<i class="band" aria-hidden="true"></i>
<div class="head"><h2>${claimed ? "Yours?" : "Not now"}</h2></div>
<section class="sec hold">
${saidBad(bad)}
${claimed ? `<p class="lede">Type ${esc(handle)} into Kliner as your username, then the code you got when you held it.</p>` : ""}
</section>` : ""}`,
  });
}

function page({ title, description, canonical, cfg, body, handle, hidden }) {
  const home = esc(cfg.publicUrl);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark light">
<meta name="theme-color" content="#080808" media="(prefers-color-scheme: dark)">
<meta name="theme-color" content="#fbfbfa" media="(prefers-color-scheme: light)">
<title>${esc(title)}</title>
${description ? `<meta name="description" content="${esc(description)}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">` : ""}
${canonical ? `<link rel="canonical" href="${esc(canonical)}">
<meta property="og:url" content="${esc(canonical)}">` : ""}
<link rel="icon" href="data:,">
${hidden ? `<meta name="robots" content="noindex">\n` : ""}<style>${PAGE_CSS}</style>
</head>
<body>
<div class="page">
<i class="rails" aria-hidden="true"></i>
<header class="top">
<a class="mark" href="${home}">kliner”</a>
${handle ? `<span class="who">${esc(handle)}</span>` : ""}
<a class="get" href="${home}">Get Kliner${ARROW}</a>
</header>
<main>
${body}
</main>
<i class="band" aria-hidden="true"></i>
<footer class="foot"><span>Made with <a href="${home}">Kliner</a></span><span>${esc(hostOf(cfg.publicUrl))}</span></footer>
</div>
</body>
</html>
`;
}

// The menu bar along the top of their screen: shapes, not words — the page
// does not know what is in their menu bar and does not pretend to.
const MENU_BAR = `<div class="bar" aria-hidden="true"><span class="menus"><i></i><i></i><i></i><i></i><i></i></span><span class="gap"></span><i class="st"></i><i class="st"></i></div>`;

const ARROW = `<svg class="out" viewBox="0 0 12 12" aria-hidden="true" focusable="false"><path d="M3.4 8.6 8.6 3.4M4.4 3.4h4.2v4.2"/></svg>`;

// The small marks beside a fact. One line each, drawn here: the page fetches
// nothing, so every picture on it is either the person's own or one of these.
const GLYPHS = {
  clock: `<circle cx="12" cy="12" r="8.4"/><path d="M12 7.2V12l3.1 1.9"/>`,
  wallpaper: `<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m3 16 5-5 4.5 4.5 2.5-2.5 5 5"/><circle cx="16" cy="9.5" r="1.4"/>`,
  dark: `<path d="M20 14.2A8.2 8.2 0 1 1 9.8 4a6.4 6.4 0 0 0 10.2 10.2z"/>`,
  light: `<circle cx="12" cy="12" r="3.8"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6 7 7M17 17l1.4 1.4M5.6 18.4 7 17M17 7l1.4-1.4"/>`,
  auto: `<circle cx="12" cy="12" r="8.2"/><path d="M12 3.8a8.2 8.2 0 0 1 0 16.4z" fill="currentColor"/>`,
  desktop: `<rect x="3" y="4.5" width="18" height="12.5" rx="2"/><path d="M9 20.5h6M12 17v3.5"/>`,
  dock: `<rect x="2.5" y="14.5" width="19" height="5.5" rx="2.2"/><path d="M6 17.2h.01M10 17.2h.01M14 17.2h.01M18 17.2h.01"/>`,
  apps: `<rect x="4" y="4" width="6.5" height="6.5" rx="1.8"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.8"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.8"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.8"/>`,
  accent: `<path d="M12 3.5a8.5 8.5 0 1 0 0 17c1.2 0 1.7-.9 1.2-1.9-.5-1.1.1-2.3 1.4-2.3h1.9a4 4 0 0 0 4-4c0-4.9-3.8-8.8-8.5-8.8z"/><path d="M7.8 12h.01M9.5 8h.01M14 7.5h.01"/>`,
  chip: `<rect x="7" y="7" width="10" height="10" rx="2"/><path d="M10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4"/>`,
  memory: `<rect x="3" y="7" width="18" height="10" rx="2"/><path d="M7 11v2M11 11v2M15 11v2M19 11v2"/>`,
  disk: `<rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="M3 13.5h18"/><circle cx="17" cy="16" r="1"/>`,
  macos: `<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M3 9h18M6 6.75h.01M8.5 6.75h.01M11 6.75h.01"/>`,
  laptop: `<rect x="4" y="5" width="16" height="11" rx="2"/><path d="M2 19h20"/>`,
  imac: `<rect x="3" y="4" width="18" height="12.5" rx="2"/><path d="M9 20.5h6M12 16.5v4"/>`,
  box: `<rect x="3.5" y="8" width="17" height="8" rx="2"/><path d="M7 12h.01"/>`,
  tower: `<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M10 7h4M10 10h4"/>`,
  display: `<rect x="3" y="4.5" width="18" height="12.5" rx="2"/><path d="M9 20.5h6M12 17v3.5"/>`,
  broom: `<path d="M20 4 11.5 12.5"/><path d="M4.5 20s-1-4.5 1.5-7 6.5-1 6.5-1 1.5 4-1 6.5-7 1.5-7 1.5z"/><path d="M8 16.5 5.5 19"/>`,
  files: `<path d="M14 3.5H7.5A1.5 1.5 0 0 0 6 5v14a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 18 19V7.5z"/><path d="M14 3.5V7a.5.5 0 0 0 .5.5H18"/><path d="M9 12.5h6M9 16h4"/>`,
  link: `<path d="M10.5 13.5a4 4 0 0 0 5.7 0l2.6-2.6a4 4 0 0 0-5.7-5.7l-1.3 1.3"/><path d="M13.5 10.5a4 4 0 0 0-5.7 0l-2.6 2.6a4 4 0 0 0 5.7 5.7l1.3-1.3"/>`,
};

function glyph(name) {
  return `<svg class="g" viewBox="0 0 24 24" aria-hidden="true" focusable="false">${GLYPHS[name] || GLYPHS.link}</svg>`;
}

function modelGlyph(model) {
  const m = model.toLowerCase();
  if (m.includes("macbook")) return "laptop";
  if (m.includes("imac")) return "imac";
  if (m.includes("mac mini") || m.includes("mac studio")) return "box";
  if (m.includes("mac pro")) return "tower";
  return "display";
}

function appearanceGlyph(appearance) {
  const a = appearance.toLowerCase();
  return a === "dark" || a === "light" ? a : "auto";
}

// The accent colours macOS offers get a dot; any other word gets none.
const ACCENTS = new Set(["multicolor", "blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"]);

function swatch(accent) {
  const key = accent.toLowerCase();
  return ACCENTS.has(key) ? `<i class="sw sw-${key}" aria-hidden="true"></i>` : "";
}

// "41.3 GB" as the number and its unit, so the unit can be set smaller.
function splitFigure(value) {
  const m = /^([\d.,  ]+)\s*(.*)$/.exec(String(value));
  return m ? [m[1].trim(), m[2]] : [String(value), ""];
}

// "2026-09-01" as "September 2026" and as "Sep 2026"; the day is noise on a
// page like this, and the long name does not fit inside a cell.
function monthParts(s) {
  const m = /^(\d{4})-(\d{2})(?:-(\d{2}))?$/.exec(s);
  if (!m) return null;
  const month = Number(m[2]);
  if (!(month >= 1 && month <= 12)) return null;
  return [month - 1, m[1]];
}
function formatMonth(s) {
  const parts = monthParts(s);
  return parts ? `${LONG_MONTHS[parts[0]]} ${parts[1]}` : s;
}
function formatShortMonth(s) {
  const parts = monthParts(s);
  return parts ? `${LONG_MONTHS[parts[0]].slice(0, 3)} ${parts[1]}` : s;
}
const LONG_MONTHS = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"];

const PAGE_CSS = `
@font-face{font-family:Geist;src:url(${GEIST}) format("woff2");font-weight:400 600;font-style:normal;font-display:swap}
:root{color-scheme:dark;--col:715px;--pad:20px;
  --bg:#080808;--ink:#fafafa;--label:#d4d4d4;--muted:#a3a3a3;--faint:#737373;--soft:rgba(250,250,250,.7);
  --line:#262626;--line-2:#333335;--hatch:#171717;--dot:rgba(95,95,102,.62);
  --cell:transparent;--cell-hi:rgba(23,23,23,.55);--tile:#171717;
  --shadow:0 22px 50px -14px rgba(0,0,0,.8)}
@media (prefers-color-scheme:light){:root{color-scheme:light;
  --bg:#fbfbfa;--ink:#0a0a0a;--label:#2e2e2e;--muted:#6b6b6b;--faint:#9a9a9a;--soft:rgba(10,10,10,.68);
  --line:#e4e4e2;--line-2:#d6d6d3;--hatch:#ebebe8;--dot:rgba(0,0,0,.22);
  --cell:transparent;--cell-hi:#f3f3f1;--tile:#f1f1ef;
  --shadow:0 18px 40px -16px rgba(0,0,0,.26)}}
*{box-sizing:border-box;margin:0;padding:0}
html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
body{min-height:100vh;overflow-x:hidden;background:var(--bg);color:var(--ink);
  font-family:Geist,ui-sans-serif,-apple-system,system-ui,sans-serif;font-size:16px;line-height:1.5;
  -webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums}
img{display:block;max-width:100%}
a{color:inherit;text-decoration:none}
ul,ol,li{list-style:none}
.vh{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
.g{width:16px;height:16px;flex:none;fill:none;stroke:currentColor;stroke-width:1.55;stroke-linecap:round;stroke-linejoin:round}
.out{width:12px;height:12px;flex:none;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}

/* the column, and the two rules it is held between */
.page{position:relative;width:min(100%,var(--col));margin:0 auto}
.rails{position:absolute;top:0;bottom:0;left:-1px;right:-1px;z-index:0;pointer-events:none;
  border-left:1px solid var(--line);border-right:1px solid var(--line)}
.page>*:not(.rails){position:relative;z-index:1}
@media (max-width:820px){.page{width:100%}.rails{display:none}}

/* a hairline that crosses the whole window, not only the column */
.band,.head::after,.top::after{position:relative;left:50%;transform:translateX(-50%);width:100vw}
/* the hatch that parts one section from the next */
.band{display:block;height:24px;border-top:1px solid var(--line);border-bottom:1px solid var(--line);
  background-image:repeating-linear-gradient(315deg,transparent 0,var(--hatch) 0,var(--hatch) 1px,transparent 1px,transparent 50%);
  background-size:10px 10px}

/* the strip across the top */
.top{display:flex;align-items:center;gap:10px;height:48px;padding:0 var(--pad)}
.top::after{content:"";position:absolute;bottom:0;left:50%;height:1px;background:var(--line)}
.mark{font-size:20px;line-height:28px;font-weight:600;letter-spacing:-.02em;color:var(--ink)}
.who{font-size:14px;line-height:20px;font-weight:400;color:var(--muted)}
.get{margin-left:auto;display:inline-flex;align-items:center;gap:5px;height:30px;padding:0 12px;border-radius:7px;
  font-size:14px;line-height:20px;font-weight:500;color:var(--ink);border:1px solid var(--line);transition:background .16s ease,color .16s ease}
.get:hover{background:var(--cell-hi);color:var(--ink)}

/* what they wrote, across a field of dots */
.dots{display:flex;align-items:center;justify-content:center;min-height:104px;padding:26px var(--pad);
  background-image:radial-gradient(var(--dot) 1px,transparent 0);background-size:10px 10px}
.dots p{max-width:46ch;color:var(--ink);font-size:20px;line-height:24px;font-weight:400;letter-spacing:-.5px;
  text-align:center;text-wrap:balance;white-space:pre-line;overflow-wrap:anywhere}
.dots .quiet{color:var(--muted)}

/* who they are */
.hero{display:flex;align-items:center;gap:22px;padding:26px var(--pad) 30px;border-top:1px solid var(--line)}
.face{display:block;flex:none;width:120px;height:120px;padding:4px;border:1px solid var(--line-2);border-radius:9px}
.face img{width:100%;height:100%;border-radius:6px;object-fit:cover;background:var(--tile)}
.face.initial{display:grid;place-items:center;font-size:42px;font-weight:500;color:var(--faint);background:var(--tile)}
.hero-w{flex:1;min-width:0;display:flex;flex-direction:column;gap:4px}
.hero-w h1{font-size:30px;line-height:36px;font-weight:500;overflow-wrap:anywhere}
.at{color:var(--muted);font-size:14px;line-height:20px;font-weight:500}
.since{color:var(--muted);font-size:12px;line-height:16px;font-weight:500}
@media (max-width:560px){.hero{gap:16px;padding:22px var(--pad) 26px}.face{width:84px;height:84px}
  .face.initial{font-size:30px}.hero-w h1{font-size:24px;line-height:32px}}

/* a section name, over a rule that crosses the window */
.head{position:relative;padding:4px var(--pad)}
.head::after{content:"";position:absolute;bottom:0;left:50%;height:1px;background:var(--line)}
.head h2{font-size:30px;line-height:36px;font-weight:400;color:var(--ink)}
.sec{padding:20px var(--pad) 26px}
@media (max-width:560px){.head h2{font-size:24px;line-height:32px}}

/* facts, in cells of three */
.cells{display:flex;flex-wrap:wrap;gap:8px}
.shot+.cells{margin-top:20px}
.cell{flex:1 1 200px;display:flex;align-items:center;gap:14px;min-width:0;height:64px;padding:0 10px 0 14px;
  border:1px solid var(--line);background:var(--cell)}
.cm{display:grid;place-items:center;width:30px;height:30px;flex:none;border-radius:7px;
  color:var(--muted);background:var(--tile)}
.ct{display:flex;flex-direction:column;justify-content:center;gap:1px;min-width:0;flex:1}
.cl{color:var(--muted);font-size:14px;line-height:20px;font-weight:400;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cv{display:flex;align-items:center;gap:6px;color:var(--label);font-size:14px;line-height:20px;font-weight:500;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cf{color:var(--ink);font-size:16px;line-height:24px;font-weight:600;letter-spacing:-.4px}
.cf small{margin-left:3px;font-size:14px;font-weight:500;letter-spacing:0;color:var(--muted)}
.out-cells .cell{transition:background .16s ease}
.out-cells .cell:hover{background:var(--cell-hi)}
.out-cells .cv{color:var(--ink)}
.out-cells .out{color:var(--faint);margin-right:4px}
.out-cells .cell:hover .out{color:var(--ink)}
@media (max-width:440px){.cell{flex-basis:100%}}
.sw{width:9px;height:9px;border-radius:50%;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.2)}
.sw-multicolor{background:conic-gradient(#f45,#fa3,#4c6,#49f,#a5f,#f45)}
.sw-blue{background:#2b7fff}.sw-purple{background:#9b5cf0}.sw-pink{background:#f2609a}.sw-red{background:#e8504a}
.sw-orange{background:#f08a24}.sw-yellow{background:#e9bb24}.sw-green{background:#46ab52}.sw-graphite{background:#8b8b90}

/* the wallpapers they keep */
.walls{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}
.wp{display:flex;flex-direction:column;gap:8px;min-width:0}
.wp img,.wp i{display:block;width:100%;aspect-ratio:16/10;object-fit:cover;border-radius:7px;
  background:var(--tile);box-shadow:inset 0 0 0 1px var(--line)}
.wp.on img,.wp.on i{box-shadow:inset 0 0 0 1px var(--line),0 0 0 2px var(--ink)}
.wp figcaption{display:flex;align-items:baseline;gap:6px;min-width:0;color:var(--muted);
  font-size:12px;line-height:16px;font-weight:500}
.wp figcaption>:first-child{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.wp figcaption b{flex:none;color:var(--ink);font-weight:500}
@media (max-width:620px){.walls{grid-template-columns:repeat(3,minmax(0,1fr))}}
@media (max-width:420px){.walls{grid-template-columns:repeat(2,minmax(0,1fr))}}

/* a name, what it is, and the year — the row every page Dan picked is
   made of, and the one the links are drawn as too */
.items{border-top:1px solid var(--line)}
.items li{border-bottom:1px solid var(--line)}
.items li>a,.items li>.row{display:flex;align-items:baseline;gap:16px;padding:13px 0;
  transition:padding-left .18s cubic-bezier(.16,1,.3,1)}
.items li>a:hover{padding-left:6px}
.iw{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.in{display:inline-flex;align-items:center;gap:6px;color:var(--ink);font-size:16px;line-height:22px;font-weight:500;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.in .out{color:var(--faint);transition:color .18s ease}
.items li>a:hover .in .out{color:var(--ink)}
.io{color:var(--muted);font-size:14px;line-height:20px;font-weight:400;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.iy{flex:none;color:var(--faint);font-size:13px;line-height:22px;font-weight:500;
  font-variant-numeric:tabular-nums;white-space:nowrap}

/* what Kliner has done here */
.log{border-top:1px solid var(--line)}
.log li{display:flex;align-items:baseline;gap:14px;padding:11px 0;border-bottom:1px solid var(--line)}
.lw{flex:1;min-width:0;color:var(--label);font-size:14px;line-height:20px;font-weight:500;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ln{flex:none;color:var(--faint);font-size:12px;line-height:16px;font-weight:500;
  font-variant-numeric:tabular-nums}

/* their screen, drawn to the same figures as the one Kliner's own Home
   page draws: one cqw here is the em there — a hundredth of its width —
   so the bezel, the menu bar, the Dock and the icons come out the size
   they are in the app. */
.screen{position:relative;container-type:inline-size;aspect-ratio:16/10;border-radius:1.3cqw;overflow:hidden;
  isolation:isolate;background:#1c2633;
  box-shadow:0 0 0 1px rgba(255,255,255,.1),0 0 0 .6cqw #060606,0 0 0 calc(.6cqw + 1px) rgba(255,255,255,.12),var(--shadow)}
.shot{margin:5px 0 0}
.screen.plain{background:linear-gradient(165deg,#46698c,#1d2c3d 58%,#111a24)}
.wall{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.bar{position:absolute;left:0;right:0;top:0;z-index:3;height:2.5cqw;padding:0 1.4cqw;
  display:flex;align-items:center;gap:1.3cqw;color:rgba(255,255,255,.95);background:rgba(12,12,12,.26);
  -webkit-backdrop-filter:blur(1.6cqw) saturate(1.5);backdrop-filter:blur(1.6cqw) saturate(1.5)}
.menus{display:flex;align-items:center;gap:1.2cqw}
.menus i{display:block;width:2.6cqw;height:.62cqw;border-radius:1cqw;background:rgba(255,255,255,.5)}
.menus i:first-child{width:1cqw;height:1cqw;background:rgba(255,255,255,.92)}
.menus i:nth-child(2){width:3.4cqw;background:rgba(255,255,255,.85)}
.gap{flex:1}
.bar .st{display:block;width:1.8cqw;height:.62cqw;border-radius:1cqw;background:rgba(255,255,255,.5)}
.dock{position:absolute;left:50%;bottom:1cqw;z-index:2;transform:translateX(-50%);
  display:flex;align-items:flex-end;gap:.45cqw;min-width:14cqw;min-height:5.4cqw;padding:.55cqw .6cqw;
  border-radius:1.6cqw;background:rgba(40,40,40,.3);border:1px solid rgba(255,255,255,.2);
  -webkit-backdrop-filter:blur(1.8cqw) saturate(1.7);backdrop-filter:blur(1.8cqw) saturate(1.7)}
/* the app's own icon, square and whole — macOS already cut it */
.app{width:4.2cqw;height:4.2cqw;flex:none;display:grid;place-items:center}
.dsep{width:1px;align-self:stretch;flex:none;margin:.3cqw .15cqw;background:rgba(255,255,255,.3)}
.app img{width:100%;height:100%;object-fit:contain}
.app i{width:100%;height:100%;border-radius:23%;display:grid;place-items:center;color:#fff;font-weight:600;
  font-style:normal;background:linear-gradient(180deg,#7b8594,#3f4652);font-size:1.7cqw}
.shot figcaption{display:flex;align-items:center;gap:7px;margin-top:16px;font-size:11px;line-height:16.5px;font-weight:500;color:var(--muted)}
.shot figcaption .g{width:14px;height:14px}

/* a name's page: holding it, the code, and what a name is now */
.hold{display:flex;flex-direction:column;align-items:flex-start;gap:16px}
.lede{max-width:52ch;color:var(--label);font-size:16px;line-height:24px}
.lede b{color:var(--ink);font-weight:600}
.hold-f button{display:inline-flex;align-items:center;height:42px;padding:0 18px;border:0;border-radius:8px;
  font:inherit;font-size:15px;font-weight:500;color:var(--bg);background:var(--ink);cursor:pointer;
  transition:opacity .16s ease}
.hold-f button:hover{opacity:.86}
.hold-f button:focus-visible{outline:2px solid var(--ink);outline-offset:3px}
.say{max-width:52ch;font-size:14px;line-height:20px;font-weight:500}
.say.bad{color:#f87171}
@media (prefers-color-scheme:light){.say.bad{color:#c9372c}}
.fine{max-width:52ch;color:var(--muted);font-size:13px;line-height:19px}
.code{padding:14px 18px;border:1px solid var(--line-2);border-radius:9px;background:var(--tile);
  font-size:30px;line-height:36px;font-weight:600;letter-spacing:.08em;color:var(--ink);
  -webkit-user-select:all;user-select:all;cursor:text}
@media (max-width:420px){.code{font-size:24px;letter-spacing:.05em}}
.steps{display:flex;flex-direction:column;gap:8px;color:var(--label);font-size:15px;line-height:22px}
.steps li{display:flex;align-items:center;gap:12px}
.steps .n{display:grid;place-items:center;width:24px;height:24px;flex:none;border-radius:6px;
  font-size:12px;font-weight:600;color:var(--muted);background:var(--tile)}
.steps b{color:var(--ink);font-weight:600}

/* the line at the foot */
.foot{display:flex;align-items:center;justify-content:space-between;gap:12px;height:56px;padding:0 var(--pad);
  font-size:14px;line-height:20px;color:var(--soft)}
.foot a{color:var(--muted);border-bottom:1px solid var(--line-2)}
.foot a:hover{color:var(--ink)}

@keyframes rise{from{opacity:0;transform:translateY(8px)}}
main>*{animation:rise .5s cubic-bezier(.16,1,.3,1) both}
main>*:nth-child(n+3){animation-delay:.07s}
main>*:nth-child(n+6){animation-delay:.13s}
@media (prefers-reduced-motion:reduce){*,::before,::after{animation:none!important;transition:none!important}}
`.trim();

function str(value) {
  return typeof value === "string" ? value.trim() : "";
}

function firstLetter(s) {
  const ch = [...String(s).trim()][0] || "?";
  return ch.toUpperCase();
}

function capitalize(s) {
  return typeof s === "string" && s ? s[0].toUpperCase() + s.slice(1) : null;
}

function hostOf(url) {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}

function groupDigits(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// Decimal units, like Finder.
function formatBytes(n) {
  if (n < 1000) return `${n} ${n === 1 ? "byte" : "bytes"}`;
  const units = ["KB", "MB", "GB", "TB", "PB", "EB"];
  let v = n;
  let i = -1;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  const digits = v >= 100 ? 0 : v >= 10 ? 1 : 2;
  return `${Number(v.toFixed(digits))} ${units[i]}`;
}

// ---------------------------------------------------------------------------
// Transfers (store and forward; the server only ever sees ciphertext)
// ---------------------------------------------------------------------------

async function createTransfer(c) {
  const body = await readBody(c.request, MAX_JSON_BODY);
  const me = await authenticate(c, body);
  const input = parseJsonObject(body);
  const cfg = settings(c.env);

  if (typeof input.to !== "string" || !input.to.trim()) fail(400, "invalid", "to must be the recipient's name.");
  const to = normName(input.to).replace(/^@/, "");
  const { parts, bytes, header } = input;
  if (!Number.isInteger(parts) || parts < 1 || parts > MAX_PARTS) fail(400, "invalid", "parts must be a whole number from 1 to 10000.");
  if (!Number.isInteger(bytes) || bytes < 1) fail(400, "invalid", "bytes must be a whole number, at least 1.");
  if (typeof header !== "string" || !/^[A-Za-z0-9_-]+$/.test(header) || header.length > MAX_HEADER_CHARS) {
    fail(400, "invalid", "header must be base64url text of at most 4096 characters.");
  }
  if (to === me) fail(400, "self", "You cannot send a file to yourself.");
  if (bytes > cfg.maxBytes) fail(413, "too_big", `A transfer can be at most ${formatGiB(cfg.maxBytes)}. Send a smaller file.`);
  if (bytes < parts || bytes > parts * MAX_PART_BYTES) {
    fail(400, "invalid", "bytes does not fit parts: every part holds 1 byte to 16 MiB + 64 bytes.");
  }

  const db = c.env.DB;
  const recipient = await db.prepare("SELECT 1 AS x FROM users WHERE name = ?").bind(to).first();
  if (!recipient) {
    const hold = nameProblem(to) ? null : await activeHold(db, to);
    if (hold && hold.kind === "renamed") fail(404, "renamed", renamedMessage(to));
    fail(404, "no_user", "There is no Kliner user with that name. Check the spelling.");
  }

  const id = randomId();
  const created = now();
  const expires = created + Math.round(cfg.transferDays * 86400);
  // One statement, so two sends at the same moment cannot both slip under the cap.
  const result = await db
    .prepare(
      "INSERT INTO transfers (id, sender, recipient, parts, bytes, header, status, created, expires) " +
        "SELECT ?1, ?2, ?3, ?4, ?5, ?6, 'uploading', ?7, ?8 " +
        "WHERE (SELECT COUNT(*) FROM transfers WHERE sender = ?2 AND status IN ('uploading', 'ready') AND expires > ?7) < ?9",
    )
    .bind(id, me, to, parts, bytes, header, created, expires, cfg.maxPending)
    .run();
  if (result.meta.changes !== 1) {
    fail(429, "too_many", `You already have ${cfg.maxPending} transfers waiting. Wait until some are received, or cancel one.`);
  }
  return json({ id, expires }, 201);
}

async function putPart(c) {
  const n = partNumber(c.params.n);
  const body = await readBody(c.request, MAX_PART_BYTES, "A part can be at most 16 MiB + 64 bytes.");
  const me = await authenticate(c, body);
  if (body.byteLength < 1) fail(400, "invalid", "A part must have at least 1 byte.");
  const t = await loadTransfer(c.env, c.params.id);
  if (!t || t.sender !== me) noTransfer();
  if (t.status !== "uploading") noTransfer(stateMessage(t));
  if (t.expires <= now()) noTransfer("This transfer has expired. Start a new one.");
  if (n >= t.parts) fail(400, "invalid", `The part number must be from 0 to ${t.parts - 1}.`);
  await c.env.FILES.put(partKey(t.id, n), body); // re-putting a part replaces it
  return json({ ok: true });
}

async function markReady(c) {
  const me = await authenticate(c, await readBody(c.request, MAX_JSON_BODY));
  const t = await loadTransfer(c.env, c.params.id);
  if (!t || t.sender !== me) noTransfer();
  if (t.status === "ready") return json({ ok: true }); // a retried call
  if (t.status !== "uploading") noTransfer(stateMessage(t));
  if (t.expires <= now()) noTransfer("This transfer has expired. Start a new one.");

  // Every part 0..parts-1 must be in R2, and their sizes must add up to bytes.
  const sizes = new Map();
  let cursor;
  do {
    const page = await c.env.FILES.list({ prefix: `t/${t.id}/`, cursor });
    for (const obj of page.objects) sizes.set(obj.key, obj.size);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  const missing = [];
  let total = 0;
  for (let n = 0; n < t.parts; n++) {
    const size = sizes.get(partKey(t.id, n));
    if (size === undefined) missing.push(n);
    else total += size;
  }
  if (missing.length) {
    const list = missing.slice(0, 10).join(", ") + (missing.length > 10 ? ` and ${missing.length - 10} more` : "");
    const what = missing.length === 1 ? `Part ${list} is` : `Parts ${list} are`;
    fail(409, "incomplete", `${what} missing. Upload the missing parts, then call ready again.`);
  }
  if (total !== t.bytes) {
    fail(409, "incomplete", `The parts add up to ${total} bytes, not the ${t.bytes} this transfer was created with. Re-upload the parts.`);
  }
  const result = await c.env.DB.prepare("UPDATE transfers SET status = 'ready' WHERE id = ? AND status = 'uploading'").bind(t.id).run();
  if (result.meta.changes !== 1) {
    // Changed under us (e.g. cancelled a moment ago): report what it is now.
    const latest = await loadTransfer(c.env, t.id);
    if (!latest || latest.status !== "ready") noTransfer(latest ? stateMessage(latest) : undefined);
  }
  return json({ ok: true });
}

async function inbox(c) {
  const me = await authenticate(c, await readBody(c.request, MAX_JSON_BODY));
  const { results } = await c.env.DB.prepare(
    "SELECT id, sender, parts, bytes, header, created, expires FROM transfers " +
      "WHERE recipient = ? AND status = 'ready' AND expires > ? ORDER BY created, id LIMIT ?",
  )
    .bind(me, now(), LIST_LIMIT)
    .all();
  return json({
    transfers: results.map((r) => ({
      id: r.id,
      from: r.sender,
      parts: r.parts,
      bytes: r.bytes,
      header: r.header,
      created: r.created,
      expires: r.expires,
    })),
  });
}

async function outbox(c) {
  const me = await authenticate(c, await readBody(c.request, MAX_JSON_BODY));
  const t = now();
  const since = t - Math.round(settings(c.env).transferDays * 86400);
  const { results } = await c.env.DB.prepare(
    "SELECT id, recipient, status, parts, bytes, created, expires, done FROM transfers " +
      "WHERE sender = ? AND created >= ? ORDER BY created DESC, id DESC LIMIT ?",
  )
    .bind(me, since, LIST_LIMIT)
    .all();
  return json({
    transfers: results.map((r) => {
      // Past its expiry but not yet swept by the hourly cron: report it as expired already.
      const lapsed = (r.status === "uploading" || r.status === "ready") && r.expires <= t;
      return {
        id: r.id,
        to: r.recipient,
        status: lapsed ? "expired" : r.status,
        parts: r.parts,
        bytes: r.bytes,
        created: r.created,
        done: lapsed ? r.expires : r.done ?? null,
      };
    }),
  });
}

async function getPart(c) {
  const n = partNumber(c.params.n);
  const me = await authenticate(c, await readBody(c.request, MAX_JSON_BODY));
  const t = await loadTransfer(c.env, c.params.id);
  // Anyone but the recipient gets the same 404 as for a transfer that does not exist.
  if (!t || t.recipient !== me || t.status === "uploading") noTransfer();
  if (t.status !== "ready") noTransfer(stateMessage(t));
  if (t.expires <= now()) noTransfer("This transfer has expired.");
  if (n >= t.parts) fail(400, "invalid", `The part number must be from 0 to ${t.parts - 1}.`);
  const obj = await c.env.FILES.get(partKey(t.id, n));
  if (!obj) fail(404, "no_part", "That part is missing on the server. Ask the sender to send the file again.");
  return new Response(obj.body, {
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Length": String(obj.size),
      "Cache-Control": "no-store",
    },
  });
}

function markReceived(c) {
  return finish(c, { role: "recipient", from: ["ready"], to: "received" });
}

function declineTransfer(c) {
  return finish(c, { role: "recipient", from: ["ready"], to: "declined" });
}

function cancelTransfer(c) {
  return finish(c, { role: "sender", from: ["uploading", "ready"], to: "cancelled" });
}

// Moves a transfer to a final state, stamps `done` and deletes its parts.
// Repeating the same call is fine (it answers ok again), so a retry after a
// lost response never shows the person an error.
async function finish(c, { role, from, to }) {
  const me = await authenticate(c, await readBody(c.request, MAX_JSON_BODY));
  const db = c.env.DB;
  let t = await loadTransfer(c.env, c.params.id);
  if (!t || t[role] !== me || (role === "recipient" && t.status === "uploading")) noTransfer();
  if (t.status !== to) {
    if (!from.includes(t.status)) noTransfer(stateMessage(t));
    const allowed = from.map((s) => `'${s}'`).join(", ");
    const result = await db
      .prepare(`UPDATE transfers SET status = ?1, done = ?2 WHERE id = ?3 AND status IN (${allowed})`)
      .bind(to, now(), t.id)
      .run();
    if (result.meta.changes !== 1) {
      // The other side changed it a moment ago (e.g. cancelled while we received).
      t = await loadTransfer(c.env, t.id);
      if (!t || t.status !== to) noTransfer(t ? stateMessage(t) : undefined);
    }
  }
  await deleteParts(c.env, [t]);
  return json({ ok: true });
}

async function loadTransfer(env, id) {
  if (typeof id !== "string" || !/^[A-Za-z0-9_-]{22}$/.test(id)) return null;
  return env.DB.prepare(
    "SELECT id, sender, recipient, parts, bytes, status, created, expires, done FROM transfers WHERE id = ?",
  )
    .bind(id)
    .first();
}

function noTransfer(message = "There is no such transfer for you. It may have been cancelled, declined or expired.") {
  fail(404, "no_transfer", message);
}

function stateMessage(t) {
  switch (t.status) {
    case "received":
      return "This transfer was already received.";
    case "declined":
      return "This transfer was declined.";
    case "cancelled":
      return "The sender cancelled this transfer.";
    case "expired":
      return "This transfer has expired.";
    case "ready":
      return "This transfer is already complete; its parts can no longer change.";
    default:
      return "This transfer is still uploading.";
  }
}

function partNumber(raw) {
  if (!/^\d{1,5}$/.test(raw)) fail(400, "invalid", "The part number must be a whole number from 0 to 9999.");
  return Number(raw);
}

function partKey(id, n) {
  return `t/${id}/${n}`;
}

// Deletes the R2 parts of the given transfers ({ id, parts } rows). Keys are
// built from the part count and deleted 1000 per call, several transfers per
// call, which keeps the number of R2 operations small. An unusually long
// transfer is listed instead, since usually only a few of its keys exist.
async function deleteParts(env, transfers) {
  let keys = [];
  const flush = async () => {
    if (keys.length) await env.FILES.delete(keys);
    keys = [];
  };
  for (const t of transfers) {
    if (t.parts > 1000) {
      await deletePrefix(env, `t/${t.id}/`);
      continue;
    }
    for (let n = 0; n < t.parts; n++) {
      keys.push(partKey(t.id, n));
      if (keys.length === 1000) await flush();
    }
  }
  await flush();
}

async function deletePrefix(env, prefix) {
  let cursor;
  do {
    const page = await env.FILES.list({ prefix, cursor });
    if (page.objects.length) await env.FILES.delete(page.objects.map((o) => o.key));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}

// ---------------------------------------------------------------------------
// Cron: expire transfers, drop old rows and old rate-limit counters
// ---------------------------------------------------------------------------

async function cleanup(env) {
  const db = env.DB;
  const t = now();
  let expired = 0;
  for (let round = 0; round < CRON_ROUNDS; round++) {
    const { results } = await db
      .prepare("SELECT id, parts FROM transfers WHERE status IN ('uploading', 'ready') AND expires <= ? ORDER BY expires, id LIMIT ?")
      .bind(t, CRON_BATCH)
      .all();
    if (!results.length) break;
    await deleteParts(env, results);
    const marks = results.map(() => "?").join(", ");
    await db
      .prepare(`UPDATE transfers SET status = 'expired', done = expires WHERE status IN ('uploading', 'ready') AND id IN (${marks})`)
      .bind(...results.map((r) => r.id))
      .run();
    expired += results.length;
    if (results.length < CRON_BATCH) break;
  }
  await db.batch([
    db.prepare("DELETE FROM transfers WHERE created < ? AND status NOT IN ('uploading', 'ready')").bind(t - KEEP_ROWS_DAYS * 86400),
    // a day, so a counter that covers a day still has its row
    db.prepare("DELETE FROM hits WHERE window < ?").bind(t - 90000),
    db.prepare("DELETE FROM holds WHERE expires <= ?").bind(t),
  ]);
  console.log(`cleanup: ${expired} transfer(s) expired`);
}

// ---------------------------------------------------------------------------
// Beta codes and waitlist (not signed)
// ---------------------------------------------------------------------------

async function betaActivate(c) {
  await rateLimit(c, "beta", 10);
  const input = parseJsonObject(await readBody(c.request, MAX_JSON_BODY));
  if (typeof input.code !== "string") fail(400, "invalid", "code is required.");
  // Normalise like gen-codes.mjs: uppercase, no spaces, no dashes.
  const code = input.code.toUpperCase().replace(/[\s\-\u2010-\u2015\u2212]/g, "");
  if (!code || code.length > 64) fail(404, "unknown_code", "That code is not valid. Check it and try again.");
  const device = cleanText(input.device, "device", 64);
  if (!device) fail(400, "invalid", "device is required.");

  const db = c.env.DB;
  const hash = await sha256Hex(utf8(code));
  let row = await db.prepare("SELECT device FROM beta_codes WHERE hash = ?").bind(hash).first();
  if (!row) fail(404, "unknown_code", "That code is not valid. Check it and try again.");
  if (row.device == null) {
    // Claim it only if still unused, so two Macs racing for one code cannot both win.
    const result = await db
      .prepare("UPDATE beta_codes SET device = ?, used = ? WHERE hash = ? AND device IS NULL")
      .bind(device, now(), hash)
      .run();
    if (result.meta.changes === 1) return json({ ok: true });
    row = await db.prepare("SELECT device FROM beta_codes WHERE hash = ?").bind(hash).first();
  }
  if (row && row.device === device) return json({ ok: true });
  fail(409, "used_code", "This code was already used on another Mac. Each code works on one Mac.");
}

const EMAIL = /^[^\s@<>()[\]\\,;:"]+@([^\s@<>()[\]\\,;:".]+\.)+[^\s@<>()[\]\\,;:".]{2,}$/;

async function joinWaitlist(c) {
  await rateLimit(c, "waitlist", 10);
  const input = parseJsonObject(await readBody(c.request, MAX_JSON_BODY));
  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  if (!email || email.length > 120 || !EMAIL.test(email)) {
    fail(400, "invalid", "Enter a real email address (at most 120 characters).");
  }
  const db = c.env.DB;
  // Next position in the same statement; D1 runs writes one at a time, so
  // positions never repeat. A known address keeps its original position.
  await db
    .prepare("INSERT OR IGNORE INTO waitlist (email, position, created) VALUES (?1, (SELECT COALESCE(MAX(position), 0) + 1 FROM waitlist), ?2)")
    .bind(email, now())
    .run();
  const row = await db.prepare("SELECT position FROM waitlist WHERE email = ?").bind(email).first();
  return json({ ok: true, position: row.position });
}

// ---------------------------------------------------------------------------
// Rate limits: one D1 row per bucket, IP and minute, e.g. "names:1.2.3.4:29833333"
// ---------------------------------------------------------------------------

async function rateLimit(c, bucket, perMinute) {
  const minute = Math.floor(now() / 60);
  const key = `${bucket}:${clientAddress(c.request)}:${minute}`;
  const row = await c.env.DB.prepare(
    "INSERT INTO hits (key, count, window) VALUES (?1, 1, ?2) ON CONFLICT(key) DO UPDATE SET count = count + 1 RETURNING count",
  )
    .bind(key, minute * 60)
    .first();
  if (row && row.count > perMinute) {
    const wait = 60 - (now() % 60);
    fail(429, "rate_limited", `Too many requests from your network. Wait ${wait} seconds and try again.`, {
      "Retry-After": String(wait),
    });
  }
}

// The same counters over a longer window (an hour, a day) and any key: the
// names one network holds, the times one key changes its name.
async function countIn(c, key, max, seconds, message) {
  const slot = Math.floor(now() / seconds);
  const row = await c.env.DB.prepare(
    "INSERT INTO hits (key, count, window) VALUES (?1, 1, ?2) ON CONFLICT(key) DO UPDATE SET count = count + 1 RETURNING count",
  )
    .bind(`${key}:${seconds}:${slot}`, slot * seconds)
    .first();
  if (row && row.count > max) {
    const wait = (slot + 1) * seconds - now();
    fail(429, "rate_limited", message(wait), { "Retry-After": String(wait) });
  }
}

// IPv4 as is. IPv6 per /64, since one home or phone usually holds a whole /64.
function clientAddress(request) {
  const ip = (request.headers.get("CF-Connecting-IP") || "unknown").trim().toLowerCase();
  if (!ip.includes(":")) return ip;
  if (ip.includes(".")) return ip.slice(ip.lastIndexOf(":") + 1); // IPv4-mapped
  const [head, tail] = ip.split("::");
  const left = head ? head.split(":") : [];
  const right = tail === undefined ? [] : tail ? tail.split(":") : [];
  const groups = tail === undefined ? left : [...left, ...Array(Math.max(0, 8 - left.length - right.length)).fill("0"), ...right];
  return `${groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, "")).join(":")}::/64`;
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function now() {
  return Math.floor(Date.now() / 1000);
}

function settings(env) {
  const number = (value, fallback, min) => {
    const n = Number(value);
    return Number.isFinite(n) && n >= min ? n : fallback;
  };
  return {
    publicUrl: String(env.PUBLIC_URL || "https://kliner.app").replace(/\/+$/, ""),
    maxBytes: number(env.MAX_BYTES, 5368709120, 1),
    transferDays: number(env.TRANSFER_DAYS, 7, 0),
    maxPending: number(env.MAX_PENDING, 20, 1),
  };
}

function formatGiB(bytes) {
  const gib = bytes / 1024 ** 3;
  return gib >= 1 ? `${Number(gib.toFixed(2))} GiB` : `${bytes} bytes`;
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });
}

function errorResponse(status, code, message, headers) {
  return json({ error: code, message }, status, headers || {});
}

// Reads the whole body into memory (the signature covers the exact bytes),
// giving up with 413 as soon as it passes `limit`, so an oversized upload is
// never buffered in full.
async function readBody(request, limit, tooBig = "The request body is too large.") {
  const declared = request.headers.get("Content-Length");
  if (declared !== null && Number(declared) > limit) fail(413, "too_big", tooBig);
  if (!request.body) return new Uint8Array(0);
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel().catch(() => {});
      fail(413, "too_big", tooBig);
    }
    chunks.push(value);
  }
  if (chunks.length === 1) return chunks[0];
  const out = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

function parseJsonObject(bytes) {
  let value;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    fail(400, "invalid", "The request body must be a JSON object.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(400, "invalid", "The request body must be a JSON object.");
  return value;
}

function utf8(s) {
  return new TextEncoder().encode(s);
}

async function sha256Hex(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  let hex = "";
  for (const b of digest) hex += b.toString(16).padStart(2, "0");
  return hex;
}

function randomId() {
  return b64uEncode(crypto.getRandomValues(new Uint8Array(16))); // 22 characters
}

function b64uEncode(bytes) {
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// base64url without padding (trailing "=" is forgiven). null when malformed.
function b64uDecode(s) {
  if (typeof s !== "string") return null;
  const data = s.replace(/=+$/, "");
  if (!/^[A-Za-z0-9_-]*$/.test(data) || data.length % 4 === 1) return null;
  const bin = atob(data.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((data.length + 3) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

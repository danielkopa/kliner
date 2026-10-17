#!/usr/bin/env node
// End-to-end test of the Kliner Worker against a local `wrangler dev`.
//
// It creates a temp dir for local D1 + R2 state, applies schema.sql there,
// runs gen-codes.mjs in a scratch copy and loads its beta-codes.sql, starts
//   wrangler dev --local --persist-to <temp> --port <free> --test-scheduled
// runs every scenario over HTTP with the reference client, prints a pass/fail
// summary, stops wrangler and exits non-zero on any failure.
//
// Run from anywhere:  node test/e2e.mjs        (KEEP=1 keeps the temp dir)
// Uses ./node_modules/.bin/wrangler when present, else `npx --yes wrangler@3`.

import { execFile, spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { CHUNK, Kliner, b64u, decryptPart, encryptFile, newIdentity, sha256Hex, signRequest } from "./client.mjs";

const run = promisify(execFile);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const LOCAL_WRANGLER = path.join(ROOT, "node_modules", ".bin", "wrangler");
const WRANGLER = fs.existsSync(LOCAL_WRANGLER) ? [LOCAL_WRANGLER] : ["npx", "--yes", "wrangler@3"];

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "kliner-e2e-"));
const PERSIST = path.join(TMP, "state");
const ENV = {
  ...process.env,
  WRANGLER_SEND_METRICS: "false",
  // Keep wrangler's own state (logs, metrics id, dev registry) in the temp dir, not ~/.config.
  WRANGLER_LOG_PATH: path.join(TMP, "logs"),
  XDG_CONFIG_HOME: path.join(TMP, "config"),
  // Miniflare otherwise downloads workers.cloudflare.com/cf.json (only for the
  // Request.cf placeholder) on every start; behind a proxy that blocks it each
  // wrangler call waits ~10 s for a timeout. The Worker never reads NODE_ENV.
  NODE_ENV: "test",
  NO_COLOR: "1",
  FORCE_COLOR: "0",
};

const RUN_ID = crypto.randomBytes(2).toString("hex"); // keeps names unique if KEEP=1 state is reused
const MAX_PENDING = 20;
const MAX_BYTES = 5368709120;
const CSP =
  "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const HOLD_CSP = CSP.replace("form-action 'none'", "form-action 'self'");

let BASE = "";
let dev = null;
const APP_ZIP = Buffer.concat([Buffer.from([0x50, 0x4b, 0x03, 0x04]), crypto.randomBytes(4096)]);
// a disk image's worth of fake bytes, with the "koly" trailer a real one ends in
const APP_DMG = Buffer.concat([crypto.randomBytes(8192), Buffer.from("koly"), Buffer.alloc(508)]);
const DMG_SHA = crypto.createHash("sha256").update(APP_DMG).digest("hex");

// ---------------------------------------------------------------------------
// Tiny test harness: named tests made of checks; a failed check is recorded
// and the test goes on, so one run shows every problem.
// ---------------------------------------------------------------------------

const results = [];
let current = null;

async function test(name, fn) {
  current = { name, checks: 0, failures: [] };
  const started = Date.now();
  try {
    await fn();
  } catch (err) {
    current.failures.push(`threw: ${err && err.stack ? err.stack.split("\n").slice(0, 4).join(" | ") : err}`);
  }
  const ms = Date.now() - started;
  results.push(current);
  const ok = current.failures.length === 0;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}  (${current.checks} checks, ${ms} ms)`);
  for (const f of current.failures) console.log(`        x ${f}`);
}

function check(condition, message) {
  current.checks++;
  if (!condition) current.failures.push(message);
  return Boolean(condition);
}

function same(actual, expected, message) {
  return check(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
  );
}

function show(res) {
  return `${res.status} ${(res.text ?? `<${res.bytes.length} bytes>`).slice(0, 240)}`;
}

function isOk(res, status, message) {
  return check(res.status === status, `${message}: expected ${status}, got ${show(res)}`);
}

// An error must be {"error": code, "message": "..."} with the right status and no-store.
function isError(res, status, code, message, mention) {
  check(res.status === status && res.json?.error === code, `${message}: expected ${status} ${code}, got ${show(res)}`);
  check(typeof res.json?.message === "string" && res.json.message.length > 10, `${message}: has a readable message`);
  check(res.headers.get("cache-control") === "no-store", `${message}: error is no-store`);
  if (mention) check(res.json?.message?.includes(mention), `${message}: message names "${mention}" (got "${res.json?.message}")`);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let ipCount = 0;
function nextIp() {
  ipCount++;
  return `10.77.${Math.floor(ipCount / 250)}.${(ipCount % 250) + 1}`;
}

function user(prefix) {
  return new Kliner(BASE, { name: `${prefix}${RUN_ID}`, ip: nextIp() });
}

function anon() {
  return new Kliner(BASE, { ip: nextIp() });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const nowSec = () => Math.floor(Date.now() / 1000);

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

async function wrangler(args) {
  return run(WRANGLER[0], [...WRANGLER.slice(1), ...args], { cwd: ROOT, env: ENV, maxBuffer: 64 * 1024 * 1024 });
}

// Runs SQL on the local D1 that wrangler dev uses; returns the last statement's rows.
async function sql(query) {
  const { stdout } = await wrangler(["d1", "execute", "kliner", "--local", "--persist-to", PERSIST, "--json", "--command", query]);
  const start = stdout.indexOf("[");
  const parsed = JSON.parse(stdout.slice(start));
  return parsed.at(-1).results;
}

// Puts an object into the local R2 the way deploy.sh does, while wrangler dev runs.
async function r2Put(key, bytes, type) {
  const file = path.join(TMP, "put-" + crypto.randomBytes(4).toString("hex"));
  fs.writeFileSync(file, bytes);
  await wrangler(["r2", "object", "put", `kliner-transfers/${key}`, "--local", "--persist-to", PERSIST, "--file", file, "--content-type", type]);
}

async function r2Has(key) {
  try {
    await wrangler(["r2", "object", "get", `kliner-transfers/${key}`, "--local", "--persist-to", PERSIST, "--pipe"]);
    return true;
  } catch (err) {
    if (/does not exist/i.test(`${err.stdout}${err.stderr}`)) return false;
    throw err;
  }
}

// Fake image bytes with the right file signature (the server checks signatures, not pixels).
function fakeImage(kind, size) {
  const magic = kind === "png" ? [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] : [0xff, 0xd8, 0xff, 0xe0];
  return Buffer.concat([Buffer.from(magic), crypto.randomBytes(Math.max(0, size - magic.length))]);
}

function dataUrl(kind, bytes) {
  return `data:image/${kind};base64,${bytes.toString("base64")}`;
}

// A raw transfer the test controls part by part (header is opaque to the server).
async function rawTransfer(sender, to, partSizes) {
  const bytes = partSizes.reduce((a, b) => a + b, 0);
  const res = await sender.request("POST", "/v1/transfers", {
    body: { to, parts: partSizes.length, bytes, header: b64u.encode(crypto.randomBytes(48)) },
    signed: true,
  });
  if (res.status !== 201) throw new Error(`create failed: ${show(res)}`);
  return res.json.id;
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

const alice = () => shared.alice;
const bob = () => shared.bob;
const carol = () => shared.carol;
const shared = {};

async function scenarios(betaCodes) {
  await test("health", async () => {
    const res = await anon().request("GET", "/v1/health");
    isOk(res, 200, "GET /v1/health");
    same(res.json, { ok: true, version: "1" }, "health body");
    check(res.headers.get("content-type")?.startsWith("application/json"), "health is JSON");
    check(res.headers.get("cache-control") === "no-store", "health is no-store");
    check(res.headers.get("x-kliner") === "1", "an answer says it is Kliner's (X-Kliner: 1)");
    const head = await anon().request("HEAD", "/v1/health");
    check(head.status === 200 && head.bytes.length === 0, `HEAD /v1/health gives 200 without a body, got ${head.status}`);
    check(head.headers.get("x-kliner") === "1", "HEAD carries X-Kliner too");
  });

  await test("register: create, idempotent repeat, taken by another key", async () => {
    shared.alice = user("alice");
    shared.bob = user("bob");
    shared.carol = user("carol");
    const t0 = nowSec();
    const first = await alice().request("POST", "/v1/users", {
      body: { name: alice().name, sign: alice().signPublic, box: alice().boxPublic, device: "Alice's MacBook" },
      signed: true,
    });
    isOk(first, 201, "first registration");
    same(Object.keys(first.json ?? {}), ["name", "created"], "201 body keys");
    check(first.json?.name === alice().name, "201 echoes the name");
    check(Math.abs(first.json?.created - t0) < 10, "created is now");

    const again = await alice().request("POST", "/v1/users", {
      body: { name: alice().name, sign: alice().signPublic, box: alice().boxPublic, device: "Alice's MacBook" },
      signed: true,
    });
    isOk(again, 200, "same name, same key again");
    same(again.json, first.json, "idempotent repeat returns the original name and created");

    const upper = await alice().request("POST", "/v1/users", {
      body: { name: alice().name.toUpperCase(), sign: alice().signPublic, box: alice().boxPublic, device: "x" },
      signed: true,
    });
    isOk(upper, 200, "uppercase spelling of my own name is the same name");
    check(upper.json?.name === alice().name, "stored lowercase");

    await bob().register("Bob's iMac");
    await carol().register("Carol's Mac mini");

    const thief = new Kliner(BASE, { name: alice().name, ip: nextIp() });
    isError(await thief.request("POST", "/v1/users", {
      body: { name: alice().name, sign: thief.signPublic, box: thief.boxPublic, device: "other" },
      signed: true,
    }), 409, "taken", "same name, different key");

    const x = anon();
    x.name = "support";
    isError(await x.request("POST", "/v1/users", { body: { name: "support", sign: x.signPublic, box: x.boxPublic }, signed: true }), 400, "reserved", "reserved name");
    x.name = "9lives";
    isError(await x.request("POST", "/v1/users", { body: { name: "9lives", sign: x.signPublic, box: x.boxPublic }, signed: true }), 400, "invalid", "invalid name");
    x.name = `kay${RUN_ID}`;
    isError(await x.request("POST", "/v1/users", { body: { name: x.name, sign: "abc", box: x.boxPublic }, signed: true }), 400, "invalid", "short sign key", "sign");
    isError(await x.request("POST", "/v1/users", { body: { name: x.name, sign: x.signPublic, box: "@@" }, signed: true }), 400, "invalid", "bad box key", "box");
    isError(await x.request("POST", "/v1/users", { body: { name: x.name, sign: x.signPublic, box: x.boxPublic, device: "d".repeat(65) }, signed: true }), 400, "invalid", "device too long", "device");
    // Signed by a key other than the one being registered: no proof of possession.
    isError(await x.request("POST", "/v1/users", {
      body: { name: x.name, sign: x.signPublic, box: x.boxPublic },
      signed: true,
      signer: newIdentity().sign.privateKey,
    }), 401, "bad_signature", "registration signed by another key");
    isError(await x.request("POST", "/v1/users", { body: { name: x.name, sign: x.signPublic, box: x.boxPublic }, signed: true, time: nowSec() - 900 }), 401, "stale", "stale registration");
    isError(await x.request("POST", "/v1/users", { body: "not an object", signed: true }), 400, "invalid", "non-object body");
    const lookup = await anon().request("GET", `/v1/users/${x.name}`);
    isError(lookup, 404, "no_user", "failed registrations created nothing");
  });

  await test("names: free, taken, reserved, invalid", async () => {
    const c = anon();
    const fresh = `zed${RUN_ID}x`;
    const free = await c.request("GET", `/v1/names/${fresh}`);
    isOk(free, 200, "free name");
    same(free.json, { name: fresh, free: true }, "free body");
    check(free.headers.get("cache-control") === "no-store", "names is no-store");
    same((await c.request("GET", `/v1/names/${fresh.toUpperCase()}`)).json, { name: fresh, free: true }, "names compare lowercase");
    same((await c.request("GET", "/v1/names/a.b_c9")).json?.free, true, "dots, underscores, digits are fine");

    const taken = await c.request("GET", `/v1/names/${alice().name}`);
    same([taken.json?.name, taken.json?.free, taken.json?.reason], [alice().name, false, "taken"], "taken");
    check(typeof taken.json?.message === "string" && taken.json.message.length > 5, "taken has a message");
    same(Object.keys(taken.json ?? {}), ["name", "free", "reason", "message"], "taken body keys");

    for (const name of ["admin", "support", "me", "waitlist", "Kliner"]) {
      const res = await c.request("GET", `/v1/names/${name}`);
      same([res.json?.free, res.json?.reason], [false, "reserved"], `reserved: ${name}`);
    }
    for (const name of ["ab", "1abc", "_abc", "a..b", "abc.", "ab-c", "abc def", "abcdefghijklmnopqrstu", "tomáš", "a/b"]) {
      const res = await c.request("GET", `/v1/names/${encodeURIComponent(name)}`);
      isOk(res, 200, `invalid name answers 200: ${name}`);
      same([res.json?.free, res.json?.reason], [false, "invalid"], `invalid: ${JSON.stringify(name)}`);
      check(typeof res.json?.message === "string" && res.json.message.length > 5, `invalid has a message: ${name}`);
    }
    same((await c.request("GET", "/v1/names/abcdefghijklmnopqrst")).json?.free, true, "exactly 20 characters is fine");
  });

  await test("signed requests: bad signature, stale time, unknown user", async () => {
    const a = alice();
    isOk(await a.request("GET", "/v1/inbox", { signed: true }), 200, "a correct signature works");
    isError(await a.request("GET", "/v1/inbox", { signed: true, signer: newIdentity().sign.privateKey }), 401, "bad_signature", "wrong key");
    isError(await a.request("GET", "/v1/inbox", { signed: true, time: nowSec() - 301 - 5 }), 401, "stale", "time 5 minutes in the past");
    isError(await a.request("GET", "/v1/inbox", { signed: true, time: nowSec() + 400 }), 401, "stale", "time in the future");
    isOk(await a.request("GET", "/v1/inbox", { signed: true, time: nowSec() - 240 }), 200, "4 minutes of skew is accepted");
    isError(await a.request("GET", "/v1/inbox", { signed: true, user: `nobody${RUN_ID}` }), 401, "bad_signature", "unknown user");
    isError(await a.request("GET", "/v1/inbox"), 401, "bad_signature", "no signature headers");
    isError(await a.request("GET", "/v1/inbox", { signed: true, headers: { "X-Kliner-Time": "soon" } }), 401, "bad_signature", "non-numeric time");

    // Signature over one body, a different body sent.
    const t = String(nowSec());
    const signed = Buffer.from(JSON.stringify({ visible: false }));
    const sent = Buffer.from(JSON.stringify({ visible: true }));
    const tampered = await fetch(`${BASE}/v1/profile`, {
      method: "PUT",
      headers: {
        "X-Kliner-User": a.name,
        "X-Kliner-Time": t,
        "X-Kliner-Sig": signRequest(a.identity.sign.privateKey, "PUT", "/v1/profile", t, signed),
        "CF-Connecting-IP": a.ip,
      },
      body: sent,
    });
    const body = await tampered.json();
    check(tampered.status === 401 && body.error === "bad_signature", `tampered body is rejected, got ${tampered.status} ${JSON.stringify(body)}`);

    // Signature for another path.
    const wrongPath = await fetch(`${BASE}/v1/inbox`, {
      headers: {
        "X-Kliner-User": a.name,
        "X-Kliner-Time": t,
        "X-Kliner-Sig": signRequest(a.identity.sign.privateKey, "GET", "/v1/outbox", t, Buffer.alloc(0)),
      },
    });
    check(wrongPath.status === 401, `signature for another path is rejected, got ${wrongPath.status}`);
    // The empty-body hash from the spec.
    check(sha256Hex(Buffer.alloc(0)) === "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty body hash");
  });

  await test("lookup", async () => {
    const res = await anon().request("GET", `/v1/users/${alice().name}`);
    isOk(res, 200, "lookup alice");
    same(Object.keys(res.json ?? {}), ["name", "sign", "box", "created"], "lookup keys");
    same([res.json?.name, res.json?.sign, res.json?.box], [alice().name, alice().signPublic, alice().boxPublic], "lookup values");
    check(Number.isInteger(res.json?.created), "created is an integer");
    same((await anon().request("GET", `/v1/users/${alice().name.toUpperCase()}`)).json?.name, alice().name, "lookup is case-insensitive");
    check(res.headers.get("cache-control") === "no-store", "lookup is no-store");
    isError(await anon().request("GET", `/v1/users/nobody${RUN_ID}`), 404, "no_user", "unknown user");
    isError(await anon().request("GET", "/v1/users/me"), 404, "no_user", "GET /v1/users/me is not a user");
  });

  await test("profile: PUT strips and validates, GET json, HTML page", async () => {
    const a = alice();
    const avatar = dataUrl("jpeg", fakeImage("jpeg", 2000));
    const thumb = dataUrl("png", fakeImage("png", 3000));
    const dockIcon = dataUrl("png", fakeImage("png", 900));
    const put = await a.request("PUT", "/v1/profile", {
      signed: true,
      body: {
        visible: true,
        display: "  Daniel <b>Novák</b>  ",
        bio: "  Designer in Bratislava <script>alert('x')</script> & more  ",
        links: [
          { title: " Site ", url: " https://example.com/a?b=1&c=2 ", junk: 1 },
          { title: 'Quote " and <tag>', url: "https://example.org/" },
          { url: "https://github.com/kliner" },
        ],
        avatar,
        mac: { model: " MacBook Air ", chip: "Apple M2", memory: "8 GB", macos: "macOS 26.1", storage: "228 GB", serial: "C02XYZ" },
        setup: {
          wallpaper: "Sequoia Sunrise",
          wallpaperThumb: thumb,
          appearance: "Dark",
          accent: "multicolor",
          dock: ["Safari", { name: " Figma ", icon: dockIcon, junk: 1 }, "", { name: "Mail" }, { name: "" }],
          dockAutohide: true,
          desktop: "icons hidden",
          apps: 142,
          secret: "dropped",
        },
        stats: { freedBytes: 1932735283, tidied: 214, cleanSince: "2026-09-01", extra: true },
        since: "2026-09-30",
        email: "dropped@example.com",
        name: "mallory",
      },
    });
    isOk(put, 200, "PUT /v1/profile");
    same(put.json, { ok: true, url: `https://kliner.app/@${a.name}` }, "PUT answer");

    const got = await anon().request("GET", `/v1/users/${a.name}/profile`);
    isOk(got, 200, "GET profile json");
    const p = got.json ?? {};
    same(p.name, a.name, "profile json carries the real name, not the one in the body");
    same(p.visible, true, "visible");
    same(p.display, "Daniel <b>Novák</b>", "display trimmed (and stored as text)");
    same(p.bio, "Designer in Bratislava <script>alert('x')</script> & more", "bio trimmed");
    same(p.links, [
      { title: "Site", url: "https://example.com/a?b=1&c=2" },
      { title: 'Quote " and <tag>', url: "https://example.org/" },
      { url: "https://github.com/kliner" },
    ], "links trimmed, junk dropped");
    same(p.avatar, avatar, "avatar kept");
    same(p.mac, { model: "MacBook Air", chip: "Apple M2", memory: "8 GB", macos: "macOS 26.1", storage: "228 GB" }, "mac stripped");
    same(p.setup, {
      wallpaper: "Sequoia Sunrise",
      wallpaperThumb: thumb,
      appearance: "dark",
      accent: "multicolor",
      dock: ["Safari", { name: "Figma", icon: dockIcon }, { name: "Mail" }],
      dockAutohide: true,
      desktop: "icons hidden",
      apps: 142,
    }, "setup stripped, empty dock names dropped, an app's own icon kept");
    same(p.stats, { freedBytes: 1932735283, tidied: 214, cleanSince: "2026-09-01" }, "stats stripped");
    same(p.since, "2026-09-30", "since");
    check(!("email" in p) && !("serial" in (p.mac ?? {})), "unknown fields are gone");

    // Validation: each wrong field is a 400 naming it.
    const bad = [
      [{ display: "x".repeat(61) }, "display"],
      [{ bio: 42 }, "bio"],
      [{ bio: "b".repeat(281) }, "bio"],
      [{ visible: "yes" }, "visible"],
      [{ links: "https://x.com" }, "links"],
      [{ links: Array.from({ length: 6 }, (_, i) => ({ title: `L${i}`, url: `https://x${i}.com` })) }, "links"],
      [{ links: [{ title: "Old", url: "http://example.com" }] }, "links[0].url"],
      [{ links: [{ title: "JS", url: "javascript:alert(1)" }] }, "links[0].url"],
      [{ links: [{ title: "t".repeat(41), url: "https://a.co" }] }, "links[0].title"],
      [{ links: [{ title: "Long", url: `https://a.co/${"p".repeat(200)}` }] }, "links[0].url"],
      [{ links: [7] }, "links[0]"],
      [{ avatar: "data:image/gif;base64,R0lGODlhAQABAAAAACw=" }, "avatar"],
      [{ avatar: "https://example.com/me.jpg" }, "avatar"],
      [{ avatar: dataUrl("png", fakeImage("jpeg", 500)) }, "avatar"],
      [{ avatar: `data:image/jpeg;base64,${fakeImage("jpeg", 500).toString("base64")}"onerror="x` }, "avatar"],
      [{ avatar: dataUrl("jpeg", fakeImage("jpeg", 150 * 1024 + 1)) }, "avatar"],
      [{ mac: "MacBook" }, "mac"],
      [{ mac: { chip: 2 } }, "mac.chip"],
      [{ setup: { apps: "many" } }, "setup.apps"],
      [{ setup: { apps: -1 } }, "setup.apps"],
      [{ setup: { apps: 1.5 } }, "setup.apps"],
      [{ setup: { appearance: "purple" } }, "setup.appearance"],
      [{ setup: { accent: "a".repeat(21) } }, "setup.accent"],
      [{ setup: { desktop: "d".repeat(21) } }, "setup.desktop"],
      [{ setup: { dock: ["x".repeat(41)] } }, "setup.dock[0]"],
      [{ setup: { dock: [{ name: "x".repeat(41) }] } }, "setup.dock[0].name"],
      [{ setup: { dock: [{ name: "Safari", icon: "https://example.com/safari.png" }] } }, "setup.dock[0].icon"],
      [{ setup: { dock: [{ name: "Safari", icon: dataUrl("png", fakeImage("jpeg", 500)) }] } }, "setup.dock[0].icon"],
      [{ setup: { dock: [{ name: "Safari", icon: dataUrl("png", fakeImage("png", 28 * 1024 + 1)) }] } }, "setup.dock[0].icon"],
      [{ setup: { trash: dataUrl("png", fakeImage("png", 28 * 1024 + 1)) } }, "setup.trash"],
      [{ setup: { walls: "many" } }, "setup.walls"],
      [{ setup: { walls: Array.from({ length: 9 }, () => ({ name: "W" })) } }, "setup.walls"],
      [{ setup: { walls: ["Pro Black"] } }, "setup.walls[0]"],
      [{ setup: { walls: [{ name: "x".repeat(81) }] } }, "setup.walls[0].name"],
      [{ setup: { walls: [{ name: "Pro Black", thumb: dataUrl("jpeg", fakeImage("jpeg", 60 * 1024 + 1)) }] } }, "setup.walls[0].thumb"],
      [{ done: "lots" }, "done"],
      [{ done: Array.from({ length: 11 }, () => ({ what: "Tidied" })) } , "done"],
      [{ done: ["Tidied"] }, "done[0]"],
      [{ done: [{ what: "x".repeat(81) }] }, "done[0].what"],
      [{ role: "r".repeat(61) }, "role"],
      [{ place: "p".repeat(61) }, "place"],
      [{ work: "lots" }, "work"],
      [{ work: Array.from({ length: 15 }, () => ({ name: "A" })) }, "work"],
      [{ work: ["Kliner"] }, "work[0]"],
      [{ work: [{ name: "x".repeat(61) }] }, "work[0].name"],
      [{ work: [{ name: "Kliner", when: "w".repeat(21) }] }, "work[0].when"],
      [{ work: [{ name: "Kliner", note: "n".repeat(91) }] }, "work[0].note"],
      [{ work: [{ name: "Kliner", url: "http://kliner.app" }] }, "work[0].url"],
      [{ setup: { wallpaperThumb: dataUrl("jpeg", fakeImage("jpeg", 330 * 1024 + 1)) } }, "setup.wallpaperThumb"],
      [{ setup: { dock: Array.from({ length: 41 }, () => "App") } }, "setup.dock"],
      [{ setup: { dockAutohide: "yes" } }, "setup.dockAutohide"],
      [{ stats: { freedBytes: "1 GB" } }, "stats.freedBytes"],
      [{ stats: { tidied: -3 } }, "stats.tidied"],
      [{ since: 20260930 }, "since"],
    ];
    for (const [body, field] of bad) {
      isError(await a.request("PUT", "/v1/profile", { body, signed: true }), 400, "invalid", `bad ${field}`, field);
    }
    isError(await a.request("PUT", "/v1/profile", { body: new TextEncoder().encode("{not json"), signed: true }), 400, "invalid", "not JSON");
    isError(await a.request("PUT", "/v1/profile", { body: [1, 2], signed: true }), 400, "invalid", "a JSON array");
    isError(await a.request("PUT", "/v1/profile", { body: { bio: "x".repeat(810 * 1024) }, signed: true }), 413, "too_big", "body over 800 KB");
    isError(await a.request("PUT", "/v1/profile", { body: { visible: true } }), 401, "bad_signature", "unsigned PUT");
    // A big but allowed profile: a sharp wallpaper, a full Dock of real
    // icons and the bin, all near their limits and the body under 800 KB.
    const big = await a.request("PUT", "/v1/profile", {
      signed: true,
      body: {
        visible: true,
        display: "Big",
        avatar: dataUrl("jpeg", fakeImage("jpeg", 100 * 1024)),
        setup: {
          wallpaperThumb: dataUrl("jpeg", fakeImage("jpeg", 230 * 1024)),
          trash: dataUrl("png", fakeImage("png", 15 * 1024)),
          dock: Array.from({ length: 6 }, (_, i) => ({ name: `App ${i}`, icon: dataUrl("png", fakeImage("png", 15 * 1024)) })),
        },
      },
    });
    isOk(big, 200, "a sharp wallpaper and a Dock of real icons, under 800 KB");

    // The failed PUTs changed nothing; restore the full profile for the page checks.
    isOk(await a.request("PUT", "/v1/profile", {
      signed: true,
      body: {
        visible: true,
        display: "Daniel <b>Novák</b>",
        bio: "Designer in Bratislava <script>alert('x')</script> & more",
        role: "Building Kliner",
        place: "Bratislava",
        work: [
          { name: "Kliner", when: "2026", url: "https://kliner.app", note: "A Mac that stays tidy" },
          { name: "No <b>link</b> here", when: "2024" },
        ],
        links: [{ title: "Site", url: "https://example.com/a?b=1&c=2" }, { title: 'Quote " and <tag>', url: "https://example.org/" }],
        avatar,
        mac: { model: "MacBook Air", chip: "Apple M2", memory: "8 GB", macos: "macOS 26.1", storage: "228 GB" },
        setup: {
          wallpaper: "Sequoia Sunrise", wallpaperThumb: thumb, appearance: "dark",
          dock: ["Safari", { name: "Figma", icon: dockIcon }], trash: dockIcon, desktop: "clear", apps: 142,
          walls: [{ name: "Pro Black", thumb, on: true }, { name: "Named <b>only</b>" }],
        },
        done: [{ what: "Sorted your downloads", when: "Oct 9, 11:40" }, { what: "Cleared your desktop" }],
        stats: { freedBytes: 1932735283, tidied: 214, cleanSince: "2026-09-01" },
        since: "2026-09-30",
      },
    }), 200, "restore profile");

    const page = await anon().request("GET", `/@${a.name}`);
    isOk(page, 200, "GET /@name");
    same(page.headers.get("x-kliner"), "1", "a profile page carries X-Kliner too");
    const html = page.text ?? "";
    check(page.headers.get("content-type") === "text/html; charset=utf-8", `HTML content type, got ${page.headers.get("content-type")}`);
    same(page.headers.get("content-security-policy"), CSP, "CSP header");
    same(page.headers.get("cache-control"), "public, max-age=60", "profile page cache");
    check(html.includes('<p>Designer in Bratislava &lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; more</p>'), "bio <script> is escaped in the bio paragraph");
    check(!/<script/i.test(html), "no <script> anywhere in the page");
    check(html.includes("Daniel &lt;b&gt;Novák&lt;/b&gt;") && !html.includes("<b>Novák"), "display is escaped");
    check(html.includes("Quote &quot; and &lt;tag&gt;"), "link title is escaped");
    check(html.includes('href="https://example.com/a?b=1&amp;c=2"'), "link href is escaped");
    check(html.includes(`@${a.name}`), "handle shown");
    check(html.includes("kliner”") && html.includes('href="https://kliner.app"'), "wordmark links to PUBLIC_URL");
    check(html.includes(`<span class="face"><img src="${avatar}"`), "avatar image in its frame");
    check(html.includes(thumb) && html.includes("Sequoia Sunrise"), "wallpaper thumbnail and name");
    check(html.includes(`<img src="${dockIcon}" alt="Figma"`), "the Dock draws the app's own icon");
    check(html.includes('<span class="vh">Safari</span>'), "an app without an icon is still named");
    check(html.includes('<span class="dsep" aria-hidden="true"></span>') && html.includes('alt="Trash"'), "the bin closes the Dock, behind its line");
    for (const text of ["This Mac", "MacBook Air", "Apple M2", "Setup", "Safari", "With Kliner", "Made with"]) {
      check(html.includes(text), `page shows ${JSON.stringify(text)}`);
    }
    // A figure is the number, then its unit set smaller beside it.
    check(html.includes('<b class="cf">1.93<small>GB</small></b>'), "freed is drawn as a figure and its unit");
    check(html.includes('<span class="cl">Files tidied</span><b class="cf">214</b>'), "the count is drawn under its label");
    check(html.includes('<b class="cf">Sep 2026</b>'), "clean since is the month, not the day");
    check(html.includes('<span class="cl">Storage</span><span class="cv">228 GB</span>'), "This Mac is cells of label over value");
    // The frame: rails down the page, a hatch band between sections, and a
    // rule under each section name that crosses the whole window.
    check(html.includes('<i class="rails"'), "the two rules the column is held between");
    check((html.match(/class="band"/g) || []).length >= 4, "a hatch band parts every section");
    check(html.includes('<div class="head"><h2>Setup</h2></div>'), "a section opens with its name");
    // The wallpapers they keep, and what Kliner has done here.
    check(html.includes(">Wallpapers</h2>") && html.includes('class="wp on"') && html.includes("<b>on now</b>"),
      "the wallpapers, with the one that is on marked");
    check(html.includes("Named &lt;b&gt;only&lt;/b&gt;") && !html.includes("Named <b>only"), "a wallpaper name is escaped");
    check(html.includes(">Done with Kliner</h2>") && html.includes('<span class="lw">Sorted your downloads</span><span class="ln">Oct 9, 11:40</span>'),
      "what Kliner has done, in min's own words");
    check(html.includes('<span class="lw">Cleared your desktop</span></li>'), "a line with no time is still a line");
    // The page is a person first: what they do, then what they made.
    check(html.includes(">Work</h2>") && html.includes('<span class="in">Kliner') && html.includes('<span class="iy">2026</span>'),
      "what they made, with its year");
    check(html.includes('<span class="io">A Mac that stays tidy</span>'), "the line under a thing's name");
    check(html.includes('href="https://kliner.app"') && html.includes('<span class="row">'), "a thing with an address is a link, one without is not");
    check(html.includes("No &lt;b&gt;link&lt;/b&gt; here") && !html.includes("No <b>link"), "a thing's name is escaped");
    check(html.includes("Building Kliner") && html.includes("Bratislava"), "the role and the place");
    // Work and Links come before the Mac, not after it.
    check(html.indexOf(">Work</h2>") < html.indexOf(">Setup</h2>") &&
          html.indexOf(">Links</h2>") < html.indexOf(">Setup</h2>"), "the person comes before the machine");
    check(html.includes('name="viewport"') && html.includes("prefers-color-scheme:light"), "phone viewport and light mode CSS");
    same((await anon().request("GET", `/@${a.name.toUpperCase()}`)).status, 200, "/@NAME in capitals works");
    const head = await anon().request("HEAD", `/@${a.name}`);
    check(head.status === 200 && head.bytes.length === 0, `HEAD /@name: 200 without body, got ${head.status}`);

    // Only sections with data are drawn.
    const b = bob();
    isOk(await b.request("PUT", "/v1/profile", { body: { visible: true, display: "Only Name" }, signed: true }), 200, "minimal profile");
    const minimal = (await anon().request("GET", `/@${b.name}`)).text ?? "";
    check(!minimal.includes("This Mac") && !minimal.includes(">Setup<") && !minimal.includes("With Kliner"), "empty sections are not drawn");
    check(minimal.includes('class="face initial"') && minimal.includes(">O</span>"), "letter avatar without a photo");

    // Not visible: JSON 404 no_profile, HTML 404 page.
    const c = carol();
    isOk(await c.request("PUT", "/v1/profile", { body: { visible: false, display: "Secret Carol", bio: "hidden" }, signed: true }), 200, "hidden profile");
    isError(await anon().request("GET", `/v1/users/${c.name}/profile`), 404, "no_profile", "hidden profile json");
    const hidden = await anon().request("GET", `/@${c.name}`);
    check(hidden.status === 404, `hidden profile page is 404, got ${hidden.status}`);
    same(hidden.headers.get("content-security-policy"), CSP, "404 page has the CSP");
    check((hidden.text ?? "").includes("Their page is not public") && !(hidden.text ?? "").includes("Secret Carol"), "the page says the name is somebody's and shows nothing of the hidden profile");
    check(!(hidden.text ?? "").includes("<form"), "and offers nothing to hold");
    isOk(await c.request("PUT", "/v1/profile", { body: { display: "No visible field" }, signed: true }), 200, "PUT without visible");
    isError(await anon().request("GET", `/v1/users/${c.name}/profile`), 404, "no_profile", "visible defaults to false");
    isError(await anon().request("GET", `/v1/users/nobody${RUN_ID}/profile`), 404, "no_profile", "profile of an unknown user");
    const nobody = await anon().request("GET", `/@nobody${RUN_ID}`);
    check(nobody.status === 200 && (nobody.text ?? "").includes("is free"), "a name nobody has says it is free");
    same(nobody.headers.get("content-security-policy"), HOLD_CSP, "and its page may post its one form here");
    same(nobody.headers.get("cache-control"), "no-store", "and is never kept");
    const evil = await anon().request("GET", `/@${encodeURIComponent("<img src=x onerror=alert(1)>")}`);
    check(evil.status === 404 && !(evil.text ?? "").includes("<img src=x"), "a hostile name in the URL is not echoed raw");
  });

  await test("transfer: ~20 MiB file in 3 parts, end to end", async () => {
    const a = alice();
    const b = bob();
    const data = crypto.randomBytes(20 * 1024 * 1024 + 4321);
    const recipient = await a.lookup(b.name);
    const enc = encryptFile(data, b64u.decode(recipient.box), { fileName: "poster.mov", from: a.name });
    same(enc.parts.length, 3, "20 MiB is 3 parts of 8 MiB");
    same(enc.parts.map((p) => p.length), [CHUNK + 28, CHUNK + 28, data.length - 2 * CHUNK + 28], "part sizes (nonce + tag = 28)");

    const t0 = nowSec();
    const created = await a.request("POST", "/v1/transfers", {
      body: { to: b.name, parts: 3, bytes: enc.bytes, header: enc.header },
      signed: true,
    });
    isOk(created, 201, "create transfer");
    const id = created.json?.id;
    check(/^[A-Za-z0-9_-]{22}$/.test(id ?? ""), `id is 22 chars of base64url, got ${id}`);
    check(Math.abs(created.json?.expires - (t0 + 7 * 86400)) < 10, "expires in 7 days");
    same(Object.keys(created.json ?? {}), ["id", "expires"], "create body keys");
    same((await a.outbox()).transfers.find((t) => t.id === id)?.status, "uploading", "outbox: uploading");
    check(!(await b.inbox()).transfers.some((t) => t.id === id), "not in the inbox while uploading");
    isError(await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true }), 409, "incomplete", "ready with no parts");

    for (let n = 0; n < 3; n++) {
      const res = await a.request("PUT", `/v1/transfers/${id}/parts/${n}`, { body: enc.parts[n], signed: true });
      isOk(res, 200, `PUT part ${n}`);
      same(res.json, { ok: true }, `PUT part ${n} body`);
    }
    check(await r2Has(`t/${id}/0`), "part 0 is in R2 at t/<id>/0");
    isError(await b.request("PUT", `/v1/transfers/${id}/parts/0`, { body: enc.parts[0], signed: true }), 404, "no_transfer", "someone else cannot put a part");
    const ready = await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true });
    isOk(ready, 200, "ready");
    same(ready.json, { ok: true }, "ready body");
    isOk(await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true }), 200, "ready again is fine");
    isError(await a.request("PUT", `/v1/transfers/${id}/parts/1`, { body: enc.parts[1], signed: true }), 404, "no_transfer", "no part changes after ready");
    same((await a.outbox()).transfers.find((t) => t.id === id)?.status, "ready", "outbox: ready");

    const inbox = await b.inbox();
    const entry = inbox.transfers.find((t) => t.id === id);
    check(entry, "the transfer is in bob's inbox");
    same(Object.keys(entry ?? {}), ["id", "from", "parts", "bytes", "header", "created", "expires"], "inbox entry keys");
    same([entry?.from, entry?.parts, entry?.bytes, entry?.header], [a.name, 3, enc.bytes, enc.header], "inbox entry values");

    const meta = b.openHeader(entry);
    same([meta.name, meta.size, meta.sha256, meta.chunk, meta.from], ["poster.mov", data.length, sha256Hex(data), CHUNK, a.name], "header decrypts to the file metadata");
    check(/^[A-Za-z0-9_-]{43}$/.test(meta.k), "file key is 32 bytes b64u");
    let wrongReader = false;
    try {
      carol().openHeader(entry);
    } catch {
      wrongReader = true;
    }
    check(wrongReader, "carol cannot open bob's header");

    const key = b64u.decode(meta.k);
    const plain = [];
    for (let n = 0; n < 3; n++) {
      const res = await b.request("GET", `/v1/transfers/${id}/parts/${n}`, { signed: true });
      isOk(res, 200, `GET part ${n}`);
      same(res.headers.get("content-type"), "application/octet-stream", `part ${n} content type`);
      same(res.headers.get("content-length"), String(enc.parts[n].length), `part ${n} Content-Length`);
      same(res.headers.get("cache-control"), "no-store", `part ${n} no-store`);
      check(res.bytes.equals(enc.parts[n]), `part ${n} bytes are what was uploaded`);
      if (n === 1) {
        let refused = false;
        try {
          decryptPart(key, 0, res.bytes);
        } catch {
          refused = true;
        }
        check(refused, "part 1 does not open as part 0 (nonce check)");
      }
      plain.push(decryptPart(key, n, res.bytes));
    }
    const file = Buffer.concat(plain);
    same(file.length, data.length, "decrypted size");
    same(sha256Hex(file), sha256Hex(data), "sha256 of the decrypted file matches the original");
    same(sha256Hex(file), meta.sha256, "sha256 matches the header");

    isError(await carol().request("GET", `/v1/transfers/${id}/parts/0`, { signed: true }), 404, "no_transfer", "another user cannot read a part");
    isError(await a.request("GET", `/v1/transfers/${id}/parts/0`, { signed: true }), 404, "no_transfer", "the sender cannot read a part");
    isError(await b.request("GET", `/v1/transfers/${id}/parts/3`, { signed: true }), 400, "invalid", "part number out of range");
    isError(await carol().request("POST", `/v1/transfers/${id}/received`, { signed: true }), 404, "no_transfer", "another user cannot mark received");
    isError(await carol().request("POST", `/v1/transfers/${id}/decline`, { signed: true }), 404, "no_transfer", "another user cannot decline");
    isError(await b.request("DELETE", `/v1/transfers/${id}`, { signed: true }), 404, "no_transfer", "the recipient cannot cancel");

    const done = await b.request("POST", `/v1/transfers/${id}/received`, { signed: true });
    isOk(done, 200, "received");
    same(done.json, { ok: true }, "received body");
    isOk(await b.request("POST", `/v1/transfers/${id}/received`, { signed: true }), 200, "received again is fine");
    isError(await b.request("GET", `/v1/transfers/${id}/parts/0`, { signed: true }), 404, "no_transfer", "parts are gone after received");
    check(!(await r2Has(`t/${id}/0`)) && !(await r2Has(`t/${id}/2`)), "R2 objects are deleted");
    check(!(await b.inbox()).transfers.some((t) => t.id === id), "gone from the inbox");
    const out = (await a.outbox()).transfers.find((t) => t.id === id);
    same(Object.keys(out ?? {}), ["id", "to", "status", "parts", "bytes", "created", "done"], "outbox entry keys");
    same([out?.to, out?.status, out?.parts, out?.bytes], [b.name, "received", 3, enc.bytes], "outbox shows received");
    check(Number.isInteger(out?.done) && out.done >= out.created, "done is set");
    isError(await a.request("DELETE", `/v1/transfers/${id}`, { signed: true }), 404, "no_transfer", "cannot cancel a received transfer");
  });

  await test("transfer: incomplete ready is 409, part rules", async () => {
    const a = alice();
    const id = await rawTransfer(a, bob().name, [10, 20]);
    isError(await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true }), 409, "incomplete", "no parts", "0");
    isOk(await a.request("PUT", `/v1/transfers/${id}/parts/0`, { body: crypto.randomBytes(10), signed: true }), 200, "part 0");
    isError(await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true }), 409, "incomplete", "part 1 missing", "1");
    isOk(await a.request("PUT", `/v1/transfers/${id}/parts/1`, { body: crypto.randomBytes(25), signed: true }), 200, "part 1, wrong size");
    isError(await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true }), 409, "incomplete", "sizes do not add up");
    isOk(await a.request("PUT", `/v1/transfers/${id}/parts/1`, { body: crypto.randomBytes(20), signed: true }), 200, "re-put part 1 replaces it");
    isError(await a.request("PUT", `/v1/transfers/${id}/parts/2`, { body: crypto.randomBytes(5), signed: true }), 400, "invalid", "n past the last part");
    isError(await a.request("PUT", `/v1/transfers/${id}/parts/x`, { body: crypto.randomBytes(5), signed: true }), 400, "invalid", "n not a number");
    isError(await a.request("PUT", `/v1/transfers/${id}/parts/0`, { body: new Uint8Array(0), signed: true }), 400, "invalid", "empty part");
    isError(await a.request("PUT", `/v1/transfers/${id}/parts/0`, { body: new Uint8Array(16 * 1024 * 1024 + 65), signed: true }), 413, "too_big", "part over 16 MiB + 64");
    isError(await a.request("PUT", `/v1/transfers/AAAAAAAAAAAAAAAAAAAAAA/parts/0`, { body: crypto.randomBytes(5), signed: true }), 404, "no_transfer", "unknown transfer");
    isOk(await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true }), 200, "ready once complete");
    await a.cancel(id); // clean up
  });

  await test("transfer: decline", async () => {
    const a = alice();
    const b = bob();
    const { id } = await a.send(b.name, crypto.randomBytes(5000), { fileName: "notes.txt" });
    check((await b.inbox()).transfers.some((t) => t.id === id), "in the inbox");
    check(await r2Has(`t/${id}/0`), "part is in R2");
    const res = await b.request("POST", `/v1/transfers/${id}/decline`, { signed: true });
    isOk(res, 200, "decline");
    same(res.json, { ok: true }, "decline body");
    isOk(await b.request("POST", `/v1/transfers/${id}/decline`, { signed: true }), 200, "decline again is fine");
    check(!(await b.inbox()).transfers.some((t) => t.id === id), "gone from the inbox");
    const out = (await a.outbox()).transfers.find((t) => t.id === id);
    same(out?.status, "declined", "outbox shows declined");
    check(Number.isInteger(out?.done), "done is set");
    isError(await b.request("GET", `/v1/transfers/${id}/parts/0`, { signed: true }), 404, "no_transfer", "no parts after decline");
    isError(await b.request("POST", `/v1/transfers/${id}/received`, { signed: true }), 404, "no_transfer", "cannot receive a declined transfer");
    check(!(await r2Has(`t/${id}/0`)), "R2 part deleted");
  });

  await test("transfer: cancel", async () => {
    const a = alice();
    const b = bob();
    const id = await rawTransfer(a, b.name, [100, 100]);
    isOk(await a.request("PUT", `/v1/transfers/${id}/parts/0`, { body: crypto.randomBytes(100), signed: true }), 200, "part 0");
    const res = await a.request("DELETE", `/v1/transfers/${id}`, { signed: true });
    isOk(res, 200, "cancel while uploading");
    same(res.json, { ok: true }, "cancel body");
    isOk(await a.request("DELETE", `/v1/transfers/${id}`, { signed: true }), 200, "cancel again is fine");
    const out = (await a.outbox()).transfers.find((t) => t.id === id);
    same(out?.status, "cancelled", "outbox shows cancelled");
    check(Number.isInteger(out?.done), "done is set");
    isError(await a.request("PUT", `/v1/transfers/${id}/parts/1`, { body: crypto.randomBytes(100), signed: true }), 404, "no_transfer", "no uploads after cancel");
    isError(await a.request("POST", `/v1/transfers/${id}/ready`, { signed: true }), 404, "no_transfer", "no ready after cancel");
    check(!(await r2Has(`t/${id}/0`)), "R2 part deleted");

    const sent = await a.send(b.name, crypto.randomBytes(3000));
    check((await b.inbox()).transfers.some((t) => t.id === sent.id), "ready transfer is in the inbox");
    isOk(await a.request("DELETE", `/v1/transfers/${sent.id}`, { signed: true }), 200, "cancel a ready transfer");
    check(!(await b.inbox()).transfers.some((t) => t.id === sent.id), "cancelled transfer leaves the inbox");
    isError(await b.request("GET", `/v1/transfers/${sent.id}/parts/0`, { signed: true }), 404, "no_transfer", "no download after cancel");
  });

  await test("transfer: self, too_big, no_user, invalid", async () => {
    const a = alice();
    const header = b64u.encode(crypto.randomBytes(40));
    const create = (body) => a.request("POST", "/v1/transfers", { body, signed: true });
    isError(await create({ to: a.name, parts: 1, bytes: 100, header }), 400, "self", "to yourself");
    isError(await create({ to: a.name.toUpperCase(), parts: 1, bytes: 100, header }), 400, "self", "to yourself in capitals");
    isError(await create({ to: bob().name, parts: 400, bytes: MAX_BYTES + 1, header }), 413, "too_big", "over MAX_BYTES");
    isError(await create({ to: `nobody${RUN_ID}`, parts: 1, bytes: 100, header }), 404, "no_user", "unknown recipient");
    for (const [body, what] of [
      [{ to: bob().name, parts: 0, bytes: 100, header }, "parts 0"],
      [{ to: bob().name, parts: 10001, bytes: 20000, header }, "parts over 10000"],
      [{ to: bob().name, parts: "3", bytes: 100, header }, "parts as text"],
      [{ to: bob().name, parts: 1, bytes: 0, header }, "bytes 0"],
      [{ to: bob().name, parts: 1, bytes: 1.5, header }, "fractional bytes"],
      [{ to: bob().name, parts: 5, bytes: 3, header }, "fewer bytes than parts"],
      [{ to: bob().name, parts: 1, bytes: 16 * 1024 * 1024 + 65, header }, "one part over 16 MiB + 64"],
      [{ to: bob().name, parts: 1, bytes: 100, header: "" }, "empty header"],
      [{ to: bob().name, parts: 1, bytes: 100, header: "a+b/c=" }, "header not base64url"],
      [{ to: bob().name, parts: 1, bytes: 100, header: "h".repeat(4097) }, "header over 4096"],
      [{ parts: 1, bytes: 100, header }, "no recipient"],
    ]) {
      isError(await create(body), 400, "invalid", what);
    }
    const edge = await create({ to: bob().name, parts: 10000, bytes: 10000, header: "h".repeat(4096) });
    isOk(edge, 201, "10000 parts and a 4096-char header are allowed");
    if (edge.json?.id) await a.cancel(edge.json.id);
    isError(await a.request("POST", "/v1/transfers", { body: { to: bob().name, parts: 1, bytes: 1, header } }), 401, "bad_signature", "unsigned create");
  });

  await test("transfer: too_many at MAX_PENDING", async () => {
    const d = user("dave");
    await d.register();
    const ids = [];
    for (let i = 0; i < MAX_PENDING; i++) ids.push(await rawTransfer(d, bob().name, [50]));
    same(ids.length, MAX_PENDING, `${MAX_PENDING} transfers created`);
    const header = b64u.encode(crypto.randomBytes(40));
    isError(await d.request("POST", "/v1/transfers", { body: { to: bob().name, parts: 1, bytes: 50, header }, signed: true }), 429, "too_many", "one more than MAX_PENDING");
    await d.cancel(ids[0]);
    isOk(await d.request("POST", "/v1/transfers", { body: { to: carol().name, parts: 1, bytes: 50, header }, signed: true }), 201, "room again after a cancel");
  });

  await test("beta activate: unknown, first use, same device, other device", async () => {
    const c = anon();
    const activate = (code, device) => c.request("POST", "/v1/beta/activate", { body: { code, device } });
    check(betaCodes.length === 20 && betaCodes.every((x) => /^KLNR-[ABCDEFGHJKMNPQRSTVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTVWXYZ23456789]{4}$/.test(x)), "gen-codes made 20 KLNR-XXXX-XXXX codes");
    isError(await activate("KLNR-0000-0000", "mac-a"), 404, "unknown_code", "unknown code");
    const first = await activate(betaCodes[0], "mac-a");
    isOk(first, 200, "first use");
    same(first.json, { ok: true }, "first use body");
    check(first.headers.get("cache-control") === "no-store", "beta is no-store");
    const messy = ` ${betaCodes[0].toLowerCase().replace(/-/g, " - ")} `;
    same((await activate(messy, "mac-a")).json, { ok: true }, "same device again, code typed with spaces and lowercase");
    isError(await activate(betaCodes[0], "mac-b"), 409, "used_code", "another device");
    same((await activate(betaCodes[1].replace(/-/g, ""), "mac-b")).json, { ok: true }, "second code on the other device");
    isError(await c.request("POST", "/v1/beta/activate", { body: { code: betaCodes[2] } }), 400, "invalid", "no device");
    isError(await c.request("POST", "/v1/beta/activate", { body: { device: "mac-c" } }), 400, "invalid", "no code");
    const rows = await sql(`SELECT device, used FROM beta_codes WHERE hash = '${sha256Hex(betaCodes[0].replace(/-/g, ""))}'`);
    same(rows[0]?.device, "mac-a", "the code row records the device");
    check(Number.isInteger(rows[0]?.used), "and when it was used");
  });

  await test("waitlist: stable positions", async () => {
    const c = anon();
    const join = (email) => c.request("POST", "/v1/waitlist", { body: { email } });
    const e1 = `first.${RUN_ID}@example.com`;
    const r1 = await join(e1);
    isOk(r1, 200, "join");
    same(Object.keys(r1.json ?? {}), ["ok", "position"], "waitlist body keys");
    const p1 = r1.json?.position;
    check(Number.isInteger(p1) && p1 >= 1, "position is a number");
    const p2 = (await join(`second.${RUN_ID}@example.com`)).json?.position;
    same(p2, p1 + 1, "next address, next position");
    same((await join(`  FIRST.${RUN_ID}@Example.COM `)).json, { ok: true, position: p1 }, "same address again keeps its position");
    same((await join(`third.${RUN_ID}@example.co`)).json?.position, p2 + 1, "positions keep counting");
    same((await join(e1)).json?.position, p1, "still the original position");
    for (const bad of ["nope", "a@b", "a@b.c", "two@@example.com", `${"x".repeat(111)}@example.com`]) {
      isError(await join(bad), 400, "invalid", `bad email ${bad.slice(0, 20)}`);
    }
  });

  await test("cron: expires overdue transfers, drops old rows", async () => {
    const a = alice();
    const b = bob();
    const sent = await a.send(b.name, crypto.randomBytes(2000));
    const half = await rawTransfer(a, b.name, [64, 64]);
    isOk(await a.request("PUT", `/v1/transfers/${half}/parts/0`, { body: crypto.randomBytes(64), signed: true }), 200, "half uploaded");
    check(await r2Has(`t/${sent.id}/0`) && (await r2Has(`t/${half}/0`)), "parts are in R2 before the cron");

    // Make both overdue, and plant rows the cron should delete or keep.
    const t = nowSec();
    const oldId = `old${crypto.randomBytes(12).toString("hex")}`.slice(0, 22);
    await sql(
      `UPDATE transfers SET expires = ${t - 60} WHERE id IN ('${sent.id}', '${half}');` +
        `INSERT INTO transfers (id, sender, recipient, parts, bytes, header, status, created, expires, done) VALUES ('${oldId}', '${a.name}', '${b.name}', 1, 1, 'aa', 'received', ${t - 31 * 86400}, ${t - 24 * 86400}, ${t - 30 * 86400});` +
        `INSERT INTO hits (key, count, window) VALUES ('names:198.51.100.1:1', 3, ${t - 26 * 3600}), ('names:198.51.100.2:2', 3, ${t - 2 * 3600});` +
        `INSERT INTO holds (name, kind, sign, code, created, expires) VALUES ('gone${RUN_ID}', 'renamed', 'x', NULL, ${t - 8 * 86400}, ${t - 86400}), ('kept${RUN_ID}', 'claimed', NULL, 'y', ${t}, ${t + 86400});`,
    );
    // Before the cron runs, the API already treats them as expired.
    check(!(await b.inbox()).transfers.some((x) => x.id === sent.id), "overdue transfer is hidden from the inbox");
    isError(await b.request("GET", `/v1/transfers/${sent.id}/parts/0`, { signed: true }), 404, "no_transfer", "overdue parts cannot be downloaded");
    const lapsed = (await a.outbox()).transfers.find((x) => x.id === sent.id);
    same([lapsed?.status, lapsed?.done], ["expired", t - 60], "outbox reports it expired");

    const url = `${BASE}/__scheduled?cron=17+*+*+*+*`;
    const { stdout } = await run("curl", ["-sS", "-f", url]);
    check(/ran scheduled event/i.test(stdout), `scheduled handler ran: ${stdout.trim()}`);

    const rows = await sql(`SELECT id, status, done, expires FROM transfers WHERE id IN ('${sent.id}', '${half}') ORDER BY id`);
    same(rows.map((r) => r.status), ["expired", "expired"], "both transfers are expired");
    check(rows.every((r) => r.done === r.expires), "done is the expiry time");
    check(!(await r2Has(`t/${sent.id}/0`)) && !(await r2Has(`t/${half}/0`)), "their R2 parts are deleted");
    same((await sql(`SELECT COUNT(*) AS n FROM transfers WHERE id = '${oldId}'`))[0]?.n, 0, "rows older than 30 days are deleted");
    same((await sql("SELECT key FROM hits WHERE key LIKE 'names:198.51.100.%' ORDER BY key")).map((r) => r.key), ["names:198.51.100.2:2"], "rate-limit rows older than a day are deleted, newer kept");
    same((await sql(`SELECT name FROM holds WHERE name IN ('gone${RUN_ID}', 'kept${RUN_ID}')`)).map((r) => r.name), [`kept${RUN_ID}`], "a hold that ran out is deleted, a live one kept");
    same((await a.outbox()).transfers.find((x) => x.id === sent.id)?.status, "expired", "outbox after the cron");
    isError(await a.request("PUT", `/v1/transfers/${half}/parts/1`, { body: crypto.randomBytes(64), signed: true }), 404, "no_transfer", "no uploads to an expired transfer");
  });

  await test("DELETE /v1/users/me removes the user, profile, transfers and parts", async () => {
    const e = user("erin");
    await e.register();
    isOk(await e.request("PUT", "/v1/profile", { body: { visible: true, display: "Erin" }, signed: true }), 200, "profile");
    const out = await e.send(bob().name, crypto.randomBytes(1000));
    const inc = await alice().send(e.name, crypto.randomBytes(1000));
    check(await r2Has(`t/${out.id}/0`) && (await r2Has(`t/${inc.id}/0`)), "parts exist before");
    const res = await e.request("DELETE", "/v1/users/me", { signed: true });
    isOk(res, 200, "delete me");
    same(res.json, { ok: true }, "delete body");
    isError(await anon().request("GET", `/v1/users/${e.name}`), 404, "no_user", "user gone");
    isError(await anon().request("GET", `/v1/users/${e.name}/profile`), 404, "no_profile", "profile gone");
    const gone = await anon().request("GET", `/@${e.name}`);
    check(gone.status === 200 && (gone.text ?? "").includes("is free") && !(gone.text ?? "").includes("Erin"), "profile page gone, and the name free");
    check(!(await bob().inbox()).transfers.some((t) => t.id === out.id), "their sends left the recipient's inbox");
    check(!(await alice().outbox()).transfers.some((t) => t.id === inc.id), "transfers to them left the sender's outbox");
    check(!(await r2Has(`t/${out.id}/0`)) && !(await r2Has(`t/${inc.id}/0`)), "R2 parts deleted");
    isError(await e.request("GET", "/v1/inbox", { signed: true }), 401, "bad_signature", "old key no longer works");
    same((await anon().request("GET", `/v1/names/${e.name}`)).json?.free, true, "the name is free again");
  });

  await test("download: the app zip, and /download sends you to it", async () => {
    const res = await anon().request("GET", "/download/Kliner.app.zip");
    isOk(res, 200, "GET /download/Kliner.app.zip");
    same(res.headers.get("content-type"), "application/zip", "it is a zip");
    same(res.headers.get("content-disposition"), 'attachment; filename="Kliner.app.zip"', "it downloads as Kliner.app.zip");
    check(res.bytes.equals(APP_ZIP), "the bytes are exactly the ones put up");
    same(res.headers.get("x-kliner"), "1", "the download carries X-Kliner too");
    const head = await anon().request("HEAD", "/download/Kliner.app.zip");
    check(head.status === 200 && head.bytes.length === 0, `HEAD gives 200 without a body, got ${head.status}`);
    same(head.headers.get("content-length"), String(APP_ZIP.length), "HEAD says how big it is");
    const hop = await fetch(BASE + "/download", { redirect: "manual" });
    same(hop.status, 302, "GET /download redirects");
    same(hop.headers.get("location"), "/download/Kliner.app.zip", "to the zip");
    isError(await anon().request("POST", "/download/Kliner.app.zip", { body: {} }), 405, "method_not_allowed", "POST to the download");
  });

  await test("download: the disk image, named for its version, and /v1/release says which", async () => {
    let rel = await anon().request("GET", "/v1/release");
    isOk(rel, 200, "GET /v1/release before there is a disk image");
    same(rel.headers.get("access-control-allow-origin"), "*", "any page may read it");
    same(rel.json?.version, null, "no version yet");
    same(rel.json?.dmg, null, "and no disk image");
    same(rel.json?.zip?.bytes, APP_ZIP.length, "but the zip, and how big it is");
    // what deploy.sh puts up: the image, and the note of which version it is
    await r2Put("releases/Kliner.dmg", APP_DMG, "application/x-apple-diskimage");
    await r2Put("releases/latest.json", Buffer.from(JSON.stringify({ version: "0.62.0", dmg: { bytes: APP_DMG.length, sha256: DMG_SHA }, published: "2026-10-16T12:00:00Z" })), "application/json");
    const hop = await fetch(BASE + "/download", { redirect: "manual" });
    same(hop.status, 302, "GET /download redirects");
    same(hop.headers.get("location"), "/download/Kliner-0.62.0.dmg", "to the disk image, named for its version");
    const res = await anon().request("GET", "/download/Kliner-0.62.0.dmg");
    isOk(res, 200, "GET /download/Kliner-0.62.0.dmg");
    same(res.headers.get("content-type"), "application/x-apple-diskimage", "it is a disk image");
    same(res.headers.get("content-disposition"), 'attachment; filename="Kliner-0.62.0.dmg"', "it saves as Kliner-0.62.0.dmg");
    check(res.bytes.equals(APP_DMG), "the bytes are exactly the ones put up");
    same(res.headers.get("x-kliner"), "1", "the download carries X-Kliner too");
    const old = await anon().request("GET", "/download/Kliner-0.50.0.dmg");
    isOk(old, 200, "an old version's link");
    same(old.headers.get("content-disposition"), 'attachment; filename="Kliner-0.62.0.dmg"', "gets the newest, under its own name");
    const head = await anon().request("HEAD", "/download/Kliner.dmg");
    check(head.status === 200 && head.bytes.length === 0, `HEAD gives 200 without a body, got ${head.status}`);
    same(head.headers.get("content-length"), String(APP_DMG.length), "HEAD says how big it is");
    rel = await anon().request("GET", "/v1/release");
    same(rel.json?.version, "0.62.0", "/v1/release: the version");
    same(rel.json?.dmg?.url, "/download/Kliner-0.62.0.dmg", "where the disk image is");
    same(rel.json?.dmg?.bytes, APP_DMG.length, "how big it is");
    same(rel.json?.dmg?.sha256, DMG_SHA, "and its checksum");
    same(rel.json?.published, "2026-10-16T12:00:00Z", "and when it went up");
    const zip = await anon().request("GET", "/download/Kliner.app.zip");
    check(zip.status === 200 && zip.bytes.equals(APP_ZIP), "the zip is still there for the old links");
    isError(await anon().request("GET", "/download/Kliner.exe"), 404, "not_found", "anything else under /download");
    isError(await anon().request("GET", "/download/latest.json"), 404, "not_found", "the note itself is not a download");
    isError(await anon().request("POST", "/download/Kliner.dmg", { body: {} }), 405, "method_not_allowed", "POST to the disk image");
  });

  await test("claims: a name held on kliner.app, taken with its code", async () => {
    const site = anon();
    const name = `held${RUN_ID}`;
    const pre = await site.request("OPTIONS", "/v1/claims", { headers: { Origin: "https://kliner.app", "Access-Control-Request-Method": "POST" } });
    isOk(pre, 204, "a page may ask before it posts");
    same([pre.headers.get("access-control-allow-origin"), pre.headers.get("access-control-allow-methods"), pre.headers.get("access-control-allow-headers")],
      ["*", "GET, POST, OPTIONS", "Content-Type"], "and is told it may");
    const t0 = nowSec();
    const held = await site.request("POST", "/v1/claims", { body: { name: `@${name.toUpperCase()}` } });
    isOk(held, 201, "hold a free name");
    same(Object.keys(held.json ?? {}), ["name", "code", "expires"], "201 body keys");
    check(held.json?.name === name, "the name, as it is stored");
    check(/^[A-HJKMNP-Z2-9]{5}-[A-HJKMNP-Z2-9]{5}$/.test(held.json?.code ?? ""), `the code is XXXXX-XXXXX with no look-alikes, got ${held.json?.code}`);
    check(Math.abs(held.json?.expires - (t0 + 30 * 86400)) < 10, "held for 30 days");
    same(held.headers.get("access-control-allow-origin"), "*", "a page can read the answer");
    const code = held.json?.code ?? "";

    const look = await site.request("GET", `/v1/names/${name}`);
    same([look.json?.free, look.json?.reason, look.json?.until], [false, "claimed", held.json?.expires], "the name says it is held");
    check(/kliner\.app/.test(look.json?.message ?? ""), "and where");
    same(look.headers.get("access-control-allow-origin"), "*", "names are open to pages");

    const again = await anon().request("POST", "/v1/claims", { body: { name } });
    isError(again, 409, "claimed", "holding a held name");
    same(again.headers.get("access-control-allow-origin"), "*", "a page can read why, too");
    isError(await anon().request("POST", "/v1/claims", { body: { name: alice().name } }), 409, "taken", "holding a taken name");
    isError(await anon().request("POST", "/v1/claims", { body: { name: "support" } }), 400, "reserved", "holding a reserved name");
    isError(await anon().request("POST", "/v1/claims", { body: { name: "9x" } }), 400, "invalid", "holding an invalid name");
    isError(await anon().request("POST", "/v1/claims", { body: {} }), 400, "invalid", "no name");

    const other = new Kliner(BASE, { name, ip: nextIp() });
    isError(await other.request("POST", "/v1/users", { body: { name, sign: other.signPublic, box: other.boxPublic }, signed: true }), 409, "claimed", "registering it without the code");
    isError(await other.request("POST", "/v1/users", { body: { name, sign: other.signPublic, box: other.boxPublic, claim: "AAAAA-AAAAA" }, signed: true }), 403, "wrong_code", "with a wrong code");
    const mine = await other.request("POST", "/v1/users", {
      body: { name, sign: other.signPublic, box: other.boxPublic, claim: code.toLowerCase().replace("-", " ") },
      signed: true,
    });
    isOk(mine, 201, "with its code, typed loosely");
    same((await anon().request("GET", `/v1/names/${name}`)).json?.reason, "taken", "the name is taken now");
    same((await sql(`SELECT COUNT(*) AS n FROM holds WHERE name = '${name}'`))[0]?.n, 0, "and its hold is gone");

    // a Mac that has a name already takes a held one by changing to it
    const h = user("hal");
    await h.register();
    const second = `hal2${RUN_ID}`;
    const code2 = (await anon().claimOnSite(second)).code;
    isError(await h.request("POST", "/v1/users/me/name", { body: { name: second }, signed: true }), 409, "claimed", "changing to a held name without its code");
    isError(await h.request("POST", "/v1/users/me/name", { body: { name: second, claim: "BBBBB-BBBBB" }, signed: true }), 403, "wrong_code", "with a wrong one");
    same((await h.rename(second, code2)).name, second, "with its code");
    same((await sql(`SELECT COUNT(*) AS n FROM holds WHERE name = '${second}'`))[0]?.n, 0, "that hold is gone too");

    // three an hour from one network
    const busy = anon();
    for (let i = 0; i < 3; i++) isOk(await busy.request("POST", "/v1/claims", { body: { name: `many${i}${RUN_ID}` } }), 201, `hold ${i + 1} of 3`);
    const fourth = await busy.request("POST", "/v1/claims", { body: { name: `many3${RUN_ID}` } });
    isError(fourth, 429, "rate_limited", "a fourth in an hour");
    check(Number(fourth.headers.get("retry-after")) > 0, "with Retry-After");
    same(fourth.headers.get("access-control-allow-origin"), "*", "which a page can read");
  });

  await test("name pages: a free name held from kliner.app/@name, its code shown again for the same form", async () => {
    const form = { "Content-Type": "application/x-www-form-urlencoded", "Sec-Fetch-Site": "same-origin" };
    const nonceOf = (res) => /name="n" value="([A-Za-z0-9_-]{22})"/.exec(res.text ?? "")?.[1] ?? "";
    const codeOf = (res) => /<p class="code">([A-Z0-9-]+)<\/p>/.exec(res.text ?? "")?.[1] ?? "";
    const post = (who, name, nonce, headers = form) => who.request("POST", `/@${name}`, { body: Buffer.from(`n=${nonce}`), headers });

    const visitor = anon();
    const name = `page${RUN_ID}`;
    const free = await visitor.request("GET", `/@${name}`);
    check(free.status === 200 && (free.text ?? "").includes(`@${name} is free`), `a free name's page, got ${show(free)}`);
    check((free.text ?? "").includes(`<form class="hold-f" method="post" action="/@${name}">`), "with the form that holds it");
    check((free.text ?? "").includes('<meta name="robots" content="noindex">'), "and left out of search engines");
    const nonce = nonceOf(free);
    check(nonce.length === 22, "the form carries a fresh nonce");
    // the same page open in another tab, or on another Mac
    const otherTab = nonceOf(await anon().request("GET", `/@${name}`));
    check(otherTab.length === 22 && otherTab !== nonce, "a new one each time the page is drawn");

    const t0 = nowSec();
    const held = await post(visitor, name, nonce);
    check(held.status === 200 && (held.text ?? "").includes(`@${name} is held for you`), `held from the page, got ${show(held)}`);
    const code = codeOf(held);
    check(/^[A-HJKMNP-Z2-9]{5}-[A-HJKMNP-Z2-9]{5}$/.test(code), `the code is shown, got ${code}`);
    same(held.headers.get("cache-control"), "no-store", "the page with the code is never kept");
    same(held.headers.get("content-security-policy"), CSP, "and has no form on it");
    const look = await anon().request("GET", `/v1/names/${name}`);
    same([look.json?.reason, Math.abs((look.json?.until ?? 0) - (t0 + 30 * 86400)) < 10], ["claimed", true], "the name is held for 30 days");

    const twice = await post(visitor, name, nonce);
    check(twice.status === 200 && codeOf(twice) === code, "the same form sent again shows the same code");
    const other = await post(anon(), name, otherTab);
    check(other.status === 409 && !codeOf(other) && (other.text ?? "").includes("Somebody is holding this name"), `another form gets no code, got ${other.status}`);
    const page = await anon().request("GET", `/@${name}`);
    check(page.status === 200 && (page.text ?? "").includes("is held") && !(page.text ?? "").includes("<form"), "its page now says it is held, with no form");

    // only from its own page, and only with a nonce it handed out
    const second = `page2${RUN_ID}`;
    const nonce2 = nonceOf(await anon().request("GET", `/@${second}`));
    const cross = await post(anon(), second, nonce2, { "Content-Type": "application/x-www-form-urlencoded", "Sec-Fetch-Site": "cross-site" });
    check(cross.status === 403 && !codeOf(cross), `a form on another site is turned away, got ${cross.status}`);
    const evil = await post(anon(), second, nonce2, { "Content-Type": "application/x-www-form-urlencoded", Origin: "https://evil.example" });
    check(evil.status === 403, `so is one that says it is from another site, got ${evil.status}`);
    const bare = await post(anon(), second, nonce2, { "Content-Type": "application/x-www-form-urlencoded" });
    check(bare.status === 403, `and one that says nothing, got ${bare.status}`);
    const stale = await post(anon(), second, "not-a-nonce");
    check(stale.status === 400 && (stale.text ?? "").includes("out of date"), `a form without its nonce, got ${stale.status}`);
    same((await anon().request("GET", `/v1/names/${second}`)).json?.free, true, "none of them held it");
    const sameOrigin = await post(anon(), second, nonce2, { "Content-Type": "application/x-www-form-urlencoded", Origin: new URL(BASE).origin });
    check(sameOrigin.status === 200 && codeOf(sameOrigin), `a browser that only sends Origin, from this host, holds it, got ${sameOrigin.status}`);

    // the code from the page is the code the app asks for
    const mac = new Kliner(BASE, { name, ip: nextIp() });
    isOk(await mac.request("POST", "/v1/users", { body: { name, sign: mac.signPublic, box: mac.boxPublic, claim: code }, signed: true }), 201, "registered with the page's code");
    const taken = await anon().request("GET", `/@${name}`);
    check(taken.status === 404 && (taken.text ?? "").includes(`@${name} is on Kliner`), "now it is somebody's, without a public page");
    const late = await post(anon(), name, nonce);
    check(late.status === 409 && (late.text ?? "").includes("already taken") && !codeOf(late), `holding a taken name from its old form, got ${late.status}`);

    // a reserved or impossible name has no form at all
    const reserved = await anon().request("GET", "/@support");
    check(reserved.status === 404 && (reserved.text ?? "").includes("reserved") && !(reserved.text ?? "").includes("<form"), "a reserved name's page");
  });

  await test("rename: files follow, the old name is kept a week, and changing back", async () => {
    const f = user("fay");
    const g = user("gus");
    await f.register("Fay's Mac");
    await g.register();
    const was = f.name;
    isOk(await f.request("PUT", "/v1/profile", { body: { visible: true, display: "Fay" }, signed: true }), 200, "a profile before");
    const waiting = await g.send(was, crypto.randomBytes(3000), { fileName: "notes.txt" });

    const t0 = nowSec();
    const to = `fay2${RUN_ID}`;
    const res = await f.request("POST", "/v1/users/me/name", { body: { name: `@${to.toUpperCase()}` }, signed: true });
    isOk(res, 200, "change the name");
    same(Object.keys(res.json ?? {}), ["name", "was", "until"], "body keys");
    same([res.json?.name, res.json?.was], [to, was], "the new name and the old");
    check(Math.abs(res.json?.until - (t0 + 7 * 86400)) < 10, "the old one kept a week");
    f.name = to;

    const lookup = await anon().request("GET", `/v1/users/${to}`);
    same([lookup.json?.sign, lookup.json?.box], [f.signPublic, f.boxPublic], "the same keys under the new name");
    isError(await anon().request("GET", `/v1/users/${was}`), 404, "renamed", "the old name, looked up", "changed their username");
    const name = await anon().request("GET", `/v1/names/${was}`);
    same([name.json?.free, name.json?.reason, name.json?.until], [false, "held", res.json?.until], "the old name says it is kept");
    const thief = new Kliner(BASE, { name: was, ip: nextIp() });
    isError(await thief.request("POST", "/v1/users", { body: { name: was, sign: thief.signPublic, box: thief.boxPublic }, signed: true }), 409, "held", "somebody else taking the old name");
    isError(await anon().request("POST", "/v1/claims", { body: { name: was } }), 409, "held", "holding it on the site");
    isError(await g.request("POST", "/v1/transfers", { body: { to: was, parts: 1, bytes: 100, header: "aa" }, signed: true }), 404, "renamed", "sending to the old name");

    const inbox = (await f.inbox()).transfers;
    check(inbox.some((x) => x.id === waiting.id && x.from === g.name), "the file waiting for the old name waits for the new one");
    check((await g.outbox()).transfers.find((x) => x.id === waiting.id)?.to === to, "and the sender's outbox says the new name");
    same((await anon().request("GET", `/v1/users/${to}/profile`)).json?.display, "Fay", "the profile moved with it");
    isError(await anon().request("GET", `/v1/users/${was}/profile`), 404, "no_profile", "nothing under the old name");
    isError(await f.request("GET", "/v1/inbox", { signed: true, user: was }), 401, "bad_signature", "signing as the old name");

    isError(await f.request("POST", "/v1/users/me/name", { body: { name: to }, signed: true }), 400, "same", "changing to the same name");
    isError(await f.request("POST", "/v1/users/me/name", { body: { name: alice().name }, signed: true }), 409, "taken", "changing to a taken name");
    isError(await f.request("POST", "/v1/users/me/name", { body: { name: "admin" }, signed: true }), 400, "reserved", "changing to a reserved name");
    isError(await f.request("POST", "/v1/users/me/name", { body: {}, signed: true }), 400, "invalid", "no name");
    isError(await f.request("POST", "/v1/users", { body: { name: `fay9${RUN_ID}`, sign: f.signPublic, box: f.boxPublic }, signed: true }), 409, "has_name", "a second name for the same Mac");

    same((await f.rename(was)).name, was, "changing back within the week");
    same((await anon().request("GET", `/v1/names/${to}`)).json?.reason, "held", "now the other one is kept");
    same((await f.rename(`fay3${RUN_ID}`)).was, was, "a third change today");
    same((await anon().request("GET", `/v1/names/${to}`)).json?.free, true, "one old name is kept at a time: the one before is free");
    same((await anon().request("GET", `/v1/names/${was}`)).json?.reason, "held", "and the last one is kept");
    isError(await f.request("POST", "/v1/users/me/name", { body: { name: `fay4${RUN_ID}` }, signed: true }), 429, "rate_limited", "a fourth change in a day");

    isOk(await f.request("DELETE", "/v1/users/me", { signed: true }), 200, "the account goes");
    same((await anon().request("GET", `/v1/names/${was}`)).json?.free, true, "and the name it kept is free at once");
  });

  await test("routing: unknown paths, wrong methods", async () => {
    isError(await anon().request("GET", "/"), 404, "not_found", "GET /");
    isError(await anon().request("GET", "/v1/nothing"), 404, "not_found", "unknown API path");
    const wrong = await anon().request("POST", "/v1/health", { body: {} });
    isError(wrong, 405, "method_not_allowed", "POST /v1/health");
    same(wrong.headers.get("allow"), "GET", "Allow header");
    same(wrong.headers.get("x-kliner"), "1", "an error carries X-Kliner too");
    isError(await anon().request("DELETE", `/v1/users/${alice().name}`), 405, "method_not_allowed", "DELETE someone else");
    const posted = await anon().request("POST", `/@${alice().name}`, { body: {} });
    check(posted.status === 403 && (posted.text ?? "").includes("from its page"), `a POST from outside a name's page is turned away, got ${posted.status}`);
    isError(await anon().request("PUT", `/@${alice().name}`, { body: {} }), 405, "method_not_allowed", "PUT to a profile page");
  });

  await test("rate limits: names 60/min, beta 10/min, waitlist 10/min", async () => {
    // Stay inside one clock minute, since the counters are per minute.
    const second = new Date().getSeconds();
    if (second > 40) await sleep((61 - second) * 1000);
    const c = anon();
    const statuses = [];
    for (let i = 0; i < 60; i++) statuses.push((await c.request("GET", `/v1/names/rate${i}x`)).status);
    check(statuses.every((s) => s === 200), `60 name checks pass, got ${statuses.filter((s) => s !== 200).length} failures`);
    const limited = await c.request("GET", "/v1/names/rate61x");
    isError(limited, 429, "rate_limited", "the 61st name check in a minute");
    check(Number(limited.headers.get("retry-after")) > 0, "Retry-After is set");
    isOk(await anon().request("GET", "/v1/names/rate62x"), 200, "another address is not limited");

    const beta = anon();
    for (let i = 0; i < 10; i++) await beta.request("POST", "/v1/beta/activate", { body: { code: "KLNR-0000-0000", device: "x" } });
    isError(await beta.request("POST", "/v1/beta/activate", { body: { code: "KLNR-0000-0000", device: "x" } }), 429, "rate_limited", "the 11th beta try");

    const wait = anon();
    for (let i = 0; i < 10; i++) await wait.request("POST", "/v1/waitlist", { body: { email: `r${i}.${RUN_ID}@example.com` } });
    isError(await wait.request("POST", "/v1/waitlist", { body: { email: `r10.${RUN_ID}@example.com` } }), 429, "rate_limited", "the 11th waitlist join");
    const keys = await sql(`SELECT key, count FROM hits WHERE key LIKE 'names:${c.ip}:%'`);
    check(keys.length === 1 && /^names:10\.77\.\d+\.\d+:\d+$/.test(keys[0].key) && keys[0].count === 61, `hits row is names:<ip>:<minute>, got ${JSON.stringify(keys)}`);
  });
}

// ---------------------------------------------------------------------------
// Setup, run, teardown
// ---------------------------------------------------------------------------

async function waitForHealth(timeoutMs) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    if (dev.exitCode !== null) throw new Error(`wrangler dev exited with code ${dev.exitCode}`);
    try {
      const res = await fetch(`${BASE}/v1/health`);
      if (res.ok) return;
    } catch {
      /* not up yet */
    }
    await sleep(300);
  }
  throw new Error(`wrangler dev did not answer within ${timeoutMs / 1000} s`);
}

async function stopDev() {
  if (!dev || dev.exitCode !== null) return;
  const exited = new Promise((resolve) => dev.once("exit", resolve));
  try {
    process.kill(-dev.pid, "SIGTERM"); // the whole group: npx, wrangler, workerd
  } catch {
    /* already gone */
  }
  const timer = setTimeout(() => {
    try {
      process.kill(-dev.pid, "SIGKILL");
    } catch {
      /* already gone */
    }
  }, 5000);
  await exited;
  clearTimeout(timer);
}

function logTail(lines = 40) {
  try {
    return fs.readFileSync(path.join(TMP, "wrangler-dev.log"), "utf8").split("\n").slice(-lines).join("\n");
  } catch {
    return "(no log)";
  }
}

async function main() {
  console.log(`Kliner e2e: wrangler = ${WRANGLER.join(" ")}`);
  console.log(`temp dir: ${TMP}`);

  // 1. Local D1: schema, then beta codes made by gen-codes.mjs in a scratch copy
  //    (so the real beta-codes.local.txt next to this test is never touched).
  await wrangler(["d1", "execute", "kliner", "--local", "--persist-to", PERSIST, "--file", path.join(ROOT, "schema.sql")]);
  const codesDir = path.join(TMP, "codes");
  fs.mkdirSync(codesDir);
  fs.copyFileSync(path.join(ROOT, "gen-codes.mjs"), path.join(codesDir, "gen-codes.mjs"));
  await run(process.execPath, [path.join(codesDir, "gen-codes.mjs")], { cwd: codesDir });
  const betaCodes = fs.readFileSync(path.join(codesDir, "beta-codes.local.txt"), "utf8").trim().split("\n");
  await wrangler(["d1", "execute", "kliner", "--local", "--persist-to", PERSIST, "--file", path.join(codesDir, "beta-codes.sql")]);

  // The app zip, put up the way deploy.sh puts it up (fake bytes with a zip's signature).
  const zipFile = path.join(TMP, "Kliner.app.zip");
  fs.writeFileSync(zipFile, APP_ZIP);
  await wrangler(["r2", "object", "put", "kliner-transfers/releases/Kliner.app.zip", "--local", "--persist-to", PERSIST,
    "--file", zipFile, "--content-type", "application/zip"]);

  // 2. wrangler dev on free ports, with /__scheduled enabled.
  const port = await freePort();
  const inspectorPort = await freePort();
  BASE = `http://127.0.0.1:${port}`;
  const log = fs.openSync(path.join(TMP, "wrangler-dev.log"), "w");
  dev = spawn(
    WRANGLER[0],
    [...WRANGLER.slice(1), "dev", "--local", "--persist-to", PERSIST, "--port", String(port), "--ip", "127.0.0.1",
      "--inspector-port", String(inspectorPort), "--test-scheduled", "--show-interactive-dev-session=false"],
    { cwd: ROOT, env: ENV, detached: true, stdio: ["ignore", log, log] },
  );
  const cleanupAndExit = async () => {
    await stopDev();
    process.exit(130);
  };
  process.on("SIGINT", cleanupAndExit);
  process.on("SIGTERM", cleanupAndExit);

  let failed = true;
  try {
    await waitForHealth(90000);
    console.log(`wrangler dev is up on ${BASE}\n`);
    const started = Date.now();
    await scenarios(betaCodes);
    const passed = results.filter((r) => r.failures.length === 0);
    const checks = results.reduce((n, r) => n + r.checks, 0);
    const failedChecks = results.reduce((n, r) => n + r.failures.length, 0);
    console.log(`\n${"=".repeat(64)}`);
    console.log(`${passed.length}/${results.length} tests passed, ${checks - failedChecks}/${checks} checks passed (${((Date.now() - started) / 1000).toFixed(1)} s)`);
    for (const r of results.filter((x) => x.failures.length)) console.log(`FAILED: ${r.name} (${r.failures.length} failed checks)`);
    console.log("=".repeat(64));
    failed = passed.length !== results.length;
    if (failed) console.log(`\nLast lines of the wrangler dev log:\n${logTail()}`);
  } catch (err) {
    console.error(`\nE2E setup failed: ${err.stack || err}\n\nLast lines of the wrangler dev log:\n${logTail()}`);
  } finally {
    await stopDev();
    if (process.env.KEEP) console.log(`kept ${TMP}`);
    else fs.rmSync(TMP, { recursive: true, force: true });
  }
  process.exit(failed ? 1 : 0);
}

main();

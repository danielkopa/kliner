// Kliner reference client for Node 22, built-in `crypto` only.
//
// It does what the Mac app does, byte for byte, so it doubles as executable
// documentation of SPEC.md:
//   - signed requests: Ed25519 over
//       KLINER1\n<METHOD>\n<PATH>\n<TIME>\n<hex sha256 of the raw body>
//   - file encryption: ChaCha20-Poly1305 per 8 MiB chunk with nonce
//       00 00 00 00 || uint64 big-endian n, in CryptoKit's combined layout
//       nonce(12) || ciphertext || tag(16)
//   - the header: X25519 with an ephemeral key, HKDF-SHA256 (salt =
//       ephemeral public || recipient box public, info "kliner-file-v1"),
//       then ChaCha20-Poly1305 of the file metadata JSON.
//
// Usage:
//   import { Kliner } from "./client.mjs";
//   const dan = new Kliner("http://127.0.0.1:8787", { name: "dan" });
//   await dan.register("my-mac");
//   const { id } = await dan.send("alice", fileBytes, { fileName: "poster.mov" });
//   // as alice:
//   const [t] = (await alice.inbox()).transfers;
//   const { meta, data } = await alice.receive(t);   // decrypted and verified
//   await alice.received(t.id);

import crypto from "node:crypto";

export const CHUNK = 8 * 1024 * 1024; // 8 MiB of plaintext per part
const HKDF_INFO = "kliner-file-v1";

// ---------------------------------------------------------------------------
// Encoding and hashing
// ---------------------------------------------------------------------------

export const b64u = {
  encode: (bytes) => Buffer.from(bytes).toString("base64url"), // no padding
  decode: (text) => Buffer.from(text, "base64url"),
};

export function sha256Hex(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

// A fresh identity: an Ed25519 signing pair and an X25519 box pair.
export function newIdentity() {
  return {
    sign: crypto.generateKeyPairSync("ed25519"),
    box: crypto.generateKeyPairSync("x25519"),
  };
}

// Raw 32-byte public key (what CryptoKit calls rawRepresentation).
export function rawPublicKey(publicKey) {
  return b64u.decode(publicKey.export({ format: "jwk" }).x);
}

export function publicKeyFromRaw(raw, curve /* "Ed25519" | "X25519" */) {
  return crypto.createPublicKey({ key: { kty: "OKP", crv: curve, x: b64u.encode(raw) }, format: "jwk" });
}

// ---------------------------------------------------------------------------
// Signing
// ---------------------------------------------------------------------------

export function signingString(method, path, time, body) {
  return `KLINER1\n${method.toUpperCase()}\n${path}\n${time}\n${sha256Hex(body)}`;
}

export function signRequest(privateKey, method, path, time, body) {
  return b64u.encode(crypto.sign(null, Buffer.from(signingString(method, path, time, body), "utf8"), privateKey));
}

// ---------------------------------------------------------------------------
// File encryption
// ---------------------------------------------------------------------------

// 00 00 00 00 || uint64 big-endian n
export function partNonce(n) {
  const nonce = Buffer.alloc(12);
  nonce.writeBigUInt64BE(BigInt(n), 4);
  return nonce;
}

// ChaCha20-Poly1305 in CryptoKit's combined layout: nonce || ciphertext || tag.
export function seal(key, nonce, plaintext) {
  const cipher = crypto.createCipheriv("chacha20-poly1305", key, nonce, { authTagLength: 16 });
  const body = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([nonce, body, cipher.getAuthTag()]);
}

export function open(key, combined, expectedNonce) {
  combined = Buffer.from(combined);
  if (combined.length < 28) throw new Error("sealed box is too short");
  const nonce = combined.subarray(0, 12);
  if (expectedNonce && !nonce.equals(expectedNonce)) throw new Error("unexpected nonce");
  const decipher = crypto.createDecipheriv("chacha20-poly1305", key, nonce, { authTagLength: 16 });
  decipher.setAuthTag(combined.subarray(combined.length - 16));
  return Buffer.concat([decipher.update(combined.subarray(12, combined.length - 16)), decipher.final()]);
}

function wrapKey(shared, ephemeralRaw, recipientBoxRaw) {
  const salt = Buffer.concat([ephemeralRaw, recipientBoxRaw]); // 64 bytes
  return Buffer.from(crypto.hkdfSync("sha256", shared, salt, HKDF_INFO, 32));
}

// The `header` field: b64u of {"v":1,"epk":...,"box":...}.
export function sealHeader(recipientBoxRaw, meta) {
  const ephemeral = crypto.generateKeyPairSync("x25519");
  const ephemeralRaw = rawPublicKey(ephemeral.publicKey);
  const shared = crypto.diffieHellman({
    privateKey: ephemeral.privateKey,
    publicKey: publicKeyFromRaw(recipientBoxRaw, "X25519"),
  });
  const box = seal(wrapKey(shared, ephemeralRaw, recipientBoxRaw), crypto.randomBytes(12), Buffer.from(JSON.stringify(meta), "utf8"));
  const outer = { v: 1, epk: b64u.encode(ephemeralRaw), box: b64u.encode(box) };
  return b64u.encode(Buffer.from(JSON.stringify(outer), "utf8"));
}

// Returns {k, name, size, sha256, chunk, from}; throws if it is not for us.
export function openHeader(header, boxPrivateKey, boxPublicRaw) {
  const outer = JSON.parse(b64u.decode(header).toString("utf8"));
  if (outer.v !== 1) throw new Error(`unknown header version ${outer.v}`);
  const ephemeralRaw = b64u.decode(outer.epk);
  const shared = crypto.diffieHellman({ privateKey: boxPrivateKey, publicKey: publicKeyFromRaw(ephemeralRaw, "X25519") });
  const meta = JSON.parse(open(wrapKey(shared, ephemeralRaw, boxPublicRaw), b64u.decode(outer.box)).toString("utf8"));
  return meta;
}

// Encrypts a whole file for one recipient: the parts to upload and the header.
export function encryptFile(data, recipientBoxRaw, { fileName, from }) {
  data = Buffer.from(data);
  const key = crypto.randomBytes(32);
  const count = Math.max(1, Math.ceil(data.length / CHUNK));
  const parts = [];
  for (let n = 0; n < count; n++) parts.push(seal(key, partNonce(n), data.subarray(n * CHUNK, (n + 1) * CHUNK)));
  const meta = { k: b64u.encode(key), name: fileName, size: data.length, sha256: sha256Hex(data), chunk: CHUNK, from };
  return {
    header: sealHeader(recipientBoxRaw, meta),
    parts,
    bytes: parts.reduce((sum, p) => sum + p.length, 0),
    meta,
  };
}

export function decryptPart(key, n, combined) {
  return open(key, combined, partNonce(n));
}

// The receiver saves under the sender's file name, never a path.
export function safeFileName(name) {
  const base = String(name || "").split(/[/\\]/).pop().replace(/[\u0000-\u001f\u007f:]/g, "").trim();
  return !base || base === "." || base === ".." ? "Kliner file" : base.replace(/^\.+/, "") || "Kliner file";
}

// ---------------------------------------------------------------------------
// HTTP client
// ---------------------------------------------------------------------------

export class ApiError extends Error {
  constructor(res) {
    super(`${res.status} ${res.json?.error ?? ""}: ${res.json?.message ?? res.text ?? ""}`);
    this.res = res;
    this.status = res.status;
    this.code = res.json?.error;
  }
}

export class Kliner {
  // base: server URL without trailing slash. ip: optional CF-Connecting-IP
  // (only honoured by a local `wrangler dev`; tests use it to keep
  // rate-limit buckets apart).
  constructor(base, { name, identity = newIdentity(), ip } = {}) {
    this.base = base.replace(/\/+$/, "");
    this.name = name;
    this.identity = identity;
    this.ip = ip;
  }

  get signPublic() {
    return b64u.encode(rawPublicKey(this.identity.sign.publicKey));
  }

  get boxPublic() {
    return b64u.encode(rawPublicKey(this.identity.box.publicKey));
  }

  // Low-level request. Returns {status, headers, bytes, text, json}.
  // Options: body (object -> JSON, Buffer/Uint8Array -> raw), signed,
  // time (override X-Kliner-Time), user (override X-Kliner-User),
  // signer (override the private key), headers.
  async request(method, path, { body, signed = false, time, user, signer, headers = {} } = {}) {
    const isRaw = body instanceof Uint8Array;
    const bytes = body === undefined ? Buffer.alloc(0) : isRaw ? Buffer.from(body) : Buffer.from(JSON.stringify(body), "utf8");
    const h = {};
    if (body !== undefined) h["Content-Type"] = isRaw ? "application/octet-stream" : "application/json";
    if (this.ip) h["CF-Connecting-IP"] = this.ip;
    if (signed) {
      const t = String(time ?? Math.floor(Date.now() / 1000));
      h["X-Kliner-User"] = user ?? this.name;
      h["X-Kliner-Time"] = t;
      h["X-Kliner-Sig"] = signRequest(signer ?? this.identity.sign.privateKey, method, new URL(path, "http://x").pathname, t, bytes);
    }
    Object.assign(h, headers); // last, so a caller (a test) can override anything
    const hasBody = method !== "GET" && method !== "HEAD" && (body !== undefined || method !== "DELETE");
    const res = await fetch(this.base + path, { method, headers: h, body: hasBody ? bytes : undefined });
    const buf = Buffer.from(await res.arrayBuffer());
    const out = { status: res.status, headers: res.headers, bytes: buf, text: undefined, json: undefined };
    if ((res.headers.get("content-type") || "").includes("json")) {
      out.text = buf.toString("utf8");
      try {
        out.json = JSON.parse(out.text);
      } catch {
        /* leave json undefined */
      }
    } else if (!(res.headers.get("content-type") || "").includes("octet-stream")) {
      out.text = buf.toString("utf8");
    }
    return out;
  }

  // Like request(), but throws ApiError unless the status is 2xx; returns the JSON.
  async call(method, path, options) {
    const res = await this.request(method, path, options);
    if (res.status < 200 || res.status > 299) throw new ApiError(res);
    return res.json;
  }

  health() {
    return this.call("GET", "/v1/health");
  }

  checkName(name) {
    return this.call("GET", `/v1/names/${encodeURIComponent(name)}`);
  }

  // POST /v1/users, signed with the key being registered. `claim` is the
  // code kliner.app showed for a name held there.
  register(device = "node-client", claim) {
    return this.call("POST", "/v1/users", {
      body: { name: this.name, sign: this.signPublic, box: this.boxPublic, device, ...(claim ? { claim } : {}) },
      signed: true,
    });
  }

  // POST /v1/users/me/name: the same keys, a new name; this client signs as
  // the new name from then on.
  async rename(name, claim) {
    const out = await this.call("POST", "/v1/users/me/name", { body: claim ? { name, claim } : { name }, signed: true });
    this.name = out.name;
    return out;
  }

  // POST /v1/claims, the way kliner.app's page does it: not signed.
  claimOnSite(name) {
    return this.call("POST", "/v1/claims", { body: { name } });
  }

  lookup(name) {
    return this.call("GET", `/v1/users/${encodeURIComponent(name)}`);
  }

  deleteMe() {
    return this.call("DELETE", "/v1/users/me", { signed: true });
  }

  putProfile(profile) {
    return this.call("PUT", "/v1/profile", { body: profile, signed: true });
  }

  profile(name) {
    return this.call("GET", `/v1/users/${encodeURIComponent(name)}/profile`);
  }

  inbox() {
    return this.call("GET", "/v1/inbox", { signed: true });
  }

  outbox() {
    return this.call("GET", "/v1/outbox", { signed: true });
  }

  createTransfer({ to, parts, bytes, header }) {
    return this.call("POST", "/v1/transfers", { body: { to, parts, bytes, header }, signed: true });
  }

  putPart(id, n, bytes) {
    return this.call("PUT", `/v1/transfers/${id}/parts/${n}`, { body: new Uint8Array(bytes), signed: true });
  }

  ready(id) {
    return this.call("POST", `/v1/transfers/${id}/ready`, { signed: true });
  }

  async getPart(id, n) {
    const res = await this.request("GET", `/v1/transfers/${id}/parts/${n}`, { signed: true });
    if (res.status !== 200) throw new ApiError(res);
    return res.bytes;
  }

  received(id) {
    return this.call("POST", `/v1/transfers/${id}/received`, { signed: true });
  }

  decline(id) {
    return this.call("POST", `/v1/transfers/${id}/decline`, { signed: true });
  }

  cancel(id) {
    return this.call("DELETE", `/v1/transfers/${id}`, { signed: true });
  }

  // Encrypts `data` for `to`, uploads every part and marks it ready.
  async send(to, data, { fileName = "file.bin" } = {}) {
    const recipient = await this.lookup(to);
    const enc = encryptFile(data, b64u.decode(recipient.box), { fileName, from: this.name });
    const { id, expires } = await this.createTransfer({ to, parts: enc.parts.length, bytes: enc.bytes, header: enc.header });
    for (let n = 0; n < enc.parts.length; n++) await this.putPart(id, n, enc.parts[n]);
    await this.ready(id);
    return { id, expires, parts: enc.parts.length, bytes: enc.bytes, meta: enc.meta };
  }

  // Opens an inbox entry's header (who sent what).
  openHeader(transfer) {
    return openHeader(transfer.header, this.identity.box.privateKey, rawPublicKey(this.identity.box.publicKey));
  }

  // Downloads and decrypts an inbox entry; checks the size and sha256.
  // Does not call received(): the caller does, once the file is safely saved.
  async receive(transfer) {
    const meta = this.openHeader(transfer);
    const key = b64u.decode(meta.k);
    const chunks = [];
    for (let n = 0; n < transfer.parts; n++) chunks.push(decryptPart(key, n, await this.getPart(transfer.id, n)));
    const data = Buffer.concat(chunks);
    if (data.length !== meta.size) throw new Error(`size mismatch: got ${data.length}, header says ${meta.size}`);
    if (sha256Hex(data) !== meta.sha256) throw new Error("sha256 mismatch");
    return { meta, data, fileName: safeFileName(meta.name) };
  }
}

-- Kliner Cloud D1 schema (from SPEC.md). Safe to apply more than once.
--
-- users      one row per @name: public signing + box keys (raw 32 bytes, base64url)
-- profiles   the opt-in public profile, stored as cleaned JSON
-- transfers  encrypted store-and-forward sends; the parts live in R2 at t/<id>/<n>
-- beta_codes sha256 hex of each normalised beta code, and the device that used it
-- waitlist   email + stable position
-- hits       rate-limit counters, one row per bucket and window (a minute, an
--            hour or a day), kept a day
-- holds      a name kept for somebody for a while: for its owner for 7 days
--            after they change it (kind 'renamed', sign = their key), or held
--            on kliner.app for 30 days (kind 'claimed', code = sha256 hex of the
--            code the site showed)

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

-- RefTime's backup: who signed in, their devices' keys, and their items.
-- Health numbers and routes are never sent here (the app strips them), so
-- an item is a match's setup and timeline, or a team sheet.

CREATE TABLE users (
  id          TEXT PRIMARY KEY,           -- random, ours
  provider    TEXT NOT NULL,              -- 'apple' | 'google'
  subject     TEXT NOT NULL,              -- the provider's stable id for the person
  email       TEXT,                       -- as the provider shared it, if it did
  created_at  TEXT NOT NULL,
  UNIQUE (provider, subject)
);

-- One per signed-in device. Only the SHA-256 of the key is kept.
CREATE TABLE device_keys (
  key_hash     TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   TEXT NOT NULL,
  last_used_at TEXT NOT NULL
);
CREATE INDEX device_keys_user ON device_keys (user_id);

-- Matches and teams, one row each, last write wins. A deletion is a row
-- with deleted = 1 and no body, so other devices learn of it.
CREATE TABLE items (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL,              -- 'match' | 'team'
  id          TEXT NOT NULL,              -- the app's UUID
  body        TEXT,                       -- the app's JSON, or NULL when deleted
  deleted     INTEGER NOT NULL DEFAULT 0,
  updated_at  INTEGER NOT NULL,           -- server ms, for "changes since"
  PRIMARY KEY (user_id, kind, id)
);
CREATE INDEX items_since ON items (user_id, updated_at);

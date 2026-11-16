-- DuckLearn telemetry (docs/TELEMETRY.md). Anonymous: install_id is a random id the app
-- makes when the learner agrees to share; there is no name, account or device id.

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,              -- the app's event id (ULID): resending is harmless
  install_id TEXT NOT NULL,
  ts_utc TEXT NOT NULL,
  tz_offset_min INTEGER,
  type TEXT NOT NULL,
  session_id TEXT,
  app_version TEXT,
  content_version TEXT,
  device_kind TEXT,
  payload TEXT NOT NULL,            -- JSON, already stripped of anything typed or said
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX IF NOT EXISTS events_install ON events(install_id, ts_utc);
CREATE INDEX IF NOT EXISTS events_type ON events(type);

CREATE TABLE IF NOT EXISTS crashes (
  n INTEGER PRIMARY KEY AUTOINCREMENT,
  install_id TEXT,
  ts_utc TEXT,
  app_version TEXT,
  device_kind TEXT,
  os_version TEXT,
  where_ TEXT,
  error_type TEXT,
  message TEXT,
  stack TEXT,
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

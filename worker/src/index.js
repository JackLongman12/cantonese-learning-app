// DuckLearn telemetry Worker (docs/TELEMETRY.md).
//
//   POST /v1/events   {events: [...]}   anonymous usage events from the app (≤ 400)
//   POST /v1/crash    {...}             one crash report
//   GET  /v1/export   ?table=events|crashes&after=<rowid>&limit=<n>
//                     Authorization: Bearer <ADMIN_TOKEN>  (for `duk telemetry pull`)
//   GET  /v1/health
//
// Everything sent is untrusted: shapes and sizes are checked, unknown fields dropped.
// Raw events older than RETENTION_DAYS are deleted by the daily cron.

const MAX_BODY = 600_000;
const MAX_EVENTS = 400;
const MAX_PAYLOAD = 4_000;
const RETENTION_DAYS = 400;

const ID = /^[0-9A-Za-z_-]{1,64}$/;

// The event types the app shares (app/lib/events/telemetry_filter.dart, sharedTypes).
// Anything else is dropped, so the table only ever holds what the privacy notice lists.
const SHARED_TYPES = new Set([
  "app.open", "session.start", "session.end", "session.more", "item.shown", "item.check",
  "item.reveal", "item.audio", "item.done", "review.applied", "speech.attempt",
  "conv.choice", "nav.screen", "plan.step", "settings.change", "reader.open",
  "reader.lookup", "word.save", "word.remove", "word.flag", "word.practice",
  "experiment.assigned", "onboarding.done", "app.crash",
]);
const TYPE = /^[a-z][a-z_.]{0,39}$/;
const ISO = /^\d{4}-\d{2}-\d{2}T[\d:.]+Z?$/;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });

const str = (v, max) => (typeof v === "string" ? v.slice(0, max) : null);

async function readJson(request) {
  const len = Number(request.headers.get("content-length") || 0);
  if (len > MAX_BODY) return null;
  const text = await request.text();
  if (text.length > MAX_BODY) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/** One event as stored, or null when it is malformed. */
export function cleanEvent(e) {
  if (!e || typeof e !== "object") return null;
  if (!ID.test(e.id ?? "") || !ID.test(e.install_id ?? "")) return null;
  if (!TYPE.test(e.type ?? "") || !SHARED_TYPES.has(e.type)) return null;
  if (!ISO.test(e.ts_utc ?? "")) return null;
  const payload = JSON.stringify(
    e.payload && typeof e.payload === "object" ? e.payload : {},
  );
  if (payload.length > MAX_PAYLOAD) return null;
  return [
    e.id,
    e.install_id,
    e.ts_utc,
    Number.isInteger(e.tz_offset_min) ? e.tz_offset_min : null,
    e.type,
    str(e.session_id, 64),
    str(e.app_version, 32),
    str(e.content_version, 64),
    str(e.device_kind, 16),
    payload,
  ];
}

/** Per-IP request limit (Cloudflare rate limiting binding). Missing binding: allowed. */
async function allowed(limiter, request) {
  if (!limiter) return true;
  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  const { success } = await limiter.limit({ key: ip });
  return success;
}

async function postEvents(request, env) {
  if (!(await allowed(env.EVENTS_LIMIT, request))) return json({ error: "slow down" }, 429);
  const body = await readJson(request);
  const list = body?.events;
  if (!Array.isArray(list) || list.length === 0 || list.length > MAX_EVENTS) {
    return json({ error: "bad batch" }, 400);
  }
  // one install per request: a single request can't invent many learners
  const installs = new Set(list.map((e) => e?.install_id));
  if (installs.size !== 1) return json({ error: "bad batch" }, 400);
  const rows = list.map(cleanEvent).filter(Boolean);
  if (rows.length) {
    const stmt = env.DB.prepare(
      `INSERT OR IGNORE INTO events
       (id, install_id, ts_utc, tz_offset_min, type, session_id, app_version,
        content_version, device_kind, payload)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    await env.DB.batch(rows.map((r) => stmt.bind(...r)));
  }
  return json({ ok: true, stored: rows.length, dropped: list.length - rows.length });
}

async function postCrash(request, env) {
  if (!(await allowed(env.SLOW_LIMIT, request))) return json({ error: "slow down" }, 429);
  const c = await readJson(request);
  if (!c || typeof c !== "object" || !ID.test(c.install_id ?? "")) {
    return json({ error: "bad crash" }, 400);
  }
  await env.DB.prepare(
    `INSERT INTO crashes
     (install_id, ts_utc, app_version, device_kind, os_version, where_, error_type,
      message, stack)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      c.install_id,
      ISO.test(c.ts_utc ?? "") ? c.ts_utc : null,
      str(c.app_version, 32),
      str(c.device_kind, 16),
      str(c.os_version, 120),
      str(c.where, 16),
      str(c.error_type, 120),
      str(c.message, 600),
      str(c.stack, 6000),
    )
    .run();
  return json({ ok: true });
}

/** Constant-time comparison, so the token cannot be guessed by timing. */
function sameToken(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function exportRows(request, env, url) {
  if (!(await allowed(env.SLOW_LIMIT, request))) return json({ error: "slow down" }, 429);
  const auth = request.headers.get("authorization") || "";
  if (!env.ADMIN_TOKEN || !sameToken(auth, `Bearer ${env.ADMIN_TOKEN}`)) {
    return json({ error: "unauthorized" }, 401);
  }
  const table = url.searchParams.get("table") === "crashes" ? "crashes" : "events";
  const after = Number(url.searchParams.get("after") || 0) || 0;
  const limit = Math.min(Number(url.searchParams.get("limit") || 5000) || 5000, 10000);
  const { results } = await env.DB.prepare(
    `SELECT rowid AS _row, * FROM ${table} WHERE rowid > ? ORDER BY rowid LIMIT ?`,
  )
    .bind(after, limit)
    .all();
  return json({ rows: results });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method === "POST" && url.pathname === "/v1/events") {
        return await postEvents(request, env);
      }
      if (request.method === "POST" && url.pathname === "/v1/crash") {
        return await postCrash(request, env);
      }
      if (request.method === "GET" && url.pathname === "/v1/export") {
        return await exportRows(request, env, url);
      }
      if (url.pathname === "/v1/health") return json({ ok: true });
      return json({ error: "not found" }, 404);
    } catch (err) {
      console.error(err);
      return json({ error: "server" }, 500);
    }
  },

  // daily: raw events past the retention period are deleted
  async scheduled(_event, env) {
    await env.DB.prepare(
      `DELETE FROM events WHERE received_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)`,
    )
      .bind(`-${RETENTION_DAYS} days`)
      .run();
    await env.DB.prepare(
      `DELETE FROM crashes WHERE received_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)`,
    )
      .bind(`-${RETENTION_DAYS} days`)
      .run();
  },
};

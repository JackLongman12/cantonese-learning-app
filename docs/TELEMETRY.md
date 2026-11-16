# Usage data, crash reports and A/B tests

Added 2026-11-17 when DuckLearn became an app for beginners (speakers who can't read, and
people learning the language). The owner can no longer judge the app from their own use, so
anonymous data from real learners decides what to change.

## What the learner agrees to

Asked once: in onboarding (new installs) or as a card on Home (installs from before). Nothing
is sent until they say yes; Settings → "Share anonymous usage and crash reports" turns it off.

- **Sent:** the learning events in `app/lib/events/telemetry_filter.dart` (`sharedTypes`):
  sessions, which sentences and characters were shown, checks, reveals, misses, grades, screens
  opened, settings changed, experiment arms, app version, `android`/`windows`, time zone offset.
  Crash reports: error type, message (600 characters), stack (6,000), app and OS version.
- **Never sent:** anything typed, pasted or said (payload keys `text`, `en`, `reading`,
  `per_token`, `heard`, `said`, `query` are removed; characters looked up in pasted text are
  removed), the device id, names, accounts, location, contacts.
- **Id:** a random `telemetry_id` made when sharing is turned on. Turning sharing off deletes
  it and any unsent crash reports; turning it on again makes a new one and sends only what
  happens from then on. The first time sharing is turned on, the history so far is sent too.
- **Kept:** 400 days on Cloudflare D1, then deleted by the Worker's daily cron.

Changing what is collected: edit `telemetry_filter.dart` and its test, and this section, in the
same change. Never add free text.

## Pieces

| Piece | Where |
|---|---|
| Worker (Cloudflare, free plan) | `worker/` · `https://ducklearn-telemetry.lp-reports.workers.dev` |
| Database | D1 `ducklearn-telemetry` (`worker/schema.sql`) |
| App uploader | `app/lib/platform/telemetry.dart` (the event log is the queue; a cursor file records what went out) |
| Crash capture | `app/lib/main.dart`: `FlutterError.onError` and `PlatformDispatcher.onError` → a file → sent on the next upload |
| Download and report | `duk telemetry pull` → `data/telemetry/` (git-ignored) · `duk telemetry report` → `build/telemetry_report.md` |
| Admin token | `secrets.json` → `telemetry_admin_token`, and the Worker secret `ADMIN_TOKEN`. Never in the app or the repo. |

Uploads happen 10 s after start, every 2 minutes while the app is open, when it is put in
the background and when it comes back, 400 events per request; a crash is sent at once. There
are no background jobs or wake-ups, so a closed app uses no battery, and an idle check only
compares file sizes. The Worker accepts at most 400 events and 600 KB per request, drops malformed events,
and ignores duplicates (event ids are ULIDs).

Abuse protection (2026-11-17): per-IP rate limits (30 event requests and 10 crash or export
requests a minute, Cloudflare rate-limiting bindings `EVENTS_LIMIT` / `SLOW_LIMIT`), only the
event types in `sharedTypes` are stored (the Worker keeps its own copy of the list; keep both in
sync), one install id per request, and `no-store` / `nosniff` on every response. The export
needs the admin token (constant-time compare). Crash messages and stacks are scrubbed on the
device first: Chinese text, long numbers and email addresses become placeholders
(`redactCrashText`).

Deploying the Worker (from `worker/`, PowerShell needs `npx.cmd`, not `npx`):

```
npx.cmd wrangler@4 deploy
npx.cmd wrangler@4 d1 execute ducklearn-telemetry --remote --file schema.sql   # new tables only
```

Rotating the admin token: write a new one into `secrets.json`, then pipe it to
`npx.cmd wrangler@4 secret put ADMIN_TOKEN`. Never print it.

## Experiments (A/B)

Each install is put into one arm of every experiment, for good, from a hash of its device id
(`app/lib/engine/experiments.dart`). The arms are logged once as `experiment.assigned`.

| Id | Arms (control first) | Who | Question | Decides on |
|---|---|---|---|---|
| `meaning_after_check` | shown, hidden | speakers | After hearing a sentence, does the English meaning help or distract someone who understood it by ear? | lapse rate at later reviews |
| `first_session` | short (5 sentences, 4 new), longer (8, 6) | everyone | Which first session brings more people back on a later day? | came back on a later day |

Adding one: add it to `experiments` in Dart and `EXPERIMENT_ARMS` in
`pipeline/duk/telemetry.py`, use `services.arm(id)` where it matters, add a row here. Never
reuse an id. Ending one: hard-code the winner, remove it from both lists, and record the result
in `docs/CHANGELOG.md`.

## Reading the report, and what to do

`duk telemetry pull` then open `build/telemetry_report.md`. Rules for acting on it:

1. **Experiments.** The report decides only when each arm has at least 30 installs. Day-1
   return is compared with a two-proportion test; lapse rates with a bootstrap that resamples
   whole installs (one learner's reads are not independent). "Adopt it" → make that arm the
   only behavior. "No difference" after 30+ per arm → keep the simpler arm and end the test.
   "Still collecting" → wait; the report says how many installs a 15-point effect needs.
2. **Hardest characters** (ranked by the low end of a Wilson interval, at least 8 reads):
   first check the reading is right (review queue, `fix_yue`). If it is, give the character
   more help: a sound-family example, a deck card, or a note in `char_info`.
3. **Sentences to look at** (lapses and skips per showing): check readings first. A correct
   but hard sentence moves later in its topic's path or is rewritten with fewer new characters.
4. **First session finished / came back.** If under half finish the first session, shorten it
   or the onboarding. If few come back, look at where they stopped (`session.end` reasons,
   screens).
5. **Crashes.** Grouped by error and the first DuckLearn frame. Fix the top group before any
   feature work; a crash that recurs after a fix's version is not fixed.
6. **Where people go.** A screen almost nobody opens is a candidate to remove or merge (fewer
   tools, clearer path).

Write what was decided and why into `docs/CHANGELOG.md`, so the next reader of the report
knows what has already been acted on.

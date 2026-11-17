# Event schema (v1)

The event log is the source of truth for everything the app knows about the learner. All other progress tables are caches rebuilt by replaying it. Changing this schema is the most expensive change in the project, so additions are fine, but existing fields never change meaning.

## Envelope

| Field | Type | Notes |
|---|---|---|
| `id` | ULID | globally unique, sortable; dedup key for sync |
| `ts_utc` | ISO 8601 ms | wall clock, UTC |
| `tz_offset_min` | int | local offset at the time |
| `mono_ms` | int | monotonic ms since session start; use for all durations |
| `device_id` | string | random, generated on first run |
| `device_kind` | `android` \| `windows` \| `macos` | |
| `session_id` | ULID | |
| `app_version`, `content_version` | string | |
| `schema_v` | int | 1 |
| `type` | string | below |
| `payload` | object | below |

Stored one JSON object per line (`.jsonl`), gzip-compressed for sync.

## Types

### Session and app
- `app.open` `{source: icon|notification|widget|hotkey, notif_id?}`
- `app.background` / `app.foreground` `{}`
- `app.close` `{}`
- `session.start` `{mode: review|reader|deck|map|placement|paste|ocr, goal?, planned_items, region_ctx?: macau|hk|other}`
- `session.end` `{reason: done|quit|fatigue_stop|timeout, items_done, active_ms}`
- `idle.start` / `idle.end` `{}` (no input for 20 s; excluded from latencies)
- `nav.screen` `{screen}`

### Items
- `item.shown` `{exposure_id, sentence_id?|card_id?, lang, item_ids[], scaffold[], planner: {score, reasons[]}, pos_in_session}`
- `item.reveal` `{exposure_id, item_id, token_idx, what: reading|tone|meaning|translation, latency_ms, auto?}` — `auto: true` when the app showed the translation after the audio finished (not a learner request)
- `item.audio` `{exposure_id, scope: sentence|char|word, rate: normal|slow, nth, available, auto?}` — `auto: true` when the app played it on open (not counted in `audio_plays`)
- `item.grade` `{exposure_id, grade: again|hard|good|easy, explicit: bool, latency_ms}`
- `item.check` `{exposure_id, read_ms, revealed, via: listen|mic}` — read, then check (2026-11-17): the learner finished reading a sentence with tested characters and asked to hear it (or read it aloud); every reading is shown from here
- `item.done` `{exposure_id, dwell_ms, active_ms, reveals, missed, checked, audio_plays, skipped}` — `missed`: characters marked wrong after the check
- `review.applied` `{item_id, grade, signal: noReveal|reveal|missed|slow|introduced|explicit, s_before}` — one per item affected; this is what replay consumes. `missed`: marked wrong after the check (graded again, like a reveal)
- `error.diagnosed` `{item_id, kind: tone|sibling|polyphone|cross_lang|lookalike, given?, expected}`

### Reading and input
- `reader.open` `{source: library|paste|ocr|clipboard|srt, chars, unknown_ratio}`
- `reader.lookup` `{char, reading_shown, in_sentence?}` — long-press on a character; `words_found` = dictionary words covering it
- `word.save` `{text, lang, reading?, en?, sentence_id?, context?, context_en?}` — added to "My words" (replayed into `WordBook`; a later save of the same `lang:text` replaces it)
- `word.remove` `{text, lang}`
- `word.flag` `{text, lang, reason: read|say, reading?, sentence_id?, context?, context_en?}` — automatic: you revealed a reading you were meant to read, or read-aloud heard the word wrong; it joins the practice list
- `word.practice` `{text, lang, ok}` — one practice of a flagged word (mic-graded, or self-graded without a mic); two `ok` in a row take it off the list
- `listen.answer` `{id, correct, slow}` — newcomer Listen drill: a reply (`rep:<situation>:<zh>`, content/practice.yaml) was heard and its meaning picked; `slow`: the slow play was used. Missed ones come first next time (`engine/practice_log.dart`)
- `tone.answer` `{set, played, picked, correct, voice}` — tone ear training: which member of a tone set played and which was picked; `voice`: the round, which picks the speaker
- `frame.say` `{id, ok, via: mic|self}` — Build a sentence: a frame sentence (`frame:<frame>:<word>`) said, graded by the learner (after the mic check, if any)
- `picture.rate` `{card_id, kind: photo|icon, ref, good}` — Settings → Developer → Rate pictures (owner's tool): does the picture fit the word? A Bad picture stops showing on the device; `duk pictures ratings` applies them to content/pictures.yaml
- `challenge.done` `{id}` — "I did it" on a real-world challenge; done ones stop showing (no streaks)
- `plan.step` `{step: review|learn|weak|words|cards, day}` — a step of Today's plan was finished
- `conv.choice` `{exposure_id, sentence_id, correct, tries}` — the learner picked a line on their turn in a conversation (visual-novel mode); wrong options are lines from other conversations of the topic
- `reader.scrollback` `{from_idx, to_idx}`
- `speech.attempt` `{exposure_id, engine, expected, heard, per_token: [{ok, tone_ok}], score}`
- `typing.attempt` `{expected, typed, ms}`

### Content and audio feedback
- `content.flag` `{target_id, problem: wrong_reading|wrong_audio|unnatural|wrong_fact, note?}`
- `content.approve` `{target_id}`
- `user.card_add` `{card}` / `user.sentence_add` `{sentence}` (full object so it syncs)

### System
- `settings.change` `{key, from, to}` — includes `speaker` and `share_data`
- `onboarding.done` `{speaker, help_shift, goal, share}` — first-run answers
- `experiment.assigned` `{arms: {experiment_id: arm}}` — logged when the install's set of A/B arms changes (docs/TELEMETRY.md)
- `app.crash` — reserved; crashes go to the Worker's crash endpoint, not the event log
- `goal.set` `{kind: trip|topic, target, until}`
- `notif.sent` `{notif_id, kind, planned_for}` / `notif.action` `{notif_id, action: open|dismiss|ignore}`
- `bandit.assign` `{arm_set, arm, params}` / `bandit.reward` `{arm_set, arm, reward, window}`
- `model.load` `{name, version}`
- `sync.done` `{pushed, pulled, ms}` / `sync.error` `{code}`
- `update.check` `{channel, found?}` / `update.apply` `{kind: app|content, from, to}`
- `placement.result` `{lang, estimate, items_seeded}`
- `state.rebuild` `{events, ms}`

## Rules

1. Log first, derive second. UI never writes `item_state` directly.
2. Latencies use `mono_ms` and exclude idle spans.
3. Events are immutable. Corrections are new events (`review.undo {exposure_id}`).
4. Unknown types and unknown fields must be ignored by readers, not rejected (forward compatibility across devices on different app versions).
5. `schema_v` increments only for breaking changes, with an upcaster in `events/upcast.dart` and a replay test.
6. Never log raw pasted/OCR text; log lengths and character IDs only.
7. Location is region-level only and opt-in.

## Derived metrics (computed, not logged)

Best study hours; fatigue curve; ideal session length; retention by device and by time of day; latency-as-confidence per item; drop-off points; notification effectiveness; coverage over time; retained items per active minute.

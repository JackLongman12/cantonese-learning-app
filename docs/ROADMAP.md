# Roadmap

Work top to bottom. Do not start a phase until the previous phase's "Done when" list is met. Tick boxes as tasks land and keep the **Status** line current.

**Goals (2026-11-16):** first run asks what you want Cantonese for (get around, eat out and shop, daily life, work, make friends, a bit of everything); the path puts those topics first and Today's Learn/Speak draw from them; change it on Today (Goal · Change) or in Settings (engine/goals.dart). Grouped controls: one Listen button (hold for slow), no Skip; one 'Practise my words' in Words.

**Status (2026-11-17, both modes share all content (five tabs; Home differs by level); newcomer mode: situations of essential words, English-first drill, search, understanding replies, tone ear training, sentence frames, a Jyutping guide, real-world challenges, word pictures; Home A/B by level; see CHANGELOG):** DuckLearn is now for beginners (speakers who can't read, and learners); the reader is read first, then Check; opt-in anonymous usage and crash data go to a Cloudflare Worker and `duk telemetry report` says what to change (docs/TELEMETRY.md); two A/B tests run. Before that: Android arm64 is the release target. 18 topics (each ≥ 100 sentences, 5+ conversations), 18 stories, 1,077 flashcards, word variants, a voice picker in every exercise (phone voice by default). Audio ships as Opus; conversation pictures download on first launch. Content is LLM-drafted and accepted by the owner as-is (2026-11-16). Next open work: 1.3/1.4 planner polish, 1.6 placement test, 2.8 error drills. History: `docs/CHANGELOG.md`.

## Product principle: serve the unmet need, not a Duolingo copy

The owner was explicit: this must fill a gap the market leaves, not imitate gamified apps. Every
feature is judged against these gaps; anything that is only engagement mechanics is out.

0. **Newcomers first** (owner, 2026-11-17, later the same day): the main audience is people
   new to Hong Kong and Macau who want to get their point across. They learn **essential
   words and short chunks**, not whole sentences (situations in `content/situations.yaml`,
   drilled English first: see the English, say it, hear it). Perfection comes later; most
   users should outgrow the app and move to fuller courses. Onboarding's level picks the
   mode: new to Cantonese or knows a little → newcomer mode (Home B: search, today's drill,
   situations); speaks it but can't read → the reading app (Home A: continue your topic,
   flashcards out loud). The points below describe Home A's reading side.
1. **Beginners at reading Cantonese** (since 2026-11-17; the owner outgrew the content).
   Two kinds, asked in onboarding: speakers who can't read (the original gap: they know the
   words by ear, so the app teaches only character → sound, and hearing a line is the answer
   key) and people learning the language too (meanings and Jyutping stay on longer). Every
   sentence with characters being tested is read first, then checked by ear.
2. **Help that fades per character.** Jyutping disappears character by character as each one is
   learned, so real text gets readable gradually instead of "pinyin on / pinyin off".
3. **Real Macau and Hong Kong language.** Spoken written-Cantonese (佢哋、唔係) and standard
   written Chinese (signs, forms, news) are both taught; content is local situations, not
   textbook dialogues.
4. **Read anything you meet.** Paste or share any menu, sign, form or chat and get Jyutping over
   only the characters *you* don't know yet; what you look up feeds back into what you study.
   Built-in OCR was removed (2026-11-15): Lens / Live Text / Pleco recognise text better, so
   DuckLearn receives text from them instead (Android Share and text-selection menu).
5. **Cantonese only.** Mandarin was dropped (owner, 2026-11-15): other apps already serve it,
   and every hour spent there is an hour not spent on the Cantonese gap.

The duck mascot is branding and gentle feedback only: no XP, no hearts, no streak guilt.
No streaks or per-day attendance displays of any kind (owner, 2026-11-16): they push quick, poor
sessions to keep a record going. Progress is shown as outcomes (new characters, sentences read, weak spots).
No pressure mechanics at all: no session-length quota (sessions size themselves from how you practise,
`engine/adaptive.dart`, and "Keep going" removes any cap), stopping early still counts, reminders only
nudge on days with no reading and never guilt-trip.

## Pronunciation accuracy (built 2026-11-15: sound check on device; tones by ear)

- **Read aloud** button (mic, key R) in the reader. Recognition runs on the device with
  SenseVoice (sherpa-onnx, int8, 240 MB, downloaded once on first use, nothing leaves the
  device). Output is compared by **Jyutping, not characters** (`engine/pronunciation.dart`),
  so homophones the recogniser writes (比/俾, 翻/返) don't count as errors. Lazy sounds
  (n/l, dropped ng-, gw/g before o) are accepted.
- Per character: ok / tone / wrong / missed, shown as coloured underlines; errors count as
  reading lapses. `speech.attempt` is logged with readings only.
- **Measured limits.** Recognition catches wrong *sounds* reliably (integration test:
  睇 tai2 for 買 maai5 is flagged). It does **not** catch a tone slip that forms another real
  word: a 賣 maai6 recording was transcribed as 買. A pitch-contour tone classifier
  (pYIN + per-syllable timestamps, trained on 2,069 syllables of app audio) reached only 47%
  tone accuracy and couldn't separate 買/賣, so it was not shipped: false "wrong tone"
  marks would teach the learner to distrust the app.
- **Tones are therefore checked by ear:** after reading aloud, "Play mine" and "Native"
  play the two back to back. The learner is a native listener; this is the reliable judge.
- Whisper (large-v3-turbo) was also tried and rejected: it rewrites Cantonese into Mandarin
  wording (我喺屋企返工 -> 我在家上班).
- Next, if wanted: a dedicated tone model trained on real (not TTS) Cantonese speech.

## Duck ideas (branding; build only where it supports learning)

- Mascot grows with characters known well: 蛋 egg → 小鴨 duckling → 鴨 duck → 天鵝 swan (built).
- Session summary cheers; nothing-due state sleeps (built).
- Later: duck footprints across a calendar for days read (no penalties for missed days); a
  soft quack when a session ends (setting, off by default); duck poses in empty states.

## Needed from the owner (ask once, early; do not block on optional ones)

| Item | Needed for | Blocking? |
|---|---|---|
| ~~GitHub repo name, and public or private~~ | done: public `cantonese-learning-app` (releases there) | — |
| ~~Azure Speech key + region~~ | not needed: phone voice by default, edge-tts recorded fallback | — |
| Anthropic API key | sentence drafting | Phase 1 content (can start with owner-written + corpus sentences) |
| Which Android phone/version; is a Mac available for testing | builds | Phase 2 |
| Google Cloud TTS key (Chirp 3 HD) | an extra voice in the picker, only if wanted | optional |
| Google Cloud project for Drive OAuth | sync | Phase 3 |

## Machine state

See CLAUDE.md "Environment notes" (kept current there). ffmpeg (winget) is needed by `duk bundle` for Opus audio.

---

## Phase 0 — Foundations and proof

Goal: prove the three risky things (readings, audio, ruby rendering) on 20 sentences before building anything wide.

- [x] 0.1 Repo initialised and pushed (public since releases moved there).
- [x] 0.2 Toolchain installed: Flutter, VS 2022 C++ Build Tools, JDK 17, Android SDK. `flutter doctor` clean for Windows and Android.
- [x] 0.3 `pipeline/`: Python project (`uv` or venv, `pyproject.toml`, `ruff`, `pytest`).
- [x] 0.4 `duk fetch`: Unihan and Make Me a Hanzi, hash-locked. (CC-Canto, words.hk, rime-cantonese still to add as a fourth voter and word source.)
- [x] 0.5 `pipeline/duk/annotate.py`: text → tokens → Jyutping/Pinyin arrays, polyphone flags, review queue.
- [x] ~~0.6 `content/test_sets/tts_bakeoff.yaml`: 30 sentences (polyphones, particles, Macau/HK place names, numbers, prices). Owner checks them.~~ Replaced (2026-11-16): the owner picks voices by ear in the in-app voice picker.
- [x] ~~0.7 `pipeline/tts_bakeoff.py`: render the set with every available engine into `build/bakeoff/` plus an HTML page for blind rating. **Owner picks voices.**~~ Replaced by the voice picker (Settings and every exercise's top bar).
- [x] 0.8 Flutter skeleton in `app/` with the folder layout from DESIGN §4.1; bundled Noto HK/SC fonts; a `RubyText` widget with golden tests (long readings, line wrap, punctuation, mixed Latin).
- [x] 0.9 Vertical slice (done: the owner uses release builds on the phone, signed with the release key): content → `content.db` → reader with ruby and audio. Runs on Windows: launched, and the integration test plays audio for real (switched from `just_audio`, which has no Windows backend, to `audioplayers`). Android: `flutter build apk --release` builds a 72.5 MB APK; **not yet installed on the owner's phone**. It is signed with the machine's debug key (`%USERPROFILE%\.android\debug.keystore`); back that file up or replace it with a release key before relying on in-place updates (ROADMAP 2.6).

**Done when:** owner reads the 20 sentences in the app on phone and PC, readings are correct, audio is acceptable, voices are chosen.

## Phase 1 — Daily-usable core

- [x] 1.1 `events/`: envelope, logger, idle detection, JSONL export, replay → `item_state`. Replay test in CI.
- [x] 1.2 `engine/learner_model`: FSRS per item, implicit signals → grades, scaffold level from state.
- [ ] 1.3 `engine/planner`: scoring and greedy session builder done, reasons recorded in `item.shown`, unlock value from everyday frequency (HKCanCor, 2026-11-17). Still to do: family size, fatigue shaping, on-screen "why this?" overlay.
- [ ] 1.4 Simulated learner + tests: coverage rises, due load stays bounded, no sentence starvation.
- [x] 1.5 Reader UI: fading ruby, tap-to-reveal, sentence audio (normal/slow), meaning toggle; tapped characters and words speak; Review is cross-topic; Jyutping help setting.
- [ ] 1.6 Placement test (yue first).
- [x] 1.7 Pipeline: validate → annotate → build → TTS → bundle (Opus) works; `tool/release.sh` runs it all. Dropped: ASR back-check, TTS-only substitutions and Azure (the phone voice is the default).
- [x] 1.8 Content: **≥ 100 sentences per topic** (owner requirement), with variations grouped by `pattern`. See the topic table below.
### Topic table (each needs ≥ 100 sentences)

| Topic | File | Sentences | Notes |
|---|---|---|---|
| Getting around Macau (bus, taxi, LRT, border, directions) | `scenarios/macau/getting-around.yaml` | 100 | |
| Eating out and paying (茶餐廳, Macanese food, bills, money) | `scenarios/macau/food-and-money.yaml` | 100 | |
| Shopping and markets (supermarket, wet market, pharmacy) | `scenarios/macau/shopping.yaml` | 100 | |
| Home and renting (landlord, repairs, utilities, deliveries) | `scenarios/macau/home.yaml` | 100 | |
| Health (clinic, hospital, pharmacy, symptoms) | `scenarios/macau/health.yaml` | 100 | |
| Government and paperwork (ID, forms, bank, post office) | `scenarios/macau/government-and-paperwork.yaml` | 100 | |
| Work and study | `scenarios/macau/work-and-study.yaml` | 100 | |
| Friends, family, small talk and slang | `scenarios/macau/friends-and-chat.yaml` | 100 | |
| Phone, messaging and written Cantonese (chat style) | `scenarios/macau/phone-and-messaging.yaml` | 100 | |
| Weather and emergencies (typhoon, rainstorm, police, fire) | `scenarios/macau/weather-and-emergencies.yaml` | 100 | |
| Signs and notices (written register) | `scenarios/macau/signs-and-notices.yaml` | 100 | |
| Casinos, hotels and tourism spots in Macau | `scenarios/macau/hotels-and-sightseeing.yaml` | 100 | |
| Getting around Hong Kong (MTR, minibus, Octopus, tram, ferry, taxi, border) | `scenarios/hk/getting-around-hk.yaml` + 5 conversations | 100 | |
| Hong Kong daily life (commute, 茶餐廳, buildings, malls, errands, weekends, queues) | `scenarios/hk/hk-daily-life.yaml` + 5 conversations + 1 advanced | 120 | |
| Same thing, different words (word variants; was "Many ways to say it") | `scenarios/hk/many-ways-to-say-it.yaml` + 5 conversations | 103 | groups in `variants.yaml` |
| Cantonese food (yum cha, siu mei, cha chaan teng, congee, tong sui, Macau snacks, tastes) | `scenarios/hk/cantonese-food.yaml` + 5 conversations | 100 | |
| Numbers, time, dates and prices | `scenarios/macau/numbers-and-time.yaml` | 100 | |
| Swearing and rude Cantonese (粗口: the big five, insults, euphemisms, DLLM/on9, when not to) — owner's request; no group slurs; 撚 = lan2 per CC-Canto | `scenarios/hk/swearing.yaml` + 8 conversations + 1 advanced | 200 | |

Write one topic at a time: draft → `duk build` → check the new review-queue items and print
readings by eye (pin wrong ones with `fix_yue`) → `duk tts` → `duk bundle`.

- [x] ~~1.9 In-app "approve / flag" action~~ Dropped (owner, 2026-11-16): LLM content is accepted as-is. `build/review_queue.md` still lists readings the sources disagree on.
- [ ] 1.10 Dev menu: fake clock, rebuild state, view event log, reset item.

**Done when:** owner uses it daily for a week; ruby visibly fades on mastered characters; rebuild-from-log reproduces state exactly.

## Phase 2 — Breadth: cards, places, updates

- [ ] 2.1 Place import from open data (Macau first), `content/places/`, special-reading overrides. (Names now come from OSM for decks; coordinates/districts not yet.)
- [x] 2.2 Flashcards (first version): decks of real names from OpenStreetMap (Macau streets with Portuguese, Macau LRT, HK MTR, HK streets with English). Each card is its own FSRS item (`card:<deck>:<zh>`) and also grades its characters. Each visit is a fresh shuffled set (2026-11-16): up to 8 new cards picked at random from the next unseen ones, the rest your weakest seen cards (lowest recall first), and cards from the set you just did are skipped unless nothing else is left, so a deck never says "nothing due". Street-ending hints ("大馬路 is usually Avenida") are counted from the map data. Still to do: templates beyond read-the-sign (listening, Portuguese → Chinese), menu/sign decks.
- [ ] 2.3 Map mode with offline tiles for Macau and HK.
- [ ] 2.4 Scenario browser and trip mode (`goal.set`).
- [x] ~~2.5 Mandarin track~~ **Dropped by the owner (2026-11-15):** Mandarin reading is well served by other apps; DuckLearn is Cantonese only. Mandarin content, Pinyin display, the language switch, Noto Sans SC and the pypinyin/jieba dependencies were removed.
- [x] 2.6 Releases: `tool/release.sh` builds signed Android APKs + Windows zip on the dev PC and publishes a GitHub Release (CI signing was not set up: the key stays on the PC). macOS later.
- [x] 2.7 Auto-update on launch (Android + Windows), from public GitHub Releases. Content packs separate from the app: not yet.
- [ ] 2.8 Error diagnosis and targeted drills (DESIGN §2.6).
- [ ] 2.9 Conversation branches written by hand: on your turn, several acceptable answers (not just one right line and two from other conversations), each leading to its own reply.
- [ ] 2.10 Character expressions (happy, confused, annoyed) per line in the visual-novel stage.

**Done when:** a push to main reaches the phone as an update without a cable; Macau place deck usable on a walk.

## Phase 3 — Sync and dashboard

- [ ] 3.1 Google Drive appData sync, per-device logs, merge, weekly backups; Windows loopback OAuth.
- [ ] 3.2 Dashboard: coverage, retained items per minute, forecast, study-time heatmap.
- [ ] 3.6 Remove the temporary Settings → Developer tools (Replay onboarding, Restore setup; Rate pictures already went in b2081) before a public launch (owner's test tools, 2026-11-17).
- [x] 3.4 Opt-in anonymous usage data and crash reports (Cloudflare Worker + D1), A/B experiments per install, `duk telemetry pull/report` (2026-11-17, docs/TELEMETRY.md).
- [ ] 3.5 Act on the first report once 30+ installs share data: end or extend each experiment, fix the hardest characters and sentences, the top crash.
- [x] ~~3.3 Crash/error log capture.~~ Dropped (owner, 2026-11-16): few users; they report problems directly.

**Done when:** progress made on the phone appears on the PC and survives a reinstall.

## Phase 4 — Real-world text

- [x] 4.1 Paste reader (Read anything) with the phone voice; Android Share and text-selection entry.
- [x] ~~4.2 OCR~~ Removed (owner, 2026-11-15): Lens / Live Text share text in instead.
- [ ] 4.3 Personal frequency list feeds `unlock_value`; "add to deck" from reader.
- [x] 4.4 Read-aloud check (SenseVoice on device), lazy-sound tolerance. Tones by ear (see Pronunciation accuracy).

## Phase 5 — Adaptive models (needs 1–2 months of logs)

- [ ] 5.1 `ml/`: features from events, recall model, ONNX export, offline evaluation against plain FSRS.
- [ ] 5.2 On-device inference with safety limits; ship only if it beats FSRS on held-out data.
- [ ] 5.3 Bandit over pacing parameters; smart notification timing.

## Phase 6 — Extras

- [ ] 6.x Your own photo for a word (owner's idea, 2026-11-17): personal or funny pictures are remembered best. Kept on the device only, never uploaded.

Claude "explain this" and roleplay; local-LLM weekly report; desktop clipboard hotkey reader; Android widget; `.srt` import; Jyutping typing practice; LLM on-demand sentence generation for planner gaps; browser extension; Anki export.

---

## Test and quality bar (every phase)

- `engine/` and `events/` are pure Dart with unit tests; planner changes need a simulation run.
- Pipeline has `pytest` tests with small fixture dictionaries (no network in tests).
- Golden tests for `RubyText`.
- CI runs `flutter analyze`, `flutter test`, `ruff`, `pytest` on every push.
- No phase is done until the owner has used the result on a real device.

## Friction (2026-11-15)

Built: Android Share and text-selection "Read in DuckLearn"; clipboard prompt on open/resume
(Android: asks only whether text exists, reads on tap, so no system clipboard notice);
remembers language and last topic ("Continue" card); session length 5/15/30; swipe left for
next.
Also built: resume a half-finished session; Android home-screen widget (characters to review);
daily reminder at the learner's usual study time (learned from session starts, inexact, off by
default); Settings screen (language, Jyutping help more/normal/less, text size, session length,
read-along, clipboard prompt, reminder, speech model, updates, licences).
Paused by the owner (2026-11-15): Windows releases and the Windows global hotkey; arm32 builds
dropped (arm64 only).

## Learning techniques (2026-11-15)

Built: graded stories (18 Cantonese in content/stories/), sorted by
how much the learner can already read with a "Good next read"; read-along (audio plays as each
line appears); shadowing (native line, then recording starts); sound families (phonetic
components from Make Me a Hanzi, with same-sound / tone-only / different marks); spoken vs
written Cantonese reference; resume a half-finished session from home.

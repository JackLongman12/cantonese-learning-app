# Roadmap

Work top to bottom. Do not start a phase until the previous phase's "Done when" list is met. Tick boxes as tasks land and keep the **Status** line current.

**Goals (2026-11-16):** first run asks what you want Cantonese for (get around, eat out and shop, daily life, work, make friends, a bit of everything); the path puts those topics first and Today's Learn/Speak draw from them; change it on Today (Goal · Change) or in Settings (engine/goals.dart). Grouped controls: one Listen button (hold for slow), no Skip; one 'Practise my words' in Words.

**Status (2026-11-16, voice picker):** A voice button in the top bar of every exercise (reading, Speak, cards, practice words, sound families, skills, Read anything) opens the same picker mid-practice. Settings → Sentence voice: the phone's default voice stays the default; any other Cantonese voice on the phone (online ones first) or the recorded voice can be picked, each with a sample. Before (word variants): 34 groups of everyday words for the same thing (content/variants.yaml: 白車/救護車/救傷車/十字車, 𨋢/電梯/升降機, 雪櫃/冰箱, 而家/依家/宜家...); tapping any of them shows the whole group with readings and when each is used; new topic "Many ways to say it" (103 sentences, LLM-drafted, unreviewed). Before (phone voice): Sentences, cards and words now play in the phone's own Cantonese voice (the one a tapped word uses), which says the tones people use; the recorded voice is a Settings switch and the fallback without a Cantonese voice. Before (spoken tones): Readings now follow how Cantonese is spoken: HKCanCor speech counts and rime-cantonese words vote alongside ToJyutping and pycantonese, and the formal Unihan reading no longer breaks ties in sentences (澳門 ou3 mun2, 會 wui5, 坐 co5, 錢 cin2, 平靚正 peng4 leng3 zeng3; 110 sentence readings and 8 card readings changed). Reminders are smart by default (learned weekday and weekend times, skip days you read, mention reviews ready), with an optional fixed time. Next stops a playing comparison (your attempt, then the native) at once. Home has no scroll bounce. Before (variety + progress): Sessions vary: reading, speaking and flashcards skip what you saw recently and shuffle near-ties, while due and weak items still lead. Progress tab: a one-line summary of the week, characters met/learned/readable with a weekly bar chart, this week vs last week (new characters, read without help, sounds said right, sentences read) with the change, "What to work on" with a button for each (weak characters, sound mix-ups, words, due cards), and your first week vs now. Review is one screen (due cards stay on the Cards tile), so Back leaves it in one press. Before (redesign): Warm terracotta look (cream, oat tiles, one terracotta accent, sage for done). Tabs: Home, Topics, Stories, Progress. Home = numbered plan with egg markers (Review, Learn, Speak), one Start button, and six tools (Topics, Stories, Cards, Speak, My words, Skills). × in any exercise goes Home; every finish screen offers Up next, the same six tools, Keep going and Home. Subtle characters (ui/critters.dart): a chick with moods (innocent, happy, proud with stars, confused on a miss, curious on a new topic, sleepy when done), a mama duck walking on the Start button (a duckling joins per finished step, reset daily, never counted), a duckling riding progress bars; anything moving faces its direction. Tap a word for sound, reading and meaning (no holding); Listen alternates normal and slower; audio never plays while recording. American English throughout. Before: Speaking: the mic starts only when tapped (automatic listening was removed by the owner, 2026-11-16: too hectic, and it kept running after leaving); leaving a screen stops any recording. Sentences still open silently (try first, audio after). Misses below 70% play your attempt then the native audio (temp file, deleted). Speak drill (rapid, back-to-back). Today: Review (due + weak + flagged words + due cards) / Learn / Speak, with weekly metrics as numbers. Sessions adapt (no session length), Keep going, early exit counts. Gentle reminders skip days you read. Sounds only on Next and finish. Level counts learned characters. Before: Today is a daily plan (review, next topic on the path, flagged words, due cards). Practice tab: reading skills (sound families, spoken vs written, radicals, particles, measure words) and flashcards. Topics have filter chips. 14 stories (8 long daily-life ones). Pictures: emoji chosen from each sentence's meaning (engine/pictures.dart); food cards use Commons photos. Earlier: App is named **DuckLearn**; **Cantonese only** (Mandarin dropped). Tabs: Today (start button above the tabs, reading level 1-10), Topics (two-column grid in beginner-path order, 'Up next'), Cards (food with photos, streets, stations; mic check; missed cards return), Stories, Words (auto-flagged words to practise by reading aloud, saved words, lookup, paste reader). First-run setup for beginners. 15 advanced conversations (level 3). App size cut by ~48 MB (one audio clip per line, slim dictionary, subset font). Words are underlined as whole words (context segmentation checked against the dictionary); conversations play as a visual novel (Irasutoya characters, pick your line on your turn, backlog); food deck of 169 dishes with Commons photos; 16 topics incl. swearing, Cantonese food and Getting around Hong Kong; Android arm64 is the release target (Windows releases paused, macOS later). Home has bottom tabs: Today, Topics (with flashcard decks of real Macau/HK names from OpenStreetMap), Stories, Words ("My words": long-press any character for dictionary meanings from CC-Canto/CC-CEDICT and save it with its sentence), Read (paste/share). Thirteen 100-sentence Macau topics, 65 conversations, 6 stories. Sentences auto-play on open; read-aloud stops when you finish and shows a sound-accuracy percent; soft synthesised UI sounds; settings screen; daily reminder; home-screen widget; auto-update from public GitHub Releases. HK topics and owner review of LLM-written content are the biggest content gaps.

## Product principle: serve the unmet need, not a Duolingo copy

The owner was explicit: this must fill a gap the market leaves, not imitate gamified apps. Every
feature is judged against these gaps; anything that is only engagement mechanics is out.

1. **Heritage speakers who can't read.** Existing apps teach Cantonese as a foreign language
   (vocabulary + speaking). This learner already knows the words by ear; the only missing link
   is character → sound. The app teaches exactly that link and nothing they already know.
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
| GitHub repo name, and public or private | CI, auto-update | Phase 0 (private repo ⇒ separate public releases repo) |
| Azure Speech key + region | TTS | Phase 0 bake-off |
| Anthropic API key | sentence drafting | Phase 1 content (can start with owner-written + corpus sentences) |
| Which Android phone/version; is a Mac available for testing | builds | Phase 2 |
| Google/ElevenLabs keys | bake-off extras | optional |
| Google Cloud project for Drive OAuth | sync | Phase 3 |

## Machine state (checked 2026-11-15)

Windows 11, RTX 4060 Laptop 8 GB, Python 3.11.9, Git, Node, GitHub CLI (logged in), Flutter 3.50 at `C:\src\flutter`. **Missing:** Visual Studio C++ desktop workload (needed to build/run on Windows), Android SDK + JDK 17 (needed for the phone; only Java 8 present), Ollama. macOS builds are CI-only.

---

## Phase 0 — Foundations and proof

Goal: prove the three risky things (readings, audio, ruby rendering) on 20 sentences before building anything wide.

- [x] 0.1 Repo initialised and pushed (private).
- [x] 0.2 Toolchain installed: Flutter, VS 2022 C++ Build Tools, JDK 17, Android SDK. `flutter doctor` clean for Windows and Android.
- [x] 0.3 `pipeline/`: Python project (`uv` or venv, `pyproject.toml`, `ruff`, `pytest`).
- [x] 0.4 `duk fetch`: Unihan and Make Me a Hanzi, hash-locked. (CC-Canto, words.hk, rime-cantonese still to add as a fourth voter and word source.)
- [x] 0.5 `pipeline/duk/annotate.py`: text → tokens → Jyutping/Pinyin arrays, polyphone flags, review queue.
- [ ] 0.6 `content/test_sets/tts_bakeoff.yaml`: 30 sentences (polyphones, particles, Macau/HK place names, numbers, prices). Owner checks them.
- [ ] 0.7 `pipeline/tts_bakeoff.py`: render the set with every available engine into `build/bakeoff/` plus an HTML page for blind rating. **Owner picks voices.**
- [x] 0.8 Flutter skeleton in `app/` with the folder layout from DESIGN §4.1; bundled Noto HK/SC fonts; a `RubyText` widget with golden tests (long readings, line wrap, punctuation, mixed Latin).
- [ ] 0.9 Vertical slice: content → `content.db` → reader with ruby and audio. Runs on Windows: launched, and the integration test plays audio for real (switched from `just_audio`, which has no Windows backend, to `audioplayers`). Android: `flutter build apk --release` builds a 72.5 MB APK; **not yet installed on the owner's phone**. It is signed with the machine's debug key (`%USERPROFILE%\.android\debug.keystore`); back that file up or replace it with a release key before relying on in-place updates (ROADMAP 2.6).

**Done when:** owner reads the 20 sentences in the app on phone and PC, readings are correct, audio is acceptable, voices are chosen.

## Phase 1 — Daily-usable core

- [x] 1.1 `events/`: envelope, logger, idle detection, JSONL export, replay → `item_state`. Replay test in CI.
- [x] 1.2 `engine/learner_model`: FSRS per item, implicit signals → grades, scaffold level from state.
- [ ] 1.3 `engine/planner`: scoring and greedy session builder done, reasons recorded in `item.shown`. Still to do: unlock value from frequency/family size, fatigue shaping, on-screen "why this?" overlay.
- [ ] 1.4 Simulated learner + tests: coverage rises, due load stays bounded, no sentence starvation.
- [ ] 1.5 Reader UI: fading ruby, tap-to-reveal, sentence audio (normal/slow), meaning toggle, skip — done. Still to do: per-character audio, a cross-topic review session, settings (help shift).
- [ ] 1.6 Placement test (yue first).
- [ ] 1.7 Pipeline: validate → annotate → build → TTS → bundle works. Still to do: ASR back-check of audio, TTS-only substitutions, Azure engine, one-command wrapper.
- [ ] 1.8 Content: **≥ 100 sentences per topic** (owner requirement), with variations grouped by `pattern`. See the topic table below.
### Topic table (each needs ≥ 100 sentences)

| Topic | File | Sentences | Owner-reviewed |
|---|---|---|---|
| Getting around Macau (bus, taxi, LRT, border, directions) | `scenarios/macau/getting-around.yaml` | 100 | 0 |
| Eating out and paying (茶餐廳, Macanese food, bills, money) | `scenarios/macau/food-and-money.yaml` | 100 | 0 |
| Shopping and markets (supermarket, wet market, pharmacy) | `scenarios/macau/shopping.yaml` | 100 | 0 |
| Home and renting (landlord, repairs, utilities, deliveries) | `scenarios/macau/home.yaml` | 100 | 0 |
| Health (clinic, hospital, pharmacy, symptoms) | `scenarios/macau/health.yaml` | 100 | 0 |
| Government and paperwork (ID, forms, bank, post office) | `scenarios/macau/government-and-paperwork.yaml` | 100 | 0 |
| Work and study | `scenarios/macau/work-and-study.yaml` | 100 | 0 |
| Friends, family, small talk and slang | `scenarios/macau/friends-and-chat.yaml` | 100 | 0 |
| Phone, messaging and written Cantonese (chat style) | `scenarios/macau/phone-and-messaging.yaml` | 100 | 0 |
| Weather and emergencies (typhoon, rainstorm, police, fire) | `scenarios/macau/weather-and-emergencies.yaml` | 100 | 0 |
| Signs and notices (written register) | `scenarios/macau/signs-and-notices.yaml` | 100 | 0 |
| Casinos, hotels and tourism spots in Macau | `scenarios/macau/hotels-and-sightseeing.yaml` | 100 | 0 |
| Getting around Hong Kong (MTR, minibus, Octopus, tram, ferry, taxi, border) | `scenarios/hk/getting-around-hk.yaml` + 5 conversations | 100 | 0 |
| Hong Kong daily life (茶餐廳, shopping, districts) | to write | 0 | 0 |
| Cantonese food (yum cha, siu mei, cha chaan teng, congee, tong sui, Macau snacks, tastes) | `scenarios/hk/cantonese-food.yaml` + 5 conversations | 100 | 0 |
| Numbers, time, dates and prices | `scenarios/macau/numbers-and-time.yaml` | 100 | 0 |
| Swearing and rude Cantonese (粗口: the big five, insults, euphemisms, DLLM/on9, when not to) — owner's request; no group slurs; 撚 = lan2 per CC-Canto | `scenarios/hk/swearing.yaml` + 5 conversations | 100 | 0 |

Write one topic at a time: draft → `duk build` → clear the review queue → print readings and
check them by eye → `duk tts` → `duk bundle`. The owner then confirms wording by ear.

- [ ] 1.9 Content review tooling: `build/review_queue.md` and an in-app "approve / flag" action.
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
- [ ] 3.3 Crash/error log capture.

**Done when:** progress made on the phone appears on the PC and survives a reinstall.

## Phase 4 — Real-world text

- [ ] 4.1 Paste reader with live TTS and cache.
- [ ] 4.2 OCR: ML Kit (Android), Windows OCR / PaddleOCR, Apple Vision (macOS).
- [ ] 4.3 Personal frequency list feeds `unlock_value`; "add to deck" from reader.
- [ ] 4.4 Read-aloud check (ASR), lazy-sound tolerance.

## Phase 5 — Adaptive models (needs 1–2 months of logs)

- [ ] 5.1 `ml/`: features from events, recall model, ONNX export, offline evaluation against plain FSRS.
- [ ] 5.2 On-device inference with safety limits; ship only if it beats FSRS on held-out data.
- [ ] 5.3 Bandit over pacing parameters; smart notification timing.

## Phase 6 — Extras

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
next; one "drafts" note per topic instead of a Draft tag on every sentence.
Also built: resume a half-finished session; Android home-screen widget (characters to review);
daily reminder at the learner's usual study time (learned from session starts, inexact, off by
default); Settings screen (language, Jyutping help more/normal/less, text size, session length,
read-along, clipboard prompt, reminder, speech model, updates, licences).
Paused by the owner (2026-11-15): Windows releases and the Windows global hotkey; arm32 builds
dropped (arm64 only).

## Learning techniques (2026-11-15)

Built: graded stories (6 Cantonese; content/stories/; the 2 Mandarin retellings were removed with the Mandarin track), sorted by
how much the learner can already read with a "Good next read"; read-along (audio plays as each
line appears); shadowing (native line, then recording starts); sound families (phonetic
components from Make Me a Hanzi, with same-sound / tone-only / different marks); spoken vs
written Cantonese reference; resume a half-finished session from home.

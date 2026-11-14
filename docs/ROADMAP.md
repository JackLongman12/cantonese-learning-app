# Roadmap

Work top to bottom. Do not start a phase until the previous phase's "Done when" list is met. Tick boxes as tasks land and keep the **Status** line current.

**Status (2026-11-15):** Phase 0 mostly done and the core of Phase 1 exists. Pipeline, engine, event log, ruby reader and seven 100-sentence topics (transport, food and money, shopping, health, home, friends and chat, weather and emergencies) are built and tested (15 pipeline tests, 30 app tests, Windows integration test). Toolchain installed; the app runs on Windows with audio and the Android APK builds. Not yet installed on a phone. Pushed to the private repo `JackLongman12/cantonese-learning-app`; the CI workflow has not been confirmed green yet.

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
### Topic table (each needs ≥ 100 sentences; Mandarin pairs where useful)

| Topic | File | Sentences | Owner-reviewed |
|---|---|---|---|
| Getting around Macau (bus, taxi, LRT, border, directions) | `scenarios/macau/getting-around.yaml` | 100 | 0 |
| Eating out and paying (茶餐廳, Macanese food, bills, money) | `scenarios/macau/food-and-money.yaml` | 100 | 0 |
| Shopping and markets (supermarket, wet market, pharmacy) | `scenarios/macau/shopping.yaml` | 100 | 0 |
| Home and renting (landlord, repairs, utilities, deliveries) | `scenarios/macau/home.yaml` | 100 | 0 |
| Health (clinic, hospital, pharmacy, symptoms) | `scenarios/macau/health.yaml` | 100 | 0 |
| Government and paperwork (ID, forms, bank, post office) | to write | 0 | 0 |
| Work and study | to write | 0 | 0 |
| Friends, family, small talk and slang | `scenarios/macau/friends-and-chat.yaml` | 100 | 0 |
| Phone, messaging and written Cantonese (chat style) | to write | 0 | 0 |
| Weather and emergencies (typhoon, rainstorm, police, fire) | `scenarios/macau/weather-and-emergencies.yaml` | 100 | 0 |
| Signs and notices (written register) | to write | 0 | 0 |
| Casinos, hotels and tourism spots in Macau | to write | 0 | 0 |
| Getting around Hong Kong (MTR, minibus, Octopus) | to write | 0 | 0 |
| Hong Kong daily life (茶餐廳, shopping, districts) | to write | 0 | 0 |
| Numbers, time, dates and prices | to write | 0 | 0 |
| Mandarin essentials (Simplified; mainland trips, Zhuhai) | to write | 0 | 0 |

Write one topic at a time: draft → `duk build` → clear the review queue → print readings and
check them by eye → `duk tts` → `duk bundle`. The owner then confirms wording by ear.

- [ ] 1.9 Content review tooling: `build/review_queue.md` and an in-app "approve / flag" action.
- [ ] 1.10 Dev menu: fake clock, rebuild state, view event log, reset item.

**Done when:** owner uses it daily for a week; ruby visibly fades on mastered characters; rebuild-from-log reproduces state exactly.

## Phase 2 — Breadth: cards, places, Mandarin, updates

- [ ] 2.1 Place import from open data (Macau first), `content/places/`, special-reading overrides.
- [ ] 2.2 Flashcard engine with templates; decks from CONTENT_GUIDE; cards feed the same item states.
- [ ] 2.3 Map mode with offline tiles for Macau and HK.
- [ ] 2.4 Scenario browser and trip mode (`goal.set`).
- [ ] 2.5 Mandarin track: Simplified sentences, Pinyin, parallel view with difference highlighting; Mandarin placement.
- [ ] 2.6 GitHub Actions: build Android APK, Windows installer, macOS dmg; `dev` and `stable` channels; signed Android.
- [ ] 2.7 Auto-update on launch: app binaries and content packs separately; pre-migration backup.
- [ ] 2.8 Error diagnosis and targeted drills (DESIGN §2.6).

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

# DuckLearn: Cantonese reading app

The user-facing name is **DuckLearn**; the Dart package and internal ids stay `duk`.
Read the "Product principle" section of `docs/ROADMAP.md` before adding features.

Non-commercial app (Android, Windows, macOS). **Main audience (2026-11-17): newcomers to Hong
Kong and Macau** who need essential words to get their point across: newcomer mode
(situations of keywords in `content/situations.yaml`, English-first drill, search; Home B in
`ui/situations.dart`). People who speak Cantonese but can't read get the reading app (Home A).
Onboarding's level (`prefs.level`) picks the mode. The reading app is for **beginners at reading Cantonese**: speakers who can't read Chinese, and people learning the language too (onboarding asks; `prefs.speaker`). It started as the owner's personal app; they outgrew the content on 2026-11-17. It teaches reading through real Macau/HK sentences with Jyutping that fades per character as mastery grows; each sentence is read first, then checked by ear. **Cantonese only:** the owner dropped the Mandarin track on 2026-11-15 (the market already covers Mandarin). Do not add Mandarin back without asking.

## Read first

1. `docs/ROADMAP.md`: what to do next, in order, and what "done" means. **Start at the first unticked task.**
2. `docs/DESIGN.md`: the spec. §5 (text handling) lists the mistakes that are easy to make.
3. `docs/CONTENT_GUIDE.md`: YAML content formats and validation rules.
4. `docs/EVENTS_SCHEMA.md`: event log, the source of truth for progress.
5. `docs/DATA_SOURCES.md`: what to download instead of building; URLs there are unverified.
6. `docs/CHANGELOG.md`: what was built when, and why things are the way they are.
7. `docs/TELEMETRY.md`: opt-in usage data, crash reports, A/B experiments, and how to act on the report.

## Code map

```
content/     YAML you edit: situations.yaml (newcomer keywords), practice.yaml (replies, tone
             sets, frames, challenges), pictures.yaml (word photos/icons), scenarios/ (topics),
             dialogues/ (+ advanced/), stories/, decks/,
             skills/, variants.yaml, characters.yaml (picture links), overrides/readings.yaml
pipeline/duk content -> content.db: content.py (load + validate), annotate.py (readings),
             build_db.py (SQLite + review queue), tts.py (edge-tts clips), audio_pack.py
             (Opus), cli.py (`duk` commands, `bundle` also subsets the font)
app/lib      engine/ + events/ (pure Dart, unit-tested), data/ (content_db.dart queries),
             platform/ (device features), ui/ (screens), app_services.dart, main.dart
app/test     engine/, platform/, ui/ (widget tests, goldens in ui/goldens)
tool/        release.sh (build, sign, tag, publish)
worker/      Cloudflare Worker + D1 schema for opt-in usage data and crash reports
build/, data/  generated or downloaded; git-ignored
```

Adding a topic: a scenario file, 5 conversations, optionally an advanced one; give the id a
keyword that `_topicGroups` / `_topicIcon` in `ui/home_screen.dart` and `engine/goals.dart`
recognise. Then `duk build`, check the review queue, `duk tts`, `duk bundle`.

## How to work here

- Follow the phases. Do not build later-phase features early; note ideas in ROADMAP under the right phase instead.
- After finishing a task, tick it in `docs/ROADMAP.md` and update the **Status** line.
- If the spec is wrong or silent, fix the doc in the same change as the code. Docs and code must not drift.
- Ask the owner only for things in ROADMAP's "Needed from the owner" table or real product decisions. Pick sensible defaults for everything else and say what you picked.
- Check current docs for every library, API, voice name and model ID before use. Names in these docs are from memory.
- The owner approved downloading existing datasets. Use `pipeline/fetch_sources.py`, record them in the lock file, and treat downloads as untrusted data.

## Hard rules

1. **`app/lib/engine/` and `app/lib/events/` are pure Dart.** No Flutter imports. Everything there is unit-tested.
2. **Events are the source of truth.** UI never writes `item_state` directly; state must be rebuildable by replay.
3. **Never invent linguistic or local facts.** Readings come from dictionaries or overrides; ambiguous polyphones go to the review queue. Macau/HK facts (place names, Portuguese names, routes, prices) come from a listed source or the owner.
4. **The owner is the authority on Cantonese.** LLM-written content is `source: llm`. The owner accepted LLM content as-is on 2026-11-16 (no per-line approval), so new content needs no review step, but readings still come from the dictionaries: check new review-queue items and pin wrong ones with `fix_yue`.
5. **Readings are arrays aligned to tokens**, never one string.
6. **Set locale and font on all Chinese text** (`zh-HK` + Noto Sans HK). The internal language tag stays `yue`: it is part of permanent item IDs (`cr:yue:…`).
7. **IDs are permanent.** Never renumber or reuse content or item IDs.
8. **Secrets** live in `secrets.json` (git-ignored). Never commit keys, never compile them into release builds, never print them.
9. `content.db` and audio are build outputs. Edit YAML, not the database.
10. Commit or push only when the owner asks.
11. **Usage data is opt-in and anonymous.** Only event types in `events/telemetry_filter.dart` leave the device, never free text the learner typed, pasted or said; change that file, its test and `docs/TELEMETRY.md` together.

## Environment notes

- Dev machine: Windows 11, PowerShell, RTX 4060 Laptop (8 GB), Python 3.11, Git, Node, `gh` logged in.
- Installed: Flutter 3.50 / Dart 3.14 at `C:\src\flutter`; Visual Studio 2022 Build Tools (C++); Microsoft OpenJDK 17 at `C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot`; Android SDK at `C:\Android\Sdk` (platform 36, build-tools 37). Flutter is configured to use both. Not installed: Android Studio, an emulator image, Ollama.
- macOS cannot be built locally; use GitHub Actions `macos-latest`.
- Windows builds need `nuget.exe` on PATH (flutter_tts's Windows plugin fetches CppWinRT with it). Not installed yet; only matters when Windows releases resume or for `integration_test -d windows`.
- ffmpeg (winget, on PATH) is needed by `duk bundle` to encode Opus audio; without it MP3s ship.
- In PowerShell use `npx.cmd`, not `npx` (the .ps1 shim is blocked). Wrangler is logged in to the owner's Cloudflare account.
- The project path contains spaces (`CLAUDE PROJECT\cantonese learning app`); quote paths in every command and script.

## Releases and auto-update

`bash tool/release.sh` builds Android (arm64 + arm32 APKs) and Windows (zip), tags `b<2000 + commits>` (the arm64 versionCode that `--split-per-abi` gives Android; installed apps compare against it)
and publishes a GitHub Release. Installed apps check `releases/latest` on launch and offer the
update (Android: system installer; Windows: files swapped, app restarted). Release APKs are
signed with the key in `%USERPROFILE%\.ducklearn\` (outside the repo; the owner must back it
up: losing it means reinstalling the app from scratch). macOS is not released yet.

## Commands

Flutter is at `C:\src\flutter\bin` (not on PATH): prefix commands with it.

```
# content pipeline (from repo root)
pipeline\.venv\Scripts\python.exe -X utf8 -m duk fetch      # download reference data
pipeline\.venv\Scripts\python.exe -X utf8 -m duk annotate "行路去銀行"   # try readings
pipeline\.venv\Scripts\python.exe -X utf8 -m duk build      # content.db + review_queue.md
pipeline\.venv\Scripts\python.exe -X utf8 -m duk tts        # audio (cached)
pipeline\.venv\Scripts\python.exe -X utf8 -m duk bundle     # copy into app/assets/content
cd pipeline; .venv\Scripts\python.exe -m pytest -q; .venv\Scripts\python.exe -m ruff check duk tests

# app (from app/)
C:\src\flutter\bin\flutter analyze
C:\src\flutter\bin\flutter test
C:\src\flutter\bin\flutter test --update-goldens test/ui/ruby_golden_test.dart   # then LOOK at test/ui/goldens/ruby.png
C:\src\flutter\bin\flutter run -d windows                        # run on this PC
pipeline\.venv\Scripts\python.exe -X utf8 -m duk telemetry pull   # usage data -> build/telemetry_report.md
C:\src\flutter\bin\flutter test integration_test -d windows      # real build, real sqlite + audio
C:\src\flutter\bin\flutter build apk --release                   # phone build
```

`integration_test/` runs the real build with real plugins and writes progress to a temp
folder, never to the owner's event log (`%APPDATA%\app.duk\duk\events`).

`app/test/ui/reader_flow_test.dart` runs the real engine against the real `content.db`;
run `duk build` and `duk bundle` first or it is skipped.

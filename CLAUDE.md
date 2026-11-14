# DuckLearn: Cantonese reading app

The user-facing name is **DuckLearn**; the Dart package and internal ids stay `duk`.
Read the "Product principle" section of `docs/ROADMAP.md` before adding features.

Personal, non-commercial app (Android, Windows, macOS) for one user who **speaks Cantonese natively but cannot read Chinese**. It teaches reading through real Macau/HK sentences with Jyutping that fades per character as mastery grows. **Cantonese only:** the owner dropped the Mandarin track on 2026-11-15 (the market already covers Mandarin). Do not add Mandarin back without asking.

## Read first

1. `docs/ROADMAP.md` â€” what to do next, in order, and what "done" means. **Start at the first unticked task.**
2. `docs/DESIGN.md` â€” the spec. Â§5 (text handling) lists the mistakes that are easy to make.
3. `docs/CONTENT_GUIDE.md` â€” YAML content formats and validation rules.
4. `docs/EVENTS_SCHEMA.md` â€” event log, the source of truth for progress.
5. `docs/DATA_SOURCES.md` â€” what to download instead of building; URLs there are unverified.

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
4. **The owner is the authority on Cantonese.** LLM-written content is `source: llm`, `reviewed: false` until they approve it.
5. **Readings are arrays aligned to tokens**, never one string.
6. **Set locale and font on all Chinese text** (`zh-HK` + Noto Sans HK). The internal language tag stays `yue`: it is part of permanent item IDs (`cr:yue:…`).
7. **IDs are permanent.** Never renumber or reuse content or item IDs.
8. **Secrets** live in `secrets.json` (git-ignored). Never commit keys, never compile them into release builds, never print them.
9. `content.db` and audio are build outputs. Edit YAML, not the database.
10. Commit or push only when the owner asks.

## Environment notes

- Dev machine: Windows 11, PowerShell, RTX 4060 Laptop (8 GB), Python 3.11, Git, Node, `gh` logged in.
- Installed: Flutter 3.50 / Dart 3.14 at `C:\src\flutter`; Visual Studio 2022 Build Tools (C++); Microsoft OpenJDK 17 at `C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot`; Android SDK at `C:\Android\Sdk` (platform 36, build-tools 37). Flutter is configured to use both. Not installed: Android Studio, an emulator image, Ollama.
- macOS cannot be built locally; use GitHub Actions `macos-latest`.
- The project path contains spaces (`CLAUDE PROJECT\cantonese learning app`); quote paths in every command and script.

## Releases and auto-update

`bash tool/release.sh` builds Android (arm64 + arm32 APKs) and Windows (zip), tags `b<commits>`
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
C:\src\flutter\bin\flutter test integration_test -d windows      # real build, real sqlite + audio
C:\src\flutter\bin\flutter build apk --release                   # phone build
```

`integration_test/` runs the real build with real plugins and writes progress to a temp
folder, never to the owner's event log (`%APPDATA%\app.duk\duk\events`).

`app/test/ui/reader_flow_test.dart` runs the real engine against the real `content.db`;
run `duk build` and `duk bundle` first or it is skipped.

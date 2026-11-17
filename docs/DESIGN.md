# Design spec

> **2026-11-15: Cantonese only.** The owner dropped the Mandarin track. Mentions of Mandarin, Pinyin or `cmn` below are historical.

Working title: **Duk6** (讀, "to read"). Rename freely.

## 1. Who it is for and what it must do

> Rewritten 2026-11-17 (launch check). It started as the owner's personal app; the text
> below is current. Historical detail is in `docs/CHANGELOG.md`.

Public, non-commercial, free. Released on GitHub only (Android arm64; Windows and macOS
later). Two kinds of learner, picked by the level question in onboarding (`prefs.level`):

- **Newcomers to Macau and Hong Kong (the main audience).** They don't speak Cantonese
  and need essential words to get their point across: ordering, taxis, a flat, school,
  the doctor. **Newcomer mode:** situations (`content/situations.yaml`), each a deck of
  key words and short chunks, drilled English first (see the English, say it, hear it);
  search "What do you want to say?"; practice beyond words (`content/practice.yaml`):
  understanding replies, hearing tones, building sentences from frames, real-world
  challenges; a Jyutping guide and particles; a picture for each word where one fits.
  Home B (`ui/situations.dart`).
- **Speakers who can't read** (and learners who also want to read). **The reading app:**
  real Macau/HK sentences with Jyutping that fades per character as it is learned; each
  sentence is read first, then checked by ear. Home A.

Both modes share all content and the same five tabs (Home, Topics, Situations, Drill,
Progress); only Home and the tab order differ.

**Goal (reading app):** go from needing Jyutping over every character to reading real
Macau/HK text with none. **Goal (newcomer mode):** say and understand the essential words
of the situations a newcomer meets in the first months.

**Headline metric:** *unaided coverage* = share of characters in a reference corpus (Macau signs, menus, news, chat) whose predicted recall is at least 0.9.

### Non-goals

- Not an Anki clone. No isolated-word-first decks. Anki `.apkg` export is a late, optional extra.
- No handwriting teaching (stroke order is shown for reference only).
- No multi-user accounts, no server we operate.
- No commercial distribution. Licences still matter (the app is public): every source is recorded in `DATA_SOURCES.md`, and those that ask for credit are credited on Settings → About.

## 2. Core mechanics

### 2.1 Items (the things memory is tracked for)

| Item kind | Key | Example |
|---|---|---|
| `char_reading` | (lang, char, reading) | (yue, 行, hong4) and (yue, 行, hang4) are two items |
| `phonetic_family` | component | 青 → 清 晴 精 請 |
| `tone` | (lang, tone) | confusions like tone 3 vs tone 6 |
| `word` | (lang, word) | 唔該, 埋單 |
| `pattern` | id | 係咪…?, 把-construction |
| `place` | id | 議事亭前地 |
| `card` | (item, template) | place × "PT→ZH" direction |

`lang` is always `yue` (Cantonese, Traditional, HK variant glyphs). The Mandarin track (`cmn`) was dropped by the owner on 2026-11-15; the tag stays because it is part of permanent item IDs.

Item IDs are **stable forever**. Content updates may add or retire items but never reuse or renumber an ID, so progress never detaches.

### 2.2 Ruby fading (the main feature)

Every `char_reading` has a scaffold level, derived from its memory state (never stored):

| Level | Shown | When |
|---|---|---|
| 0 Full | Jyutping/Pinyin above the character | never reviewed: this exposure introduces it |
| 1 Hint | tone number only; tap shows the rest | in the scheduler's short-term (re)learning steps |
| 2 Tap | nothing, faint underline; tap reveals | in long-term review but not yet mastered |
| 3 None | plain text; long-press still reveals | stability ≥ 21 days and recall probability ≥ 0.85 |

The level follows how well an item is established, **not** how likely it is to be recalled
right now. An item whose recall has decayed is exactly the one to test, so it stays hidden;
showing it again would hide the lapse. A reveal at levels 1–3 is logged as a lapse, which
moves the item back to relearning (level 1). A global shift ("more help / less help")
moves every level by one for a session.

### 2.3 Scheduling

- **FSRS** per item (Dart `fsrs` package), parameters re-optimised from the owner's own log.
- Fuzzing is off: replaying the log must give identical state on every device.
- Reviews happen **inside sentences**, graded from behaviour (`engine/signals.dart`):
  shown in full → introduction (good); hidden and not revealed → good; hidden, not revealed
  but slow (> 2.5 s per character, reading time before the check) → hard; revealed → again;
  marked wrong after the check → again (`missed`).
- **Read, then check** (2026-11-17): a sentence with any character not shown in full is read
  first with no sound (and, for speakers, no meaning). Check (or a read-aloud attempt) plays
  it and shows every reading; the learner taps characters they read wrong, then "I read it
  right" or Next. Listening is not available before the check, because hearing the line is
  the answer. Read-along stories (audio on open) skip the check.
- A sentence left in under 150 ms per character was skipped, not read: nothing is graded.
- Explicit grading is only asked when no implicit signal exists.

### 2.4 Planner (what to show next)

For each session, score candidate sentences and cards:

```
score = w_due   × Σ urgency(due items covered)
      + w_new   × Σ unlock_value(new items, max 2 per sentence)
      + w_rel   × relevance(region, active goal, personal-corpus hits)
      − w_over  × count(unknown items beyond the targets)
      − w_rep   × recently_seen(sentence)
```

- Target 90–95% known characters per sentence.
- `unlock_value` = corpus frequency (weighted to Macau/HK and the owner's own pasted/OCR text) + size of the phonetic family the item unlocks.
- Greedy selection, re-scored after each pick so one sentence covers many due items.
- Variety (2026-11-16): `recently_seen` = sentences read or said in the last 2 days (event log), and each candidate gets a random nudge of up to 0.5 per session (less than one due item, so due and weak items still decide what is studied; only which sentence carries them changes). Review also passes the weak characters as `focus`: they count as due even before FSRS says so. Flashcards (`deck_planner.dart`): every visit is a shuffled set of up to 8 new cards drawn at random from the next 16 unseen, filled with the weakest seen cards (lowest recall), skipping cards answered in the last 30 minutes unless nothing else is left. Tests fix the random seed.
- Session shape: warm-up (easy) → hardest items early → cool-down. End or ease off on detected fatigue.
- Hard limits the model/bandit may not exceed: max new items/day, max session length, FSRS interval may be adjusted by at most ±30%.

### 2.5 Skip what is known

- **Placement test** on first run: adaptive sampling over frequency bands, about 5 minutes per language, seeds item states.
- **Family inference:** mastering most of a phonetic family raises the prior for unseen members; they get a one-shot probe instead of a full introduction.

### 2.6 Error diagnosis

| Detected error | Response |
|---|---|
| Right syllable, wrong tone | tone contrast drill |
| Confused with a phonetic sibling | side-by-side contrast card |
| Wrong reading of a polyphone | word-context drill (行路 vs 銀行) |
| Mandarin reading given for Cantonese (or reverse) | contrast card; space the other language away from that character |
| Look-alike confusion (己/已/巳) | look-alike drill |

### 2.7 Adaptive layer (later phases)

- **Recall model:** small gradient-boosted model, trained on desktop from the event log, exported to ONNX, run on device. Features: FSRS state, time of day, latency history, device, position in session, reveal counts.
- **Bandit** (Thompson sampling) over: new items/day, session length, fade thresholds, notification time. Reward = retained items per study minute.
- **Local LLM** (desktop, optional): weekly coaching summary, explanations, roleplay, offline sentence drafts. Not used for scheduling.

## 3. Features

| # | Feature | Phase |
|---|---|---|
| F1 | Reader with ruby fading, tap-to-reveal, audio per sentence and per character | 1 |
| F2 | Sentence review sessions driven by the planner | 1 |
| F3 | Event log of every interaction | 1 |
| F4 | Placement test | 1 |
| F5 | Scenario browser (Macau/HK topics), trip mode | 2 |
| F6 | Flashcards: places, signs, menus, forms, surnames, emergencies, etc. | 2 |
| F7 | Map mode for places (offline tiles) | 2 |
| F8 | Auto-update (app + separate content packs) from GitHub Releases | 2 |
| F9 | Google Drive sync | 3 |
| F10 | Paste reader + live TTS | 4 |
| F11 | OCR reader (camera / image / screenshot) | 4 |
| F12 | Read-aloud check (ASR) | 4 |
| F13 | ~~Cantonese ⇄ Mandarin parallel view~~ (dropped with Mandarin, 2026-11-15) | — |
| F14 | Recall model + bandit | 5 |
| F15 | Dashboard: coverage, efficiency, forecast, best study times | 3–5 |
| F16 | Claude "explain this" and roleplay; local LLM weekly report | 6 |
| F17 | Desktop clipboard hotkey reader; Android widget; `.srt` import; Jyutping typing practice; browser extension; Anki export | 6+ |
| F18 | Newcomer mode: situations, English-first drill, replies, tones, frames, challenges | built 2026-11-17 |

## 4. Architecture

```
content/ (YAML, hand-editable)  ──►  pipeline/ (Python)  ──►  content.db + audio packs  ──► GitHub Release
                                                                                              │
ml/ (Python, desktop)  ◄── event logs (Drive) ◄── app  ◄─────────────────────────────────────┘
        └──► recall.onnx (Drive) ──► app
```

### 4.1 App (Flutter)

```
app/lib/
  main.dart          start-up: copies content.db out, replays the event log, builds AppServices
  app_services.dart  everything screens need, passed down explicitly (no global state)
  engine/     PURE DART, no Flutter imports: learner model (FSRS), planner, scaffold, goals,
              pronunciation compare, weak spots, word book. Unit-tested.
  events/     PURE DART: event envelope, logger, JSONL store, replay
  data/       content_db.dart (read-only queries on the bundled SQLite), prefs.dart
  platform/   device things: phone voice (flutter_tts), speech recogniser (sherpa-onnx),
              updater, reminders, share inbox, sound effects, character-picture download
  ui/         screens and widgets; *_screen.dart is one screen each
```
Planned and not built: `sync/` (Google Drive, Phase 3).

Packages in use: `sqlite3` (raw, no code generation), `fsrs`, `audioplayers` (has a Windows backend; `just_audio` does not), `flutter_tts`, `sherpa_onnx`, `http`, `ulid`, `path_provider`, `package_info_plus`; widgets come from `package:material_ui` (Flutter ≥ 3.47 moved Material out of the SDK). The updater is custom (`platform/updater.dart`). Planned: `flutter_map` (+ tile caching), `googleapis`/`google_sign_in` (sync).

### 4.2 Two databases

- `content.db`: read-only, shipped as a release asset, replaced wholesale on content update.
- `progress.db`: the owner's event log and derived state. Never replaced. Backed up before every schema migration.

**Derived state is a cache.** `learner state = fold(events)`. A "rebuild from log" command must always reproduce it. This is what makes sync trivial and algorithm changes safe.

### 4.3 content.db (sketch)

```
sentence(id, lang, text, en, register, region, scenario_id, source, reviewed, pair_id)
token(sentence_id, idx, surface, kind, char, reading, word_id)   -- one row per character or non-CJK run
item(id, kind, lang, key, freq, unlock_value)
sentence_item(sentence_id, item_id)                             -- index for the planner
word(id, lang, text, reading, en)
char_info(char, lang, readings, phonetic_component, semantic_component, simp_trad_map, strokes_ref)
family(component, members)
place(id, zh, readings, official_pt, en, region, district, type, lat, lon, photo)
card(id, item_id, template, front, back, media)
scenario(id, region, title, tags)
audio(hash, lang, voice, rate, path)                            -- hash = sha1(tts_text|voice|rate)
meta(content_version, schema_version, built_at)
```

`pair_id` links a Cantonese sentence to its Mandarin counterpart.

### 4.4 Progress storage

Today progress is **only** the event log: `events/<deviceId>/<yyyy-mm>.jsonl` under the app
support directory, replayed into memory at start-up (`LearnerModel.replay`). That file layout
is also the sync unit. A `progress.db` cache of derived state is added only when replay time
becomes noticeable (tens of thousands of events); it must stay rebuildable from the log.

If an event older than one already applied arrives (merged from another device),
`LearnerModel.needsReplay` turns true and the state must be rebuilt before use.

## 5. Text handling rules (easy to get wrong)

1. **Readings are stored per character as an array, never as one string.** Ruby alignment is by index. Non-CJK runs ("MOP", "3A") are single tokens with an optional spoken reading.
2. **Glyph variants.** Chinese fonts unify code points across regions. Bundle **Noto Sans HK** and set the text locale `zh-HK` on every Chinese `Text`, or characters render in the wrong regional form.
3. **Normalisation.** Canonical Traditional form = OpenCC HK standard. Keep an alias table for common written-Cantonese variants (俾/畀, 嚟/黎, 啲/D, 裏/裡) so lookup and progress hit one item.
4. **Polyphones and spoken tones.** Show the tones people actually say (owner, 2026-11-16), not formal citation tones. Voters, in `pipeline/duk/annotate.py`:
   - ToJyutping (in context) and pycantonese must agree, as before.
   - **HKCanCor speech counts** (recorded everyday HK speech, shipped with pycantonese): a word's reading counts when it has at least 3 uses and 80% share. A whole word said one way (澳門 ou3 mun2, 公園 gung1 jyun2) overrules both dictionaries and is flagged for the owner; how a character is said on its own (錢 cin2, 坐 co5, 魚 jyu2) only breaks ties. Not for 重 (HKCanCor writes 仲 as 重), 呢 (particle outnumbers "this"), 會 ("will" outnumbers "association"). Lazy sounds (n→l, dropped ng-) are never taken.
   - **rime-cantonese words** with a single listed reading (糖水 tong4 seoi2) settle a disagreement when they side with one source. Only on pycantonese's own word splits (greedy matching found 度街 inside 飛能便度街).
   - Otherwise sentences show ToJyutping's reading (it keeps colloquial tones); Unihan's context-free reading no longer breaks ties there (it was choosing 澳門 ou3 mun4). Names on cards (streets, dishes) keep the old tie-break and use only whole-word speech evidence, since transliterations and names don't follow everyday speech.
   - Every unsettled reading waits in `build/review_queue.md`; word overrides live in `content/overrides/readings.yaml`. The owner's ear stays the final check.
5. **Colloquial vs literary readings** (聽 teng1/ting1, 平 peng4/ping4) are separate `char_reading` items, tagged.
6. **Place-name readings** override dictionary defaults (涌 cung1 in HK place names; 氹 tam5).
7. **Display form.** Readings are shown as Jyutping (`hong4`) (`engine/reading_format.dart`).
7a. (Mandarin tone sandhi: no longer relevant; Mandarin was dropped.)
8. **Registers:** every sentence is tagged `spoken` (written Cantonese) or `written` (standard written Chinese read in Cantonese). Both are taught.
9. **Lazy sounds** (n→l, dropped ng-) are accepted in read-aloud checks and noted, not marked wrong.

## 6. Audio

- **Sentences play in the phone's own Cantonese voice by default** (owner, 2026-11-16: Android's Google "Cantonese (Hong Kong)" voice says everyday tones, e.g. 澳門 ou3 mun2; the recorded edge-tts voice reads some words in a formal tone and ignores our Jyutping). Picking "Recorded voice" switches to the recorded clips, which are also the fallback where no Cantonese voice is installed (most Windows PCs). Settings → Sentence voice lists the phone's default voice (the default), every other Cantonese voice the phone's engine offers (Google's online voices first; the choice applies to tapped words too), and the recorded voice. Cloud candidates for better quality, not built (each needs an owner key): Google Cloud TTS yue-HK Chirp 3 HD voices (likely the same tone habits as the phone's Google voice), Amazon Polly Hiujin (neural), MiniMax Speech, cantonese.ai (claims Jyutping pronunciation control). Checked 2026-11-16: the edge-tts endpoint rejects custom SSML (`<phoneme>`, `<sub>`), so the recorded voice cannot be told a reading.
- **Recorded clips** (the fallback and the "Recorded voice" option): edge-tts `zh-HK-HiuMaanNeural`, one clip per line, cached as MP3 in `build/audio`. `duk bundle` ships them as **Opus in Ogg, 24 kbps mono** (`pipeline/duk/audio_pack.py`, needs ffmpeg; about 40% of the MP3 size, 21 MB for 3,500 clips) and points the bundled `content.db` at the `.ogg` files. Android plays Ogg Opus from Android 10. "Slow" plays the same clip at 75% speed.
- Pasted text has no clip: it plays in the phone voice.
- Not built (superseded by the phone voice, 2026-11-16): the Azure bake-off, an ASR back-check loop, TTS-only substitutions and a "wrong audio" button.

## 7. Sync, update, privacy

- **Google Drive `appDataFolder`** (`drive.appdata` scope). Each device writes only `events/<deviceId>/<yyyy-mm>.jsonl.gz`. Devices merge by event ID; no conflicts possible. Also holds `models/` and weekly `backups/`.
- **Windows** has no `google_sign_in`: use the loopback OAuth flow. OAuth app must be published (not left in Testing) or refresh tokens expire weekly.
- **Updates:** check GitHub Releases on launch, in the background. Channels `dev` (every push to main) and `stable` (tags). App binaries and content packs are versioned independently; content packs declare the minimum app version they need.
- Downloads are untrusted (2026-11-17): app updates only from `github.com` /
  `*.githubusercontent.com` over HTTPS, saved under a checked file name, and verified against
  the SHA-256 digest GitHub publishes for the asset; the Android installer only accepts APKs in
  `cache/ducklearn_updates` (FileProvider scoped to that folder). The speech model is pinned
  to one HuggingFace commit and each file's SHA-256. Conversation pictures: HTTPS only, PNG or
  JPEG only, at most 3 MB. Shared-in text is capped at 20,000 characters. CI runs with a
  read-only token and actions pinned to commit SHAs.
- Android builds must always be signed with the same keystore: `%USERPROFILE%\.ducklearn\` on the build PC, backed up to `D:\Backups\DuckLearn signing key` and the owner's OneDrive (2026-11-16). CI does not sign.
- Location is opt-in and stored as region only (macau / hk / other).
- Secrets live in `secrets.json` (git-ignored). No key is compiled into a released binary; the app asks for keys in Settings and stores them in the OS keystore.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Scope is large | Strict phases; Phase 1 must be usable daily before anything else starts |
| Wrong Jyutping teaches wrong readings | Dictionary-first annotation, polyphone flags, `reviewed` gate, owner is the final check |
| LLM-written Cantonese sounds unnatural | Generated content is `reviewed: false` and visibly marked until approved |
| Event schema churn | Versioned from day one; replay tests in CI |
| Planner feels random | "Why this?" debug overlay; simulated-learner tests |
| macOS cannot be built on the Windows dev machine | macOS builds only via GitHub Actions `macos-latest` |
| Unsigned desktop builds | Accept SmartScreen/Gatekeeper prompts; document the one-time workaround |
| Data loss | Drive backups; pre-migration snapshot; export button |

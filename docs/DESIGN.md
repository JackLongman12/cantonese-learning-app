# Design spec

Working title: **Duk6** (讀, "to read"). Rename freely.

## 1. Who it is for and what it must do

One user (the owner). Personal, non-commercial.

- Speaks and understands Cantonese natively. **Cannot reliably read** Traditional Chinese or written Cantonese: cannot get from a character to its sound without looking it up.
- Also wants Mandarin with Simplified characters (weaker; needs sound *and* some vocabulary).
- Lives/moves in **Macau first, Hong Kong second**. Content must be real-life sentences for those places, not isolated words.
- Platforms: Android, Windows, macOS.

**Goal:** go from needing Jyutping over every character to reading real Macau/HK text with none.

**Headline metric:** *unaided coverage* = share of characters in a reference corpus (Macau signs, menus, news, chat) whose predicted recall is at least 0.9.

### Non-goals

- Not an Anki clone. No isolated-word-first decks. Anki `.apkg` export is a late, optional extra.
- No handwriting teaching (stroke order is shown for reference only).
- No multi-user accounts, no server we operate.
- No commercial distribution. Licences are therefore not a constraint, but every source is still recorded in `DATA_SOURCES.md`.

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

`lang` is `yue` (Cantonese, Traditional, HK variant glyphs) or `cmn` (Mandarin, Simplified). The same character has independent state per language.

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
  but slow (> 2.5 s per character) → hard; revealed → again.
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
| F13 | Cantonese ⇄ Mandarin parallel view with differences highlighted | 2–4 |
| F14 | Recall model + bandit | 5 |
| F15 | Dashboard: coverage, efficiency, forecast, best study times | 3–5 |
| F16 | Claude "explain this" and roleplay; local LLM weekly report | 6 |
| F17 | Desktop clipboard hotkey reader; Android widget; `.srt` import; Jyutping typing practice; browser extension; Anki export | 6+ |

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
  ui/         views only; no business logic
  engine/     PURE DART, no Flutter imports: learner_model, planner, fsrs glue, diagnosis, bandit
  events/     schema, logger, idle detection, replay
  data/       drift databases, repositories
  sync/       Google Drive appDataFolder
  update/     GitHub release check, content-pack updater
  audio/      playback, cache, live TTS client, OS-TTS fallback
  platform/   OCR channels, hotkeys
```

Packages in use: `sqlite3` (raw, no code generation), `fsrs`, `just_audio`, `ulid`, `path_provider`; widgets come from `package:material_ui` (Flutter ≥ 3.47 moved Material out of the SDK). Planned: `flutter_map` (+ tile caching), `google_mlkit_text_recognition` (Android), `flutter_tts`, `googleapis`/`googleapis_auth`/`google_sign_in`, `package_info_plus`, `onnxruntime`, `auto_updater` or a custom updater.

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
2. **Glyph variants.** Chinese fonts unify code points across regions. Bundle **Noto Sans HK** (yue) and **Noto Sans SC** (cmn) and set the text locale (`zh-HK` / `zh-CN`) on every Chinese `Text`, or characters render in the wrong regional form.
3. **Normalisation.** Canonical Traditional form = OpenCC HK standard. Keep an alias table for common written-Cantonese variants (俾/畀, 嚟/黎, 啲/D, 裏/裡) so lookup and progress hit one item.
4. **Polyphones.** Cantonese readings need two independent sources (ToJyutping, pycantonese) to agree; Unihan confirms a lone source and picks the default while a disagreement waits in `build/review_queue.md`. Curated word overrides live in `content/overrides/readings.yaml`. Two sources can agree on a formal reading where speech differs (聲 sing1/seng1), so the owner's ear remains the final check.
5. **Colloquial vs literary readings** (聽 teng1/ting1, 平 peng4/ping4) are separate `char_reading` items, tagged.
6. **Place-name readings** override dictionary defaults (涌 cung1 in HK place names; 氹 tam5).
7. **Mandarin tone sandhi:** store citation tones; optionally display sandhi for 不/一/third-tone as a setting.
8. **Registers:** every sentence is tagged `spoken` (written Cantonese) or `written` (standard written Chinese read in Cantonese). Both are taught.
9. **Lazy sounds** (n→l, dropped ng-) are accepted in read-aloud checks and noted, not marked wrong.

## 6. Audio

- **Primary TTS: Azure Speech** (zh-HK and zh-CN neural voices), chosen by a bake-off that the owner rates (see ROADMAP Phase 0). Candidates to compare: Azure, Google Cloud, a local model on the RTX 4060 (CosyVoice family), ElevenLabs.
- Content audio is **pre-generated** in the pipeline: 2 voices per language, normal + slow (SSML rate, not time-stretch).
- **Verification loop:** synthesise → ASR back-transcribe → compare → flag mismatches. Fix with SSML phoneme where supported, else a *TTS-only* homophone substitution (display text unchanged).
- Single characters are synthesised in a carrier and trimmed, or taken from a per-syllable set if a good one is found.
- App has a "wrong audio" button → emits an event → pipeline regenerates.
- Pasted/OCR text: live Azure call, cached by hash; OS voice as offline fallback.

## 7. Sync, update, privacy

- **Google Drive `appDataFolder`** (`drive.appdata` scope). Each device writes only `events/<deviceId>/<yyyy-mm>.jsonl.gz`. Devices merge by event ID; no conflicts possible. Also holds `models/` and weekly `backups/`.
- **Windows** has no `google_sign_in`: use the loopback OAuth flow. OAuth app must be published (not left in Testing) or refresh tokens expire weekly.
- **Updates:** check GitHub Releases on launch, in the background. Channels `dev` (every push to main) and `stable` (tags). App binaries and content packs are versioned independently; content packs declare the minimum app version they need.
- Android builds must always be signed with the same keystore (stored as a GitHub Actions secret, backed up by the owner).
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

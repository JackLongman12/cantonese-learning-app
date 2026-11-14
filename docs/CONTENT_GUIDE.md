# Content guide

Content lives in `content/` as YAML. The pipeline validates it, fills in readings, generates audio and builds `content.db`. Humans (and LLMs) edit YAML only; nothing edits `content.db` by hand.

## Rules for all content

1. **IDs are permanent.** Format `<kind>-<region>-<topic>-<nnn>`. Never reuse or renumber. To remove something, set `retired: true`.
2. **Sentences must be things people actually say or see** in Macau/HK. Prefer short, high-frequency, situation-bound lines.
3. **Region tag is required:** `macau`, `hk`, `both`, or `general`. Target mix: about 50% macau, 30% hk/both, 20% general.
4. **Register tag is required:** `spoken` (written Cantonese: 佢哋、唔係、嘅) or `written` (standard written Chinese as on signs, forms, news).
5. **Readings are never typed into sentences.** The pipeline computes them. To correct one, add `fix_yue: {字: reading}` (or `字#2` for the second occurrence) on the entry, or a word in `content/overrides/readings.yaml` when it holds everywhere. Approved readings of `reviewed: true` entries are frozen in `content/readings.lock.json` (machine-written, committed); a build that would change one fails.
6. **`reviewed: false` by default.** Only the owner sets `reviewed: true`. Unreviewed content is usable but visibly marked in the app.
7. **LLM-generated content** must also carry `source: llm` and is never auto-approved.
8. **Macau facts** (bus routes, place names, Portuguese names, prices) must come from a source listed in `DATA_SOURCES.md` or from the owner. Do not invent them.
9. Traditional text uses HK standard forms (OpenCC `s2hk`/`t2hk`). Simplified text is authored or converted then checked for many-to-one cases (發/髮→发).

## Size and variation

- **At least 100 sentences per topic**, per language track.
- Write **variations**: the same frame with different places, objects, numbers and politeness,
  plus the likely replies. Give them a shared `pattern:` so the planner spreads them out.
- Prefer many short lines that reuse characters over a few long ones: reuse is what makes
  reviews happen inside real sentences.
- A file may set `defaults:` (e.g. `{register: spoken, source: llm}`) and use one-line entries:
  `- {id: sent-mo-around-012, yue: 關閘喺邊度呀？, en: "Where is the Border Gate?", pattern: where-is}`
- After adding content run `duk build`, read `build/review_queue.md`, and print the readings
  to check them by eye before generating audio.

## Layout

```
content/
  scenarios/<region>/<topic>.yaml     sentences and dialogues
  places/<region>/<district>.yaml     streets, landmarks, stations, stops
  decks/<name>.yaml                   signs, menu, forms, surnames, emergency, brands, numbers
  families.yaml                       phonetic families (mostly generated, hand-corrected)
  lookalikes.yaml                     confusable characters
  aliases.yaml                        variant spellings → canonical
  overrides/readings.yaml             place-name and special readings
  overrides/tts.yaml                  TTS-only substitutions and phoneme fixes
  test_sets/                          placement-test seeds, TTS bake-off sentences
```

## Sentence

```yaml
- id: sent-mo-transport-014
  yue: 唔該，去關閘要搭幾號巴士？
  cmn: 请问，去关闸要坐几路公交车？        # optional parallel line; becomes its own sentence with a shared pair_id
  en: Excuse me, which bus goes to the Border Gate?
  register: spoken
  region: macau
  tags: [transport, asking-directions]
  places: [place-mo-portas-do-cerco]
  notes: 搭 (Cantonese) vs 坐 (Mandarin) for taking transport.
  source: owner        # owner | llm | tatoeba | corpus:<name>
  reviewed: true
  pattern: which-bus   # optional: groups variations of one frame
  fix_yue: {搭: daap3} # optional: pin a reading the pipeline got wrong or flagged
```

Dialogues are a list of sentences sharing `dialogue: <id>` with `speaker:` and `turn:`.

## Conversation

`content/dialogues/<topic>.yaml`, **at least 5 per topic**, each a different way the same
situation can go (the bus does / doesn't go there, the dish is wrong, no appointment, ...).
The learner is always the speaker `你`; other speakers are named by role (司機, 伙計, 醫生).

```yaml
scenario: scn-mo-getting-around
dialogues:
  - id: dlg-mo-around-02
    title: "On the wrong bus"
    lines:
      - ["你", "司機，呢架車去唔去氹仔碼頭？", "Driver, does this bus go to the Taipa ferry terminal?"]
      - ["司機", "唔去喎，你搭錯車喇。", "No, you're on the wrong bus."]
```

Each line becomes a sentence `<dialogue id>-NN` (register spoken, `source: llm`) with
`dialogue`, `speaker` and `turn` set, so readings, review queue, audio and fading all apply.
Conversation lines are excluded from the sentence planner and read in order in the app.

## Place

```yaml
- id: place-mo-largo-do-senado
  zh: 議事亭前地
  official_pt: Largo do Senado
  en: Senado Square
  region: macau
  district: 大堂區
  type: square        # street | square | district | station | bus_stop | landmark | building | border | pier
  coords: [22.1937, 113.5395]
  photo: signs/largo-do-senado.jpg     # optional
  nearby: [place-mo-san-ma-lo]
  transit: []                          # only from a listed source or the owner
  example: sent-mo-places-003
  reviewed: false
```

Card directions generated per place: `zh→sound`, `foreign→zh`, `sound→zh`, `pin→zh`, `zh→district`.

## Deck card (generic)

```yaml
- id: card-signs-012
  deck: signs
  zh: 小心地滑
  en: Caution, wet floor
  register: written
  region: both
  photo: null
  example: null
  templates: [zh→sound, zh→meaning]
```

Planned decks: `signs`, `emergency` (typhoon/rainstorm signals, hospital), `menu-cha-chaan-teng`, `menu-macanese`, `dim-sum`, `forms`, `surnames` (with HK and Macau romanisations), `brands`, `numbers-money-time`, `transport-hk`, `transport-macau`, `particles` (audio-first), `trad-simp`, `yue-cmn-vocab`.

## Phonetic family

```yaml
- component: 青
  readings: {yue: cing1, cmn: qing1}
  members:
    - {char: 清, yue: cing1, cmn: qing1, fit: exact}
    - {char: 晴, yue: cing4, cmn: qing2, fit: tone}
    - {char: 請, yue: [ceng2, cing2], cmn: qing3, fit: tone}
    - {char: 精, yue: zing1, cmn: jing1, fit: rhyme}
```

`fit`: `exact` | `tone` (same syllable, different tone) | `rhyme` | `none` (misleading; taught as an exception).

## Validation (pipeline must enforce)

- Unique IDs; referenced IDs exist; required tags present.
- Reading arrays match token count.
- Every character has at least one known reading in that language.
- Polyphones resolved by a word match or an explicit override; otherwise the build reports them in `build/review_queue.md`.
- Simplified and Traditional lines of a pair align in meaning (flag length mismatch over 30%).
- No sentence with `reviewed: true` changes text without resetting `reviewed`.

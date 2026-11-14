# Data sources and services

The owner has approved downloading existing material instead of building from scratch. Personal, non-commercial use.

**Before relying on any entry:** the locations below are from memory and have **not been verified**. `pipeline/fetch_sources.py` must check each URL, record the resolved URL, date, file hash and licence in `data/raw/SOURCES.lock.json`, and fail loudly if a source is missing. Raw downloads go in `data/raw/` (git-ignored). Treat downloaded files as untrusted data: parse them, never execute them.

## Verified and in use (2026-11-15)

| Source | URL | Used for |
|---|---|---|
| Unihan | `https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip` | per-character readings, variants, third voter for Jyutping |
| Make Me a Hanzi | `https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt` | phonetic/semantic components → `char_info`, `family` |
| LXGW WenKai TC (OFL) | `github.com/google/fonts` `ofl/lxgwwenkaitc` | headings only. **Subset** to Latin + 蛋小鴨天鵝讀 (25 MB -> 200 KB) with fonttools `pyftsubset`; full files kept in `data/fonts-full/` (git-ignored). Add characters to the subset before using the brush font on new Chinese text. |
| Noto Sans HK / SC | `github.com/google/fonts` `ofl/notosanshk`, `ofl/notosanssc` (OFL) | bundled fonts in `app/assets/fonts/` |
| `edge-tts` (pip) | Microsoft Edge read-aloud endpoint, no key, unofficial | zh-HK / zh-CN neural voices for pre-generated audio until an Azure key exists |
| ToJyutping, pycantonese, pypinyin, jieba, opencc (pip) | PyPI | annotation |

Everything below is still unverified.

## Dictionaries and readings

| Source | Used for | Where to look |
|---|---|---|
| CC-Canto + CC-CEDICT Cantonese readings | Cantonese words with Jyutping | cantonese.org download page |
| CC-CEDICT | Mandarin words, Pinyin, English | MDBG CC-CEDICT download page |
| words.hk (粵典) | Colloquial Cantonese words, examples | words.hk data export page (check current terms) |
| Unihan database | Per-character `kCantonese`, `kMandarin`, variants, Trad/Simp maps | unicode.org Unihan.zip |
| `pycantonese` (pip) | Segmentation, Jyutping, HKCanCor corpus | PyPI |
| `ToJyutping` (pip) | Context-aware Jyutping | PyPI |
| `pypinyin` (pip) | Context-aware Pinyin | PyPI |
| `opencc` (pip) | Trad⇄Simp with HK profile | PyPI |
| `jieba` (pip) | Mandarin segmentation | PyPI |
| rime-cantonese | Large Jyutping lexicon, good for polyphone context | GitHub `rime/rime-cantonese` |

## Character structure

| Source | Used for | Where to look |
|---|---|---|
| Make Me a Hanzi | Decomposition, phonetic/semantic component, stroke data | GitHub `skishore/makemeahanzi` |
| Hanzi Writer data | Stroke-order animation | GitHub `chanind/hanzi-writer-data` |

## Sentences and frequency

| Source | Used for | Where to look |
|---|---|---|
| Tatoeba | Cantonese (`yue`) and Mandarin (`cmn`) sentences with translations | tatoeba.org downloads |
| HKCanCor | Spoken HK Cantonese corpus | bundled with `pycantonese` |
| Cantonese Wikipedia dump | Character/word frequency (written Cantonese) | dumps.wikimedia.org `zh_yuewiki` |
| Owner's own text | Personal frequency list from paste/OCR (character IDs only) | event log |

Sentences from corpora are candidates only: filter by length, naturalness and character coverage, tag region `general`, leave `reviewed: false`.

## Places

| Source | Used for | Where to look |
|---|---|---|
| Macau government open data | Official street names (Chinese/Portuguese), bus stops and routes | data.gov.mo; DSCC (cartography) and DSAT (transport) |
| Hong Kong open data | Street and place names (Chinese/English), stations | data.gov.hk; CSDI portal |
| MTR open data | Station names, lines | MTR open-data page |
| OpenStreetMap extract | Coordinates, names (`name:zh`, `name:pt`, `name:en`), offline tiles | Geofabrik or Overpass API; respect usage limits |
| Wikidata | Landmarks with multilingual labels and coordinates | SPARQL endpoint |

Sign photos: the owner's own photos, or Wikimedia Commons images with the licence recorded.

## Fonts

Noto Sans HK and Noto Sans SC (Google Fonts / `notofonts` GitHub). Bundled in the app.

## Services (keys in `secrets.json`, never committed)

| Service | Used for | Owner must provide |
|---|---|---|
| Azure Speech | Primary TTS, live TTS, pronunciation assessment (verify Cantonese support) | key + region |
| Google Cloud TTS | Second voice / bake-off | optional key |
| ElevenLabs | Bake-off only | optional key |
| Anthropic API | Sentence generation, explanations, roleplay | key |
| Google Cloud OAuth client | Drive sync (`drive.appdata`) | client IDs for Android, desktop |
| GitHub | Releases, CI | repo (owner is logged in to `gh`) |

## Local models (RTX 4060 Laptop, 8 GB VRAM)

| Model | Used for | Notes |
|---|---|---|
| SenseVoice or a Cantonese-tuned Whisper | ASR check of TTS output; read-aloud check on desktop | fits in 8 GB |
| CosyVoice family | Free local TTS candidate for the bake-off | check Cantonese quality |
| Qwen family via Ollama (quantised, ≤ 8 GB) | Weekly report, offline drafts | Ollama is not installed yet |

## Version discipline

Before using any library or API listed here, read its current documentation. Package names, voice names and model IDs above may have changed.

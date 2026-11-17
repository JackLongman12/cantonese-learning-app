# Changelog

What changed, newest first. Moved out of the ROADMAP Status line on 2026-11-16 so the
roadmap stays short; `git log` has the per-commit detail.

## 2026-11-17 (b2083): second security pass

- **Shared text is capped at 5,000 characters**: readings are worked out on the UI thread,
  so a whole web page shared into DuckLearn froze it. Cut by code point.
- Checked again and fine: SQL is parameterised everywhere, the Windows update only expands
  a zip whose SHA-256 matched, CI runs with a read-only token and pinned actions, Dart
  packages are current (patch releases only). GitHub's Dependabot alerts are off for the
  repo; turning them on is the owner's call (a repo security setting).

## 2026-11-17 (b2082): launch check

- **Licence credits** (launch check): Settings → About now credits the dictionary data
  (CC-CEDICT, CC-Canto, rime-cantonese, Unihan, HKCanCor), OpenStreetMap place names
  (ODbL), the SenseVoice speech model (FunASR model licence) and Noto Sans HK (OFL), as
  those licences require. Before, only the icons and photos were credited.
- **Usage report covers newcomers**: a "Newcomer practice" section (replies understood,
  tones heard, sentences said, challenges, the hardest replies and tone sets). It had
  only reading-app numbers, though newcomers are the main audience.
- Security review found nothing to fix: no secrets in the git history, updates checked
  by SHA-256 from HTTPS GitHub only and installed by Android's signature check, photo
  and model downloads pinned to their hosts and size-limited, Worker inputs validated
  and rate-limited. Open launch decisions are in ROADMAP 3.7.

## 2026-11-17 (b2081): word photos load again; picture rating retired

- **Photos were blank** (owner's report): Wikimedia now serves thumbnails from
  thumb.wikimedia.org, which the downloader's host check refused, so 198 of 200 photos
  never loaded. The host is trusted now (still HTTPS, Wikimedia only) and requests carry
  a DuckLearn User-Agent as Wikimedia asks. All 200 photo links checked.
- **Rate pictures removed**: the owner accepted every picture as fine, so all 349 `doubt`
  marks are gone and the Settings tile with them. Earlier ratings no longer hide pictures.

## 2026-11-17 (b2080): OK rating for pictures

- **Rate pictures has an OK button** between Bad and Good (owner's request): the picture
  fits but a better one would be welcome. `duk pictures ratings` keeps it like Good and
  marks it `ok: true` in content/pictures.yaml, so those are the first to replace. The
  event gains `rating: good|ok|bad`; `good` stays (false only for Bad).

## 2026-11-17 (b2079): one app for both modes, half the audio, picture ratings

- **Both modes share the same content** (owner's bug report: the speaker mode still looked
  like the old build). Every learner now has the same five tabs: Home, Topics, Situations,
  Drill (word drill, Understand replies, Hear the tones, Build a sentence, flashcard decks)
  and Progress. Only Home and the tab order differ by mode; it was always one database.
- **Audio halved** (27.2 MB → 14.9 MB for 4,998 clips): edge-tts pads clips with silence
  (often 0.2 s before, 0.9 s after); it is trimmed to 0.05 s / 0.15 s, and Opus goes from 24
  to 16 kbps (voip). Speech length checked unchanged on a sample. Playback also starts and
  ends sooner. `duk bundle` now replaces clips whose encoding changed.
- **Rate pictures** (Settings → Developer, temporary): the 349 word pictures I wasn't sure
  of (all 202 photos, which were only checked by file name, and 147 icons for abstract
  words), one at a time, Good or Bad, Back to change. A Bad picture stops showing on the
  device; with usage sharing on, `duk pictures ratings` pulls the ratings and applies
  them to content/pictures.yaml. Schema 17 adds `card_picture.doubt`.

## 2026-11-17 (b2078): understanding replies, tones, sentences, pictures

Gaps from the language-learning review, all but non-native accents (no material for them:
the app only has text-to-speech; owner, 2026-11-17):
- **Understanding replies:** "What you'll hear" in a situation, and "Understand replies" on
  the Drill tab: 59 replies people give (行過去轉左, 賣晒喇, 唔收卡). Hear one, pick the
  meaning, then see it with Jyutping; Play again and Slow. Missed ones come back first.
- **Hearing tones:** "Hear the tones": 12 sets that differ only by tone (詩 史 試 時 市 事,
  買/賣, 湯/糖, 死/四, 貴/鬼…). Each round switches speaker (both recorded voices and the
  phone's); the sets you mix up most come back first. Readings from the dictionaries, and
  `duk build` checks each set shares one syllable with distinct tones.
- **Sentence frames:** "Build a sentence": a word you know in 7 frames (＿喺邊？, 我想要＿,
  有冇＿？, 唔該＿, 我想去＿, ＿幾錢？, 我＿痛), 42 sentences; say it (mic check), then
  check.
- **Jyutping guide** on the Situations tab: the letters that don't sound like English, and
  the six tones, every example playable. **Sentence particles** (啦 呀 喎 咩) linked there too.
- **Real use:** "Try it for real" on Home: one small challenge at a time (走冰, 唔該借借,
  前面有落), "I did it" or "Another". No streaks; done ones stop showing.
- Content in `content/practice.yaml`; each line is a card in a hidden `prc-*` deck
  (readings, review queue and audio as usual); schema 16 adds `practice`. New events
  `listen.answer`, `tone.answer`, `frame.say`, `challenge.done` (shared if opted in:
  content ids only), replayed by `engine/practice_log.dart`.
- **Word pictures:** 202 photos (Wikimedia Commons, downloaded on the phone with their
  credit, never bundled) and 409 icons (OpenMoji, 240 PNGs, 600 KB). Matching is Chinese
  first with a type filter; 113 wrong matches were replaced by an icon or removed
  (`fixed: true`). Fixed a hang in the photo cache (a future waiting on itself).
- **Smaller and faster:** the font is cut to the characters the app uses plus the 2,632 Hong
  Kong primary-school characters (3 MB → 2.2 MB); content.db is copied out only when it
  changed (a stamp), not on every launch; release builds are obfuscated.

## 2026-11-17 (b2077): 927 newcomer words

- Situations grow to 35 and words to 927. New: dim sum, clothes, haircut, free time,
  sport, cooking at home, housework, festivals, animals and pets, polite phrases; every
  older situation got more words (countries in Meeting people, colours, transport, money).
- Spoken readings pinned: 手袋 sau2 doi2, 拖鞋 to1 haai2, 舅父 kau5 fu2, 慢慢行 maan6
  maan2 haang4, 隨便坐 ceoi4 bin2 co5, 好輕 hou2 heng1 (cards use 好輕 and 未熟 where the
  bare character's spoken reading can't be pinned without breaking other words).

## 2026-11-17 (b2076): much more newcomer content

- Situations grow from 15 to 25 and words from 214 to 551. New: question words, everyday
  verbs, describing things (with colours), family, feelings and reactions, places in town,
  fruit, veg and the market, body, hotels and sightseeing, everyday slang. Every older
  situation got more words.
- Spoken readings pinned where the dictionaries' first choice is the formal one: 公園
  gung1 jyun2, 妹妹 mui4 mui2, 坐低 co5 dai1, 好驚 hou2 geng1.
- Settings → Developer → Restore my original setup (b2075) puts back the answers saved
  before the first Replay onboarding.

## 2026-11-17 (b2074): walkthrough, tones lesson, matching glosses

- First-run walkthrough (intro_pages.dart, six illustrated pages, also on Replay
  onboarding): what DuckLearn is, the two modes, the drill, search, tones change the
  meaning, and that the app teaches spoken Cantonese, not formal written Chinese.
- Reading skills: "Tones change the meaning" (係 hai6 / 喺 hai2 / 閪 hai1, 買 / 賣, the six
  tones of si, 雞 and 叫雞); newcomers reach it from the Situations tab.
- Drill cards: the English now mirrors the Cantonese unit (要 "want", not "I want it");
  rule added to CONTENT_GUIDE and situations.yaml.
- Settings → Developer → Replay onboarding (temporary; ROADMAP 3.6 removes it).

## 2026-11-17 (b2071): newcomer mode, Home A and B

The owner set the direction: an app for newcomers to Hong Kong and Macau who need key words
to get their point across, not whole sentences.

- Onboarding asks "Which sounds most like you?": new to Cantonese / know a little →
  newcomer mode; speak it but can't read → the reading app. Existing installs keep their
  mode (`prefs.level`, from the earlier speaker answer).
- Newcomer mode (Home B): "What do you want to say?" search over the words and short
  sentences; today's drill (due words first, then new ones, from your situations); next
  situation; your situations; words you can say. Tabs: Home, Situations, Drill, Progress.
- 15 situations, 214 essential words and short chunks (content/situations.yaml), each with
  English and a tip where useful; readings from the dictionaries (overrides for 好平, 請假).
- Cards: an English-first mode for the drill (see the English, say it with the mic check,
  then see and hear the word); only the word is graded, not character reading.
- Reading app (Home A): Continue your topic as the main button, your topics, a flashcards
  block with "drill out loud", a small "characters fading" chip instead of the Review step,
  and stories, speaking, my words and skills behind one chip. Tabs: Home, Topics, Cards,
  Progress. The three-step plan is gone (it was finished twice in the owner's data).

## 2026-11-17 (b2070): repeat after me plays every line

- Speak drill: Next and Skip now wait for the recording and the old line's audio to stop
  before the next line appears. Before, the stop landed after the new line had started and
  cut off "repeat after me", and Skip during a recording left the mic open, which blocks
  playback.

## 2026-11-17 (later): first usage data, fixes, content pass, security

First telemetry pull (the owner's install, 3,805 events, Nov 14–16, no crashes). What it
showed and what was done:

- Every event said app version `0.1.0-dev`: release builds never set `APP_VERSION`.
  `tool/release.sh` now passes the tag.
- Pairs of sessions starting within a second: a double tap opened a screen twice.
  `pushOnce` (ui/finish.dart) ignores a second open while the first is still showing.
- 79 of 103 sessions ended before the end, many after one line; read-aloud was used on about
  70% of sentences; the voice setting was changed 32 times (the TTS problem since fixed).
- Hardest characters: 叉 燒 路 嚟 包 (readings checked, correct).
- The owner: the reader didn't ask them to read and had no way to say "I got it wrong".
  Now a prompt above every sentence ("Read this sentence, then tap Check" / "Did you read
  it right?") and a **Not quite** button that marks every tested character (tap to unmark).
- Speak drill: words can be tapped to hear them and long-pressed for the meaning (counts as
  help).
- Planner: new characters weighted by how common they are in everyday Hong Kong speech
  (`frequencyValue`, 0.5–1.5), so 係 唔 我 come before rare characters.
- Uploads every 2 minutes while the app is open, on pause and on resume; nothing in the
  background.
- Topics: one-line descriptions on every tile and page (pipeline requires one), clearer
  names ("Many ways to say it" is now "Same thing, different words"; "Cantonese food" is
  "Dishes and menus"), and groups in a beginner's order.
- Content: all 2,794 lines read. Fixed missing words (呢碗麵, 整好要幾耐, 香港人行路比澳門人快),
  a word-order error (下得班), Hong Kong things in Macau conversations (轉數快 → MPay,
  地鐵 → 巴士); 55 bare fragments in Numbers and time ("上個月。") became full sentences;
  長龍 reads coeng4 everywhere. Six new Gen Z stories (group chat, Shenzhen weekend,
  concert tickets, café, part-time job, a first date).
- Security: updates only from GitHub over HTTPS, checked file names, SHA-256 verified against
  GitHub's digest; speech model pinned to a commit and SHA-256; picture downloads capped at
  3 MB and HTTPS only; FileProvider limited to the update folder; shared text capped; crash
  text scrubbed of Chinese text, long numbers and emails; Worker rate limits, an event-type
  allowlist and one install per request; CI token read-only with actions pinned to SHAs.

## 2026-11-17: an app for beginners; read, then check; usage data

The owner found the content too basic for their own use, so DuckLearn is now for beginners:
Cantonese speakers who can't read, and people learning the language too (onboarding asks).

- **Read, then check.** A sentence with characters being tested is read first with no sound;
  Check plays it and shows every reading; the learner taps any character they read wrong
  (graded `missed`, like a reveal). Before, Next without a tap counted as read, and Listen did
  not count as help, so hearing the line first earned full credit.
- Feedback: a live count of characters read on your own, the characters light up on
  "I read it right", and the summary shows which characters need less help next time.
- Speakers: meanings hidden until wanted (A/B test on showing them after the check).
  Learners: meanings always shown, Jyutping a step longer.
- "N% of everyday Cantonese": share of characters in HKCanCor (recorded everyday Hong Kong
  conversation) that the learner has learned, on Home and Progress, with the most useful
  characters to learn next. Replaces "% of the app readable".
- Home: four small tools in one row; finish screens: tools as chips.
- Anonymous usage data and crash reports, opt-in, to a Cloudflare Worker (docs/TELEMETRY.md),
  with `duk telemetry pull/report`. Reverses "no crash logs" (2026-11-16).
- A/B experiments per install: `meaning_after_check`, `first_session`.

## 2026-11-16: launch prep (b2067)

- Conversation pictures (Irasutoya) are downloaded on the device on first launch, never
  bundled in the APK or committed: their terms forbid redistributing the files.
- Bundled audio is Opus (.ogg, 24 kbps mono) instead of 48 kbps MP3: 52 MB to 21 MB.
- New topic Hong Kong daily life (120 sentences, 5 conversations, 1 advanced) and 4 Hong
  Kong stories; swearing grows to 200 sentences, 8 conversations and 1 advanced;
  Many ways to say it gets 5 conversations. 撚 reads lan2 everywhere.
- The owner accepted LLM-drafted content as-is; the app no longer shows draft notes.
- Signing key backed up to `D:\Backups\DuckLearn signing key` and OneDrive.

## 2026-11-15/16: voice picker

A voice button in the top bar of every exercise (reading, Speak, cards, practice words, sound families, skills, Read anything) opens the same picker mid-practice. Settings → Sentence voice: the phone's default voice stays the default; any other Cantonese voice on the phone (online ones first) or the recorded voice can be picked, each with a sample.

## 2026-11-15/16: word variants

34 groups of everyday words for the same thing (content/variants.yaml: 白車/救護車/救傷車/十字車, 𨋢/電梯/升降機, 雪櫃/冰箱, 而家/依家/宜家...); tapping any of them shows the whole group with readings and when each is used; new topic "Many ways to say it" (103 sentences, LLM-drafted, unreviewed).

## 2026-11-15/16: phone voice

Sentences, cards and words now play in the phone's own Cantonese voice (the one a tapped word uses), which says the tones people use; the recorded voice is a Settings switch and the fallback without a Cantonese voice.

## 2026-11-15/16: spoken tones

Readings now follow how Cantonese is spoken: HKCanCor speech counts and rime-cantonese words vote alongside ToJyutping and pycantonese, and the formal Unihan reading no longer breaks ties in sentences (澳門 ou3 mun2, 會 wui5, 坐 co5, 錢 cin2, 平靚正 peng4 leng3 zeng3; 110 sentence readings and 8 card readings changed). Reminders are smart by default (learned weekday and weekend times, skip days you read, mention reviews ready), with an optional fixed time. Next stops a playing comparison (your attempt, then the native) at once. Home has no scroll bounce.

## 2026-11-15/16: variety + progress

Sessions vary: reading, speaking and flashcards skip what you saw recently and shuffle near-ties, while due and weak items still lead. Progress tab: a one-line summary of the week, characters met/learned/readable with a weekly bar chart, this week vs last week (new characters, read without help, sounds said right, sentences read) with the change, "What to work on" with a button for each (weak characters, sound mix-ups, words, due cards), and your first week vs now. Review is one screen (due cards stay on the Cards tile), so Back leaves it in one press.

## 2026-11-15/16: redesign

Warm terracotta look (cream, oat tiles, one terracotta accent, sage for done). Tabs: Home, Topics, Stories, Progress. Home = numbered plan with egg markers (Review, Learn, Speak), one Start button, and six tools (Topics, Stories, Cards, Speak, My words, Skills). × in any exercise goes Home; every finish screen offers Up next, the same six tools, Keep going and Home. Subtle characters (ui/critters.dart): a chick with moods (innocent, happy, proud with stars, confused on a miss, curious on a new topic, sleepy when done), a mama duck walking on the Start button (a duckling joins per finished step, reset daily, never counted), a duckling riding progress bars; anything moving faces its direction. Tap a word for sound, reading and meaning (no holding); Listen alternates normal and slower; audio never plays while recording. American English throughout.

## 2026-11-15/16: before

Speaking: the mic starts only when tapped (automatic listening was removed by the owner, 2026-11-16: too hectic, and it kept running after leaving); leaving a screen stops any recording. Sentences still open silently (try first, audio after). Misses below 70% play your attempt then the native audio (temp file, deleted). Speak drill (rapid, back-to-back). Today: Review (due + weak + flagged words + due cards) / Learn / Speak, with weekly metrics as numbers. Sessions adapt (no session length), Keep going, early exit counts. Gentle reminders skip days you read. Sounds only on Next and finish. Level counts learned characters.

## 2026-11-15/16: before

Today is a daily plan (review, next topic on the path, flagged words, due cards). Practice tab: reading skills (sound families, spoken vs written, radicals, particles, measure words) and flashcards. Topics have filter chips. 14 stories (8 long daily-life ones). Pictures: emoji chosen from each sentence's meaning (engine/pictures.dart); food cards use Commons photos.

## 2026-11-15/16: earlier

App is named **DuckLearn**; **Cantonese only** (Mandarin dropped). Tabs: Today (start button above the tabs, reading level 1-10), Topics (two-column grid in beginner-path order, 'Up next'), Cards (food with photos, streets, stations; mic check; missed cards return), Stories, Words (auto-flagged words to practise by reading aloud, saved words, lookup, paste reader). First-run setup for beginners. 15 advanced conversations (level 3). App size cut by ~48 MB (one audio clip per line, slim dictionary, subset font). Words are underlined as whole words (context segmentation checked against the dictionary); conversations play as a visual novel (Irasutoya characters, pick your line on your turn, backlog); food deck of 169 dishes with Commons photos; 16 topics incl. swearing, Cantonese food and Getting around Hong Kong; Android arm64 is the release target (Windows releases paused, macOS later). Home has bottom tabs: Today, Topics (with flashcard decks of real Macau/HK names from OpenStreetMap), Stories, Words ("My words": long-press any character for dictionary meanings from CC-Canto/CC-CEDICT and save it with its sentence), Read (paste/share). Thirteen 100-sentence Macau topics, 65 conversations, 6 stories. Sentences auto-play on open; read-aloud stops when you finish and shows a sound-accuracy percent; soft synthesised UI sounds; settings screen; daily reminder; home-screen widget; auto-update from public GitHub Releases. HK topics and owner review of LLM-written content are the biggest content gaps.

# Changelog

What changed, newest first. Moved out of the ROADMAP Status line on 2026-11-16 so the
roadmap stays short; `git log` has the per-commit detail.

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

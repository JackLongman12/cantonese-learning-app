![DuckLearn: a beginner-friendly app for learning Cantonese](docs/banner.png)

# DuckLearn

A beginner-friendly app for learning Cantonese, made for reading. You learn with real Macau and Hong Kong sentences. Jyutping sits above each character and fades as you learn it. Speaking practice uses an on-device mic check.

- **Today's plan:** review, learn the next topic for your goal, then speak. One Start button.
- **Topics:** grouped by situation (getting around, food and shopping, errands, and more).
- **Stories and conversations** to read whole texts.
- **Flashcards** for dishes, streets and stations.
- **Saved words** that you practice in the sentence they came from.
- No streaks and no session quotas. You go at your own pace.

Android builds are on the [Releases](../../releases) page; the app updates itself.

- [Design spec](docs/DESIGN.md)
- [Roadmap](docs/ROADMAP.md)
- [Content guide](docs/CONTENT_GUIDE.md)
- [Event schema](docs/EVENTS_SCHEMA.md)
- [Data sources](docs/DATA_SOURCES.md)

Layout:

```
content/    YAML sentences, stories, decks, skills
pipeline/   Python: fetch, annotate, validate, TTS, build content.db
app/        Flutter app
docs/
```

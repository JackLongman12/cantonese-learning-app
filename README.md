# Cantonese + Mandarin reading app

A personal app for learning to **read** Chinese when you can already speak Cantonese. Real Macau and Hong Kong sentences, Jyutping that fades character by character, flashcards for places and signs, and a Mandarin/Simplified track.

Status: planning complete, no code yet.

- [Design spec](docs/DESIGN.md)
- [Roadmap](docs/ROADMAP.md)
- [Content guide](docs/CONTENT_GUIDE.md)
- [Event schema](docs/EVENTS_SCHEMA.md)
- [Data sources](docs/DATA_SOURCES.md)

Planned layout:

```
content/    YAML sentences, places, decks
pipeline/   Python: fetch, annotate, validate, TTS, build content.db
ml/         recall model training (later)
app/        Flutter app
docs/
```

"""Pre-generate sentence audio into build/audio/ and register it in content.db.

Engine today: `edge-tts`, which reaches Microsoft's neural zh-HK / zh-CN voices without a
key. It is an unofficial endpoint, fine for personal use and for the voice bake-off; the
`Engine` protocol is where the official Azure Speech client plugs in once the owner has a
key (docs/DESIGN.md section 6). Files are cached by hash(lang|voice|rate|text), so a rebuild
only synthesises what changed.
"""

from __future__ import annotations

import asyncio
import hashlib
import sqlite3
from pathlib import Path
from typing import Protocol

from . import paths

VOICES = {
    "yue": ["zh-HK-HiuMaanNeural", "zh-HK-WanLungNeural"],
}
RATES = {"normal": "+0%", "slow": "-25%"}


def audio_hash(lang: str, voice: str, rate: str, text: str) -> str:
    return hashlib.sha1(f"{lang}|{voice}|{rate}|{text}".encode()).hexdigest()


class Engine(Protocol):
    async def synthesise(self, text: str, voice: str, rate: str, out: Path) -> None: ...


class EdgeEngine:
    async def synthesise(self, text: str, voice: str, rate: str, out: Path) -> None:
        import edge_tts

        tmp = out.with_suffix(".part")
        await edge_tts.Communicate(text, voice, rate=RATES[rate]).save(str(tmp))
        if tmp.stat().st_size < 1024:
            tmp.unlink()
            raise RuntimeError("empty audio")
        tmp.replace(out)


def synthesise_all(
    db_path: Path = paths.CONTENT_DB,
    audio_dir: Path = paths.AUDIO,
    *,
    engine: Engine | None = None,
    voices_per_lang: int = 1,
    limit: int | None = None,
) -> tuple[int, int, int]:
    """Returns (newly made, already cached, failed)."""
    engine = engine or EdgeEngine()
    audio_dir.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(db_path)
    rows = db.execute("SELECT lang, text FROM sentence ORDER BY id").fetchall()
    jobs = []
    for lang, text in rows[:limit]:
        for voice in VOICES[lang][:voices_per_lang]:
            # normal speed only: the app slows playback itself (half the audio size)
            for rate in ("normal",):
                h = audio_hash(lang, voice, rate, text)
                jobs.append((h, lang, voice, rate, text, audio_dir / f"{h}.mp3"))
    # flashcard names: normal speed only (they are two to six syllables)
    has_cards = db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='card'"
    ).fetchone()
    cards = db.execute("SELECT zh FROM card ORDER BY id").fetchall() if has_cards else []
    has_skills = db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='skill_entry'"
    ).fetchone()
    if has_skills:
        cards += db.execute("SELECT example FROM skill_entry ORDER BY id").fetchall()
    for (text,) in cards[:limit]:
        for voice in VOICES["yue"][:voices_per_lang]:
            h = audio_hash("yue", voice, "normal", text)
            jobs.append((h, "yue", voice, "normal", text, audio_dir / f"{h}.mp3"))

    made = cached = failed = 0

    async def run() -> None:
        nonlocal made, cached, failed
        sem = asyncio.Semaphore(4)

        async def one(job) -> None:
            nonlocal made, cached, failed
            h, lang, voice, rate, text, out = job
            if out.exists():
                cached += 1
            else:
                async with sem:
                    try:
                        await engine.synthesise(text, voice, rate, out)
                        made += 1
                    except Exception as e:  # network or service failure: report, keep going
                        failed += 1
                        print(f"  tts failed [{voice} {rate}] {text}: {e}")
                        return
            db.execute(
                "INSERT OR REPLACE INTO audio VALUES(?,?,?,?,?,?)",
                (h, lang, voice, rate, text, f"audio/{h}.mp3"),
            )

        await asyncio.gather(*(one(j) for j in jobs))

    asyncio.run(run())
    db.commit()
    db.close()
    return made, cached, failed

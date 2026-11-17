"""Turn the TTS cache (MP3) into what the app ships: Opus in Ogg, 16 kbps mono, with the
silence around each clip trimmed.

edge-tts pads every clip with silence (often 0.2 s before and 0.9 s after the speech):
trimming it to 0.05 s before and 0.15 s after, and 16 kbps Opus (clear for speech, the
voip mode), halve the audio again (27 MB -> about 14 MB for 5,000 clips, 2026-11-17).
Only silence at the very start and end is cut; pauses inside a sentence stay. Encoded
copies are cached in build/<CACHE_NAME>, so only new clips are encoded.
Needs ffmpeg with libopus on PATH; without it the MP3s are shipped unchanged.
"""

from __future__ import annotations

import shutil
import sqlite3
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import paths

BITRATE = "16k"
# keep 0.05 s before the speech and 0.15 s after (reverse, trim the start again, reverse)
TRIM = (
    "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse,"
    "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.15,areverse"
)
# encodes are cached per setting, so changing either re-encodes everything
CACHE_NAME = "audio_ogg_16k_trim"


def _encode(src: Path, out: Path) -> None:
    tmp = out.with_suffix(".tmp.ogg")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(src), "-map_metadata", "-1",
         "-af", TRIM, "-c:a", "libopus", "-b:a", BITRATE, "-application", "voip",
         "-ac", "1", str(tmp)],
        check=True,
    )  # fmt: skip
    tmp.replace(out)


def pack_audio(
    wanted: set[str],
    mp3_dir: Path,
    dest: Path,
    bundled_db: Path,
    cache: Path | None = None,
) -> int:
    """Fill [dest] with one clip per name in [wanted] (MP3 file names) and point the
    bundled database's audio paths at them. Returns the number of clips shipped."""
    dest.mkdir(parents=True, exist_ok=True)
    use_ogg = shutil.which("ffmpeg") is not None
    if not use_ogg:
        print("ffmpeg not found: shipping MP3 audio (larger app)", file=sys.stderr)
    ext = ".ogg" if use_ogg else ".mp3"
    names = {Path(n).stem + ext for n in wanted}
    for stale in [*dest.glob("*.mp3"), *dest.glob("*.ogg")]:
        if stale.name not in names:
            stale.unlink()
    if use_ogg:
        cache = cache or paths.ROOT / "build" / CACHE_NAME
        cache.mkdir(parents=True, exist_ok=True)
        todo = [n for n in wanted if not (cache / (Path(n).stem + ".ogg")).exists()]
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda n: _encode(mp3_dir / n, cache / (Path(n).stem + ".ogg")), todo))
        for n in names:
            # replace a clip encoded with older settings too (same name, different bytes)
            d = dest / n
            if not d.exists() or d.stat().st_size != (cache / n).stat().st_size:
                shutil.copy2(cache / n, d)
        with sqlite3.connect(bundled_db) as db:
            db.execute("UPDATE audio SET path = substr(path, 1, length(path) - 4) || '.ogg' "
                       "WHERE path LIKE '%.mp3'")  # fmt: skip
    else:
        for n in names:
            if not (dest / n).exists():
                shutil.copy2(mp3_dir / n, dest / n)
    return len(names)

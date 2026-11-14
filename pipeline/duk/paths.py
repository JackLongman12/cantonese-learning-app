"""Repository paths. Everything is resolved from this file, never from the cwd."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "content"
RAW = ROOT / "data" / "raw"
BUILD = ROOT / "build"
AUDIO = BUILD / "audio"
CONTENT_DB = BUILD / "content.db"
REVIEW_QUEUE = BUILD / "review_queue.md"
READINGS_LOCK = CONTENT / "readings.lock.json"
SOURCES_LOCK = RAW / "SOURCES.lock.json"

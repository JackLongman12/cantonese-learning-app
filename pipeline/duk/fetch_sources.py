"""Download reference datasets into data/raw/ and record them in SOURCES.lock.json.

Every download is pinned by SHA-256 on first fetch; a later fetch that yields
different bytes is reported so a changed upstream never slips in unnoticed.
Archives are unpacked with path checks; nothing downloaded is ever executed.
"""

from __future__ import annotations

import hashlib
import io
import json
import zipfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import requests

from . import paths


@dataclass(frozen=True)
class Source:
    name: str
    url: str
    licence: str
    filename: str
    unzip: bool = False


SOURCES = [
    Source(
        "unihan",
        "https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip",
        "Unicode License v3",
        "Unihan.zip",
        unzip=True,
    ),
    Source(
        "makemeahanzi",
        "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt",
        "LGPL (derived from Arphic PL fonts and Unihan)",
        "dictionary.txt",
    ),
]


def _safe_extract(data: bytes, dest: Path) -> list[str]:
    names = []
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for info in zf.infolist():
            target = (dest / info.filename).resolve()
            if info.is_dir() or not target.is_relative_to(dest.resolve()):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(zf.read(info))
            names.append(info.filename)
    return names


def fetch(raw_root: Path = paths.RAW, only: list[str] | None = None) -> list[str]:
    raw_root.mkdir(parents=True, exist_ok=True)
    lock_path = raw_root / "SOURCES.lock.json"
    lock = json.loads(lock_path.read_text("utf-8")) if lock_path.exists() else {}
    report = []
    for src in SOURCES:
        if only and src.name not in only:
            continue
        dest = raw_root / src.name
        dest.mkdir(parents=True, exist_ok=True)
        resp = requests.get(src.url, timeout=120, headers={"User-Agent": "content-pipeline"})
        resp.raise_for_status()
        data = resp.content
        digest = hashlib.sha256(data).hexdigest()
        previous = lock.get(src.name, {}).get("sha256")
        changed = previous is not None and previous != digest
        (dest / src.filename).write_bytes(data)
        files = _safe_extract(data, dest) if src.unzip else [src.filename]
        lock[src.name] = {
            "url": src.url,
            "resolved_url": resp.url,
            "licence": src.licence,
            "sha256": digest,
            "bytes": len(data),
            "fetched_at": datetime.now(UTC).isoformat(timespec="seconds"),
            "files": files,
        }
        report.append(
            f"{src.name}: {len(data):,} bytes"
            + (" (CHANGED since last fetch — review before trusting)" if changed else "")
        )
    lock_path.write_text(json.dumps(lock, indent=1) + "\n", "utf-8")
    return report

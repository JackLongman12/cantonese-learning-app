"""Download reference datasets into data/raw/ and record them in SOURCES.lock.json.

Every download is pinned by SHA-256 on first fetch; a later fetch that yields
different bytes is reported so a changed upstream never slips in unnoticed.
Archives are unpacked with path checks; nothing downloaded is ever executed.
"""

from __future__ import annotations

import hashlib
import io
import json
import time
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
    query: str | None = None  # Overpass QL, sent as a POST


_OVERPASS = "https://overpass-api.de/api/interpreter"


def _osm_query(iso: str, highways: str) -> str:
    return f"""[out:json][timeout:240];
area["ISO3166-1"="{iso}"]->.a;
(way(area.a)["highway"~"^({highways})$"]["name:zh"];
 nwr(area.a)["railway"~"^(station|stop)$"]["name:zh"];);
out tags;"""


_ROADS = (
    "primary|secondary|tertiary|trunk|residential|unclassified|pedestrian"
    "|living_street|service|footway|steps"
)


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
    Source(
        "cedict",
        "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.zip",
        "CC BY-SA 4.0 (CC-CEDICT)",
        "cedict.zip",
        unzip=True,
    ),
    Source(
        "cccanto",
        "https://cantonese.org/cccanto-170202.zip",
        "CC BY-SA 3.0 (CC-Canto, Pleco)",
        "cccanto.zip",
        unzip=True,
    ),
    Source(
        "cccanto_readings",
        "https://cantonese.org/cccedict-canto-readings-150923.zip",
        "CC BY-SA 3.0 (Jyutping for CC-CEDICT entries)",
        "readings.zip",
        unzip=True,
    ),
    Source(
        "osm_macau",
        _OVERPASS,
        "ODbL 1.0 (© OpenStreetMap contributors)",
        "osm_macau.json",
        query=_osm_query("MO", _ROADS),
    ),
    Source(
        "osm_hk",
        _OVERPASS,
        "ODbL 1.0 (© OpenStreetMap contributors)",
        "osm_hk.json",
        query=_osm_query(
            "HK", "primary|secondary|tertiary|trunk|residential|unclassified|pedestrian"
        ),
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
        headers = {"User-Agent": "content-pipeline"}
        if src.query:
            # the public Overpass server sheds load with 429/502/504: wait and retry
            for attempt in range(4):
                resp = requests.post(
                    src.url, data={"data": src.query}, timeout=300, headers=headers
                )
                if resp.status_code not in (429, 502, 503, 504):
                    break
                time.sleep(30 * (attempt + 1))
        else:
            resp = requests.get(src.url, timeout=120, headers=headers)
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

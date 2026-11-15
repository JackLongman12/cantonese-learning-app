"""Download the conversation characters listed in content/characters.yaml.

The images are Irasutoya illustrations: free for non-commercial use, but the files must
not be redistributed, so they go to data/raw/characters and app/assets/characters, both
git-ignored. Downloaded bytes are only checked to be PNG/JPEG images; nothing is executed.
"""

from __future__ import annotations

import shutil
import time
from pathlib import Path

import requests
import yaml

from . import paths

_MAGIC = (b"\x89PNG", b"\xff\xd8\xff")


def file_name(role: str) -> str:
    """ASCII file name for a role: code points in hex, 伙計 -> 4f19-8a08.png (app does the same)."""
    return "-".join(f"{ord(c):x}" for c in role) + ".png"


def fetch_characters(
    content_root: Path = paths.CONTENT,
    raw_root: Path = paths.RAW,
    app_assets: Path = paths.ROOT / "app" / "assets" / "characters",
) -> list[str]:
    doc = yaml.safe_load((content_root / "characters.yaml").read_text("utf-8"))
    dest = raw_root / "characters"
    dest.mkdir(parents=True, exist_ok=True)
    app_assets.mkdir(parents=True, exist_ok=True)
    report = []
    for role, info in (doc.get("characters") or {}).items():
        out = dest / file_name(role)
        if not out.exists():
            time.sleep(0.5)
            r = requests.get(info["image"], timeout=60, headers={"User-Agent": "content-pipeline"})
            r.raise_for_status()
            if not r.content.startswith(_MAGIC):
                report.append(f"{role}: not an image, skipped")
                continue
            out.write_bytes(r.content)
        shutil.copyfile(out, app_assets / out.name)
        report.append(f"{role}: {out.name}")
    return report

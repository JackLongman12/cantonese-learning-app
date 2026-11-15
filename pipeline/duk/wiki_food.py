"""Food flashcards from Cantonese Wikipedia, with freely licensed photos.

`fetch_food` reads the categories in content/decks/food.yaml from zh-yue.wikipedia.org
(one request per category, paced; the API rate-limits bursts), asks Commons for each
photo's licence, and downloads a 320 px thumbnail only when the licence is free
(CC, CC0, public domain). Everything lands in data/raw/food/: pages.json (titles,
English names, photo file, licence, author) and img/*.jpg. Nothing is executed.

`load_food_deck` turns that into deck cards at build time.
"""

from __future__ import annotations

import hashlib
import json
import re
import time
from dataclasses import dataclass
from pathlib import Path

import requests
import yaml

from . import paths

API = "https://zh-yue.wikipedia.org/w/api.php"
HEADERS = {"User-Agent": "DuckLearnContentPipeline/1.0 (personal non-commercial study app)"}
_FREE = re.compile(r"^(cc|public domain|pd)", re.I)
_DISAMBIG = re.compile(r"\s*\(.*?\)\s*$")


def _get(params: dict) -> dict:
    for attempt in range(5):
        r = requests.get(API, params={**params, "format": "json", "formatversion": 2},
                         headers=HEADERS, timeout=60)  # fmt: skip
        if r.status_code == 429:
            time.sleep(10 * (attempt + 1))
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError("Wikipedia kept rate-limiting; try again later")


def _curation(content_root: Path) -> dict:
    return yaml.safe_load((content_root / "decks" / "food.yaml").read_text("utf-8"))


def fetch_food(content_root: Path = paths.CONTENT, raw_root: Path = paths.RAW) -> list[str]:
    cur = _curation(content_root)
    exclude = set(cur.get("exclude") or [])
    out_dir = raw_root / "food"
    img_dir = out_dir / "img"
    img_dir.mkdir(parents=True, exist_ok=True)
    pages: dict[str, dict] = {}
    for cat, keep in (cur.get("categories") or {}).items():
        time.sleep(3)
        data = _get({
            "action": "query", "generator": "categorymembers", "gcmtitle": f"Category:{cat}",
            "gcmlimit": 200, "gcmtype": "page", "prop": "pageimages|langlinks",
            "piprop": "thumbnail|name", "pithumbsize": 320, "lllang": "en", "lllimit": 500,
        })  # fmt: skip
        for p in data.get("query", {}).get("pages", []):
            title = p["title"]
            if ":" in title or title in exclude or title in pages:
                continue
            if keep != "all" and title not in keep:
                continue
            pages[title] = {
                "title": title,
                "category": cat,
                "en": (p.get("langlinks") or [{}])[0].get("title", ""),
                "file": p.get("pageimage"),
                "thumb": (p.get("thumbnail") or {}).get("source"),
            }
    # licences, 40 files per request
    files = [p["file"] for p in pages.values() if p["file"]]
    meta: dict[str, dict] = {}
    for i in range(0, len(files), 40):
        time.sleep(3)
        data = _get({
            "action": "query", "titles": "|".join(f"File:{f}" for f in files[i : i + 40]),
            "prop": "imageinfo", "iiprop": "extmetadata",
        })  # fmt: skip
        for p in data.get("query", {}).get("pages", []):
            info = (p.get("imageinfo") or [{}])[0].get("extmetadata", {})
            name = p["title"].split(":", 1)[1]
            meta[name.replace(" ", "_")] = {
                "licence": info.get("LicenseShortName", {}).get("value", ""),
                "author": re.sub(r"<[^>]+>", "", info.get("Artist", {}).get("value", "")).strip(),
            }
    made = 0
    for p in pages.values():
        m = meta.get((p["file"] or "").replace(" ", "_"), {})
        p["licence"], p["author"] = m.get("licence", ""), m.get("author", "")[:120]
        p["image"] = None
        if not (p["thumb"] and _FREE.match(p["licence"])):
            continue
        name = hashlib.sha1(p["file"].encode("utf-8")).hexdigest()[:16] + ".jpg"
        target = img_dir / name
        if not target.exists():
            time.sleep(1)
            r = requests.get(p["thumb"], headers=HEADERS, timeout=60)
            if r.status_code != 200 or r.content[:3] not in (b"\xff\xd8\xff", b"\x89PN"):
                continue
            target.write_bytes(r.content)
            made += 1
        p["image"] = name
    (out_dir / "pages.json").write_text(
        json.dumps(
            sorted(pages.values(), key=lambda x: x["title"]), ensure_ascii=False, indent=1
        ),  # fmt: skip
        "utf-8",
    )
    with_img = sum(1 for p in pages.values() if p["image"])
    return [f"food: {len(pages)} dishes, {with_img} with a free photo ({made} new)"]


@dataclass
class FoodCard:
    zh: str
    en: str
    image: str | None
    credit: str
    category: str


def load_food_deck(raw_root: Path = paths.RAW) -> list[FoodCard] | None:
    f = raw_root / "food" / "pages.json"
    if not f.exists():
        return None
    out = []
    for p in json.loads(f.read_text("utf-8")):
        zh = _DISAMBIG.sub("", p["title"])
        en = _DISAMBIG.sub("", p.get("en") or "")
        credit = ""
        if p.get("image"):
            author = (p.get("author") or "").strip()
            if not author or "machine-readable" in author or len(author) > 60:
                author = "Wikimedia Commons contributor"
            credit = f"Photo: {author}, {p['licence']}"
        out.append(FoodCard(zh, en, p.get("image"), credit, p["category"]))
    return out

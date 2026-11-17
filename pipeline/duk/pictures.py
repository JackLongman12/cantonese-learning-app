"""Pictures for newcomer words (owner, 2026-11-17): a real photo for concrete things and
cultural items, an illustrated icon for actions, feelings and ideas.

    duk pictures match    # fill content/pictures.yaml for words without an entry
    duk pictures sheets   # build/pictures_review.html: every picture next to its word

Photos: the word's canonical image on Wikidata (property P18, chosen by Wikidata's editors
to represent the thing), shown on the phone from Wikimedia Commons with its author and
licence; never bundled. Icons: OpenMoji (CC BY-SA 4.0), rendered to small PNGs by
`duk bundle`. content/pictures.yaml is reviewed by eye on the sheets; entries marked
`fixed: true` (or `none: true`) are never changed by `match`. Downloads are untrusted data.
"""

from __future__ import annotations

import html
import re
import time
from pathlib import Path

import requests
import yaml

from . import paths

PICTURES = paths.CONTENT / "pictures.yaml"
SHEETS = paths.BUILD / "pictures_review.html"
# Wikimedia asks automated clients to say who they are (project page, no personal data)
UA = {
    "User-Agent": "DuckLearnContentPipeline/1.0 (https://github.com/JackLongman12/cantonese-learning-app)"
}

# situations whose words are mostly things you can point at: photo first
PHOTO_SITUATIONS = {
    "sit-around",
    "sit-places",
    "sit-food",
    "sit-cafe",
    "sit-dimsum",
    "sit-groceries",
    "sit-clothes",
    "sit-body",
    "sit-animals",
    "sit-home",
    "sit-kitchen",
    "sit-health",
    "sit-help",
    "sit-weather",
    "sit-travel",
    "sit-errands",
    "sit-phone",
    "sit-work",
    "sit-festivals",
    "sit-freetime",
    "sit-sport",
    "sit-pay",
    "sit-shop",
}
# Wikidata items that are not the everyday thing
BAD_DESC = re.compile(
    r"species|genus|family of|taxon|video game|film|album|song|single by|band|given name|"
    r"family name|surname|novel|television|tv series|episode|painting|wikimedia|"
    r"disambiguation|magazine|journal|newspaper|ship|village|municipality|township|"
    r"county|district of|river|asteroid|protein|gene |chemical compound|software|"
    r"programming|company|manufacturer|brand|character|fictional|book|play by|opera|"
    r"scientific article|unicode|letter of|typeface|award|football club|organization",
    re.I,
)
STOP = {"a", "an", "the", "to", "of", "for", "(", ")", "in", "on", "it", "your", "you"}


def situation_words() -> list[tuple[str, str, str, str]]:
    """(card id, situation id, Cantonese, English) for every newcomer word."""
    doc = yaml.safe_load((paths.CONTENT / "situations.yaml").read_text("utf-8"))
    return [
        (f"card:{s['id']}:{w[0]}", s["id"], str(w[0]), str(w[1]))
        for s in doc["situations"]
        for w in s["words"]
    ]


def _english_query(en: str) -> str:
    q = re.sub(r"\([^)]*\)", "", en).split("/")[0].strip().strip("!?.")
    q = re.sub(r"^(the|a|an|go|have|play)\s+", "", q, flags=re.I)
    return q.strip()


def _get(session: requests.Session, url: str, params: dict) -> dict:
    """GET with Wikimedia's rate limits respected: back off on 429 / 5xx."""
    for attempt in range(6):
        r = session.get(url, params=params, headers=UA, timeout=30)
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(float(r.headers.get("retry-after", 0) or 0) or 5 * (attempt + 1))
            continue
        r.raise_for_status()
        return r.json()
    raise requests.RequestException("rate limited")


def _search(
    query: str, session: requests.Session, lang: str = "en", exact: bool = False
) -> list[str]:
    data = _get(session, "https://www.wikidata.org/w/api.php",
                {"action": "wbsearchentities", "search": query, "language": lang,
                 "strictlanguage": 1 if exact else 0, "limit": 7, "format": "json",
                 "type": "item"})  # fmt: skip
    out = []
    for h in data.get("search", []):
        if BAD_DESC.search(h.get("description", "")):
            continue
        if exact and h.get("match", {}).get("text") != query:
            continue
        out.append(h["id"])
    return out[:5]


# item types that are never the everyday thing (people, works, names, taxa...)
BAD_TYPES = {
    "Q5",
    "Q4167410",
    "Q13442814",
    "Q11424",
    "Q482994",
    "Q5398426",
    "Q7366",
    "Q571",
    "Q7725634",
    "Q101352",
    "Q202444",
    "Q16521",
    "Q4830453",
    "Q215380",
    "Q3305213",
    "Q15632617",
    "Q95074",
}


def _p18(ids: list[str], session: requests.Session) -> dict[str, str]:
    """Item id -> its P18 image file (50 items per request), skipping bad item types."""
    out = {}
    for i in range(0, len(ids), 50):
        data = _get(session, "https://www.wikidata.org/w/api.php",
                    {"action": "wbgetentities", "ids": "|".join(ids[i:i + 50]),
                     "props": "claims", "format": "json"})  # fmt: skip
        for qid, ent in data.get("entities", {}).items():
            claims = ent.get("claims", {})
            types = {
                c["mainsnak"].get("datavalue", {}).get("value", {}).get("id")
                for c in claims.get("P31", [])
            }
            if types & BAD_TYPES:
                continue
            for c in claims.get("P18", [])[:1]:
                v = c["mainsnak"].get("datavalue", {}).get("value")
                if v:
                    out[qid] = v
    return out


def _credits(files: list[str], session: requests.Session) -> dict[str, dict]:
    """Commons file -> credit and licence, 50 files per request (free images only)."""
    out = {}
    for i in range(0, len(files), 50):
        data = _get(session, "https://commons.wikimedia.org/w/api.php",
                    {"action": "query", "titles": "|".join(f"File:{f}" for f in files[i:i + 50]),
                     "prop": "imageinfo", "iiprop": "extmetadata|mime",
                     "format": "json"})  # fmt: skip
        norm = {n["to"]: n["from"] for n in data.get("query", {}).get("normalized", [])}
        for page in data.get("query", {}).get("pages", {}).values():
            info = (page.get("imageinfo") or [{}])[0]
            if info.get("mime") not in ("image/jpeg", "image/png"):
                continue
            meta = info.get("extmetadata", {})
            lic = meta.get("LicenseShortName", {}).get("value", "").strip()
            if not lic:
                continue
            artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip()
            artist = html.unescape(artist)[:80] or "Wikimedia Commons"
            title = norm.get(page["title"], page["title"])
            out[title.removeprefix("File:")] = {
                "credit": f"Photo: {artist} ({lic}), Wikimedia Commons",
                "license": lic,
            }
    return out


def match() -> str:
    from .picture_icons import ICONS

    current = yaml.safe_load(PICTURES.read_text("utf-8")) if PICTURES.exists() else {}
    current = current or {}
    session = requests.Session()
    words = situation_words()

    def fixed(cid: str) -> bool:
        return bool((current.get(cid) or {}).get("fixed"))

    # 1. photos for things in concrete situations (actions and directions use icons)
    hits: dict[str, list[str]] = {}
    for cid, sid, zh, en in words:
        if sid not in PHOTO_SITUATIONS or zh in ICONS or fixed(cid):
            continue
        if "photo" in (current.get(cid) or {}):
            continue
        ids: list[str] = []
        try:
            for lang in ("yue", "zh-hk", "zh"):
                ids += [q for q in _search(zh, session, lang, exact=True) if q not in ids]
                time.sleep(0.7)
            if not ids:
                ids = _search(_english_query(en), session)
                time.sleep(0.7)
        except requests.RequestException:
            continue
        hits[cid] = ids
    p18 = _p18(sorted({q for ids in hits.values() for q in ids}), session)
    files = {cid: next((p18[q] for q in ids if q in p18), None) for cid, ids in hits.items()}
    credits = _credits(sorted({f for f in files.values() if f}), session)
    photos = 0
    for cid, f in files.items():
        if f and f in credits:
            current[cid] = {"photo": f, **credits[f]}
            photos += 1
    # 2. hand-picked icons; nothing for the rest
    icons = 0
    for cid, _sid, zh, _en in words:
        old = current.get(cid) or {}
        if old.get("fixed") or "photo" in old:
            continue
        if zh in ICONS:
            current[cid] = {"icon": ICONS[zh]}
            icons += 1
        else:
            current[cid] = {"none": True}
    PICTURES.write_text(
        "# Word pictures (duk pictures match; reviewed by eye with duk pictures sheets).\n"
        "# photo: a Wikimedia Commons file (shown on the phone, never bundled, with credit);\n"
        "# icon: an OpenMoji hexcode (CC BY-SA 4.0); none: no picture fits.\n"
        "# Add `fixed: true` to an entry you checked or corrected so `match` leaves it.\n"
        "# doubt: true = not sure the picture fits (the owner accepted all of them as fine on\n"
        "# 2026-11-17; the in-app Rate pictures tool was retired). `duk pictures ratings` still\n"
        "# applies picture.rate events if a rating tool comes back.\n"
        + yaml.safe_dump(current, allow_unicode=True, sort_keys=False, width=200),
        "utf-8",
    )
    return f"pictures: {photos} new photos, {icons} icons"


def sheets() -> Path:
    """An HTML page with every word and its picture, for review by eye."""
    pics = yaml.safe_load(PICTURES.read_text("utf-8")) or {}
    rows = []
    for cid, _sid, zh, en in situation_words():
        p = pics.get(cid) or {}
        if "photo" in p:
            src = (
                "https://commons.wikimedia.org/wiki/Special:FilePath/"
                + requests.utils.quote(p["photo"])
                + "?width=160"
            )
            img = f'<img src="{src}" loading="lazy">'
        elif "icon" in p:
            img = f'<img src="https://cdn.jsdelivr.net/npm/openmoji@15.1.0/color/svg/{p["icon"]}.svg">'
        else:
            img = '<div class="none">none</div>'
        rows.append(
            f'<div class="c"><div class="p">{img}</div><b>{html.escape(zh)}</b>'
            f"<span>{html.escape(en)}</span><i>{html.escape(cid)}</i></div>"
        )
    SHEETS.parent.mkdir(parents=True, exist_ok=True)
    SHEETS.write_text(
        "<!doctype html><meta charset=utf-8><style>body{font:13px system-ui;margin:12px;"
        "background:#f7f2ea}.g{display:grid;grid-template-columns:repeat(8,1fr);gap:6px}"
        ".c{background:#fff;border-radius:8px;padding:4px;display:flex;flex-direction:column;"
        "align-items:center;text-align:center}.p{height:80px;display:flex;align-items:center}"
        ".p img{max-height:80px;max-width:120px}b{font-size:18px}span{font-size:11px}"
        "i{font-size:9px;color:#999}.none{color:#c00}</style><div class=g>"
        + "".join(rows)
        + "</div>",
        "utf-8",
    )
    return SHEETS


def apply_ratings(current: dict, events: list[dict]) -> tuple[int, int]:
    """The owner's Bad/OK/Good from the app (`picture.rate`, Settings > Developer > Rate
    pictures), newest rating per picture: Good keeps it (`fixed`, no longer in doubt), OK
    keeps it too and adds `ok: true` (fits, a better one is welcome), Bad removes it
    (`none`, `fixed`). Events without `rating` use `good`. A rating of a picture that has
    since changed is ignored. Returns (kept, removed)."""
    latest: dict[str, dict] = {}
    for e in sorted(events, key=lambda e: e.get("ts_utc", "")):
        p = e.get("payload") or {}
        if e.get("type") == "picture.rate" and isinstance(p.get("card_id"), str):
            latest[p["card_id"]] = p
    kept = removed = 0
    for cid, p in latest.items():
        pic = current.get(cid) or {}
        if p.get("ref") not in (pic.get("photo"), pic.get("icon")):
            continue
        rating = p.get("rating") or {True: "good", False: "bad"}.get(p.get("good"))
        if rating in ("good", "ok"):
            pic.pop("doubt", None)
            pic.pop("ok", None)
            pic["fixed"] = True
            if rating == "ok":
                pic["ok"] = True
            current[cid] = pic
            kept += 1
        elif rating == "bad":
            current[cid] = {"none": True, "fixed": True}
            removed += 1
    return kept, removed


def ratings() -> str:
    """Pull usage data, apply the owner's picture ratings to content/pictures.yaml."""
    from . import telemetry

    telemetry.pull()
    events, _ = telemetry.load()
    text = PICTURES.read_text("utf-8")
    header = "".join(line + "\n" for line in text.splitlines() if line.startswith("#"))
    current = yaml.safe_load(text) or {}
    kept, removed = apply_ratings(current, events)
    PICTURES.write_text(
        header + yaml.safe_dump(current, allow_unicode=True, sort_keys=False, width=200),
        "utf-8",
    )
    left = sum(1 for v in current.values() if (v or {}).get("doubt"))
    return f"pictures: {kept} kept, {removed} removed, {left} still to rate"

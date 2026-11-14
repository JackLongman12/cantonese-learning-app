"""Load and validate the YAML content tree (docs/CONTENT_GUIDE.md)."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml

REGIONS = {"macau", "hk", "both", "general"}
REGISTERS = {"spoken", "written"}
SOURCES = {"owner", "llm", "tatoeba"}
PLACE_TYPES = {
    "street", "square", "district", "station", "bus_stop",
    "landmark", "building", "border", "pier",
}  # fmt: skip
_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)+$")


class ContentError(Exception):
    """Raised with every problem found, not just the first."""

    def __init__(self, problems: list[str]):
        self.problems = problems
        super().__init__("\n".join(problems))


@dataclass
class Sentence:
    id: str
    scenario: str
    text: dict[str, str]  # lang -> text
    en: str
    register: str
    region: str
    tags: list[str] = field(default_factory=list)
    places: list[str] = field(default_factory=list)
    notes: str = ""
    source: str = "llm"
    reviewed: bool = False
    fix: dict[str, dict[str, str]] = field(default_factory=dict)  # lang -> fix map
    pattern: str | None = None  # variations of one sentence frame share a pattern
    dialogue: str | None = None
    speaker: str | None = None
    turn: int | None = None


@dataclass
class Scenario:
    id: str
    title: str
    region: str
    tags: list[str] = field(default_factory=list)


@dataclass
class Place:
    id: str
    zh: str
    region: str
    type: str
    official_pt: str | None = None
    en: str | None = None
    district: str | None = None
    coords: tuple[float, float] | None = None
    photo: str | None = None
    nearby: list[str] = field(default_factory=list)
    example: str | None = None
    reviewed: bool = False
    fix: dict[str, dict[str, str]] = field(default_factory=dict)


@dataclass
@dataclass
class Dialogue:
    id: str
    scenario: str
    title: str
    lines: int
    kind: str = "conversation"  # conversation | story
    lang: str = "yue"
    level: int = 0
    pair: str | None = None


@dataclass
class Content:
    scenarios: list[Scenario]
    sentences: list[Sentence]
    places: list[Place]
    overrides: dict[str, dict[str, list[str]]]  # lang -> word -> readings
    dialogues: list[Dialogue] = field(default_factory=list)


def _load(path: Path):
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def _fix(raw: dict) -> dict[str, dict[str, str]]:
    return {
        lang: {str(k): str(v) for k, v in raw[f"fix_{lang}"].items()}
        for lang in ("yue",)
        if raw.get(f"fix_{lang}")
    }


def load_content(root: Path) -> Content:
    problems: list[str] = []
    seen: dict[str, Path] = {}

    def claim(id_: str, path: Path) -> bool:
        if not isinstance(id_, str) or not _ID.match(id_):
            problems.append(f"{path.name}: bad id {id_!r}")
            return False
        if id_ in seen:
            problems.append(f"{path.name}: duplicate id {id_} (also in {seen[id_].name})")
            return False
        seen[id_] = path
        return True

    def need(cond: bool, msg: str) -> None:
        if not cond:
            problems.append(msg)

    scenarios: list[Scenario] = []
    sentences: list[Sentence] = []
    for path in sorted((root / "scenarios").rglob("*.yaml")):
        doc = _load(path)
        sc = doc.get("scenario") or {}
        if not claim(sc.get("id"), path):
            continue
        need(sc.get("region") in REGIONS, f"{sc['id']}: region must be one of {sorted(REGIONS)}")
        need(bool(sc.get("title")), f"{sc['id']}: title required")
        scenarios.append(
            Scenario(sc["id"], sc.get("title", ""), sc.get("region", ""), sc.get("tags") or [])
        )
        defaults = doc.get("defaults") or {}
        for raw in doc.get("sentences") or []:
            raw = {**defaults, **raw}
            if raw.get("retired") or not claim(raw.get("id"), path):
                continue
            sid = raw["id"]
            need(not raw.get("cmn"), f"{sid}: Mandarin was dropped; remove the cmn text")
            text = {"yue": raw["yue"].strip()} if raw.get("yue") else {}
            need(bool(text), f"{sid}: needs yue text")
            need(bool(raw.get("en")), f"{sid}: en required")
            need(raw.get("register") in REGISTERS, f"{sid}: register must be spoken|written")
            region = raw.get("region", sc.get("region"))
            need(region in REGIONS, f"{sid}: bad region {region!r}")
            source = raw.get("source", "llm")
            need(
                source in SOURCES or str(source).startswith("corpus:"),
                f"{sid}: bad source {source!r}",
            )
            sentences.append(
                Sentence(
                    id=sid,
                    scenario=sc["id"],
                    text=text,
                    en=raw.get("en", ""),
                    register=raw.get("register", ""),
                    region=region or "",
                    tags=raw.get("tags") or [],
                    places=raw.get("places") or [],
                    notes=raw.get("notes") or "",
                    source=source,
                    reviewed=bool(raw.get("reviewed", False)),
                    fix=_fix(raw),
                    pattern=raw.get("pattern"),
                    dialogue=raw.get("dialogue"),
                    speaker=raw.get("speaker"),
                    turn=raw.get("turn"),
                )
            )

    # Conversations: content/dialogues/*.yaml. Each line becomes a sentence carrying its
    # dialogue id, speaker and turn, so it is annotated, voiced and reviewed like any other.
    dialogues: list[Dialogue] = []
    scenario_region = {sc.id: sc.region for sc in scenarios}
    for path in (
        sorted((root / "dialogues").rglob("*.yaml")) if (root / "dialogues").exists() else []
    ):
        doc = _load(path)
        sid = doc.get("scenario")
        if sid not in scenario_region:
            problems.append(f"{path.name}: unknown scenario {sid!r}")
            continue
        for dlg in doc.get("dialogues") or []:
            if not claim(dlg.get("id"), path):
                continue
            lines = dlg.get("lines") or []
            need(bool(dlg.get("title")), f"{dlg['id']}: title required")
            need(len(lines) >= 2, f"{dlg['id']}: a conversation needs at least two lines")
            for n, line in enumerate(lines, 1):
                if not (isinstance(line, list) and len(line) == 3 and all(line)):
                    problems.append(f"{dlg['id']} line {n}: expected [speaker, text, english]")
                    continue
                speaker, text, en = (str(x) for x in line)
                lang = "yue"
                line_id = f"{dlg['id']}-{n:02d}"
                if not claim(line_id, path):
                    continue
                sentences.append(
                    Sentence(
                        id=line_id,
                        scenario=sid,
                        text={lang: text.strip()},
                        en=en,
                        register="spoken",
                        region=scenario_region[sid],
                        source="llm",
                        reviewed=bool(dlg.get("reviewed", False)),
                        dialogue=dlg["id"],
                        speaker=speaker,
                        turn=n,
                    )
                )
            dialogues.append(Dialogue(dlg["id"], sid, str(dlg.get("title", "")), len(lines)))

    # Stories: content/stories/*.yaml. Same mechanics as conversations (ordered lines),
    # kept under one hidden "Stories" scenario so they never mix into topic sessions.
    story_files = sorted((root / "stories").rglob("*.yaml")) if (root / "stories").exists() else []
    if story_files and "scn-stories" not in scenario_region:
        scenarios.append(Scenario("scn-stories", "Stories", "general", ["stories"]))
        scenario_region["scn-stories"] = "general"
    for path in story_files:
        for st in _load(path).get("stories") or []:
            if not claim(st.get("id"), path):
                continue
            lang = st.get("lang", "yue")
            need(lang == "yue", f"{st['id']}: stories are Cantonese only (lang: yue)")
            need(bool(st.get("title")), f"{st['id']}: title required")
            lines = st.get("lines") or []
            need(len(lines) >= 3, f"{st['id']}: a story needs at least three lines")
            for n, line in enumerate(lines, 1):
                if not (isinstance(line, list) and len(line) == 2 and all(line)):
                    problems.append(f"{st['id']} line {n}: expected [text, english]")
                    continue
                line_id = f"{st['id']}-{n:02d}"
                if not claim(line_id, path):
                    continue
                sentences.append(
                    Sentence(
                        id=line_id,
                        scenario="scn-stories",
                        text={lang: str(line[0]).strip()},
                        en=str(line[1]),
                        register="spoken",
                        region="general",
                        source="llm",
                        reviewed=bool(st.get("reviewed", False)),
                        dialogue=st["id"],
                        turn=n,
                    )
                )
            dialogues.append(
                Dialogue(
                    st["id"],
                    "scn-stories",
                    str(st.get("title", "")),
                    len(lines),
                    kind="story",
                    lang=lang,
                    level=int(st.get("level", 1)),
                    pair=st.get("pair"),
                )
            )

    places: list[Place] = []
    for path in sorted((root / "places").rglob("*.yaml")):
        for raw in _load(path).get("places") or []:
            if raw.get("retired") or not claim(raw.get("id"), path):
                continue
            pid = raw["id"]
            need(bool(raw.get("zh")), f"{pid}: zh required")
            need(raw.get("region") in REGIONS, f"{pid}: bad region")
            need(raw.get("type") in PLACE_TYPES, f"{pid}: bad type {raw.get('type')!r}")
            coords = raw.get("coords")
            if coords is not None:
                ok = (
                    isinstance(coords, list)
                    and len(coords) == 2
                    and -90 <= coords[0] <= 90
                    and -180 <= coords[1] <= 180
                )
                need(ok, f"{pid}: coords must be [lat, lon]")
            places.append(
                Place(
                    id=pid,
                    zh=raw.get("zh", ""),
                    region=raw.get("region", ""),
                    type=raw.get("type", ""),
                    official_pt=raw.get("official_pt"),
                    en=raw.get("en"),
                    district=raw.get("district"),
                    coords=tuple(coords) if coords else None,
                    photo=raw.get("photo"),
                    nearby=raw.get("nearby") or [],
                    example=raw.get("example"),
                    reviewed=bool(raw.get("reviewed", False)),
                    fix=_fix(raw),
                )
            )

    place_ids = {p.id for p in places}
    sentence_ids = {s.id for s in sentences}
    for s in sentences:
        for pid in s.places:
            need(pid in place_ids, f"{s.id}: unknown place {pid}")
    for p in places:
        for pid in p.nearby:
            need(pid in place_ids, f"{p.id}: unknown nearby place {pid}")
        need(
            p.example is None or p.example in sentence_ids,
            f"{p.id}: unknown example sentence {p.example}",
        )

    overrides: dict[str, dict[str, list[str]]] = {"yue": {}}
    ov_path = root / "overrides" / "readings.yaml"
    if ov_path.exists():
        doc = _load(ov_path)
        for lang in overrides:
            for word, readings in (doc.get(lang) or {}).items():
                if not isinstance(readings, list) or len(readings) != len(str(word)):
                    problems.append(f"overrides {lang} {word!r}: need one reading per character")
                    continue
                overrides[lang][str(word)] = [str(r) for r in readings]

    if problems:
        raise ContentError(problems)
    return Content(scenarios, sentences, places, overrides, dialogues)

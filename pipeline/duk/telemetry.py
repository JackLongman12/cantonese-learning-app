"""Anonymous usage data from the app (docs/TELEMETRY.md): download it from the Worker and
turn it into a report of what to change.

    duk telemetry pull     # new rows -> data/telemetry/{events,crashes}.jsonl
    duk telemetry report   # -> build/telemetry_report.md

The Worker URL and admin token come from secrets.json (git-ignored); the token is never
printed. Downloaded rows are untrusted data: they are parsed, never executed.
"""

from __future__ import annotations

import json
import math
import random
import statistics
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

from . import paths

TELEMETRY = paths.ROOT / "data" / "telemetry"
REPORT = paths.BUILD / "telemetry_report.md"

# below this many installs per arm an experiment is "still collecting"
MIN_INSTALLS_PER_ARM = 30
# The app's experiments (app/lib/engine/experiments.dart), control arm first. Keep in
# sync: an experiment missing here is still reported, with its arms in name order.
EXPERIMENT_ARMS = {
    "meaning_after_check": ["shown", "hidden"],
    "first_session": ["short", "longer"],
}

# below this many tested reads a character or sentence is not ranked
MIN_READS = 8


# ---------------------------------------------------------------- download


def _secrets() -> dict:
    p = paths.ROOT / "secrets.json"
    if not p.exists():
        raise SystemExit("secrets.json is missing (telemetry_url, telemetry_admin_token)")
    return json.loads(p.read_text("utf-8"))


def pull(out: Path = TELEMETRY) -> dict[str, int]:
    """Appends rows not downloaded yet. Returns new rows per table."""
    s = _secrets()
    url, token = s["telemetry_url"].rstrip("/"), s["telemetry_admin_token"]
    out.mkdir(parents=True, exist_ok=True)
    state_file = out / "state.json"
    state = json.loads(state_file.read_text("utf-8")) if state_file.exists() else {}
    added = {}
    for table in ("events", "crashes"):
        after, n = int(state.get(table, 0)), 0
        with (out / f"{table}.jsonl").open("a", encoding="utf-8") as f:
            while True:
                req = urllib.request.Request(
                    f"{url}/v1/export?table={table}&after={after}&limit=5000",
                    headers={"Authorization": f"Bearer {token}", "User-Agent": "duk-pipeline"},
                )
                with urllib.request.urlopen(req, timeout=60) as r:
                    rows = json.load(r)["rows"]
                if not rows:
                    break
                for row in rows:
                    f.write(json.dumps(row, ensure_ascii=False) + "\n")
                after = rows[-1]["_row"]
                n += len(rows)
        state[table] = after
        added[table] = n
    state_file.write_text(json.dumps(state), "utf-8")
    return added


def load(folder: Path = TELEMETRY) -> tuple[list[dict], list[dict]]:
    def rows(name: str) -> list[dict]:
        p = folder / f"{name}.jsonl"
        out = []
        if p.exists():
            for line in p.read_text("utf-8").splitlines():
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(r.get("payload"), str):
                    try:
                        r["payload"] = json.loads(r["payload"])
                    except json.JSONDecodeError:
                        r["payload"] = {}
                out.append(r)
        return out

    return rows("events"), rows("crashes")


# ---------------------------------------------------------------- statistics


def wilson(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """95% interval for a proportion k/n that behaves at small n."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def two_proportion_p(k1: int, n1: int, k2: int, n2: int) -> float:
    """Two-sided p-value that two proportions differ (normal approximation)."""
    if min(n1, n2) == 0:
        return 1.0
    p = (k1 + k2) / (n1 + n2)
    se = math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2))
    if se == 0:
        return 1.0
    z = abs(k1 / n1 - k2 / n2) / se
    return math.erfc(z / math.sqrt(2))


def bootstrap_diff(
    a: list[tuple[int, int]], b: list[tuple[int, int]], reps: int = 2000, seed: int = 7
) -> tuple[float, float, float]:
    """Difference of pooled rates (b - a) with a 95% interval, resampling whole installs
    (each install's reads are not independent, so per-read tests would be too sure).
    Each element is (successes, trials) for one install."""

    def rate(xs: list[tuple[int, int]]) -> float:
        n = sum(t for _, t in xs)
        return sum(k for k, _ in xs) / n if n else 0.0

    if not a or not b:
        return (0.0, -1.0, 1.0)
    rnd = random.Random(seed)
    diffs = sorted(
        rate([rnd.choice(b) for _ in b]) - rate([rnd.choice(a) for _ in a]) for _ in range(reps)
    )
    return (rate(b) - rate(a), diffs[int(0.025 * reps)], diffs[int(0.975 * reps)])


def installs_needed(p: float, lift: float) -> int:
    """Installs per arm to see an absolute change of [lift] in a rate near [p]
    (80% power, 5% two-sided)."""
    q = p + lift
    if lift == 0 or not (0 < p < 1) or not (0 < q < 1):
        return 0
    z = 1.96 + 0.84
    return math.ceil(z * z * (p * (1 - p) + q * (1 - q)) / (lift * lift))


# ---------------------------------------------------------------- analysis


@dataclass
class Install:
    id: str
    first: datetime | None = None
    days: set = field(default_factory=set)
    sessions: int = 0
    speaker: bool | None = None
    arms: dict = field(default_factory=dict)
    versions: set = field(default_factory=set)
    tested: int = 0  # tested character reads
    lapses: int = 0  # of those, revealed or marked wrong
    checks: int = 0
    first_session_done: bool = False


def _ts(s: str) -> datetime | None:
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def analyse(events: list[dict]) -> dict:
    inst: dict[str, Install] = {}
    char_reads: Counter = Counter()
    char_lapses: Counter = Counter()
    sent_shown: Counter = Counter()
    sent_lapses: Counter = Counter()
    sent_skips: Counter = Counter()
    read_ms: list[float] = []
    exposure_sentence: dict[str, str] = {}
    screens: Counter = Counter()
    for e in sorted(events, key=lambda e: e.get("ts_utc", "")):
        iid = e.get("install_id")
        if not iid:
            continue
        i = inst.setdefault(iid, Install(iid))
        t = _ts(e.get("ts_utc", ""))
        if t:
            local = t + timedelta(minutes=e.get("tz_offset_min") or 0)
            i.first = i.first or t
            i.days.add(
                (
                    local.date() - (i.first + timedelta(minutes=e.get("tz_offset_min") or 0)).date()
                ).days
            )
        i.versions.add(e.get("app_version"))
        p = e.get("payload") or {}
        typ = e.get("type")
        if typ == "experiment.assigned":
            i.arms.update(p.get("arms") or {})
        elif typ == "onboarding.done":
            i.speaker = p.get("speaker")
        elif typ == "settings.change" and p.get("key") == "speaker":
            i.speaker = p.get("to")
        elif typ == "session.start":
            i.sessions += 1
        elif typ == "session.end" and p.get("reason") == "done" and i.sessions == 1:
            i.first_session_done = True
        elif typ == "nav.screen":
            screens[p.get("screen")] += 1
        elif typ == "item.shown" and p.get("sentence_id"):
            exposure_sentence[p.get("exposure_id")] = p["sentence_id"]
            sent_shown[p["sentence_id"]] += 1
        elif typ == "item.check":
            i.checks += 1
            if isinstance(p.get("read_ms"), (int, float)):
                read_ms.append(p["read_ms"])
        elif typ == "item.done":
            sid = exposure_sentence.get(p.get("exposure_id"))
            if sid and p.get("skipped"):
                sent_skips[sid] += 1
        elif typ == "review.applied":
            sig = p.get("signal")
            if sig in ("noReveal", "slow", "reveal", "missed"):
                lapse = sig in ("reveal", "missed")
                i.tested += 1
                i.lapses += lapse
                ch = p.get("item_id", "")
                char_reads[ch] += 1
                char_lapses[ch] += lapse
                sid = exposure_sentence.get(p.get("exposure_id"))
                if sid:
                    sent_lapses[sid] += lapse
    return {
        "installs": inst,
        "char_reads": char_reads,
        "char_lapses": char_lapses,
        "sent_shown": sent_shown,
        "sent_lapses": sent_lapses,
        "sent_skips": sent_skips,
        "read_ms": read_ms,
        "screens": screens,
    }


def _returned(i: Install, day: int) -> bool:
    return any(d >= day for d in i.days)


def experiment_rows(a: dict) -> list[dict]:
    """Per experiment: arms with installs, day-1 return, lapse rate, and a verdict."""
    from_app = {
        "meaning_after_check": ("speakers", lambda i: i.speaker is not False),
        "first_session": ("all", lambda i: True),
    }
    out = []
    ids = sorted({k for i in a["installs"].values() for k in i.arms})
    for exp in ids:
        who, keep = from_app.get(exp, ("all", lambda i: True))
        by_arm: dict[str, list[Install]] = defaultdict(list)
        for i in a["installs"].values():
            if exp in i.arms and keep(i):
                by_arm[i.arms[exp]].append(i)
        order = EXPERIMENT_ARMS.get(exp, [])
        arms = sorted(by_arm, key=lambda x: (order.index(x) if x in order else 99, x))
        row = {"id": exp, "who": who, "arms": []}
        for arm in arms:
            xs = by_arm[arm]
            ret = sum(_returned(i, 1) for i in xs)
            row["arms"].append(
                {
                    "arm": arm,
                    "installs": len(xs),
                    "returned_d1": ret,
                    "lapse": (sum(i.lapses for i in xs), sum(i.tested for i in xs)),
                    "per_install": [(i.lapses, i.tested) for i in xs if i.tested],
                }
            )
        if len(arms) == 2:
            x, y = row["arms"]
            row["p_return"] = two_proportion_p(
                x["returned_d1"], x["installs"], y["returned_d1"], y["installs"]
            )
            row["lapse_diff"] = bootstrap_diff(x["per_install"], y["per_install"])
            enough = min(x["installs"], y["installs"]) >= MIN_INSTALLS_PER_ARM
            lo, hi = row["lapse_diff"][1:]
            if not enough:
                row["verdict"] = "still collecting"
            elif row["p_return"] < 0.05:
                better = (
                    y if y["returned_d1"] / y["installs"] > x["returned_d1"] / x["installs"] else x
                )
                row["verdict"] = f"'{better['arm']}' brings more people back: adopt it"
            elif hi < 0:
                row["verdict"] = f"'{y['arm']}' has fewer lapses: adopt it"
            elif lo > 0:
                row["verdict"] = f"'{x['arm']}' has fewer lapses: keep it"
            else:
                row["verdict"] = "no difference found: keep the simpler arm and end the test"
        out.append(row)
    return out


def _pct(k: float, n: float) -> str:
    return f"{100 * k / n:.0f}%" if n else "–"


def _newcomer_section(events: list[dict]) -> list[str]:
    """Newcomer practice (content/practice.yaml): replies understood, tones heard,
    sentences said, challenges done, and the weakest replies and tone sets."""
    by: dict[str, list[bool]] = {"listen": [], "tone": [], "frame": []}
    missed: Counter = Counter()
    heard: Counter = Counter()
    tone_ok: dict[str, list[bool]] = defaultdict(list)
    challenges: Counter = Counter()
    for e in events:
        p = e.get("payload") or {}
        typ = e.get("type")
        if typ == "listen.answer" and isinstance(p.get("id"), str):
            ok = p.get("correct") is True
            by["listen"].append(ok)
            heard[p["id"]] += 1
            missed[p["id"]] += not ok
        elif typ == "tone.answer" and isinstance(p.get("set"), str):
            ok = p.get("correct") is True
            by["tone"].append(ok)
            tone_ok[p["set"]].append(ok)
        elif typ == "frame.say":
            by["frame"].append(p.get("ok") is True)
        elif typ == "challenge.done" and isinstance(p.get("id"), str):
            challenges[p["id"]] += 1
    if not any(by.values()) and not challenges:
        return []

    def share(v: list[bool]) -> str:
        return f"{len(v)} ({_pct(sum(v), len(v))} right)" if v else "0"

    lines = [
        "## Newcomer practice",
        "",
        "| | Answers |",
        "|---|---|",
        f"| Understand replies | {share(by['listen'])} |",
        f"| Hear the tones | {share(by['tone'])} |",
        f"| Build a sentence (said it) | {share(by['frame'])} |",
        f"| Real-world challenges done | {sum(challenges.values())} |",
        "",
    ]
    hard = [(r, missed[r], heard[r]) for r in heard if heard[r] >= 3 and missed[r]]
    hard.sort(key=lambda t: -t[1] / t[2])
    if hard:
        lines += ["Replies most often misheard (at least 3 tries):", "",
                  "| Reply | Missed | Tries |", "|---|---|---|"]  # fmt: skip
        lines += [f"| {r} | {m} | {h} |" for r, m, h in hard[:10]]
        lines.append("")
    tones = [(s, v) for s, v in tone_ok.items() if len(v) >= 5]
    tones.sort(key=lambda t: sum(t[1]) / len(t[1]))
    if tones:
        lines += ["Tone sets, weakest first (at least 5 tries):", "",
                  "| Set | Heard right | Tries |", "|---|---|---|"]  # fmt: skip
        lines += [f"| {s} | {_pct(sum(v), len(v))} | {len(v)} |" for s, v in tones[:10]]
        lines.append("")
    return lines


def report(events: list[dict], crashes: list[dict]) -> str:
    a = analyse(events)
    inst = list(a["installs"].values())
    n = len(inst)
    lines = [
        "# DuckLearn usage report",
        "",
        f"{len(events)} events from {n} installs, {len(crashes)} crash reports. "
        "Generated by `duk telemetry report`; see docs/TELEMETRY.md for what each number means.",
        "",
    ]
    if not n:
        lines += [
            "No data yet. Run `duk telemetry pull` once people have used a build with sharing."
        ]
        return "\n".join(lines) + "\n"

    speakers = sum(i.speaker is True for i in inst)
    learners = sum(i.speaker is False for i in inst)
    d1 = sum(_returned(i, 1) for i in inst)
    d7 = sum(_returned(i, 7) for i in inst)
    done1 = sum(i.first_session_done for i in inst)
    tested = sum(i.tested for i in inst)
    lapses = sum(i.lapses for i in inst)
    lines += [
        "## Who and how often",
        "",
        "| | |",
        "|---|---|",
        f"| Installs | {n} ({speakers} speakers, {learners} learners, "
        f"{n - speakers - learners} unknown) |",
        f"| Finished their first session | {done1} ({_pct(done1, n)}) |",
        f"| Came back on a later day | {d1} ({_pct(d1, n)}) |",
        f"| Still reading a week later | {d7} ({_pct(d7, n)}) |",
        f"| Median sessions per install | {statistics.median([i.sessions for i in inst]):.0f} |",
        f"| Characters read on their own | {tested - lapses} of {tested} tested "
        f"({_pct(tested - lapses, tested)}) |",
    ]
    if a["read_ms"]:
        lines.append(
            "| Median time reading a sentence before Check | "
            f"{statistics.median(a['read_ms']) / 1000:.1f} s |"
        )
    lines.append("")

    # experiments
    lines += ["## Experiments", ""]
    for row in experiment_rows(a):
        lines.append(f"### {row['id']} ({row['who']})")
        lines.append("")
        lines.append("| Arm | Installs | Came back | Lapse rate (95% CI) |")
        lines.append("|---|---|---|---|")
        for arm in row["arms"]:
            k, t = arm["lapse"]
            lo, hi = wilson(k, t)
            lines.append(
                f"| {arm['arm']} | {arm['installs']} | "
                f"{_pct(arm['returned_d1'], arm['installs'])} | "
                f"{_pct(k, t)} ({100 * lo:.0f}–{100 * hi:.0f}%) |"
            )
        if "verdict" in row:
            d, lo, hi = row["lapse_diff"]
            lines += [
                "",
                f"Came back: p = {row['p_return']:.3f}. Lapse rate difference "
                f"({row['arms'][1]['arm']} − {row['arms'][0]['arm']}): {100 * d:+.1f} points "
                f"(95% CI {100 * lo:+.1f} to {100 * hi:+.1f}, resampled by install).",
                "",
                f"**Verdict: {row['verdict']}.**",
            ]
            if row["verdict"] == "still collecting":
                base = row["arms"][0]
                p0 = base["returned_d1"] / base["installs"] if base["installs"] else 0.4
                need = installs_needed(min(max(p0, 0.05), 0.95), 0.15)
                lines.append(
                    f"To see a 15-point change in coming back needs about {need} installs per arm "
                    f"(minimum to decide here: {MIN_INSTALLS_PER_ARM})."
                )
        lines.append("")

    # characters
    rows = [(ch, a["char_lapses"][ch], r) for ch, r in a["char_reads"].items() if r >= MIN_READS]
    # rank by the lower end of the interval: hard for sure, not hard by chance
    rows.sort(key=lambda x: -wilson(x[1], x[2])[0])
    lines += [
        "## Hardest characters",
        "",
        f"Most often revealed or marked wrong, at least {MIN_READS} tested reads. "
        "These are the ones to give more practice (sound families, flashcards) or a mnemonic note.",
        "",
        "| Character | Reading | Lapses | Reads | Rate |",
        "|---|---|---|---|---|",
    ]
    for ch, k, r in rows[:25]:
        parts = ch.split(":")
        lines.append(
            f"| {parts[2] if len(parts) == 4 else ch} | {parts[3] if len(parts) == 4 else ''} "
            f"| {k} | {r} | {_pct(k, r)} |"
        )
    if not rows:
        lines.append("| (not enough reads yet) | | | | |")
    lines.append("")

    srows = [
        (sid, a["sent_lapses"][sid], a["sent_skips"][sid], shown)
        for sid, shown in a["sent_shown"].items()
        if shown >= MIN_READS
    ]
    srows.sort(key=lambda x: -(x[1] + 2 * x[2]) / x[3])
    lines += [
        "## Sentences to look at",
        "",
        "Many lapses or skips per showing: too hard for where they sit in the path, a wrong "
        "reading, or a confusing line. Check the reading first, then consider moving it later "
        "or rewriting it.",
        "",
        "| Sentence | Shown | Lapses | Skips |",
        "|---|---|---|---|",
    ]
    for sid, k, sk, shown in srows[:20]:
        lines.append(f"| {sid} | {shown} | {k} | {sk} |")
    if not srows:
        lines.append("| (not enough showings yet) | | | |")
    lines.append("")

    lines += _newcomer_section(events)

    lines += ["## Where people go", "", "| Screen | Opens |", "|---|---|"]
    for s, c in a["screens"].most_common(15):
        lines.append(f"| {s} | {c} |")
    lines.append("")

    groups: Counter = Counter()
    versions: dict = defaultdict(set)
    for c in crashes:
        top = next(
            (ln.strip() for ln in (c.get("stack") or "").splitlines() if "package:duk" in ln), ""
        )
        key = (c.get("error_type") or "?", (c.get("message") or "")[:80], top[:120])
        groups[key] += 1
        versions[key].add(c.get("app_version"))
    lines += [
        "## Crashes",
        "",
        "| Count | Error | Message | Where | Versions |",
        "|---|---|---|---|---|",
    ]
    for (et, msg, top), cnt in groups.most_common(20):
        msg = msg.replace("|", "/").replace("\n", " ")
        lines.append(
            f"| {cnt} | {et} | {msg} | {top.replace('|', '/')} | "
            f"{', '.join(sorted(v for v in versions[(et, msg, top)] if v))} |"
        )
    if not groups:
        lines.append("| 0 | none reported | | | |")
    lines.append("")
    return "\n".join(lines) + "\n"


def write_report(folder: Path = TELEMETRY, out: Path = REPORT) -> Path:
    events, crashes = load(folder)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(report(events, crashes), "utf-8")
    return out

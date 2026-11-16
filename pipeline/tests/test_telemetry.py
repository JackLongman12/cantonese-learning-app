"""The usage report on made-up data (no network)."""

from duk import telemetry as tm


def _ev(iid, ts, typ, **payload):
    return {"install_id": iid, "ts_utc": ts, "tz_offset_min": 480, "type": typ, "payload": payload}


def _install(iid, arm, *, lapse_every, came_back):
    ev = [
        _ev(
            iid,
            "2026-11-17T01:00:00.000Z",
            "experiment.assigned",
            arms={"first_session": arm, "meaning_after_check": "shown"},
        ),
        _ev(iid, "2026-11-17T01:00:01.000Z", "onboarding.done", speaker=True),
        _ev(iid, "2026-11-17T01:00:02.000Z", "session.start"),
        _ev(
            iid,
            "2026-11-17T01:00:03.000Z",
            "item.shown",
            exposure_id=f"{iid}-1",
            sentence_id="sent-1",
        ),
        _ev(iid, "2026-11-17T01:00:04.000Z", "item.check", exposure_id=f"{iid}-1", read_ms=3000),
    ]
    for k in range(10):
        sig = "missed" if k % lapse_every == 0 else "noReveal"
        ev.append(
            _ev(
                iid,
                "2026-11-17T01:00:05.000Z",
                "review.applied",
                exposure_id=f"{iid}-1",
                item_id="cr:yue:銀:ngan4",
                signal=sig,
            )
        )
    ev.append(_ev(iid, "2026-11-17T01:01:00.000Z", "session.end", reason="done"))
    if came_back:
        ev.append(_ev(iid, "2026-11-18T01:00:00.000Z", "session.start"))
    return ev


def test_statistics_helpers():
    lo, hi = tm.wilson(5, 10)
    assert 0.2 < lo < 0.5 < hi < 0.8
    assert tm.wilson(0, 0) == (0.0, 1.0)
    assert tm.two_proportion_p(50, 100, 50, 100) == 1.0
    assert tm.two_proportion_p(80, 100, 20, 100) < 0.001
    assert tm.installs_needed(0.4, 0.15) > 100
    d, lo, hi = tm.bootstrap_diff([(1, 10)] * 20, [(5, 10)] * 20)
    assert abs(d - 0.4) < 1e-9 and lo > 0


def test_report_from_events():
    events = []
    for k in range(40):
        events += _install(f"a{k}", "short", lapse_every=2, came_back=k % 4 == 0)
        events += _install(f"b{k}", "longer", lapse_every=5, came_back=k % 4 != 0)
    crashes = [
        {
            "error_type": "StateError",
            "message": "boom",
            "stack": "#0 x (package:duk/ui/a.dart:1)",
            "app_version": "b2070",
        }
    ] * 3
    md = tm.report(events, crashes)
    assert "| Installs | 80 (80 speakers" in md
    assert "### first_session" in md
    # 'longer' brings far more people back in this data
    assert "'longer' brings more people back" in md
    assert "| 銀 | ngan4 |" in md
    assert "| 3 | StateError | boom |" in md


def test_small_samples_are_not_decided():
    events = []
    for k in range(5):
        events += _install(f"a{k}", "short", lapse_every=2, came_back=False)
        events += _install(f"b{k}", "longer", lapse_every=5, came_back=True)
    assert "still collecting" in tm.report(events, [])


def test_empty_report():
    assert "No data yet" in tm.report([], [])

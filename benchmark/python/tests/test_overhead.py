from overhead import samples


def test_samples_keeps_only_the_lane_asked_for_in_run_order():
    rows = [
        {"mode": "get", "boxKind": "eager", "impl": "facade", "micros": 3},
        {"mode": "get", "boxKind": "eager", "impl": "raw", "micros": 2},
        {"mode": "get", "boxKind": "eager", "impl": "facade"},
        {"mode": "get", "boxKind": "eager", "impl": "facade", "micros": 1},
    ]
    assert samples(rows, mode="get", box_kind="eager", impl="facade") == [3, 1]

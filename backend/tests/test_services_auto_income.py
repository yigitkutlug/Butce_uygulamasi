from app.services.auto_income import _month_range, _next_month_key, previous_month_key


def test_next_and_previous_month_keys_cross_year():
    assert _next_month_key("2026-12") == "2027-01"
    assert previous_month_key("2026-01") == "2025-12"


def test_month_range_includes_start_and_end():
    assert _month_range("2026-05", "2026-07") == ["2026-05", "2026-06", "2026-07"]

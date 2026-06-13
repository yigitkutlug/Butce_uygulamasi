from app.services.alerts import _is_triggered


def test_is_triggered_above_condition():
    assert _is_triggered(current_price=101, target_price=100, condition="above") is True
    assert _is_triggered(current_price=99, target_price=100, condition="above") is False


def test_is_triggered_below_condition():
    assert _is_triggered(current_price=99, target_price=100, condition="below") is True
    assert _is_triggered(current_price=101, target_price=100, condition="below") is False

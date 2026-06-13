from app.services.transactions import _normalize_account, _predict_income_category


def test_normalize_account_defaults_and_known_values():
    assert _normalize_account(None) == "Card"
    assert _normalize_account("nakit") == "Cash"
    assert _normalize_account("iban") == "IBAN"


def test_predict_income_category_keyword_based():
    assert _predict_income_category("maas odemesi geldi") == "Salary"
    assert _predict_income_category("burs yatti") == "Scholarship"

from app.services.coach import (
    _extract_installment_count,
    _extract_product_label,
    _find_amount,
    _find_expression_amount,
    _has_explicit_purchase_amount,
    _is_finance_related,
    _is_installment_planning_prompt,
    _looks_like_product_research_prompt,
    _resolve_monthly_installment,
    _wants_current_product_price,
)


def test_find_expression_amount_with_multiplication_pattern():
    assert _find_expression_amount("20x400") == 8000
    assert _find_expression_amount("20 * 400") == 8000


def test_find_amount_with_currency_pattern():
    assert _find_amount("bunu 3499.90 tl alirsam") == 3499.90


def test_extract_installment_count():
    assert _extract_installment_count("9 taksite bolsen") == 9
    assert _extract_installment_count("3 ay taksit olur mu") == 3


def test_monthly_installment_amount_is_total_not_month_count():
    message = "9 ay aylik 3000 tl taksitle macbook alcam"

    assert _extract_installment_count(message) == 9
    assert _find_amount(message) == 27000
    assert _resolve_monthly_installment(message, 27000, 9) == 3000


def test_product_research_prompt_detection():
    assert _looks_like_product_research_prompt("macbook almak istiyorum")
    assert _looks_like_product_research_prompt("macbook air m2")
    assert _looks_like_product_research_prompt("akilli saat istiyorum")
    assert _looks_like_product_research_prompt("iphone 17 fiyat ne kadar")
    assert _looks_like_product_research_prompt("iphone 17 128 gb")
    assert not _looks_like_product_research_prompt("selam nasilsin")


def test_product_model_number_is_not_purchase_amount():
    assert not _has_explicit_purchase_amount("iphone 17 fiyat nedir")
    assert not _has_explicit_purchase_amount("iphone 17 128 gb")
    assert not _has_explicit_purchase_amount("macbook air m2")
    assert not _has_explicit_purchase_amount("macbook air m2 almak istiyorum")
    assert _has_explicit_purchase_amount("iphone 17 65000 tl alirsam")


def test_product_price_question_detection():
    assert _wants_current_product_price("iphone 17 fiyat nedir")
    assert not _wants_current_product_price("akilli saat istiyorum")


def test_extract_product_label_removes_intent_and_money():
    assert _extract_product_label("akilli saat istiyorum") == "akilli saat"
    assert _extract_product_label("iphone 17 65000 tl alirsam") == "iphone 17"


def test_finance_scope_filter():
    assert not _is_finance_related("recep tayyip erdogan kimdir")
    assert not _is_finance_related("bana siir yazar misin")
    assert _is_finance_related("akilli saat istiyorum")
    assert _is_finance_related("5000 tl ayirabilirim")


def test_installment_planning_prompt_detection():
    assert _is_installment_planning_prompt(
        "40,000 tl lik alisveris yapcam kac taksite bolmem lazim butcem icin"
    )
    assert not _is_installment_planning_prompt("40000 tl telefon alirsam")

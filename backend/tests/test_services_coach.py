from app.services.coach import (
    _extract_installment_count,
    _extract_product_label,
    _find_amount,
    _find_expression_amount,
    _has_explicit_purchase_amount,
    _affordability_status,
    _build_affordability_reply,
    _estimated_market_quote,
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


def test_affordability_status_uses_safe_installment_limit():
    assert _affordability_status(3100, 3000) == ("uygun değil", "danger")
    assert _affordability_status(2600, 3000) == ("riskli", "warning")
    assert _affordability_status(1500, 3000) == ("alınabilir", "safe")


def test_product_affordability_reply_uses_estimated_price_range():
    reply = _build_affordability_reply(
        "iPhone",
        {
            "price_verified": False,
            "price_type": "estimated",
            "price_min_try": 35000,
            "price_max_try": 45000,
            "price_note": "Tahmini piyasa aralığı.",
            "alternatives": ["daha uygun telefon"],
        },
        remaining=10000,
        monthly_debt=0,
        installment_count=12,
    )

    assert "tahmini piyasa fiyat aralığı" in reply["reply"]
    assert "kesin değil" in reply["reply"]
    assert reply["risk_level"] in {"warning", "danger", "safe"}


def test_product_affordability_reply_uses_unavailable_only_as_last_resort():
    reply = _build_affordability_reply(
        "bilinmeyen ürün",
        {
            "price_type": "unavailable",
            "alternatives": [],
        },
        remaining=10000,
        monthly_debt=0,
        installment_count=12,
    )

    assert "güvenilir güncel fiyat veya makul piyasa aralığı bulamadım" in reply["reply"]
    assert reply["risk_level"] == "info"


def test_product_affordability_reply_marks_installment_above_limit_danger():
    reply = _build_affordability_reply(
        "iPhone",
        {
            "product_name": "iPhone",
            "price_verified": True,
            "price_min_try": 60000,
            "price_max_try": 60000,
            "alternatives": ["iPhone SE"],
            "sources": ["Apple"],
        },
        remaining=10000,
        monthly_debt=0,
        installment_count=12,
    )

    assert "uygun değil" in reply["reply"]
    assert "güvenli aylık taksit limitin 3000.00 TL" in reply["reply"]
    assert reply["risk_level"] == "danger"


def test_estimated_market_quote_returns_helpful_range_for_known_product():
    quote = _estimated_market_quote("iPhone almak istiyorum")

    assert quote is not None
    assert quote["price_type"] == "estimated"
    assert quote["price_min_try"] > 0

import asyncio
import json
import logging
import math
import re
import urllib.error
import urllib.parse
import urllib.request

from app.core.config import settings
from app.services.analytics import get_summary

logger = logging.getLogger(__name__)

_LAST_AMOUNT_BY_USER: dict[str, float] = {}
_LAST_PRODUCT_BY_USER: dict[str, str] = {}

_KNOWN_PRODUCT_WORDS = [
    "iphone",
    "macbook",
    "ipad",
    "airpods",
    "apple watch",
    "akıllı saat",
    "akilli saat",
    "smartwatch",
    "telefon",
    "laptop",
    "bilgisayar",
    "tablet",
    "ps5",
    "playstation",
    "xbox",
    "televizyon",
    "tv",
    "kulaklık",
    "kulaklik",
]

_PRODUCT_RESEARCH_WORDS = [
    "almak",
    "alicam",
    "alcam",
    "alacağım",
    "alacagim",
    "alsam",
    "istiyorum",
    "fiyat",
    "kaç para",
    "kac para",
    "ne kadar",
]

_FINANCE_KEYWORDS = [
    "bütçe",
    "butce",
    "para",
    "tl",
    "try",
    "lira",
    "harcama",
    "gelir",
    "gider",
    "birikim",
    "tasarruf",
    "taksit",
    "borç",
    "borc",
    "kredi",
    "kart",
    "fatura",
    "abonelik",
    "maaş",
    "maas",
    "almak",
    "alicam",
    "alcam",
    "alsam",
    "istiyorum",
    "fiyat",
    "kaç para",
    "kac para",
    "ne kadar",
    "öde",
    "ode",
]


def _to_float(value: str) -> float | None:
    try:
        return float(value.replace(",", "."))
    except ValueError:
        return None


def _find_expression_amount(message: str) -> float | None:
    text = message.lower().replace("×", "x")
    patterns = [
        r"(\d+(?:[.,]\d+)?)\s*(?:x|\*)\s*(\d+(?:[.,]\d+)?)",
        r"(\d+(?:[.,]\d+)?)\s*adet\s*(\d+(?:[.,]\d+)?)",
        r"(\d+(?:[.,]\d+)?)\s*tane\s*(\d+(?:[.,]\d+)?)",
    ]
    for pattern in patterns:
        match = re.search(pattern, text)
        if not match:
            continue
        left = _to_float(match.group(1))
        right = _to_float(match.group(2))
        if left is not None and right is not None:
            return left * right
    return None


def _find_monthly_installment_amount(message: str) -> tuple[int, float] | None:
    text = message.lower().replace("₺", "tl")
    patterns = [
        r"(\d+)\s*(?:ay|taks\w*)\D{0,30}ayl\w*\s*(\d+(?:[.,]\d+)?)",
        r"ayl\w*\s*(\d+(?:[.,]\d+)?)\D{0,30}(\d+)\s*(?:ay|taks\w*)",
        r"(\d+)\s*(?:ay|taks\w*)\D{0,30}(\d+(?:[.,]\d+)?)\s*(?:tl|try|lira)",
    ]
    for index, pattern in enumerate(patterns):
        match = re.search(pattern, text)
        if not match:
            continue
        first = _to_float(match.group(1))
        second = _to_float(match.group(2))
        if first is None or second is None:
            continue
        if index == 1:
            monthly_amount = first
            count = int(second)
        else:
            count = int(first)
            monthly_amount = second
        if count > 1 and monthly_amount > 0:
            return count, monthly_amount
    return None


def _find_amount(message: str) -> float | None:
    monthly_installment = _find_monthly_installment_amount(message)
    if monthly_installment is not None:
        count, monthly_amount = monthly_installment
        return count * monthly_amount

    expression_amount = _find_expression_amount(message)
    if expression_amount is not None:
        return expression_amount

    matches = re.findall(r"(\d+(?:[.,]\d+)?)\s*(?:tl|try|₺|usd|eur)?", message.lower())
    if not matches:
        return None
    return _to_float(matches[0])


def _has_explicit_purchase_amount(message: str) -> bool:
    text = message.lower().replace("₺", "tl")
    if _find_monthly_installment_amount(text) is not None:
        return True
    if _find_expression_amount(text) is not None:
        return True
    money_patterns = [
        r"(?:tl|try|usd|eur|lira)\s*\d+(?:[.,]\d+)?",
        r"\d+(?:[.,]\d+)?\s*(?:tl|try|usd|eur|lira)",
    ]
    return any(re.search(pattern, text) for pattern in money_patterns)


def _extract_installment_count(message: str) -> int | None:
    monthly_installment = _find_monthly_installment_amount(message)
    if monthly_installment is not None:
        return monthly_installment[0]

    text = message.lower()
    patterns = [
        r"(\d+)\s*taks\w*",
        r"(\d+)\s*ay\w*",
    ]
    for pattern in patterns:
        match = re.search(pattern, text)
        if not match:
            continue
        try:
            count = int(match.group(1))
        except ValueError:
            continue
        if count > 1:
            return count
    return None


def _find_all_numbers(message: str) -> list[float]:
    values: list[float] = []
    for raw in re.findall(r"\d+(?:[.,]\d+)?", message.lower()):
        parsed = _to_float(raw)
        if parsed is not None:
            values.append(parsed)
    return values


def _resolve_amount(user_id: str, message: str, installment_count: int | None) -> float | None:
    amount = _find_amount(message)
    if installment_count is not None:
        numbers = _find_all_numbers(message)
        # "9 taksite bölsen" gibi cümlelerde tek sayı genelde fiyat değil taksit adedi.
        if len(numbers) == 1 and int(numbers[0]) == installment_count:
            amount = None
        if amount is None:
            amount = _LAST_AMOUNT_BY_USER.get(user_id)
    if amount is not None and amount > 0:
        _LAST_AMOUNT_BY_USER[user_id] = amount
    return amount


def _resolve_monthly_installment(message: str, amount: float | None, installment_count: int | None) -> float | None:
    monthly_installment = _find_monthly_installment_amount(message)
    if monthly_installment is not None:
        return monthly_installment[1]
    if amount is not None and installment_count is not None and installment_count > 1:
        return amount / installment_count
    return None


def _is_greeting(message: str) -> bool:
    text = message.lower()
    return any(word in text for word in ["selam", "merhaba", "hey", "hi", "hello", "naber"])


def _is_investment_prompt(message: str) -> bool:
    text = message.lower()
    keywords = ["yatırım", "hisse", "coin", "kripto", "borsa", "al-sat", "altın", "fon", "trade"]
    return any(k in text for k in keywords)


def _is_installment_planning_prompt(message: str) -> bool:
    text = message.lower()
    installment_words = ["taksit", "taksitle", "bol", "böl", "kac ay", "kaç ay", "aylik", "aylık"]
    budget_words = ["butce", "bütçe", "zorlar", "ode", "öde", "kalan", "gelir"]
    return any(word in text for word in installment_words) and any(
        word in text for word in budget_words
    )


def _installment_planning_reply(amount: float, remaining: float | None) -> dict:
    if remaining is None or remaining <= 0:
        return {
            "reply": (
                f"{amount:.2f} TL tutarlı alışveriş için kaç taksitin uygun olduğunu hesaplamak istiyorum, "
                "ama aylık gelir hedefin veya kalan bütçen net değil. Profilindeki aylık gelir hedefini güncellersen "
                "daha doğru taksit önerisi yapabilirim."
            ),
            "remaining_budget": round(remaining, 2) if remaining is not None else None,
            "risk_level": "warning",
        }

    comfortable_payment = max(remaining * 0.25, 1)
    upper_payment = max(remaining * 0.40, 1)
    comfortable_months = max(1, math.ceil(amount / comfortable_payment))
    upper_months = max(1, math.ceil(amount / upper_payment))
    risk_level = "danger" if amount > remaining * 2 else "warning" if amount > remaining else "safe"

    return {
        "reply": (
            f"{amount:.2f} TL alışveriş için mevcut kalan bütçen yaklaşık {remaining:.2f} TL. "
            f"Rahat kalmak için aylık taksiti yaklaşık {comfortable_payment:.2f} TL civarında tutarsan "
            f"yaklaşık {comfortable_months} taksit gerekir. "
            f"Daha agresif ama kontrollü seçenek olarak aylık {upper_payment:.2f} TL civarı ödersen "
            f"yaklaşık {upper_months} taksit olur. "
            "Benim önerim, acil değilse daha uzun vadeyi seçip ay sonunda nakit payını koruman."
        ),
        "remaining_budget": round(remaining, 2),
        "risk_level": risk_level,
    }


def _is_finance_related(message: str) -> bool:
    text = message.lower()
    if _is_greeting(text):
        return True
    if _contains_known_product(text):
        return True
    if _has_explicit_purchase_amount(text) or _find_expression_amount(text) is not None:
        return True
    return any(keyword in text for keyword in _FINANCE_KEYWORDS)


def _out_of_scope_reply(remaining: float | None) -> dict:
    return {
        "reply": (
            "Ben finansal koç olarak yardımcı oluyorum. "
            "Bütçe, harcama, taksit, birikim, borç, ürün satın alma kararı veya aylık planınla ilgili bir soru sorarsan yardımcı olayım."
        ),
        "remaining_budget": round(remaining, 2) if remaining is not None else None,
        "risk_level": "info",
    }


def _contains_known_product(message: str) -> bool:
    text = message.lower()
    return any(word in text for word in _KNOWN_PRODUCT_WORDS)


def _looks_like_product_research_prompt(message: str) -> bool:
    text = message.lower()
    if not _contains_known_product(text):
        return False
    if any(word in text for word in _PRODUCT_RESEARCH_WORDS):
        return True
    # "macbook air m2", "iphone 17 128 gb" gibi kısa ürün/model mesajları.
    return len(text.split()) <= 6


def _wants_current_product_price(message: str) -> bool:
    text = message.lower()
    price_words = ["fiyat", "kaç para", "kac para", "ne kadar", "güncel", "guncel"]
    return _contains_known_product(text) and any(word in text for word in price_words)


def _extract_product_label(message: str) -> str:
    text = message.strip()
    text = re.sub(
        r"(?:tl|try|usd|eur|lira)\s*\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)?\s*(?:tl|try|usd|eur|lira)",
        "",
        text,
        flags=re.IGNORECASE,
    )
    cleaned = re.sub(
        r"\b(almak|alicam|alcam|alacağım|alacagim|alsam|alırsam|alirsam|istiyorum|fiyat|nedir|ne kadar|kaç para|kac para)\b",
        "",
        text,
        flags=re.IGNORECASE,
    )
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .,:;")
    return cleaned or text


def _product_budget_question_reply(product: str, remaining: float | None) -> dict:
    return {
        "reply": (
            f"{product} için önce bütçeni netleştirelim. "
            "En fazla ne kadar harcayabilirsin? Peşin mi alacaksın, taksitli mi? "
            "Ayrıca önceliğin ne: pil, ekran, spor takibi, marka, garanti veya fiyat/performans?"
        ),
        "remaining_budget": round(remaining, 2) if remaining is not None else None,
        "risk_level": "info",
    }


def _build_product_research_prompt(user_message: str, budget_context: str) -> str:
    return f"""
Sen bir Türkçe bütçe ve ürün araştırma asistanısın.
Google Search ile güncel Türkiye fiyatlarını ve ürün seçeneklerini kontrol et.

Kurallar:
- Türkçe cevap ver.
- 4-7 kısa cümle yaz.
- Ürün belirsizse 2-4 makul seçenek/model belirt.
- Güncel fiyatları net tek fiyat gibi değil, yaklaşık aralık olarak ver.
- Fiyatların mağaza, stok, kampanya ve depolama/konfigürasyona göre değişebileceğini söyle.
- Kullanıcıya bütçe analizi için "peşin mi, taksitli mi; taksitliyse kaç ay ve aylık kaç TL?" diye sor.
- Kaynak gördüysen cevabın sonunda en fazla 2 kısa kaynak adı belirt.
- Yatırım tavsiyesi verme.

Bütçe bağlamı:
{budget_context}

Kullanıcı mesajı:
{user_message}
"""


def _build_product_recommendation_prompt(
    product: str,
    amount: float,
    user_message: str,
    budget_context: str,
) -> str:
    return f"""
Sen bir Türkçe bütçe ve ürün öneri asistanısın.
Google Search ile güncel Türkiye fiyatlarını kontrol ederek cevap ver.

Kullanıcının ilgilendiği ürün: {product}
Kullanıcının belirttiği bütçe/tutar: {amount:.2f} TL

Kurallar:
- Türkçe cevap ver.
- 4-7 kısa cümle yaz.
- Bütçeye uygun 2-4 ürün/model veya segment öner.
- Net tek fiyat uydurma; yaklaşık fiyat aralığı söyle.
- Bütçe yetmiyorsa ikinci el/indirim/taksit veya daha düşük segment alternatifi öner.
- Sonunda "peşin mi taksitli mi alacaksın?" diye sor.
- Kaynak gördüysen cevabın sonunda en fazla 2 kısa kaynak adı belirt.

Bütçe bağlamı:
{budget_context}

Kullanıcı mesajı:
{user_message}
"""


def _product_recommendation_fallback(
    product: str,
    amount: float,
    remaining: float | None,
    installment_count: int | None = None,
) -> dict:
    after_purchase = (remaining - amount) if remaining is not None else None
    budget_sentence = (
        f"Bu harcama sonrası tahmini kalan bütçen {after_purchase:.2f} TL olur."
        if after_purchase is not None
        else "Aylık gelir hedefin olmadığı için bütçe riskini net hesaplayamıyorum."
    )
    if installment_count is not None and installment_count > 1:
        monthly_payment = amount / installment_count
        budget_sentence = (
            f"{installment_count} taksitte aylık yaklaşık {monthly_payment:.2f} TL ödersin. "
            f"Bu ayki taksit sonrası tahmini kalan bütçen "
            f"{((remaining - monthly_payment) if remaining is not None else 0):.2f} TL olur."
            if remaining is not None
            else f"{installment_count} taksitte aylık yaklaşık {monthly_payment:.2f} TL ödersin."
        )

    return {
        "reply": (
            f"{product} için {amount:.2f} TL bütçeyi baz alıyorum. "
            f"{budget_sentence} "
            "Bu bütçede fiyat/performans odaklı modellere, garanti durumuna ve kullanıcı yorumlarına bakmanı öneririm. "
            "İstersen marka tercihini ve peşin mi taksitli mi alacağını yaz, daha net eleme yapayım."
        ),
        "remaining_budget": round(after_purchase, 2) if after_purchase is not None else None,
        "risk_level": (
            "danger"
            if after_purchase is not None and after_purchase < 0
            else "warning"
            if after_purchase is not None and remaining is not None and after_purchase <= remaining * 0.3
            else "info"
        ),
    }


async def _try_gemini_reply(
    prompt: str,
    user_message: str,
    use_google_search: bool = False,
) -> str | None:
    try:
        text, finish_reason = await asyncio.to_thread(
            _gemini_request_sync,
            prompt,
            use_google_search,
        )
    except Exception:
        logger.exception("Gemini reply generation failed.")
        return None

    if not text:
        return None
    if finish_reason and finish_reason != "STOP":
        continued = await asyncio.to_thread(_continue_answer_sync, text, user_message)
        if continued:
            text = continued
    if _looks_incomplete_answer(text):
        repaired = await asyncio.to_thread(_repair_incomplete_answer_sync, text)
        if repaired:
            text = repaired
    return text


def _product_research_unavailable_reply(message: str, remaining: float | None) -> dict:
    return {
        "reply": (
            "Bu ürün için güncel fiyat araştırması yapmam gerekiyor ama şu an canlı arama cevabı alamadım. "
            "Modeli biraz daha net yazarsan tekrar deneyebilirim; örn: 'MacBook Air M2 256 GB' veya "
            "'iPhone 17 128 GB'. Fiyatı bulduktan sonra peşin mi taksitli mi almak istediğini sorup "
            "bütçene etkisini hesaplayacağım."
        ),
        "remaining_budget": round(remaining, 2) if remaining is not None else None,
        "risk_level": "info",
    }


def _fallback_reply(
    message: str,
    remaining: float | None,
    amount_override: float | None = None,
    installment_count: int | None = None,
) -> dict:
    text = message.strip()
    if _is_greeting(text):
        return {
            "reply": (
                "Selam. Ben bütçe koçun. "
                "Ne almak istediğini ve yaklaşık fiyatını yazarsan, aylık bütçene etkisini hesaplarım."
            ),
            "remaining_budget": round(remaining, 2) if remaining is not None else None,
            "risk_level": "info",
        }

    if _is_investment_prompt(text):
        return {
            "reply": (
                "Yatırım tavsiyesi veremem. Ama bu kararın bütçeni zorlayıp zorlamayacağını hesaplayabilirim. "
                "Tutarı yazarsan aylık limit açısından risk analizi yaparım."
            ),
            "remaining_budget": round(remaining, 2) if remaining is not None else None,
            "risk_level": "info",
        }

    amount = amount_override if amount_override is not None else _find_amount(text)
    if amount is None:
        if installment_count is not None:
            return {
                "reply": (
                    f"{installment_count} taksit için aylık tutarı hesaplayabilirim. "
                    "Toplam ürün fiyatını da yazarsan net hesaplayayım."
                ),
                "remaining_budget": round(remaining, 2) if remaining is not None else None,
                "risk_level": "info",
            }
        return {
            "reply": (
                "Bunu bütçe açısından hesaplayabilmem için yaklaşık tutarı da yaz. "
                "Örn: '3500 TL' veya 'bunu 1200 liraya alsam ne olur?'"
            ),
            "remaining_budget": round(remaining, 2) if remaining is not None else None,
            "risk_level": "info",
        }

    monthly_installment = _resolve_monthly_installment(text, amount, installment_count)

    if remaining is None:
        if installment_count is not None and installment_count > 1:
            return {
                "reply": (
                    f"Toplam {amount:.2f} tutar {installment_count} taksitte aylık "
                    f"yaklaşık {(monthly_installment or 0):.2f} olur. "
                    "Aylık gelir hedefin ayarlı olmadığı için risk seviyesini net hesaplayamıyorum."
                ),
                "remaining_budget": None,
                "risk_level": "warning",
            }
        return {
            "reply": (
                f"Yaklaşık {amount:.2f} tutarlı bir harcama için analiz yaptım. "
                "Aylık gelir hedefin ayarlı değil; risk seviyesini net hesaplayamıyorum. "
                "Profil ekranından aylık gelir hedefini girersen daha doğru analiz veririm."
            ),
            "remaining_budget": None,
            "risk_level": "warning",
        }

    if installment_count is not None and installment_count > 1:
        monthly_payment = monthly_installment or (amount / installment_count)
        after_purchase = remaining - monthly_payment
        risk_level = "danger" if after_purchase < 0 else "warning" if after_purchase <= remaining * 0.3 else "safe"
        return {
            "reply": (
                f"Toplam borç {amount:.2f}. {installment_count} ay boyunca aylık yaklaşık "
                f"{monthly_payment:.2f} ödersin. "
                f"Bu ayki taksit sonrası tahmini kalan bütçe: {after_purchase:.2f}."
            ),
            "remaining_budget": round(after_purchase, 2),
            "risk_level": risk_level,
        }

    after_purchase = remaining - amount
    if remaining <= 0:
        return {
            "reply": (
                f"Bu ay zaten bütçe limitinin üstündesin. {amount:.2f} tutarlı ek harcama riski artırır."
            ),
            "remaining_budget": round(after_purchase, 2),
            "risk_level": "danger",
        }

    if after_purchase < 0:
        overflow = abs(after_purchase)
        return {
            "reply": (
                f"Bu alışverişi yaparsan aylık bütçeni yaklaşık {overflow:.2f} kadar aşabilirsin. "
                "Daha düşük tutarlı bir alternatif düşünmek iyi olur."
            ),
            "remaining_budget": round(after_purchase, 2),
            "risk_level": "danger",
        }

    if after_purchase <= remaining * 0.3:
        return {
            "reply": (
                "Alırsan bütçeyi aşmazsın ama ay sonu marjın daralır. "
                f"Kalan tahmini bütçe: {after_purchase:.2f}."
            ),
            "remaining_budget": round(after_purchase, 2),
            "risk_level": "warning",
        }

    return {
        "reply": (
            "Bu harcama mevcut plana göre yönetilebilir görünüyor. "
            f"Alışveriş sonrası tahmini kalan bütçe: {after_purchase:.2f}."
        ),
        "remaining_budget": round(after_purchase, 2),
        "risk_level": "safe",
    }


def _build_budget_context(
    summary: dict,
    message: str,
    detected_amount: float | None = None,
    installment_count: int | None = None,
) -> tuple[float | None, str]:
    monthly_income = float(summary.get("monthly_income_target", 0.0))
    current_month_expense = float(summary.get("current_month_expense", 0.0))
    remaining = monthly_income - current_month_expense if monthly_income > 0 else None
    if detected_amount is not None:
        amount = detected_amount
    elif _looks_like_product_research_prompt(message) and not _has_explicit_purchase_amount(message):
        amount = None
    else:
        amount = _find_amount(message)
    monthly_installment = _resolve_monthly_installment(message, amount, installment_count)
    monthly_budget_impact = monthly_installment if monthly_installment is not None else amount
    after_purchase = (
        remaining - monthly_budget_impact
        if (remaining is not None and monthly_budget_impact is not None)
        else None
    )
    text = (
        f"monthly_income_target={monthly_income:.2f}, "
        f"current_month_expense={current_month_expense:.2f}, "
        f"installment_count={(installment_count if installment_count is not None else 'unknown')}, "
        f"monthly_installment={(f'{monthly_installment:.2f}' if monthly_installment is not None else 'unknown')}, "
        f"remaining_budget={(f'{remaining:.2f}' if remaining is not None else 'unknown')}, "
        f"detected_total_purchase_amount={(f'{amount:.2f}' if amount is not None else 'unknown')}, "
        f"monthly_budget_impact={(f'{monthly_budget_impact:.2f}' if monthly_budget_impact is not None else 'unknown')}, "
        f"remaining_after_purchase={(f'{after_purchase:.2f}' if after_purchase is not None else 'unknown')}"
    )
    return remaining, text


def _extract_grounding_sources(payload: dict) -> list[str]:
    sources: list[str] = []
    for candidate in payload.get("candidates", []):
        metadata = candidate.get("groundingMetadata") or candidate.get("grounding_metadata") or {}
        chunks = metadata.get("groundingChunks") or metadata.get("grounding_chunks") or []
        for chunk in chunks:
            web = chunk.get("web") if isinstance(chunk, dict) else None
            if not isinstance(web, dict):
                continue
            title = str(web.get("title") or "").strip()
            uri = str(web.get("uri") or "").strip()
            label = title or uri
            if label and label not in sources:
                sources.append(label)
            if len(sources) >= 2:
                return sources
    return sources


def _call_gemini_model(prompt: str, model: str, use_google_search: bool = False) -> tuple[str | None, str | None]:
    if not settings.gemini_api_key:
        return None, None

    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={settings.gemini_api_key}"
    )
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.4,
            "maxOutputTokens": 1024,
        },
    }
    if use_google_search:
        body["tools"] = [{"google_search": {}}]
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        candidates = payload.get("candidates", [])
        if not candidates:
            return None, None
        finish_reason = candidates[0].get("finishReason")
        # Collect text from all candidates/parts to avoid partial first-part responses.
        text_chunks = []
        for candidate in candidates:
            parts = candidate.get("content", {}).get("parts", [])
            for part in parts:
                text = part.get("text")
                if isinstance(text, str) and text.strip():
                    text_chunks.append(text.strip())
        if text_chunks:
            text = "\n".join(text_chunks)
            sources = _extract_grounding_sources(payload)
            if sources and "Kaynak" not in text:
                text = f"{text}\n\nKaynaklar: {', '.join(sources)}"
            return text, finish_reason
        return None, finish_reason
    except urllib.error.HTTPError as exc:
        body_text = ""
        try:
            body_text = exc.read().decode("utf-8")[:500]
        except Exception:
            body_text = ""
        logger.warning(
            "Gemini request failed. status=%s model=%s google_search=%s body=%s",
            exc.code,
            model,
            use_google_search,
            body_text,
        )
        if exc.code == 404:
            return None, None
        return None, None
    except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as exc:
        logger.warning(
            "Gemini request failed. model=%s google_search=%s error=%s",
            model,
            use_google_search,
            exc,
        )
        return None, None


def _gemini_request_sync(prompt: str, use_google_search: bool = False) -> tuple[str | None, str | None]:
    preferred = settings.gemini_model.strip() or "gemini-2.5-flash"
    fallbacks = [
        preferred,
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-flash-latest",
    ]
    tried = set()
    for model in fallbacks:
        if model in tried:
            continue
        tried.add(model)
        result, finish_reason = _call_gemini_model(prompt, model, use_google_search=use_google_search)
        if result:
            return result, finish_reason
    return None, None


def _looks_incomplete_answer(text: str) -> bool:
    t = text.strip()
    if not t:
        return True
    if len(t) < 18:
        return True
    return not t.endswith((".", "!", "?", "…"))


def _repair_incomplete_answer_sync(answer: str) -> str | None:
    repair_prompt = (
        "Aşağıdaki metin yarım kalmış olabilir. "
        "Aynı anlamı koruyarak Türkçe, tek parça, tamamlanmış ve doğal bir cevap olarak yeniden yaz:\n\n"
        f"{answer}"
    )
    repaired, _ = _gemini_request_sync(repair_prompt)
    if repaired and not _looks_incomplete_answer(repaired):
        return repaired
    return None


def _continue_answer_sync(answer_so_far: str, user_message: str) -> str | None:
    continue_prompt = (
        "Aşağıdaki yanıt yarım kaldı. "
        "Tekrar etmeden yalnızca eksik kalan kısmı devam ettir ve tam cümle ile bitir.\n\n"
        f"Kullanıcı mesajı: {user_message}\n"
        f"Yarım yanıt: {answer_so_far}"
    )
    continued, _ = _gemini_request_sync(continue_prompt)
    if not continued:
        return None
    continued = continued.strip()
    if not continued:
        return None
    if continued.lower().startswith(answer_so_far.lower()):
        return continued
    return f"{answer_so_far.rstrip()} {continued.lstrip()}"


def _build_prompt(user_message: str, budget_context: str) -> str:
    return f"""
Sen bir "Bütçe Koçu"sun.
Kurallar:
- Türkçe cevap ver.
- Kısa ve net cevap ver (3-6 cümle).
- Yatırım tavsiyesi verme; yatırım sorusunda "yatırım tavsiyesi veremem" de.
- Kullanıcının satın alma isteğinin aylık bütçeye etkisini açıklamaya odaklan.
- Selamlaşma mesajlarına doğal cevap ver.
- Uygunsuz/boş mesajda tutar sormayı öner.
- Korkutma yapma, yargılama yapma.
- Kullanıcı "20x400", "20 x 400", "20*400", "20 adet 400" gibi yazarsa toplam tutarı hesapla ve analizi buna göre yap.
- Kullanıcı "9 ay aylık 3000 TL" gibi taksitli ifade yazarsa bunu 9 TL değil, toplam 27000 TL borç ve aylık 3000 TL bütçe etkisi olarak yorumla.
- Taksitli alışverişlerde aylık bütçe riskini aylık taksit tutarıyla değerlendir; toplam borcu ayrıca belirt.

Bütçe bağlamı:
{budget_context}

Kullanıcı mesajı:
{user_message}
"""


def _llm_asks_for_amount_again(text: str) -> bool:
    t = text.lower()
    return (
        ("tutar" in t and ("yaz" in t or "belirt" in t))
        or ("yaklaşık" in t and "tutar" in t)
        or ("hesaplayabilmem için" in t and "tutar" in t)
    )


def _looks_truncated(text: str) -> bool:
    t = text.strip()
    if len(t) < 24:
        return True
    return not t.endswith((".", "!", "?", "…"))


async def coach_reply(user_id: str, message: str) -> dict:
    summary = await get_summary(user_id)
    remaining, _ = _build_budget_context(summary, message)
    if not _is_finance_related(message):
        return _out_of_scope_reply(remaining)

    installment_count = _extract_installment_count(message)
    product_research_requested = _looks_like_product_research_prompt(message)
    current_price_requested = _wants_current_product_price(message)
    has_explicit_amount = _has_explicit_purchase_amount(message)
    product_label = _extract_product_label(message) if product_research_requested else None
    remembered_product = _LAST_PRODUCT_BY_USER.get(user_id)
    detected_amount = (
        None
        if product_research_requested and not has_explicit_amount
        else _resolve_amount(user_id, message, installment_count)
    )
    remaining, context_text = _build_budget_context(
        summary,
        message,
        detected_amount=detected_amount,
        installment_count=installment_count,
    )

    if detected_amount is not None and _is_installment_planning_prompt(message):
        return _installment_planning_reply(detected_amount, remaining)

    if product_research_requested and not has_explicit_amount:
        if product_label:
            _LAST_PRODUCT_BY_USER[user_id] = product_label

        if not current_price_requested:
            return _product_budget_question_reply(product_label or "Bu ürün", remaining)

        if not settings.gemini_api_key:
            return _product_research_unavailable_reply(message, remaining)

        product_prompt = _build_product_research_prompt(message, context_text)
        researched_text = await _try_gemini_reply(
            product_prompt,
            message,
            True,
        )
        if researched_text:
            return {
                "reply": researched_text,
                "remaining_budget": round(remaining, 2) if remaining is not None else None,
                "risk_level": "info",
            }
        return _product_research_unavailable_reply(message, remaining)

    recommendation_product = product_label if product_research_requested else remembered_product
    if recommendation_product and detected_amount is not None and has_explicit_amount:
        _LAST_PRODUCT_BY_USER[user_id] = recommendation_product
        if settings.gemini_api_key:
            recommendation_prompt = _build_product_recommendation_prompt(
                recommendation_product,
                detected_amount,
                message,
                context_text,
            )
            recommendation_text = await _try_gemini_reply(
                recommendation_prompt,
                message,
                True,
            )
            if recommendation_text:
                return {
                    "reply": recommendation_text,
                    "remaining_budget": round(remaining, 2) if remaining is not None else None,
                    "risk_level": "info",
                }
        return _product_recommendation_fallback(
            recommendation_product,
            detected_amount,
            remaining,
            installment_count=installment_count,
        )

    if not settings.gemini_api_key:
        return _fallback_reply(
            message,
            remaining,
            amount_override=detected_amount,
            installment_count=installment_count,
        )

    if installment_count is not None and detected_amount is not None:
        return _fallback_reply(
            message,
            remaining,
            amount_override=detected_amount,
            installment_count=installment_count,
        )

    prompt = _build_prompt(message, context_text)
    llm_text = await _try_gemini_reply(prompt, message)
    if llm_text:
        return {
            "reply": llm_text,
            "remaining_budget": None,
            "risk_level": "info",
        }

    return _fallback_reply(
        message,
        remaining,
        amount_override=detected_amount,
        installment_count=installment_count,
    )

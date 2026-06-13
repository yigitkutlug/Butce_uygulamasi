import json
import urllib.error
import urllib.parse
import urllib.request


class InvestmentPriceError(RuntimeError):
    pass


_GENELPARA_ALTIN_URL = "https://api.genelpara.com/json/?list=altin&sembol=GA,C,Y,T,GAG,XAUUSD"
_SYMBOL_MAP = {
    "GA": "XAU-TRY",
    "C": "CEYREK-TRY",
    "Y": "YARIM-TRY",
    "T": "TAM-TRY",
    "GAG": "XAG-TRY",
    "XAUUSD": "XAUUSD",
}


def _parse_float(value: str | None) -> float | None:
    if not value:
        return None
    raw = value.strip()
    if not raw or raw.upper() == "N/D" or raw == "-":
        return None
    if "." in raw and "," in raw:
        normalized = raw.replace(".", "").replace(",", ".")
    else:
        normalized = raw.replace(",", ".")
    try:
        return float(normalized)
    except ValueError:
        return None


def fetch_prices() -> dict[str, float]:
    req = urllib.request.Request(
        _GENELPARA_ALTIN_URL,
        headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise InvestmentPriceError(f"price source HTTP error: {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise InvestmentPriceError(f"price source connection error: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise InvestmentPriceError(f"price source JSON parse error: {exc}") from exc

    data = payload.get("data")
    if not isinstance(data, dict):
        raise InvestmentPriceError("price source response format invalid")

    out: dict[str, float] = {}
    for source_key, app_symbol in _SYMBOL_MAP.items():
        item = data.get(source_key)
        if not isinstance(item, dict):
            continue
        price = _parse_float(str(item.get("alis") or item.get("satis") or ""))
        if price is None:
            continue
        out[app_symbol] = price
    return out

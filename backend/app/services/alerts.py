import asyncio
import logging
from datetime import datetime

from bson import ObjectId
from bson.errors import InvalidId

from app.db.mongo import get_db
from app.services.investment_prices import InvestmentPriceError, fetch_prices

_ALLOWED_CONDITIONS = {"above", "below"}
# Worker global tutulur; FastAPI startup'ta başlar, shutdown'da düzgün kapanır.
_worker_task: asyncio.Task | None = None
_worker_stop: asyncio.Event | None = None
logger = logging.getLogger(__name__)


def _serialize_alert(doc: dict) -> dict:
    # Mongo ObjectId ve sayısal alanlar JSON'a uygun tiplere çevrilir.
    return {
        "id": str(doc["_id"]),
        "symbol": doc["symbol"],
        "target_price": float(doc["target_price"]),
        "condition": doc["condition"],
        "is_active": bool(doc.get("is_active", True)),
        "created_at": doc.get("created_at"),
        "triggered_at": doc.get("triggered_at"),
    }


def _serialize_event(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "alert_id": str(doc.get("alert_id", "")),
        "symbol": doc.get("symbol"),
        "target_price": float(doc.get("target_price", 0)),
        "condition": doc.get("condition"),
        "trigger_price": float(doc.get("trigger_price", 0)),
        "message": doc.get("message", ""),
        "is_read": bool(doc.get("is_read", False)),
        "triggered_at": doc.get("triggered_at"),
    }


async def create_price_alert(user_id: str, symbol: str, target_price: float, condition: str) -> dict:
    # Alarm koşulu sadece iki yönlü tutulur: fiyat hedefin üstüne çıkarsa veya
    # altına düşerse tetiklenir.
    if condition not in _ALLOWED_CONDITIONS:
        raise ValueError("condition must be 'above' or 'below'")
    if target_price <= 0:
        raise ValueError("target_price must be > 0")

    db = get_db()
    result = await db.price_alerts.insert_one(
        {
            "user_id": user_id,
            "symbol": symbol,
            "target_price": float(target_price),
            "condition": condition,
            "is_active": True,
            "created_at": datetime.utcnow(),
            "triggered_at": None,
        }
    )
    doc = await db.price_alerts.find_one({"_id": result.inserted_id})
    return _serialize_alert(doc)


async def list_price_alerts(user_id: str) -> list[dict]:
    db = get_db()
    out: list[dict] = []
    cursor = db.price_alerts.find({"user_id": user_id}).sort("created_at", -1)
    async for doc in cursor:
        out.append(_serialize_alert(doc))
    return out


async def delete_price_alert(user_id: str, alert_id: str) -> bool:
    db = get_db()
    try:
        object_id = ObjectId(alert_id)
    except (InvalidId, TypeError):
        return False
    result = await db.price_alerts.delete_one({"_id": object_id, "user_id": user_id})
    return result.deleted_count > 0


async def update_price_alert(
    user_id: str,
    alert_id: str,
    symbol: str | None = None,
    target_price: float | None = None,
    condition: str | None = None,
    is_active: bool | None = None,
) -> dict | None:
    if condition is not None and condition not in _ALLOWED_CONDITIONS:
        raise ValueError("condition must be 'above' or 'below'")
    if target_price is not None and target_price <= 0:
        raise ValueError("target_price must be > 0")

    try:
        object_id = ObjectId(alert_id)
    except (InvalidId, TypeError):
        return None

    db = get_db()
    existing = await db.price_alerts.find_one({"_id": object_id, "user_id": user_id})
    if not existing:
        return None

    updates: dict = {}
    if symbol is not None:
        updates["symbol"] = symbol.strip().upper()
    if target_price is not None:
        updates["target_price"] = float(target_price)
    if condition is not None:
        updates["condition"] = condition
    if is_active is not None:
        updates["is_active"] = bool(is_active)
        if is_active:
            # Kullanıcı alarmı tekrar aktif ederse önceki tetiklenme zamanı
            # temizlenir; yeni tetiklenme ayrı olay olarak kaydedilir.
            updates["triggered_at"] = None

    if updates:
        await db.price_alerts.update_one({"_id": object_id}, {"$set": updates})

    doc = await db.price_alerts.find_one({"_id": object_id})
    return _serialize_alert(doc) if doc else None


async def list_alert_events(user_id: str, unread_only: bool = False) -> list[dict]:
    db = get_db()
    filt: dict = {"user_id": user_id}
    if unread_only:
        filt["is_read"] = False
    cursor = db.alert_events.find(filt).sort("triggered_at", -1)
    out: list[dict] = []
    async for doc in cursor:
        out.append(_serialize_event(doc))
    return out


async def mark_alert_event_read(user_id: str, event_id: str) -> bool:
    db = get_db()
    try:
        object_id = ObjectId(event_id)
    except (InvalidId, TypeError):
        return False
    result = await db.alert_events.update_one(
        {"_id": object_id, "user_id": user_id},
        {"$set": {"is_read": True}},
    )
    return result.modified_count > 0


def _is_triggered(current_price: float, target_price: float, condition: str) -> bool:
    # Karşılaştırma küçük tutulur ki worker döngüsünde okunabilir kalsın.
    if condition == "above":
        return current_price >= target_price
    return current_price <= target_price


async def process_alerts_once() -> dict:
    db = get_db()
    cursor = db.price_alerts.find({"is_active": True})
    active_alerts: list[dict] = []
    async for doc in cursor:
        active_alerts.append(doc)
    if not active_alerts:
        return {"checked": 0, "triggered": 0}

    try:
        # Fiyat sağlayıcıları bloklayıcı çalışabildiği için event loop'u
        # kilitlememek adına ayrı thread üzerinde çağrılır.
        prices = await asyncio.to_thread(fetch_prices)
    except InvestmentPriceError:
        return {"checked": len(active_alerts), "triggered": 0}

    triggered_count = 0
    for alert in active_alerts:
        symbol = alert.get("symbol")
        if not isinstance(symbol, str):
            continue
        current = prices.get(symbol)
        if current is None:
            continue
        target = float(alert.get("target_price", 0))
        condition = str(alert.get("condition", "above"))
        if not _is_triggered(current, target, condition):
            continue

        alert_id = alert["_id"]
        message = (
            f"{symbol} fiyati {current:.2f} oldu. "
            f"Hedef: {condition} {target:.2f}."
        )

        # Alarm tek seferlik tetiklenir: aktiflik kapatılır ve mobil uygulamanın
        # okuyacağı okunmamış event kaydı oluşturulur.
        await db.price_alerts.update_one(
            {"_id": alert_id},
            {"$set": {"is_active": False, "triggered_at": datetime.utcnow()}},
        )
        await db.alert_events.insert_one(
            {
                "user_id": alert["user_id"],
                "alert_id": alert_id,
                "symbol": symbol,
                "target_price": target,
                "condition": condition,
                "trigger_price": float(current),
                "message": message,
                "triggered_at": datetime.utcnow(),
                "is_read": False,
            }
        )
        triggered_count += 1

    return {"checked": len(active_alerts), "triggered": triggered_count}


async def _worker_loop(interval_sec: int) -> None:
    global _worker_stop
    while _worker_stop is not None and not _worker_stop.is_set():
        try:
            await process_alerts_once()
        except Exception:
            logger.exception("Alert worker iteration failed.")
        try:
            # wait_for kullanımı hem periyodik bekleme sağlar hem de shutdown
            # sinyali geldiğinde beklemeyi erken bitirir.
            await asyncio.wait_for(_worker_stop.wait(), timeout=interval_sec)
        except asyncio.TimeoutError:
            continue


def start_alert_worker(interval_sec: int = 60) -> None:
    global _worker_task, _worker_stop
    if _worker_task is not None and not _worker_task.done():
        return
    _worker_stop = asyncio.Event()
    _worker_task = asyncio.create_task(_worker_loop(interval_sec))


async def stop_alert_worker() -> None:
    global _worker_task, _worker_stop
    if _worker_task is None:
        return
    if _worker_stop is not None:
        _worker_stop.set()
    try:
        await _worker_task
    except Exception:
        logger.exception("Alert worker shutdown failed.")
    finally:
        _worker_task = None
        _worker_stop = None

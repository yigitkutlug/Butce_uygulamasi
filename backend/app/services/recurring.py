from datetime import datetime

from bson import ObjectId
from bson.errors import InvalidId

from app.db.mongo import get_db


def normalize_account(value: str | None) -> str:
    # Kullanıcı Türkçe/İngilizce veya boş hesap değeri gönderebilir; analizlerde
    # tutarlı görünmesi için birkaç ana seçenekten birine indirgenir.
    if not value:
        return "Card"
    normalized = value.strip().lower()
    if normalized in {"cash", "nakit"}:
        return "Cash"
    if normalized in {"iban", "bank", "hesap"}:
        return "IBAN"
    return "Card"


def next_due_date(due_day: int, now: datetime | None = None) -> datetime:
    now = now or datetime.utcnow()
    year = now.year
    month = now.month
    # Son ödeme günü bu ay geçmediyse mevcut ay, geçtiyse sonraki ay döndürülür.
    if now.day <= due_day:
        return datetime(year, month, due_day)

    if month == 12:
        return datetime(year + 1, 1, due_day)
    return datetime(year, month + 1, due_day)


async def create_recurring(
    user_id: str,
    title: str,
    amount: float,
    category: str,
    due_day: int,
    account: str | None,
    interval: str,
) -> dict:
    db = get_db()
    acc = normalize_account(account)
    next_due = next_due_date(due_day)
    # Tekrarlayan ödeme gerçek bir gider işlemi değildir; dashboard sadece
    # yaklaşan ödeme hatırlatması üretsin diye ayrı koleksiyonda tutulur.
    result = await db.recurring_payments.insert_one(
        {
            "user_id": user_id,
            "title": title,
            "amount": float(amount),
            "category": category,
            "due_day": int(due_day),
            "account": acc,
            "interval": interval,
            "is_active": True,
            "next_due_date": next_due,
            "created_at": datetime.utcnow(),
        }
    )
    return {
        "id": str(result.inserted_id),
        "user_id": user_id,
        "title": title,
        "amount": float(amount),
        "category": category,
        "due_day": int(due_day),
        "account": acc,
        "interval": interval,
        "next_due_date": next_due,
        "is_active": True,
    }


async def list_recurring(user_id: str) -> list[dict]:
    db = get_db()
    cursor = db.recurring_payments.find({"user_id": user_id}).sort("created_at", -1)
    out: list[dict] = []
    async for doc in cursor:
        # next_due_date her listelemede yeniden hesaplanır; böylece ay geçince
        # kullanıcı eski tarihe bakmaz.
        due = next_due_date(int(doc.get("due_day", 1)))
        out.append(
            {
                "id": str(doc["_id"]),
                "user_id": doc["user_id"],
                "title": doc["title"],
                "amount": float(doc["amount"]),
                "category": doc["category"],
                "due_day": int(doc["due_day"]),
                "account": doc.get("account", "Card"),
                "interval": doc.get("interval", "monthly"),
                "next_due_date": due,
                "is_active": bool(doc.get("is_active", True)),
            }
        )
    return out


async def update_recurring_active(user_id: str, recurring_id: str, is_active: bool) -> dict | None:
    db = get_db()
    try:
        object_id = ObjectId(recurring_id)
    except (InvalidId, TypeError):
        return None
    existing = await db.recurring_payments.find_one({"_id": object_id, "user_id": user_id})
    if not existing:
        return None
    await db.recurring_payments.update_one(
        {"_id": object_id},
        {"$set": {"is_active": bool(is_active)}},
    )
    existing["is_active"] = bool(is_active)
    return {
        "id": str(existing["_id"]),
        "user_id": existing["user_id"],
        "title": existing["title"],
        "amount": float(existing["amount"]),
        "category": existing["category"],
        "due_day": int(existing["due_day"]),
        "account": existing.get("account", "Card"),
        "interval": existing.get("interval", "monthly"),
        "next_due_date": next_due_date(int(existing.get("due_day", 1))),
        "is_active": bool(existing["is_active"]),
    }

from datetime import datetime

from bson import ObjectId
from bson.errors import InvalidId

from app.db.mongo import get_db
from app.ml.model import predict_category
from app.services.auto_income import ensure_monthly_income_transactions
from app.services.ml import retrain_from_db


def _predict_income_category(description: str) -> str:
    text = description.lower()
    # Gelir açıklamaları gider modelindeki "Food/Market" gibi sınıflara
    # düşmesin diye önce gelir odaklı anahtar kelimeler kontrol edilir.
    keyword_map: list[tuple[str, str]] = [
        ("maas", "Salary"),
        ("salary", "Salary"),
        ("bordro", "Salary"),
        ("burs", "Scholarship"),
        ("scholarship", "Scholarship"),
        ("freelance", "Freelance"),
        ("danisman", "Freelance"),
        ("kira", "Rental Income"),
        ("yatirim", "Investment"),
        ("hisse", "Investment"),
        ("fon", "Investment"),
        ("kripto", "Investment"),
        ("hediye", "Gift"),
        ("harclik", "Gift"),
        ("aileden", "Gift"),
        ("ek gelir", "Additional Income"),
        ("yan is", "Additional Income"),
        ("part time", "Additional Income"),
    ]
    for keyword, category in keyword_map:
        if keyword in text:
            return category

    predicted = predict_category(description)
    expense_categories = {"Food", "Market", "Transport", "Other"}
    # Model gider kategorisi döndürürse gelir işlemi için güvenli varsayılan
    # kategoriye alınır.
    if predicted in expense_categories:
        return "General Income"
    return predicted


def _normalize_account(value: str | None) -> str:
    if not value:
        return "Card"
    normalized = value.strip().lower()
    if normalized in {"cash", "nakit"}:
        return "Cash"
    if normalized in {"iban", "bank", "hesap"}:
        return "IBAN"
    return "Card"


async def add_transaction(
    user_id: str,
    amount: float,
    description: str,
    date: datetime | None,
    category: str | None,
    account: str | None,
) -> dict:
    db = get_db()
    tx_date = date or datetime.utcnow()
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    ai_consent = bool(user.get("ai_data_consent")) if user else False

    if category:
        final_category = category
    elif amount >= 0:
        final_category = _predict_income_category(description)
    else:
        final_category = predict_category(description)

    final_account = _normalize_account(account)

    result = await db.transactions.insert_one(
        {
            "user_id": user_id,
            "amount": amount,
            "description": description,
            "category": final_category,
            "account": final_account,
            "date": tx_date,
        }
    )

    if category and ai_consent:
        # Kullanıcı izin verdiyse manuel kategori seçimi eğitim verisi olarak
        # saklanır; böylece model zamanla uygulama verisine uyum sağlar.
        await db.training_data.insert_one(
            {
                "user_id": user_id,
                "text": description,
                "category": category,
                "source": "manual",
            }
        )
        labeled_count = await db.training_data.count_documents(
            {
                "user_id": user_id,
                "source": {"$in": ["manual", "corrected"]},
            }
        )
        # Her 5 etiketli geri bildirimden sonra yeniden eğitim yapılır; bu sayı
        # demo için gözlemlenebilir, aynı zamanda gereksiz eğitimi sınırlar.
        if labeled_count > 0 and labeled_count % 5 == 0:
            await retrain_from_db(user_id)

    return {
        "id": str(result.inserted_id),
        "user_id": user_id,
        "amount": amount,
        "description": description,
        "category": final_category,
        "account": final_account,
        "date": tx_date,
    }


async def list_transactions(user_id: str) -> list[dict]:
    db = get_db()
    await ensure_monthly_income_transactions(user_id)
    cursor = db.transactions.find({"user_id": user_id}).sort("date", -1)
    results: list[dict] = []
    async for doc in cursor:
        doc["id"] = str(doc["_id"])
        doc["account"] = doc.get("account", "Card")
        doc.pop("_id", None)
        results.append(doc)
    return results


async def update_transaction_category(user_id: str, tx_id: str, category: str) -> dict | None:
    db = get_db()
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    ai_consent = bool(user.get("ai_data_consent")) if user else False
    try:
        object_id = ObjectId(tx_id)
    except (InvalidId, TypeError):
        return None

    existing = await db.transactions.find_one({"_id": object_id, "user_id": user_id})
    if not existing:
        return None

    await db.transactions.update_one({"_id": object_id}, {"$set": {"category": category}})
    if ai_consent:
        # Kategori düzeltmeleri en değerli geri bildirimdir; modelin yanlış
        # tahminlerini düzeltmek için ayrı kaynak tipiyle tutulur.
        await db.training_data.insert_one(
            {
                "user_id": user_id,
                "text": existing["description"],
                "category": category,
                "source": "corrected",
            }
        )

        labeled_count = await db.training_data.count_documents(
            {
                "user_id": user_id,
                "source": {"$in": ["manual", "corrected"]},
            }
        )
        if labeled_count > 0 and labeled_count % 5 == 0:
            await retrain_from_db(user_id)

    existing["category"] = category
    existing["id"] = str(existing["_id"])
    existing["account"] = existing.get("account", "Card")
    existing.pop("_id", None)
    return existing

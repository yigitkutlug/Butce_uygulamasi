from datetime import datetime

from bson import ObjectId
from bson.errors import InvalidId

from app.db.mongo import get_db


def _month_key(dt: datetime) -> str:
    return dt.strftime("%Y-%m")


def _month_start(month: str) -> datetime:
    year, month_number = month.split("-")
    # Otomatik gelir kayıtları ayın ilk günü sabah 09:00'a yazılır; bu sayede
    # manuel işlemlerle karışmadan kronolojik listede düzenli görünür.
    return datetime(int(year), int(month_number), 1, 9, 0, 0)


def _next_month_key(month: str) -> str:
    year, month_number = [int(part) for part in month.split("-")]
    if month_number == 12:
        return f"{year + 1}-01"
    return f"{year}-{month_number + 1:02d}"


def previous_month_key(month: str) -> str:
    year, month_number = [int(part) for part in month.split("-")]
    if month_number == 1:
        return f"{year - 1}-12"
    return f"{year}-{month_number - 1:02d}"


def _month_range(start_month: str, end_month: str) -> list[str]:
    # Kullanıcı uygulamayı birkaç ay açmazsa aradaki eksik maaş ayları da tek
    # seferde tamamlanabilsin diye kapalı aralık üretilir.
    months: list[str] = []
    current = start_month
    while current <= end_month:
        months.append(current)
        current = _next_month_key(current)
    return months


async def ensure_monthly_income_transactions(user_id: str) -> None:
    db = get_db()
    try:
        object_id = ObjectId(user_id)
    except (InvalidId, TypeError):
        return

    user = await db.users.find_one({"_id": object_id})
    if not user:
        return

    monthly_income = float(user.get("monthly_income", 0.0) or 0.0)
    if monthly_income <= 0:
        return

    current_month = _month_key(datetime.utcnow())
    last_synced = user.get("monthly_income_last_synced_month")
    # Daha önce senkron yapılmadıysa sadece mevcut ay üretilir; yapıldıysa son
    # senkronlanan aydan sonraki aylar tamamlanır.
    start_month = _next_month_key(last_synced) if isinstance(last_synced, str) else current_month

    if start_month > current_month:
        return

    for month in _month_range(start_month, current_month):
        query = {
            "user_id": user_id,
            "source": "auto_monthly_income",
            "auto_income_month": month,
        }
        metadata = {
            "description": "Aylık maaş",
            "category": "Salary",
            "account": "Maaş",
            "date": _month_start(month),
        }
        # Aynı ay için ikinci kez maaş eklenmesin diye önce mevcut otomatik
        # kayıt güncellenir; yoksa yeni kayıt oluşturulur.
        result = await db.transactions.update_one(query, {"$set": metadata})
        if result.matched_count == 0:
            await db.transactions.insert_one(
                {
                    **query,
                    **metadata,
                    "amount": monthly_income,
                }
            )

    await db.users.update_one(
        {"_id": object_id},
        {"$set": {"monthly_income_last_synced_month": current_month}},
    )

from datetime import datetime

from bson import ObjectId
from bson.errors import InvalidId
from pymongo.errors import DuplicateKeyError

from app.core.security import create_access_token, get_password_hash, verify_password
from app.db.mongo import get_db
from app.services.auto_income import previous_month_key


def _validate_password_length(password: str) -> None:
    # bcrypt en fazla 72 byte kabul eder; uzun şifreyi kayıt anında reddederek
    # ileride doğrulama sırasında belirsiz davranış oluşmasını engelleriz.
    if len(password.encode("utf-8")) > 72:
        raise ValueError("Password is too long. Use at most 72 bytes.")


def _normalize_email(email: str) -> str:
    # Aynı e-posta farklı büyük/küçük harfle ikinci kez kayıt olmasın diye
    # email adresi tek biçime çevrilir.
    return email.strip().lower()


async def register_user(email: str, password: str) -> dict:
    db = get_db()
    normalized_email = _normalize_email(email)
    # Unique index olsa da kullanıcıya daha anlaşılır hata dönmek için önce
    # manuel kontrol yapılır.
    existing = await db.users.find_one({"email": normalized_email})
    if existing:
        raise ValueError("Email already registered")
    _validate_password_length(password)
    hashed = get_password_hash(password)
    try:
        result = await db.users.insert_one(
            {
                "email": normalized_email,
                "hashed_password": hashed,
                "monthly_income": 0.0,
                "ai_data_consent": None,
                "essential_expense": 0.0,
                "savings_goal": 0.0,
                "onboarding_completed": False,
            }
        )
    except DuplicateKeyError as exc:
        raise ValueError("Email already registered") from exc
    return {
        "id": str(result.inserted_id),
        "email": normalized_email,
        "monthly_income": 0.0,
        "ai_data_consent": None,
        "essential_expense": 0.0,
        "savings_goal": 0.0,
        "onboarding_completed": False,
    }


async def register_user_with_profile(
    email: str,
    password: str,
    monthly_income: float,
    ai_data_consent: bool | None = None,
) -> dict:
    db = get_db()
    normalized_email = _normalize_email(email)
    existing = await db.users.find_one({"email": normalized_email})
    if existing:
        raise ValueError("Email already registered")
    _validate_password_length(password)
    hashed = get_password_hash(password)
    try:
        result = await db.users.insert_one(
            {
                "email": normalized_email,
                "hashed_password": hashed,
                "monthly_income": float(monthly_income),
                "ai_data_consent": ai_data_consent,
                "essential_expense": 0.0,
                "savings_goal": 0.0,
                "onboarding_completed": False,
            }
        )
    except DuplicateKeyError as exc:
        raise ValueError("Email already registered") from exc
    return {
        "id": str(result.inserted_id),
        "email": normalized_email,
        "monthly_income": float(monthly_income),
        "ai_data_consent": ai_data_consent,
        "essential_expense": 0.0,
        "savings_goal": 0.0,
        "onboarding_completed": False,
    }


async def authenticate_user(email: str, password: str) -> str:
    db = get_db()
    user = await db.users.find_one({"email": _normalize_email(email)})
    if not user:
        raise ValueError("Invalid credentials")
    hashed_password = user.get("hashed_password")
    if not isinstance(hashed_password, str) or not hashed_password:
        raise ValueError("Invalid credentials")
    if not verify_password(password, hashed_password):
        raise ValueError("Invalid credentials")
    user_id = user.get("_id")
    if user_id is None:
        raise ValueError("Invalid credentials")
    # Login başarılıysa frontend'in sonraki isteklerde kullanacağı JWT döner.
    return create_access_token(str(user_id))


async def get_user_by_id(user_id: str) -> dict | None:
    db = get_db()
    try:
        object_id = ObjectId(user_id)
    except (InvalidId, TypeError):
        return None
    return await db.users.find_one({"_id": object_id})


async def update_monthly_income(user_id: str, monthly_income: float) -> dict | None:
    db = get_db()
    try:
        object_id = ObjectId(user_id)
    except (InvalidId, TypeError):
        return None

    await db.users.update_one(
        {"_id": object_id},
        {
            "$set": {
                "monthly_income": float(monthly_income),
                # Gelir hedefi değiştiğinde otomatik maaş üretimi bir sonraki
                # liste/özet çağrısında güncel ayı yeniden senkronlayabilsin.
                "monthly_income_last_synced_month": previous_month_key(
                    datetime.utcnow().strftime("%Y-%m")
                ),
            }
        },
    )
    return await db.users.find_one({"_id": object_id})


async def update_ai_consent(user_id: str, ai_data_consent: bool) -> dict | None:
    db = get_db()
    try:
        object_id = ObjectId(user_id)
    except (InvalidId, TypeError):
        return None

    await db.users.update_one(
        {"_id": object_id},
        {"$set": {"ai_data_consent": bool(ai_data_consent)}},
    )
    return await db.users.find_one({"_id": object_id})


async def update_onboarding_profile(
    user_id: str,
    monthly_income: float,
    essential_expense: float,
    savings_goal: float,
) -> dict | None:
    db = get_db()
    try:
        object_id = ObjectId(user_id)
    except (InvalidId, TypeError):
        return None

    await db.users.update_one(
        {"_id": object_id},
        {
            "$set": {
                "monthly_income": float(monthly_income),
                "essential_expense": float(essential_expense),
                "savings_goal": float(savings_goal),
                "onboarding_completed": True,
                # Onboarding sonunda aylık gelir tanımlanır; önceki ay olarak
                # işaretleyip bu ay için otomatik gelir kaydını tetikleriz.
                "monthly_income_last_synced_month": previous_month_key(
                    datetime.utcnow().strftime("%Y-%m")
                ),
            }
        },
    )
    return await db.users.find_one({"_id": object_id})

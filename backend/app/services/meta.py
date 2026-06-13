from app.db.mongo import get_db

DEFAULT_EXPENSE_CATEGORIES = ["Food", "Market", "Transport", "Bills", "Entertainment", "Other"]
DEFAULT_INCOME_CATEGORIES = [
    "Salary",
    "Additional Income",
    "Scholarship",
    "Freelance",
    "Investment",
    "Rental Income",
    "Gift",
    "Other Income",
]
DEFAULT_BUDGET_LIMITS = {
    "Food": 4000.0,
    "Market": 5000.0,
    "Transport": 3000.0,
    "Bills": 3500.0,
    "Entertainment": 2000.0,
}


async def get_categories(_: str) -> dict:
    return {
        "expense": DEFAULT_EXPENSE_CATEGORIES,
        "income": DEFAULT_INCOME_CATEGORIES,
    }


async def list_budgets(user_id: str) -> list[dict]:
    db = get_db()
    cursor = db.budgets.find({"user_id": user_id})
    items: list[dict] = []
    async for doc in cursor:
        items.append(
            {
                "category": doc["category"],
                "limit": float(doc["limit"]),
            }
        )

    if not items:
        return [{"category": k, "limit": v} for k, v in DEFAULT_BUDGET_LIMITS.items()]
    return items


async def upsert_budget(user_id: str, category: str, limit: float) -> dict:
    db = get_db()
    await db.budgets.update_one(
        {"user_id": user_id, "category": category},
        {"$set": {"limit": float(limit)}},
        upsert=True,
    )
    return {"category": category, "limit": float(limit)}


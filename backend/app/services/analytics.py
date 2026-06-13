from collections import defaultdict
from datetime import datetime

from bson import ObjectId
from bson.errors import InvalidId

from app.db.mongo import get_db
from app.services.auto_income import ensure_monthly_income_transactions
from app.services.meta import DEFAULT_BUDGET_LIMITS
from app.services.recurring import next_due_date


def _month_key(dt: datetime) -> str:
    return dt.strftime("%Y-%m")


async def get_summary(user_id: str) -> dict:
    db = get_db()
    await ensure_monthly_income_transactions(user_id)
    cursor = db.transactions.find({"user_id": user_id})
    now = datetime.utcnow().date()

    # Dashboard tek endpoint ile beslensin diye gelir/gider, haftalık değişim,
    # kategori dağılımı ve aylık trendler aynı geçişte hesaplanır.
    total_income = 0.0
    total_expense = 0.0
    weekly_expense_current = 0.0
    weekly_expense_previous = 0.0
    category_spend: dict[str, float] = defaultdict(float)
    monthly: dict[str, dict[str, float]] = defaultdict(lambda: {"income": 0.0, "expense": 0.0})
    category_by_month: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))

    async for tx in cursor:
        amount = float(tx["amount"])
        date = tx["date"]
        month = _month_key(date)

        if amount >= 0:
            total_income += amount
            monthly[month]["income"] += amount
        else:
            expense = abs(amount)
            total_expense += expense
            monthly[month]["expense"] += expense
            category_spend[tx["category"]] += expense
            category_by_month[month][tx["category"]] += expense

            tx_date = date.date()
            days_diff = (now - tx_date).days
            if 0 <= days_diff <= 6:
                weekly_expense_current += expense
            elif 7 <= days_diff <= 13:
                weekly_expense_previous += expense

    sorted_months = sorted(monthly.keys())
    monthly_summary = [{"month": m, **monthly[m]} for m in sorted_months]

    monthly_income_target = 0.0
    try:
        object_id = ObjectId(user_id)
        user_doc = await db.users.find_one({"_id": object_id})
        if user_doc:
            monthly_income_target = float(user_doc.get("monthly_income", 0.0))
    except (InvalidId, TypeError):
        monthly_income_target = 0.0

    recommendations = _build_recommendations(
        monthly,
        category_spend,
        category_by_month,
        monthly_income_target,
    )

    budget_alerts = await _build_budget_alerts(user_id, category_spend)
    recommendations.extend([item["message"] for item in budget_alerts])
    bill_reminders = await _build_bill_reminders(user_id)

    month_change_pct = 0.0
    if len(sorted_months) >= 2:
        last_expense = monthly[sorted_months[-1]]["expense"]
        prev_expense = monthly[sorted_months[-2]]["expense"]
        if prev_expense > 0:
            month_change_pct = ((last_expense - prev_expense) / prev_expense) * 100

    top_categories = [
        {"category": k, "amount": round(v, 2)}
        for k, v in sorted(category_spend.items(), key=lambda x: x[1], reverse=True)[:3]
    ]

    current_month_expense = monthly[sorted_months[-1]]["expense"] if sorted_months else 0.0
    weekly_change_pct = 0.0
    if weekly_expense_previous > 0:
        weekly_change_pct = (
            (weekly_expense_current - weekly_expense_previous) / weekly_expense_previous
        ) * 100

    return {
        "total_income": round(total_income, 2),
        "total_expense": round(total_expense, 2),
        "active_balance": round(total_income - total_expense, 2),
        "category_spending": {k: round(v, 2) for k, v in category_spend.items()},
        "monthly_summary": monthly_summary,
        "recommendations": recommendations,
        "budget_alerts": budget_alerts,
        "bill_reminders": bill_reminders,
        "monthly_income_target": round(monthly_income_target, 2),
        "current_month_expense": round(current_month_expense, 2),
        "month_change_pct": round(month_change_pct, 2),
        "top_categories": top_categories,
        "weekly_expense_current": round(weekly_expense_current, 2),
        "weekly_expense_previous": round(weekly_expense_previous, 2),
        "weekly_change_pct": round(weekly_change_pct, 2),
    }


async def _build_budget_alerts(user_id: str, category_spend: dict[str, float]) -> list[dict]:
    db = get_db()
    budgets_cursor = db.budgets.find({"user_id": user_id})
    budget_map: dict[str, float] = {}
    async for doc in budgets_cursor:
        budget_map[doc["category"]] = float(doc["limit"])

    if not budget_map:
        budget_map = dict(DEFAULT_BUDGET_LIMITS)

    # 80% kullanımı uyarı, 100% ve üzeri aşım olarak işaretlenir. Bu eşikler
    # hem dashboard kartlarını hem de mobil bütçe hatırlatmasını besler.
    alerts: list[dict] = []
    for category, limit in budget_map.items():
        spent = float(category_spend.get(category, 0.0))
        if limit <= 0:
            continue
        ratio = spent / limit
        if ratio >= 1.0:
            alerts.append(
                {
                    "category": category,
                    "limit": round(limit, 2),
                    "spent": round(spent, 2),
                    "usage_percent": round(ratio * 100, 2),
                    "level": "danger",
                    "message": f"Budget exceeded in {category}.",
                }
            )
        elif ratio >= 0.8:
            alerts.append(
                {
                    "category": category,
                    "limit": round(limit, 2),
                    "spent": round(spent, 2),
                    "usage_percent": round(ratio * 100, 2),
                    "level": "warning",
                    "message": f"Budget is close to limit in {category}.",
                }
            )
    return alerts


async def _build_bill_reminders(user_id: str) -> list[dict]:
    db = get_db()
    now = datetime.utcnow()
    reminders: list[dict] = []
    cursor = db.recurring_payments.find({"user_id": user_id, "is_active": True})
    async for doc in cursor:
        due = next_due_date(int(doc.get("due_day", 1)), now=now)
        days_left = (due.date() - now.date()).days
        # Kullanıcıyı çok erken yormamak için yalnızca son 5 gündeki yaklaşan
        # ödemeler dashboard hatırlatması olarak gösterilir.
        if 0 <= days_left <= 5:
            reminders.append(
                {
                    "title": doc.get("title", "Payment"),
                    "amount": round(float(doc.get("amount", 0.0)), 2),
                    "category": doc.get("category", "Other"),
                    "due_date": due.isoformat(),
                    "days_left": days_left,
                    "account": doc.get("account", "Card"),
                }
            )
    reminders.sort(key=lambda x: x["days_left"])
    return reminders


def _build_recommendations(
    monthly: dict[str, dict[str, float]],
    category_spend: dict[str, float],
    category_by_month: dict[str, dict[str, float]],
    monthly_income_target: float,
) -> list[str]:
    recs: list[str] = []
    months = sorted(monthly.keys())
    if len(months) >= 2:
        last = monthly[months[-1]]["expense"]
        prev = monthly[months[-2]]["expense"]
        if prev > 0:
            change = ((last - prev) / prev) * 100
            if change >= 20:
                recs.append(f"Your overall spending increased by {change:.0f}% last month.")
            elif change <= -20:
                recs.append(f"Great job! Your overall spending decreased by {abs(change):.0f}% last month.")

    monthly_category_keys = sorted(category_by_month.keys())
    if len(monthly_category_keys) >= 2:
        last_month = monthly_category_keys[-1]
        prev_month = monthly_category_keys[-2]
        for cat, last_value in category_by_month[last_month].items():
            prev_value = category_by_month[prev_month].get(cat, 0.0)
            if prev_value > 0:
                change = ((last_value - prev_value) / prev_value) * 100
                if change >= 20:
                    recs.append(f"Your {cat.lower()} spending increased by {change:.0f}% last month.")

    for cat, value in category_spend.items():
        if value > 0 and value >= 500:
            recs.append("You exceeded transport budget" if cat.lower() == "transport" else f"High spending in {cat}.")

    if monthly_income_target > 0 and months:
        last_month = months[-1]
        last_month_expense = monthly[last_month]["expense"]
        ratio = last_month_expense / monthly_income_target
        if ratio >= 1.0:
            overspent_pct = (ratio - 1.0) * 100
            recs.append(f"You spent {overspent_pct:.0f}% above your monthly income target.")
        elif ratio >= 0.85:
            recs.append("You are close to your monthly income limit. Keep tracking your expenses.")
        elif ratio <= 0.6:
            recs.append("Great discipline! You are safely below your monthly income target.")

    return recs


async def get_prediction(user_id: str) -> dict:
    db = get_db()
    cursor = db.transactions.find({"user_id": user_id, "amount": {"$lt": 0}})
    by_month: dict[str, float] = defaultdict(float)

    async for tx in cursor:
        month = _month_key(tx["date"])
        by_month[month] += abs(float(tx["amount"]))

    months = sorted(by_month.keys())
    if not months:
        return {"predicted_next_month_spending": 0.0, "method": "average_last_3_months"}

    last_three = months[-3:]
    avg = sum(by_month[m] for m in last_three) / len(last_three)
    return {"predicted_next_month_spending": round(avg, 2), "method": "average_last_3_months"}

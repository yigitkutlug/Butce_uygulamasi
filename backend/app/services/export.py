from io import StringIO

from app.db.mongo import get_db
from app.services.analytics import get_prediction, get_summary


def _sanitize_csv_cell(value: object) -> str:
    text = str(value or "").replace("\n", " ").replace("\r", " ").replace(",", " ").strip()
    if text.startswith(("=", "+", "-", "@")):
        return f"'{text}"
    return text


async def build_csv_report(user_id: str) -> str:
    db = get_db()
    summary = await get_summary(user_id)
    prediction = await get_prediction(user_id)
    transactions: list[dict] = []
    cursor = db.transactions.find({"user_id": user_id}).sort("date", -1)
    async for doc in cursor:
        transactions.append(doc)

    out = StringIO()
    out.write("section,key,value\n")
    out.write(f"summary,total_income,{summary.get('total_income', 0)}\n")
    out.write(f"summary,total_expense,{summary.get('total_expense', 0)}\n")
    out.write(
        "summary,predicted_next_month_spending,"
        f"{prediction.get('predicted_next_month_spending', 0)}\n"
    )
    out.write("\n")

    out.write("monthly,month,income,expense\n")
    for row in summary.get("monthly_summary", []):
        out.write(
            f"monthly,{row.get('month','')},{row.get('income',0)},{row.get('expense',0)}\n"
        )
    out.write("\n")

    out.write("category,category,amount\n")
    for cat, amount in summary.get("category_spending", {}).items():
        out.write(f"category,{_sanitize_csv_cell(cat)},{amount}\n")
    out.write("\n")

    out.write("transactions,date,description,category,account,amount\n")
    for tx in transactions:
        date_str = tx.get("date").strftime("%Y-%m-%d")
        description = _sanitize_csv_cell(tx.get("description", ""))
        category = _sanitize_csv_cell(tx.get("category", ""))
        account = _sanitize_csv_cell(tx.get("account", "Card"))
        amount = tx.get("amount", 0)
        out.write(f"transaction,{date_str},{description},{category},{account},{amount}\n")

    return out.getvalue()

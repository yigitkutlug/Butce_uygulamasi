from fastapi import APIRouter, Depends

from app.core.deps import get_current_user
from app.models.budget import BudgetOut, BudgetUpdate
from app.services.meta import get_categories, list_budgets, upsert_budget

router = APIRouter()


@router.get("/categories")
async def categories(user=Depends(get_current_user)):
    return await get_categories(user["id"])


@router.get("/budgets", response_model=list[BudgetOut])
async def budgets(user=Depends(get_current_user)):
    raw = await list_budgets(user["id"])
    return [BudgetOut(category=item["category"], limit=item["limit"]) for item in raw]


@router.put("/budgets")
async def update_budget(payload: BudgetUpdate, user=Depends(get_current_user)):
    return await upsert_budget(user["id"], payload.category, payload.limit)


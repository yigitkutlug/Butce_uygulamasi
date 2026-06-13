from fastapi import APIRouter, Depends, HTTPException

from app.core.deps import get_current_user
from app.models.recurring import RecurringActiveUpdate, RecurringCreate, RecurringOut
from app.services.recurring import create_recurring, list_recurring, update_recurring_active

router = APIRouter()


@router.post("/recurring", response_model=RecurringOut)
async def create_recurring_payment(payload: RecurringCreate, user=Depends(get_current_user)):
    return await create_recurring(
        user_id=user["id"],
        title=payload.title,
        amount=payload.amount,
        category=payload.category,
        due_day=payload.due_day,
        account=payload.account,
        interval=payload.interval,
    )


@router.get("/recurring", response_model=list[RecurringOut])
async def get_recurring_payments(user=Depends(get_current_user)):
    return await list_recurring(user["id"])


@router.put("/recurring/{recurring_id}/active", response_model=RecurringOut)
async def set_recurring_active(recurring_id: str, payload: RecurringActiveUpdate, user=Depends(get_current_user)):
    updated = await update_recurring_active(user["id"], recurring_id, payload.is_active)
    if not updated:
        raise HTTPException(status_code=404, detail="Recurring payment not found")
    return updated


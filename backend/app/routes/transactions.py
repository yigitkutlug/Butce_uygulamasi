from fastapi import APIRouter, Depends, HTTPException

from app.core.deps import get_current_user
from app.models.transaction import TransactionCreate, TransactionOut, TransactionUpdateCategory
from app.services.transactions import add_transaction, list_transactions, update_transaction_category

router = APIRouter()


@router.post("/transaction", response_model=TransactionOut)
async def create_transaction(payload: TransactionCreate, user=Depends(get_current_user)):
    tx = await add_transaction(
        user["id"],
        payload.amount,
        payload.description,
        payload.date,
        payload.category,
        payload.account,
    )
    return tx


@router.get("/transactions", response_model=list[TransactionOut])
async def get_transactions(user=Depends(get_current_user)):
    return await list_transactions(user["id"])


@router.put("/transaction/{tx_id}/category", response_model=TransactionOut)
async def edit_category(tx_id: str, payload: TransactionUpdateCategory, user=Depends(get_current_user)):
    updated = await update_transaction_category(user["id"], tx_id, payload.category)
    if not updated:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return updated

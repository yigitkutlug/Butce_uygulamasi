from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.core.deps import get_current_user
from app.services.alerts import (
    create_price_alert,
    delete_price_alert,
    list_alert_events,
    list_price_alerts,
    mark_alert_event_read,
    update_price_alert,
)

router = APIRouter()


class PriceAlertCreate(BaseModel):
    symbol: str = Field(min_length=2, max_length=32)
    target_price: float = Field(gt=0)
    condition: str = Field(pattern="^(above|below)$")


class PriceAlertUpdate(BaseModel):
    symbol: str | None = Field(default=None, min_length=2, max_length=32)
    target_price: float | None = Field(default=None, gt=0)
    condition: str | None = Field(default=None, pattern="^(above|below)$")
    is_active: bool | None = None


@router.post("/alerts")
async def create_alert(payload: PriceAlertCreate, user=Depends(get_current_user)):
    try:
        return await create_price_alert(
            user_id=user["id"],
            symbol=payload.symbol.strip().upper(),
            target_price=payload.target_price,
            condition=payload.condition,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/alerts")
async def get_alerts(user=Depends(get_current_user)):
    return await list_price_alerts(user["id"])


@router.delete("/alerts/{alert_id}")
async def remove_alert(alert_id: str, user=Depends(get_current_user)):
    deleted = await delete_price_alert(user["id"], alert_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Alert not found")
    return {"status": "ok"}


@router.put("/alerts/{alert_id}")
async def put_alert(alert_id: str, payload: PriceAlertUpdate, user=Depends(get_current_user)):
    try:
        updated = await update_price_alert(
            user_id=user["id"],
            alert_id=alert_id,
            symbol=(payload.symbol.strip().upper() if payload.symbol else None),
            target_price=payload.target_price,
            condition=payload.condition,
            is_active=payload.is_active,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not updated:
        raise HTTPException(status_code=404, detail="Alert not found")
    return updated


@router.get("/alerts/events")
async def get_alert_events(
    unread_only: bool = Query(default=False),
    user=Depends(get_current_user),
):
    return await list_alert_events(user["id"], unread_only=unread_only)


@router.put("/alerts/events/{event_id}/read")
async def set_event_read(event_id: str, user=Depends(get_current_user)):
    updated = await mark_alert_event_read(user["id"], event_id)
    if not updated:
        raise HTTPException(status_code=404, detail="Event not found")
    return {"status": "ok"}

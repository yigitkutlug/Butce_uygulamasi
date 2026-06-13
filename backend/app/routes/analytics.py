from fastapi import APIRouter, Depends

from app.core.deps import get_current_user
from app.services.analytics import get_prediction, get_summary
from app.services.ml import get_ml_metrics, retrain_from_db

router = APIRouter()


@router.get("/summary")
async def summary(user=Depends(get_current_user)):
    return await get_summary(user["id"])


@router.get("/prediction")
async def prediction(user=Depends(get_current_user)):
    return await get_prediction(user["id"])


@router.post("/retrain")
async def retrain(user=Depends(get_current_user)):
    return await retrain_from_db(user["id"])


@router.get("/ml/metrics")
async def ml_metrics(user=Depends(get_current_user)):
    return await get_ml_metrics(user["id"])

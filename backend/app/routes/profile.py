from fastapi import APIRouter, Depends, HTTPException

from app.core.deps import get_current_user
from app.models.user import UserConsentUpdate, UserOnboardingUpdate, UserProfile, UserProfileUpdate
from app.services.auth import update_ai_consent, update_monthly_income, update_onboarding_profile

router = APIRouter()


@router.get("/profile", response_model=UserProfile)
async def get_profile(user=Depends(get_current_user)):
    return UserProfile(
        id=user["id"],
        email=user["email"],
        monthly_income=float(user.get("monthly_income", 0.0)),
        ai_data_consent=user.get("ai_data_consent", None),
        essential_expense=float(user.get("essential_expense", 0.0)),
        savings_goal=float(user.get("savings_goal", 0.0)),
        onboarding_completed=bool(user.get("onboarding_completed", False)),
    )


@router.put("/profile", response_model=UserProfile)
async def put_profile(payload: UserProfileUpdate, user=Depends(get_current_user)):
    updated = await update_monthly_income(user["id"], payload.monthly_income)
    if not updated:
        raise HTTPException(status_code=404, detail="User not found")
    return UserProfile(
        id=str(updated["_id"]),
        email=updated["email"],
        monthly_income=float(updated.get("monthly_income", 0.0)),
        ai_data_consent=updated.get("ai_data_consent", None),
        essential_expense=float(updated.get("essential_expense", 0.0)),
        savings_goal=float(updated.get("savings_goal", 0.0)),
        onboarding_completed=bool(updated.get("onboarding_completed", False)),
    )


@router.put("/profile/consent", response_model=UserProfile)
async def put_consent(payload: UserConsentUpdate, user=Depends(get_current_user)):
    updated = await update_ai_consent(user["id"], payload.ai_data_consent)
    if not updated:
        raise HTTPException(status_code=404, detail="User not found")
    return UserProfile(
        id=str(updated["_id"]),
        email=updated["email"],
        monthly_income=float(updated.get("monthly_income", 0.0)),
        ai_data_consent=updated.get("ai_data_consent", None),
        essential_expense=float(updated.get("essential_expense", 0.0)),
        savings_goal=float(updated.get("savings_goal", 0.0)),
        onboarding_completed=bool(updated.get("onboarding_completed", False)),
    )


@router.put("/profile/onboarding", response_model=UserProfile)
async def put_onboarding(payload: UserOnboardingUpdate, user=Depends(get_current_user)):
    updated = await update_onboarding_profile(
        user["id"],
        payload.monthly_income,
        payload.essential_expense,
        payload.savings_goal,
    )
    if not updated:
        raise HTTPException(status_code=404, detail="User not found")
    return UserProfile(
        id=str(updated["_id"]),
        email=updated["email"],
        monthly_income=float(updated.get("monthly_income", 0.0)),
        ai_data_consent=updated.get("ai_data_consent", None),
        essential_expense=float(updated.get("essential_expense", 0.0)),
        savings_goal=float(updated.get("savings_goal", 0.0)),
        onboarding_completed=bool(updated.get("onboarding_completed", False)),
    )

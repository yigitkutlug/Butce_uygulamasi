from fastapi import APIRouter, HTTPException

from app.models.user import Token, UserCreate, UserLogin
from app.services.auth import authenticate_user, register_user_with_profile

router = APIRouter()


@router.post("/register")
async def register(payload: UserCreate):
    try:
        user = await register_user_with_profile(
            payload.email,
            payload.password,
            payload.monthly_income,
            payload.ai_data_consent,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "id": user["id"],
        "email": user["email"],
        "monthly_income": user["monthly_income"],
        "ai_data_consent": user["ai_data_consent"],
    }


@router.post("/login", response_model=Token)
async def login(payload: UserLogin):
    try:
        token = await authenticate_user(payload.email, payload.password)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    return Token(access_token=token)

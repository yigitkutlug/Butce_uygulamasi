from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.core.config import settings
from app.services.auth import get_user_by_id

security = HTTPBearer()


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    # Korunan endpointlerde gelen Bearer token burada çözülür. Token geçersizse
    # route fonksiyonu hiç çalışmadan 401 döner.
    token = credentials.credentials
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        user_id: str | None = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid token") from exc

    user = await get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    # Mongo dokümanı doğrudan dışarı verilmez; route'ların ihtiyacı olan sade ve
    # tipleri normalize edilmiş kullanıcı bilgisi döndürülür.
    return {
        "id": str(user["_id"]),
        "email": user["email"],
        "monthly_income": float(user.get("monthly_income", 0.0)),
        "ai_data_consent": user.get("ai_data_consent", None),
        "essential_expense": float(user.get("essential_expense", 0.0)),
        "savings_goal": float(user.get("savings_goal", 0.0)),
        "onboarding_completed": bool(user.get("onboarding_completed", False)),
    }

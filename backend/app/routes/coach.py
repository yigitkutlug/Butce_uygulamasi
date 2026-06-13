from fastapi import APIRouter, Depends

from app.core.deps import get_current_user
from app.models.coach import CoachChatRequest, CoachChatResponse
from app.services.coach import coach_reply

router = APIRouter()


@router.post("/coach/chat", response_model=CoachChatResponse)
async def coach_chat(payload: CoachChatRequest, user=Depends(get_current_user)):
    result = await coach_reply(user["id"], payload.message)
    return CoachChatResponse(
        reply=result["reply"],
        remaining_budget=result.get("remaining_budget"),
        risk_level=result.get("risk_level", "info"),
    )


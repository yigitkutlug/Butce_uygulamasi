from pydantic import BaseModel, Field


class CoachChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)


class CoachChatResponse(BaseModel):
    reply: str
    remaining_budget: float | None = None
    risk_level: str = "info"


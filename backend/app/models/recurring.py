from datetime import datetime

from pydantic import BaseModel, Field


class RecurringCreate(BaseModel):
    title: str = Field(min_length=2)
    amount: float = Field(gt=0)
    category: str
    due_day: int = Field(ge=1, le=28)
    account: str | None = None
    interval: str = "monthly"


class RecurringActiveUpdate(BaseModel):
    is_active: bool


class RecurringOut(BaseModel):
    id: str
    user_id: str
    title: str
    amount: float
    category: str
    due_day: int
    account: str
    interval: str
    next_due_date: datetime
    is_active: bool


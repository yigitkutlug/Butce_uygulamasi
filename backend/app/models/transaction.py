from datetime import datetime
from pydantic import BaseModel, Field


class TransactionCreate(BaseModel):
    amount: float = Field(..., description="Use positive for income, negative for expense")
    description: str
    date: datetime | None = None
    category: str | None = None
    account: str | None = None


class TransactionUpdateCategory(BaseModel):
    category: str


class TransactionOut(BaseModel):
    id: str
    user_id: str
    amount: float
    description: str
    category: str
    account: str
    date: datetime

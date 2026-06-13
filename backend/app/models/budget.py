from pydantic import BaseModel, Field


class BudgetUpdate(BaseModel):
    category: str
    limit: float = Field(gt=0)


class BudgetOut(BaseModel):
    category: str
    limit: float
    spent: float = 0.0
    usage_percent: float = 0.0


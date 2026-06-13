from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    monthly_income: float = Field(gt=0)
    ai_data_consent: bool | None = None


class UserLogin(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)


class UserInDB(BaseModel):
    id: str
    email: EmailStr
    hashed_password: str
    monthly_income: float = 0.0
    ai_data_consent: bool | None = None
    essential_expense: float = 0.0
    savings_goal: float = 0.0
    onboarding_completed: bool = False


class UserProfile(BaseModel):
    id: str
    email: EmailStr
    monthly_income: float
    ai_data_consent: bool | None = None
    essential_expense: float = 0.0
    savings_goal: float = 0.0
    onboarding_completed: bool = False


class UserProfileUpdate(BaseModel):
    monthly_income: float = Field(gt=0)


class UserConsentUpdate(BaseModel):
    ai_data_consent: bool


class UserOnboardingUpdate(BaseModel):
    monthly_income: float = Field(gt=0)
    essential_expense: float = Field(ge=0)
    savings_goal: float = Field(ge=0)


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"

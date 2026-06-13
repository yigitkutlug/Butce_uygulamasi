import json
import logging
from pathlib import Path

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings
from pydantic_settings import SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    # Pydantic Settings .env dosyasını otomatik okur; deploy ortamında aynı
    # değerler environment variable olarak verilebilir.
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        populate_by_name=True,
    )

    app_name: str = "AI Budget Tracker"
    mongo_uri: str = Field(default="mongodb://localhost:27017", alias="MONGO_URI")
    mongo_db: str = Field(default="budget_tracker", alias="MONGO_DB")
    mongo_server_selection_timeout_ms: int = Field(default=5000, alias="MONGO_SERVER_SELECTION_TIMEOUT_MS")
    mongo_app_name: str = Field(default="ai-budget-tracker", alias="MONGO_APP_NAME")
    jwt_secret: str = Field(default="CHANGE_ME", alias="JWT_SECRET")
    jwt_algorithm: str = "HS256"
    access_token_exp_minutes: int = 60 * 24 * 7
    cors_allow_origins: list[str] = Field(
        default_factory=lambda: [
            "http://localhost:3000",
            "http://localhost:5173",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:5173",
            "http://localhost:8000",
            "http://127.0.0.1:8000",
        ],
        alias="CORS_ALLOW_ORIGINS",
    )
    gemini_api_key: str = Field(default="", alias="GEMINI_API_KEY")
    gemini_model: str = Field(default="gemini-2.5-flash", alias="GEMINI_MODEL")

    @field_validator("cors_allow_origins", mode="before")
    @classmethod
    def parse_cors_allow_origins(cls, value):
        # CORS listesi .env içinde JSON array veya virgüllü string olarak
        # yazılabilir; ikisini de destekleyerek deploy ayarını kolaylaştırırız.
        if isinstance(value, str):
            raw = value.strip()
            if raw.startswith("["):
                try:
                    parsed = json.loads(raw)
                    if isinstance(parsed, list):
                        return [str(item).strip() for item in parsed if str(item).strip()]
                except json.JSONDecodeError:
                    pass
            return [item.strip() for item in raw.split(",") if item.strip()]
        return value

    @model_validator(mode="after")
    def validate_security_settings(self):
        logger = logging.getLogger(__name__)
        # Geliştirme ortamı kolay açılsın ama üretimde zayıf JWT secret
        # unutulursa logda görünür olsun.
        if not self.jwt_secret or self.jwt_secret.strip() in {"CHANGE_ME", "change_me", "change_this_secret_before_production"}:
            logger.warning("JWT_SECRET is weak or placeholder; configure a strong secret in environment variables.")
        if "*" in self.cors_allow_origins:
            # Credentials açıkken wildcard CORS güvenli ve geçerli değildir; bu
            # yüzden yıldız temizlenir.
            logger.warning("CORS_ALLOW_ORIGINS contains '*'; removing wildcard to keep credentials-enabled CORS valid.")
            self.cors_allow_origins = [origin for origin in self.cors_allow_origins if origin != "*"]
            if not self.cors_allow_origins:
                self.cors_allow_origins = ["http://localhost:3000"]
        return self

settings = Settings()

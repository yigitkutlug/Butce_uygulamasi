from datetime import UTC, datetime, timedelta
from typing import Any
import logging

from jose import jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
logger = logging.getLogger(__name__)


def get_password_hash(password: str) -> str:
    # Şifre veritabanına düz metin yazılmaz; bcrypt hash kullanıcı girişinde
    # tekrar doğrulanmak üzere saklanır.
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        # Passlib hash formatını kendisi okur; beklenmeyen bozuk hash durumunda
        # login akışını patlatmak yerine False dönülür.
        return pwd_context.verify(plain_password, hashed_password)
    except Exception:
        logger.exception("Password verification failed due to an unexpected hash error.")
        return False


def create_access_token(subject: str, expires_delta: int | None = None) -> str:
    # JWT içindeki sub alanı kullanıcı id'sidir; backend sonraki isteklerde bu
    # id ile kullanıcıya ait verileri ayırır.
    expire = datetime.now(UTC) + timedelta(minutes=expires_delta or settings.access_token_exp_minutes)
    to_encode: dict[str, Any] = {"sub": subject, "exp": expire}
    return jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)


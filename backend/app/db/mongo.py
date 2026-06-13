from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import settings


class Mongo:
    # Motor client pahalı bir nesne olduğu için uygulama boyunca tek örnek
    # kullanılır; her request'te yeni bağlantı açılmaz.
    client: AsyncIOMotorClient | None = None


mongo = Mongo()


def _get_client() -> AsyncIOMotorClient:
    if mongo.client is None:
        # İlk ihtiyaç anında bağlantı kurulur. Timeout düşük tutulur ki demo
        # ortamında Mongo erişilemezse API uzun süre asılı kalmasın.
        mongo.client = AsyncIOMotorClient(
            settings.mongo_uri,
            serverSelectionTimeoutMS=settings.mongo_server_selection_timeout_ms,
            appname=settings.mongo_app_name,
        )
    return mongo.client


def get_db():
    client = _get_client()
    return client[settings.mongo_db]


async def ping_db() -> None:
    db = get_db()
    await db.command("ping")


async def ensure_indexes() -> None:
    db = get_db()
    # Email benzersizliği hem uygulama kodunda hem veritabanı indexinde korunur;
    # eş zamanlı kayıt denemelerinde duplicate kullanıcı oluşmaz.
    await db.users.create_index("email", unique=True, name="uniq_users_email")


async def close_db() -> None:
    if mongo.client is not None:
        mongo.client.close()
        mongo.client = None

import importlib
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.db.mongo import close_db, ensure_indexes, ping_db
from app.services.alerts import start_alert_worker, stop_alert_worker

app = FastAPI(
    title=settings.app_name,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)
logger = logging.getLogger(__name__)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def _include_router(module_path: str) -> None:
    # Route dosyaları tek tek import edilir; bir modül hata verirse loglanır ve
    # uygulamanın tamamen açılmaması yerine kalan servislerin çalışması sağlanır.
    try:
        module = importlib.import_module(module_path)
        router = getattr(module, "router", None)
        if router is None:
            logger.warning("Router module has no 'router': %s", module_path)
            return
        app.include_router(router)
    except Exception as exc:  # pragma: no cover - defensive import fallback
        logger.exception("Failed to import router %s: %s", module_path, exc)


for route_module in (
    # API yüzeyi modüllere ayrıldı: auth, profil, analiz, işlem, yatırım alarmı
    # gibi parçalar ayrı dosyalarda daha okunabilir ve test edilebilir durur.
    "app.routes.auth",
    "app.routes.alerts",
    "app.routes.profile",
    "app.routes.meta",
    "app.routes.export",
    "app.routes.coach",
    "app.routes.recurring",
    "app.routes.transactions",
    "app.routes.analytics",
):
    _include_router(route_module)


@app.on_event("startup")
async def startup_event():
    try:
        # Başlangıçta MongoDB bağlantısı ve indexler hazırlanır; fiyat alarmı
        # worker'ı da backend açık olduğu sürece düzenli kontrol yapar.
        await ping_db()
        await ensure_indexes()
        start_alert_worker(interval_sec=60)
    except Exception as exc:  # pragma: no cover - defensive startup fallback
        logger.exception("Startup DB initialization failed; API will run in degraded mode: %s", exc)


@app.on_event("shutdown")
async def shutdown_event():
    # Uygulama kapanırken background worker ve veritabanı bağlantısı temizlenir.
    await stop_alert_worker()
    await close_db()


@app.get("/")
async def health():
    return {"status": "ok"}

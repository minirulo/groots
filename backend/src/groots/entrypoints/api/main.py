from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from groots.config import settings
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes import router

container = Container()
container.config.from_dict(
    {
        "MONGO_DB_URI": settings.MONGO_DB_URI,
        "MONGO_DB": settings.MONGO_DB,
        "IPFS_API_URL": settings.IPFS_API_URL,
        "IPFS_GATEWAY_URL": settings.IPFS_GATEWAY_URL,
        "DISCOGS_APP_NAME": settings.DISCOGS_APP_NAME,
        "DISCOGS_USER_TOKEN": settings.DISCOGS_USER_TOKEN,
    }
)
container.wire(
    modules=[
        "groots.entrypoints.api.routes.auth",
        "groots.entrypoints.api.routes.users",
        "groots.entrypoints.api.routes.library",
        "groots.entrypoints.api.routes.albums",
        "groots.entrypoints.api.routes.playlists",
        "groots.entrypoints.api.routes.genres",
        "groots.entrypoints.api.routes.admin",
        "groots.entrypoints.api.routes.discogs",
    ]
)

app = FastAPI(
    title="Groots",
    description="Decentralized personal music streaming platform",
    version=settings.API_VERSION,
    docs_url=f"{settings.API_STR}/docs",
    redoc_url=f"{settings.API_STR}/redoc",
    openapi_url=f"{settings.API_STR}/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.ENVIRONMENT == "local" else [],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router, prefix=settings.API_STR)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "environment": settings.ENVIRONMENT}

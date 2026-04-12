from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import List


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", case_sensitive=True, extra="ignore"
    )

    # API
    API_STR: str = "/api"
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    ENVIRONMENT: str = "local"
    DEBUG: bool = False

    # JWT
    JWT_SECRET_KEY: str = "change-me-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    # API scopes
    USER_READ: str = "user:read"
    USER_WRITE: str = "user:write"
    LIBRARY_READ: str = "library:read"
    LIBRARY_WRITE: str = "library:write"
    LIBRARY_ADMIN: str = "library:admin"
    ALBUM_READ: str = "album:read"
    ALBUM_WRITE: str = "album:write"
    PLAYLIST_READ: str = "playlist:read"
    PLAYLIST_WRITE: str = "playlist:write"
    GENRE_READ: str = "genre:read"
    API_SCOPES: List[str] = [
        USER_READ,
        USER_WRITE,
        LIBRARY_READ,
        LIBRARY_WRITE,
        LIBRARY_ADMIN,
        ALBUM_READ,
        ALBUM_WRITE,
        PLAYLIST_READ,
        PLAYLIST_WRITE,
        GENRE_READ,
    ]

    # MongoDB
    MONGO_SERVER: str = "localhost"
    MONGO_PORT: int = 27017
    MONGO_USER: str = "groots"
    MONGO_PASSWORD: str = "password"
    MONGO_AUTH_DB: str = "admin"
    MONGO_DB: str = "groots"
    MONGO_DB_URI: str = ""

    @model_validator(mode="after")
    def assemble_db_uri(self) -> "Settings":
        if not self.MONGO_DB_URI:
            self.MONGO_DB_URI = (
                f"mongodb://{self.MONGO_USER}:{self.MONGO_PASSWORD}"
                f"@{self.MONGO_SERVER}:{self.MONGO_PORT}/{self.MONGO_AUTH_DB}"
            )
        return self

    # Admin & central library
    # Comma-separated list of emails that receive admin privileges on login.
    ADMIN_EMAILS: str = ""
    # Fixed ObjectId used as user_id for the central (server-owned) library.
    SYSTEM_USER_ID: str = "000000000000000000000000"

    @property
    def admin_email_set(self) -> set[str]:
        return {e.strip().lower() for e in self.ADMIN_EMAILS.split(",") if e.strip()}

    # IPFS / Cluster proxy
    # In dev, IPFS_API_HOST/PORT should point to the ipfs-cluster proxy (9095),
    # not directly to Kubo (5001). The proxy is Kubo-API-compatible.
    IPFS_API_HOST: str = "localhost"
    IPFS_API_PORT: int = 9095
    IPFS_GATEWAY_HOST: str = "localhost"
    IPFS_GATEWAY_PORT: int = 8080

    # Direct Kubo RPC — used for operations the cluster proxy doesn't handle
    # (e.g. /api/v0/id). Defaults to same host as IPFS_API but on port 5001.
    IPFS_KUBO_HOST: str = ""
    IPFS_KUBO_PORT: int = 5001

    @property
    def IPFS_API_URL(self) -> str:
        return f"http://{self.IPFS_API_HOST}:{self.IPFS_API_PORT}"

    @property
    def IPFS_KUBO_URL(self) -> str:
        host = self.IPFS_KUBO_HOST or self.IPFS_API_HOST
        return f"http://{host}:{self.IPFS_KUBO_PORT}"

    @property
    def IPFS_GATEWAY_URL(self) -> str:
        return f"http://{self.IPFS_GATEWAY_HOST}:{self.IPFS_GATEWAY_PORT}"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


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

    # MongoDB
    MONGO_SERVER: str = "localhost"
    MONGO_PORT: int = 27017
    MONGO_USER: str = "groots"
    MONGO_PASSWORD: str = "groots"
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

    # IPFS / Kubo
    IPFS_API_HOST: str = "localhost"
    IPFS_API_PORT: int = 5001
    IPFS_GATEWAY_HOST: str = "localhost"
    IPFS_GATEWAY_PORT: int = 8080

    @property
    def IPFS_API_URL(self) -> str:
        return f"http://{self.IPFS_API_HOST}:{self.IPFS_API_PORT}"

    @property
    def IPFS_GATEWAY_URL(self) -> str:
        return f"http://{self.IPFS_GATEWAY_HOST}:{self.IPFS_GATEWAY_PORT}"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

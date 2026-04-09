from dataclasses import dataclass, field
from datetime import datetime

from groots.domain.model.base import new_id


@dataclass
class User:
    username: str
    email: str
    hashed_password: str
    id: str = field(default_factory=new_id)
    created_at: datetime = field(default_factory=datetime.utcnow)
    is_active: bool = True
    is_admin: bool = False
    storage_quota_bytes: int = 10 * 1024 * 1024 * 1024  # 10 GB
    used_storage_bytes: int = 0

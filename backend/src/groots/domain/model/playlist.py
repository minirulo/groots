from dataclasses import dataclass, field
from datetime import datetime

from groots.domain.model.base import new_id


@dataclass
class Playlist:
    user_id: str
    name: str
    id: str = field(default_factory=new_id)
    track_ids: list = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)

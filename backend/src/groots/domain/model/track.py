from dataclasses import dataclass, field
from datetime import datetime

from groots.domain.model.base import new_id


@dataclass
class Track:
    user_id: str
    cid: str  # IPFS Content Identifier
    title: str
    artist: str
    duration_seconds: int
    file_size_bytes: int
    id: str = field(default_factory=new_id)
    album: str | None = None
    album_id: str | None = None  # Reference to Album entity
    track_number: int | None = None
    year: int | None = None
    genre: str | None = None
    mime_type: str = "audio/mpeg"
    pinned: bool = False  # True when central node has pinned the CID
    fingerprint_id: str | None = None  # ID of the TrackFingerprint record for this track
    matched_central_id: str | None = None  # fingerprint ID of central match, if any
    created_at: datetime = field(default_factory=datetime.utcnow)

from dataclasses import dataclass, field
from datetime import datetime

from groots.domain.model.base import new_id


@dataclass
class TrackFingerprint:
    """
    Global fingerprint record. One entry per unique audio fingerprint.
    Multiple users may upload the same audio; only one fingerprint entry exists.
    """

    fingerprint_hex: str  # raw chromaprint fingerprint stored as hex string
    duration_seconds: int
    id: str = field(default_factory=new_id)
    album_id: str | None = None  # album this fingerprint maps to (if resolved)
    title: str | None = None  # best-known title for this audio
    artist: str | None = None  # best-known artist for this audio
    is_central: bool = False  # True when part of the server-managed library
    created_at: datetime = field(default_factory=datetime.utcnow)

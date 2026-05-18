from dataclasses import dataclass, field
from datetime import datetime

from groots.domain.model.base import new_id


@dataclass
class Track:
    cid: str  # IPFS Content Identifier
    title: str
    duration_seconds: int
    file_size_bytes: int
    album_id: str | None = None  # Reference to Album entity (required for all tracks)
    id: str = field(default_factory=new_id)
    track_number: int | None = None
    mime_type: str = "audio/mpeg"
    pinned: bool = False  # True when central node has pinned the CID
    fingerprint_id: str | None = None  # ID of the TrackFingerprint record for this track
    matched_central_id: str | None = None  # fingerprint ID of central match, if any
    source: str | None = None  # e.g. "cd", "vinyl", "digital_download", "streaming_purchase"
    disc_number: int | None = None  # which disc/vinyl (1, 2…); null means single-disc album
    side: str | None = None  # vinyl side ("A", "B", "C", "D"); null for CDs
    created_at: datetime = field(default_factory=datetime.utcnow)

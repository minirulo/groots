from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum

from groots.domain.model.base import new_id


class RecordingFormat(StrEnum):
    CD = "CD"
    LP = "LP"
    EP = "EP"
    SINGLE = "Single"
    COMPILATION = "Compilation"
    DIGITAL = "Digital"
    CASSETTE = "Cassette"


@dataclass
class Album:
    """Global album shared across all users. Not owned by any single user."""

    title: str
    artist: str
    id: str = field(default_factory=new_id)
    year: int | None = None
    genre: str | None = None
    description: str | None = None
    cover_cid: str | None = None  # IPFS CID for cover artwork
    recording_format: RecordingFormat | None = None  # e.g. CD, LP, EP, Single…
    created_by: str | None = None  # user_id of whoever first created this album
    created_at: datetime = field(default_factory=datetime.utcnow)

    def __post_init__(self) -> None:
        if self.recording_format is not None and not isinstance(
            self.recording_format, RecordingFormat
        ):
            try:
                self.recording_format = RecordingFormat(self.recording_format)
            except ValueError:
                self.recording_format = None

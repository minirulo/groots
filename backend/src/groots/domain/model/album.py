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


class Genre(StrEnum):
    BLUES = "Blues"
    BRASS_AND_MILITARY = "Brass & Military"
    CHILDRENS = "Children's"
    CLASSICAL = "Classical"
    ELECTRONIC = "Electronic"
    FOLK_WORLD_AND_COUNTRY = "Folk, World, & Country"
    FUNK_SOUL = "Funk / Soul"
    HIP_HOP = "Hip Hop"
    JAZZ = "Jazz"
    LATIN = "Latin"
    NON_MUSIC = "Non-Music"
    POP = "Pop"
    REGGAE = "Reggae"
    ROCK = "Rock"
    STAGE_AND_SCREEN = "Stage & Screen"


@dataclass
class Album:
    """Global album shared across all users. Not owned by any single user."""

    title: str
    artist: str
    id: str = field(default_factory=new_id)
    year: int | None = None
    genre: Genre | None = None
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
        if self.genre is not None and not isinstance(self.genre, Genre):
            try:
                self.genre = Genre(self.genre)
            except ValueError:
                self.genre = None

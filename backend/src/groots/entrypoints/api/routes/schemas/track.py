from datetime import datetime

from pydantic import BaseModel


class AddTrackRequest(BaseModel):
    cid: str
    title: str
    artist: str
    duration_seconds: int
    file_size_bytes: int
    album: str | None = None
    album_id: str | None = None
    track_number: int | None = None
    year: int | None = None
    genre: str | None = None
    mime_type: str = "audio/mpeg"
    source: str | None = None


class CdVerificationResponse(BaseModel):
    has_isrc: bool
    has_mcn: bool
    encoder: str | None
    confidence: str  # "strong" | "medium" | "weak"


class TrackResponse(BaseModel):
    id: str
    cid: str
    title: str
    artist: str
    album: str | None
    album_id: str | None
    track_number: int | None
    year: int | None
    genre: str | None
    duration_seconds: int
    file_size_bytes: int
    mime_type: str
    pinned: bool
    matched_central_id: str | None
    source: str | None
    created_at: datetime


class StreamUrlResponse(BaseModel):
    track_id: str
    stream_url: str

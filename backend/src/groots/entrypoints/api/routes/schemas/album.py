from datetime import datetime

from pydantic import BaseModel

from groots.domain.model.album import RecordingFormat


class CreateAlbumRequest(BaseModel):
    title: str
    artist: str
    year: int | None = None
    genre: str | None = None
    description: str | None = None
    recording_format: RecordingFormat | None = None


class UpdateAlbumRequest(BaseModel):
    title: str | None = None
    artist: str | None = None
    year: int | None = None
    genre: str | None = None
    description: str | None = None
    recording_format: RecordingFormat | None = None


class AlbumResponse(BaseModel):
    id: str
    title: str
    artist: str
    year: int | None
    genre: str | None
    description: str | None
    cover_cid: str | None
    recording_format: RecordingFormat | None
    created_by: str | None
    created_at: datetime


class AssignTrackRequest(BaseModel):
    track_id: str
    track_number: int | None = None

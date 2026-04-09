from datetime import datetime

from pydantic import BaseModel


class CreatePlaylistRequest(BaseModel):
    name: str


class RenamePlaylistRequest(BaseModel):
    name: str


class PlaylistResponse(BaseModel):
    id: str
    name: str
    track_ids: list[str]
    created_at: datetime


class AddTrackToPlaylistRequest(BaseModel):
    track_id: str

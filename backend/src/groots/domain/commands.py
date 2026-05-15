from dataclasses import dataclass


@dataclass
class RegisterUser:
    username: str
    email: str
    password: str
    role_id: str


@dataclass
class LoginUser:
    email: str
    password: str


@dataclass
class AddTrack:
    user_id: str
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
    disc_number: int | None = None
    side: str | None = None


@dataclass
class RemoveTrack:
    user_id: str
    track_id: str


@dataclass
class PinTrack:
    user_id: str
    track_id: str
    cid: str


@dataclass
class UploadTrack:
    user_id: str
    filename: str
    content: bytes
    file_size_bytes: int
    mime_type: str
    source: str | None = None
    hint_artist: str | None = None
    hint_title: str | None = None
    hint_album: str | None = None
    hint_year: int | None = None
    hint_track_number: int | None = None


# ── Album commands ────────────────────────────────────────────────────────────


@dataclass
class CreateAlbum:
    title: str
    artist: str
    created_by: str | None = None  # user_id of creator; None for system
    year: int | None = None
    genre: str | None = None
    description: str | None = None
    recording_format: str | None = None


@dataclass
class UpdateAlbum:
    album_id: str
    requesting_user_id: str  # used for permission check (must be creator or admin)
    title: str | None = None
    artist: str | None = None
    year: int | None = None
    genre: str | None = None
    description: str | None = None
    recording_format: str | None = None


@dataclass
class DeleteAlbum:
    album_id: str
    requesting_user_id: str
    is_admin: bool = False


@dataclass
class UploadAlbumCover:
    user_id: str
    album_id: str
    content: bytes
    filename: str
    mime_type: str


@dataclass
class AssignTrackToAlbum:
    user_id: str
    track_id: str
    album_id: str
    track_number: int | None = None
    disc_number: int | None = None
    side: str | None = None


@dataclass
class UnassignTrackFromAlbum:
    user_id: str
    track_id: str


# ── Playlist commands ─────────────────────────────────────────────────────────


@dataclass
class CreatePlaylist:
    user_id: str
    name: str


@dataclass
class RenamePlaylist:
    user_id: str
    playlist_id: str
    name: str


@dataclass
class DeletePlaylist:
    user_id: str
    playlist_id: str


@dataclass
class AddTrackToPlaylist:
    user_id: str
    playlist_id: str
    track_id: str


@dataclass
class RemoveTrackFromPlaylist:
    user_id: str
    playlist_id: str
    track_id: str


# ── Central library commands ──────────────────────────────────────────────────


@dataclass
class IngestCentralTrack:
    """Admin command: add an audio file to the server-managed central library."""

    filename: str
    content: bytes
    file_size_bytes: int
    mime_type: str

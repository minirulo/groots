"""Read-only queries that bypass the command bus for efficiency."""

from dataclasses import asdict

from groots.service_layer.unit_of_work import AbstractUnitOfWork


async def get_user_library(user_id: str, uow: AbstractUnitOfWork) -> list[dict]:
    async with uow:
        albums = await uow.albums.list_by_user(user_id)
        album_ids = [a.id for a in albums]
        tracks = await uow.tracks.list_by_album_ids(album_ids)
        return [asdict(t) for t in tracks]


async def get_track(
    track_id: str, user_id: str, uow: AbstractUnitOfWork
) -> dict | None:
    async with uow:
        track = await uow.tracks.get(track_id)
        if not track or not track.album_id:
            return None
        album = await uow.albums.get(track.album_id)
        if album and album.user_id == user_id:
            return asdict(track)
        return None


async def get_user_profile(user_id: str, uow: AbstractUnitOfWork) -> dict | None:
    async with uow:
        user = await uow.users.get(user_id)
        if not user:
            return None
        role = await uow.roles.get(user.role_id)
        if not role:
            return None
        return {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "storage_quota_bytes": user.storage_quota_bytes,
            "used_storage_bytes": user.used_storage_bytes,
            "is_admin": user.is_admin,
            "created_at": user.created_at,
            "role": role.name,
        }


async def get_catalogue_albums(uow: AbstractUnitOfWork, limit: int = 200) -> list[dict]:
    """Return the global album catalogue (all albums, admin-curated or otherwise)."""
    async with uow:
        albums = await uow.albums.list_all()
        return [asdict(a) for a in albums[:limit]]


async def get_user_albums(user_id: str, uow: AbstractUnitOfWork) -> list[dict]:
    """Return albums owned by the given user."""
    async with uow:
        albums = await uow.albums.list_by_user(user_id)
        return [asdict(a) for a in albums]


async def get_album(album_id: str, uow: AbstractUnitOfWork) -> dict | None:
    """Return a global album by id (not user-scoped)."""
    async with uow:
        album = await uow.albums.get(album_id)
        return asdict(album) if album else None


async def search_albums(query: str, uow: AbstractUnitOfWork) -> list[dict]:
    async with uow:
        albums = await uow.albums.search(query)
        return [asdict(a) for a in albums]


async def get_central_library(uow: AbstractUnitOfWork) -> list[dict]:
    from groots.config import settings

    async with uow:
        albums = await uow.albums.list_by_user(settings.SYSTEM_USER_ID)
        album_ids = [a.id for a in albums]
        tracks = await uow.tracks.list_by_album_ids(album_ids)
        return [asdict(t) for t in tracks]


async def get_all_fingerprints(uow: AbstractUnitOfWork) -> list[dict]:
    async with uow:
        cursor = uow.fingerprints.collection.find({})
        from groots.domain.model.base import from_document
        from groots.domain.model.fingerprint import TrackFingerprint

        fps = [from_document(doc, TrackFingerprint) async for doc in cursor]
        return [asdict(f) for f in fps]


async def get_user_playlists(user_id: str, uow: AbstractUnitOfWork) -> list[dict]:
    async with uow:
        playlists = await uow.playlists.list_by_user(user_id)
        return [asdict(p) for p in playlists]


async def get_playlist(
    playlist_id: str, user_id: str, uow: AbstractUnitOfWork
) -> dict | None:
    async with uow:
        playlist = await uow.playlists.get(playlist_id)
        if playlist and playlist.user_id == user_id:
            return asdict(playlist)
        return None



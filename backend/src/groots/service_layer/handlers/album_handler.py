from groots.service_layer.handlers.library_handler import _ext_for_mime
from groots.domain.commands import (
    AssignTrackToAlbum,
    CreateAlbum,
    DeleteAlbum,
    UnassignTrackFromAlbum,
    UpdateAlbum,
    UploadAlbumCover,
)
from groots.domain.errors import (
    AdminRequired,
    AlbumNotFound,
    AlbumNotOwnedByUser,
    TrackNotFound,
    TrackNotOwnedByUser,
)
from groots.domain.model.album import Album
from groots.service_layer.unit_of_work import AbstractUnitOfWork


async def handle_create_album(cmd: CreateAlbum, uow: AbstractUnitOfWork) -> dict:
    async with uow:
        album = Album(
            title=cmd.title,
            artist=cmd.artist,
            year=cmd.year,
            genre=cmd.genre,
            description=cmd.description,
            recording_format=cmd.recording_format,
            created_by=cmd.created_by,
        )
        await uow.albums.add(album)
        await uow.commit()
        return {"album_id": album.id}


async def handle_update_album(cmd: UpdateAlbum, uow: AbstractUnitOfWork) -> dict:
    async with uow:
        album = await uow.albums.get(cmd.album_id)
        if not album:
            raise AlbumNotFound(cmd.album_id)
        if album.created_by and album.created_by != cmd.requesting_user_id:
            raise AlbumNotOwnedByUser()

        if cmd.title is not None:
            album.title = cmd.title
        if cmd.artist is not None:
            album.artist = cmd.artist
        if cmd.year is not None:
            album.year = cmd.year
        if cmd.genre is not None:
            album.genre = cmd.genre
        if cmd.description is not None:
            album.description = cmd.description
        if cmd.recording_format is not None:
            album.recording_format = cmd.recording_format

        await uow.albums.update(album)
        await uow.commit()
        return {"album_id": album.id}


async def handle_delete_album(cmd: DeleteAlbum, uow: AbstractUnitOfWork) -> None:
    if not cmd.is_admin:
        raise AdminRequired()
    async with uow:
        album = await uow.albums.get(cmd.album_id)
        if not album:
            raise AlbumNotFound(cmd.album_id)

        # Cascade: delete all tracks that belong to this album
        tracks = await uow.tracks.list_by_album(cmd.album_id)
        for track in tracks:
            if track.pinned:
                await uow.ipfs.pin_rm(track.cid)
                await uow.ipfs.mfs_rm(f"{track.title}{_ext_for_mime(track.mime_type)}")
            user = await uow.users.get(track.user_id)
            if user:
                user.used_storage_bytes = max(
                    0, user.used_storage_bytes - track.file_size_bytes
                )
                await uow.users.update(user)
            await uow.tracks.delete(track.id)

        await uow.albums.delete(cmd.album_id)
        await uow.commit()


async def handle_upload_album_cover(
    cmd: UploadAlbumCover, uow: AbstractUnitOfWork
) -> dict:
    async with uow:
        album = await uow.albums.get(cmd.album_id)
        if not album:
            raise AlbumNotFound(cmd.album_id)
        if album.created_by and album.created_by != cmd.user_id:
            raise AlbumNotOwnedByUser()

        cid = await uow.ipfs.pin_add_bytes(cmd.content, cmd.filename)
        album.cover_cid = cid
        await uow.albums.update(album)
        await uow.commit()
        return {"cover_cid": cid}


async def handle_assign_track_to_album(
    cmd: AssignTrackToAlbum, uow: AbstractUnitOfWork
) -> None:
    async with uow:
        album = await uow.albums.get(cmd.album_id)
        if not album:
            raise AlbumNotFound(cmd.album_id)

        track = await uow.tracks.get(cmd.track_id)
        if not track:
            raise TrackNotFound(cmd.track_id)
        if track.user_id != cmd.user_id:
            raise TrackNotOwnedByUser()

        track.album_id = cmd.album_id
        track.album = album.title
        if cmd.track_number is not None:
            track.track_number = cmd.track_number

        await uow.tracks.update(track)
        await uow.commit()


async def handle_unassign_track_from_album(
    cmd: UnassignTrackFromAlbum, uow: AbstractUnitOfWork
) -> None:
    async with uow:
        track = await uow.tracks.get(cmd.track_id)
        if not track:
            raise TrackNotFound(cmd.track_id)
        if track.user_id != cmd.user_id:
            raise TrackNotOwnedByUser()

        track.album_id = None
        track.track_number = None
        await uow.tracks.update(track)
        await uow.commit()

from groots.domain.commands import (
    AddTrackToPlaylist,
    CreatePlaylist,
    DeletePlaylist,
    RemoveTrackFromPlaylist,
    RenamePlaylist,
)
from groots.domain.errors import PlaylistNotFound, PlaylistNotOwnedByUser
from groots.domain.model.playlist import Playlist
from groots.service_layer.unit_of_work import AbstractUnitOfWork


async def handle_create_playlist(cmd: CreatePlaylist, uow: AbstractUnitOfWork) -> dict:
    async with uow:
        playlist = Playlist(user_id=cmd.user_id, name=cmd.name)
        await uow.playlists.add(playlist)
        await uow.commit()
        return {"playlist_id": playlist.id}


async def handle_rename_playlist(cmd: RenamePlaylist, uow: AbstractUnitOfWork) -> None:
    async with uow:
        playlist = await uow.playlists.get(cmd.playlist_id)
        if not playlist:
            raise PlaylistNotFound(cmd.playlist_id)
        if playlist.user_id != cmd.user_id:
            raise PlaylistNotOwnedByUser()

        playlist.name = cmd.name
        await uow.playlists.update(playlist)
        await uow.commit()


async def handle_delete_playlist(cmd: DeletePlaylist, uow: AbstractUnitOfWork) -> None:
    async with uow:
        playlist = await uow.playlists.get(cmd.playlist_id)
        if not playlist:
            raise PlaylistNotFound(cmd.playlist_id)
        if playlist.user_id != cmd.user_id:
            raise PlaylistNotOwnedByUser()

        await uow.playlists.delete(cmd.playlist_id)
        await uow.commit()


async def handle_add_track_to_playlist(
    cmd: AddTrackToPlaylist, uow: AbstractUnitOfWork
) -> None:
    async with uow:
        playlist = await uow.playlists.get(cmd.playlist_id)
        if not playlist:
            raise PlaylistNotFound(cmd.playlist_id)
        if playlist.user_id != cmd.user_id:
            raise PlaylistNotOwnedByUser()

        if cmd.track_id not in playlist.track_ids:
            playlist.track_ids.append(cmd.track_id)
            await uow.playlists.update(playlist)
            await uow.commit()


async def handle_remove_track_from_playlist(
    cmd: RemoveTrackFromPlaylist, uow: AbstractUnitOfWork
) -> None:
    async with uow:
        playlist = await uow.playlists.get(cmd.playlist_id)
        if not playlist:
            raise PlaylistNotFound(cmd.playlist_id)
        if playlist.user_id != cmd.user_id:
            raise PlaylistNotOwnedByUser()

        playlist.track_ids = [tid for tid in playlist.track_ids if tid != cmd.track_id]
        await uow.playlists.update(playlist)
        await uow.commit()

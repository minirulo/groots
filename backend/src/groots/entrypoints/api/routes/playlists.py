from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status, Security

from groots.domain.commands import (
    AddTrackToPlaylist,
    CreatePlaylist,
    DeletePlaylist,
    RemoveTrackFromPlaylist,
    RenamePlaylist,
)
from groots.domain.errors import SoundNetError
from groots.entrypoints.api import views
from groots.entrypoints.api.auth import get_current_oauth_user
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.playlist import (
    AddTrackToPlaylistRequest,
    CreatePlaylistRequest,
    PlaylistResponse,
    RenamePlaylistRequest,
)
from groots.service_layer.errors import to_http_exception
from groots.service_layer.messagebus import MessageBus
from groots.service_layer.unit_of_work import AbstractUnitOfWork
from groots.config import settings

router = APIRouter(prefix="/playlists", tags=["playlists"])


@router.get("")
@inject
async def list_playlists(
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.PLAYLIST_READ])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[PlaylistResponse]:
    playlists = await views.get_user_playlists(current_user["user_id"], uow)
    return [PlaylistResponse(**p) for p in playlists]


@router.post("", status_code=201)
@inject
async def create_playlist(
    body: CreatePlaylistRequest,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.PLAYLIST_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        return await bus.handle(
            CreatePlaylist(user_id=current_user["user_id"], name=body.name)
        )
    except SoundNetError as e:
        raise to_http_exception(e)


@router.get("/{playlist_id}")
@inject
async def get_playlist(
    playlist_id: str,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.PLAYLIST_READ])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> PlaylistResponse:
    playlist = await views.get_playlist(playlist_id, current_user["user_id"], uow)
    if not playlist:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Playlist not found"
        )
    return PlaylistResponse(**playlist)


@router.patch("/{playlist_id}", status_code=200)
@inject
async def rename_playlist(
    playlist_id: str,
    body: RenamePlaylistRequest,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.PLAYLIST_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        await bus.handle(
            RenamePlaylist(
                user_id=current_user["user_id"],
                playlist_id=playlist_id,
                name=body.name,
            )
        )
        return {"renamed": True}
    except SoundNetError as e:
        raise to_http_exception(e)


@router.delete("/{playlist_id}", status_code=204)
@inject
async def delete_playlist(
    playlist_id: str,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.PLAYLIST_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> None:
    try:
        await bus.handle(
            DeletePlaylist(user_id=current_user["user_id"], playlist_id=playlist_id)
        )
    except SoundNetError as e:
        raise to_http_exception(e)


@router.post("/{playlist_id}/tracks", status_code=200)
@inject
async def add_track(
    playlist_id: str,
    body: AddTrackToPlaylistRequest,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.PLAYLIST_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        await bus.handle(
            AddTrackToPlaylist(
                user_id=current_user["user_id"],
                playlist_id=playlist_id,
                track_id=body.track_id,
            )
        )
        return {"added": True}
    except SoundNetError as e:
        raise to_http_exception(e)


@router.delete("/{playlist_id}/tracks/{track_id}", status_code=200)
@inject
async def remove_track(
    playlist_id: str,
    track_id: str,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.PLAYLIST_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        await bus.handle(
            RemoveTrackFromPlaylist(
                user_id=current_user["user_id"],
                playlist_id=playlist_id,
                track_id=track_id,
            )
        )
        return {"removed": True}
    except SoundNetError as e:
        raise to_http_exception(e)

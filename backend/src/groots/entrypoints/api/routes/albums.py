from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Query,
    UploadFile,
    status,
    Security,
)

from groots.domain.commands import (
    AssignTrackToAlbum,
    CreateAlbum,
    DeleteAlbum,
    UnassignTrackFromAlbum,
    UpdateAlbum,
    UploadAlbumCover,
)
from groots.domain.errors import GrootException
from groots.entrypoints.api import views
from groots.entrypoints.api.auth import OAuthUser, get_current_oauth_user
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.album import (
    AlbumResponse,
    AssignTrackRequest,
    CreateAlbumRequest,
    UpdateAlbumRequest,
)
from groots.service_layer.errors import to_http_exception
from groots.service_layer.messagebus import MessageBus
from groots.service_layer.unit_of_work import AbstractUnitOfWork
from groots.config import settings

router = APIRouter(prefix="/albums", tags=["albums"])


@router.get("")
@inject
async def list_albums(
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.ALBUM_READ])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[AlbumResponse]:
    """Return albums that the current user has tracks in."""
    albums = await views.get_user_albums(current_user.user_id, uow)
    return [AlbumResponse(**a) for a in albums]


@router.get("/catalogue")
@inject
async def get_catalogue(
    _: Annotated[dict, Security(get_current_oauth_user, scopes=[settings.ALBUM_READ])],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[AlbumResponse]:
    """Return the global album catalogue (all albums, for browsing and sync matching)."""
    albums = await views.get_catalogue_albums(uow)
    return [AlbumResponse(**a) for a in albums]


@router.get("/search")
@inject
async def search_albums(
    q: Annotated[str, Query(min_length=1)],
    _: Annotated[dict, Security(get_current_oauth_user, scopes=[settings.ALBUM_READ])],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[AlbumResponse]:
    """Search the global album catalogue by title or artist."""
    albums = await views.search_albums(q, uow)
    return [AlbumResponse(**a) for a in albums]


@router.post("", status_code=201)
@inject
async def create_album(
    body: CreateAlbumRequest,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.ALBUM_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        return await bus.handle(
            CreateAlbum(
                title=body.title,
                artist=body.artist,
                year=body.year,
                genre=body.genre,
                description=body.description,
                recording_format=body.recording_format,
                user_id=current_user.user_id,
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.get("/{album_id}")
@inject
async def get_album(
    album_id: str,
    _: Annotated[dict, Security(get_current_oauth_user, scopes=[settings.ALBUM_READ])],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> AlbumResponse:
    album = await views.get_album(album_id, uow)
    if not album:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Album not found"
        )
    return AlbumResponse(**album)


@router.put("/{album_id}", status_code=200)
@inject
async def update_album(
    album_id: str,
    body: UpdateAlbumRequest,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.ALBUM_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        return await bus.handle(
            UpdateAlbum(
                album_id=album_id,
                requesting_user_id=current_user.user_id,
                title=body.title,
                artist=body.artist,
                year=body.year,
                genre=body.genre,
                description=body.description,
                recording_format=body.recording_format,
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.delete("/{album_id}", status_code=204)
@inject
async def delete_album(
    album_id: str,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.ALBUM_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> None:
    try:
        await bus.handle(
            DeleteAlbum(
                album_id=album_id,
                requesting_user_id=current_user.user_id,
                is_admin=current_user.is_admin,
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.post("/{album_id}/cover", status_code=200)
@inject
async def upload_cover(
    album_id: str,
    file: Annotated[UploadFile, File()],
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.ALBUM_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    content = await file.read()
    try:
        return await bus.handle(
            UploadAlbumCover(
                user_id=current_user.user_id,
                album_id=album_id,
                content=content,
                filename=file.filename or "cover",
                mime_type=file.content_type or "image/jpeg",
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.post("/{album_id}/tracks", status_code=200)
@inject
async def assign_track(
    album_id: str,
    body: AssignTrackRequest,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.ALBUM_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        await bus.handle(
            AssignTrackToAlbum(
                user_id=current_user.user_id,
                track_id=body.track_id,
                album_id=album_id,
                track_number=body.track_number,
                disc_number=body.disc_number,
                side=body.side,
            )
        )
        return {"assigned": True}
    except GrootException as e:
        raise to_http_exception(e)


@router.delete("/{album_id}/tracks/{track_id}", status_code=200)
@inject
async def unassign_track(
    album_id: str,
    track_id: str,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.ALBUM_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        await bus.handle(
            UnassignTrackFromAlbum(
                user_id=current_user.user_id,
                track_id=track_id,
            )
        )
        return {"unassigned": True}
    except GrootException as e:
        raise to_http_exception(e)

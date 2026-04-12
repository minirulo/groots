from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    UploadFile,
    status,
    Security,
)

from groots.domain.commands import AddTrack, PinTrack, RemoveTrack, UploadTrack
from groots.domain.errors import SoundNetError
from groots.entrypoints.api import views
from groots.entrypoints.api.auth import get_current_oauth_user
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.track import (
    AddTrackRequest,
    StreamUrlResponse,
    TrackResponse,
)
from groots.service_layer.errors import to_http_exception
from groots.service_layer.messagebus import MessageBus
from groots.service_layer.unit_of_work import AbstractUnitOfWork
from groots.config import settings

router = APIRouter(prefix="/library", tags=["library"])


@router.get(
    "",
)
@inject
async def list_tracks(
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_READ])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[TrackResponse]:
    tracks = await views.get_user_library(current_user["user_id"], uow)
    return [TrackResponse(**t) for t in tracks]


@router.post("", status_code=201)
@inject
async def add_track(
    body: AddTrackRequest,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        return await bus.handle(
            AddTrack(
                user_id=current_user["user_id"],
                cid=body.cid,
                title=body.title,
                artist=body.artist,
                duration_seconds=body.duration_seconds,
                file_size_bytes=body.file_size_bytes,
                album=body.album,
                album_id=body.album_id,
                track_number=body.track_number,
                year=body.year,
                genre=body.genre,
                mime_type=body.mime_type,
            )
        )
    except SoundNetError as e:
        raise to_http_exception(e)


@router.delete("/{track_id}", status_code=204)
@inject
async def remove_track(
    track_id: str,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> None:
    try:
        await bus.handle(
            RemoveTrack(user_id=current_user["user_id"], track_id=track_id)
        )
    except SoundNetError as e:
        raise to_http_exception(e)


@router.post("/{track_id}/pin", status_code=200)
@inject
async def pin_track(
    track_id: str,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> dict:
    track = await views.get_track(track_id, current_user["user_id"], uow)
    if not track:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Track not found"
        )
    try:
        await bus.handle(
            PinTrack(
                user_id=current_user["user_id"],
                track_id=track_id,
                cid=track["cid"],
            )
        )
        return {"pinned": True}
    except SoundNetError as e:
        raise to_http_exception(e)


@router.get("/{track_id}/stream", response_model=StreamUrlResponse)
@inject
async def get_stream_url(
    track_id: str,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> StreamUrlResponse:
    """
    Returns the IPFS gateway URL for streaming this track.
    The track must be pinned on the central node for availability when
    the user's home machine is offline.
    In production, proxy this URL through nginx with auth to prevent
    public CID access.
    """
    track = await views.get_track(track_id, current_user["user_id"], uow)
    if not track:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Track not found"
        )
    if not track["pinned"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Track is not pinned on the central node yet. Call /pin first.",
        )
    from groots.adapters.impl.ipfs_client import IPFSClient
    from groots.config import settings as cfg

    ipfs = IPFSClient(api_url=cfg.IPFS_API_URL, gateway_url=cfg.IPFS_GATEWAY_URL)
    return StreamUrlResponse(
        track_id=track_id, stream_url=ipfs.stream_url(track["cid"])
    )


@router.post("/upload", status_code=201)
@inject
async def upload_track(
    file: Annotated[UploadFile, File()],
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    """
    Mobile upload: client sends audio file → server adds to IPFS + pins + registers.
    The track is immediately pinned so it's available across all devices.
    """
    content = await file.read()
    try:
        return await bus.handle(
            UploadTrack(
                user_id=current_user["user_id"],
                filename=file.filename or "track",
                content=content,
                file_size_bytes=len(content),
                mime_type=file.content_type or "audio/mpeg",
            )
        )
    except SoundNetError as e:
        raise to_http_exception(e)

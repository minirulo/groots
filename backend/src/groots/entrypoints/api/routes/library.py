import base64
from typing import Annotated

from dependency_injector.wiring import inject, Provide
from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Response,
    Security,
    status,
    UploadFile,
)
from fastapi.responses import JSONResponse

from groots.adapters.impl.metadata_extractor import MetadataExtractor
from groots.config import settings
from groots.domain.commands import (
    AddTrack,
    PinTrack,
    RemoveTrack,
    ReplaceRecording,
    UploadTrack,
)
from groots.domain.errors import GrootException
from groots.entrypoints.api import views
from groots.entrypoints.api.auth import get_current_oauth_user, OAuthUser
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.track import (
    AddTrackRequest,
    StreamUrlResponse,
    TrackResponse,
)
from groots.service_layer.errors import to_http_exception
from groots.service_layer.messagebus import MessageBus
from groots.service_layer.unit_of_work import AbstractUnitOfWork

_COVER_READ_LIMIT = 1024 * 1024  # 1 MB — enough to reach any embedded cover

router = APIRouter(prefix="/library", tags=["library"])


@router.get(
    "",
)
@inject
async def list_tracks(
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.LIBRARY_READ])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[TrackResponse]:
    tracks = await views.get_user_library(current_user.user_id, uow)
    return [TrackResponse(**t) for t in tracks]


@router.post("", status_code=201)
@inject
async def add_track(
    body: AddTrackRequest,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    try:
        return await bus.handle(
            AddTrack(
                cid=body.cid,
                title=body.title,
                duration_seconds=body.duration_seconds,
                file_size_bytes=body.file_size_bytes,
                album_id=body.album_id,
                track_number=body.track_number,
                mime_type=body.mime_type,
                source=body.source,
                disc_number=body.disc_number,
                side=body.side,
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.delete("/{track_id}", status_code=204)
@inject
async def remove_track(
    track_id: str,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> None:
    try:
        await bus.handle(RemoveTrack(user_id=current_user.user_id, track_id=track_id))
    except GrootException as e:
        raise to_http_exception(e)


@router.post("/{track_id}/pin", status_code=200)
@inject
async def pin_track(
    track_id: str,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> dict:
    track = await views.get_track(track_id, current_user.user_id, uow)
    if not track:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Track not found"
        )
    try:
        await bus.handle(
            PinTrack(
                user_id=current_user.user_id,
                track_id=track_id,
                cid=track["cid"],
            )
        )
        return {"pinned": True}
    except GrootException as e:
        raise to_http_exception(e)


@router.get("/{track_id}/stream", response_model=StreamUrlResponse)
@inject
async def get_stream_url(
    track_id: str,
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
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
    track = await views.get_track(track_id, current_user.user_id, uow)
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


@router.put("/{track_id}/recording", status_code=200)
@inject
async def replace_recording(
    track_id: str,
    file: Annotated[UploadFile, File()],
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    """
    Replace the audio recording of an existing track.

    The track title, artist, album assignment and all other metadata are kept.
    The IPFS filename is derived from the track title so the name never changes
    even if the format does (e.g. WAV → FLAC).
    The old CID is unpinned from the IPFS core node (and its cluster peers);
    the new file is pinned immediately under a new CID.
    """
    content = await file.read()
    try:
        return await bus.handle(
            ReplaceRecording(
                user_id=current_user.user_id,
                track_id=track_id,
                content=content,
                file_size_bytes=len(content),
                mime_type=file.content_type or "audio/mpeg",
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.post("/upload", status_code=201)
@inject
async def upload_track(
    file: Annotated[UploadFile, File()],
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.LIBRARY_WRITE])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
    source: Annotated[str | None, Form()] = None,
    hint_artist: Annotated[str | None, Form()] = None,
    hint_title: Annotated[str | None, Form()] = None,
    hint_album: Annotated[str | None, Form()] = None,
    hint_year: Annotated[int | None, Form()] = None,
    hint_track_number: Annotated[int | None, Form()] = None,
) -> dict:
    """
    Mobile upload: client sends audio file → server adds to IPFS + pins + registers.
    The track is immediately pinned so it's available across all devices.
    Optional `source` form field declares the origin (cd, vinyl, digital_download, …).
    When source is "cd", the response includes a `cd_verification` object.
    Optional hint_* fields supply metadata when the file has no embedded tags.
    """
    content = await file.read()
    try:
        return await bus.handle(
            UploadTrack(
                user_id=current_user.user_id,
                filename=file.filename or "track",
                content=content,
                file_size_bytes=len(content),
                mime_type=file.content_type or "audio/mpeg",
                source=source,
                hint_artist=hint_artist,
                hint_title=hint_title,
                hint_album=hint_album,
                hint_year=hint_year,
                hint_track_number=hint_track_number,
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.post("/extract-cover")
async def extract_cover(
    file: Annotated[UploadFile, File()],
    _: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_READ])
    ],
) -> Response:
    """
    Reads up to 1 MB from the uploaded audio file and returns any embedded
    cover art as ``{"mime": "image/jpeg", "data": "<base64>"}``.
    Returns 204 No Content when no cover is found.
    """
    head = await file.read(_COVER_READ_LIMIT)
    meta = MetadataExtractor().extract(head)
    if not meta.cover_image:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    return JSONResponse(
        {
            "mime": meta.cover_mime or "image/jpeg",
            "data": base64.b64encode(meta.cover_image).decode(),
        }
    )

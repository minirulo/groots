from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, File, UploadFile, Security

from groots.domain.commands import IngestCentralTrack
from groots.domain.errors import GrootException
from groots.entrypoints.api.auth import get_current_oauth_user
from groots.entrypoints.api.container import Container
from groots.entrypoints.api import views
from groots.service_layer.errors import to_http_exception
from groots.service_layer.messagebus import MessageBus
from groots.service_layer.unit_of_work import AbstractUnitOfWork
from groots.config import settings

router = APIRouter(prefix="/admin", tags=["admin"])


@router.post("/library/ingest", status_code=201)
@inject
async def ingest_central_track(
    file: Annotated[UploadFile, File()],
    _: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_ADMIN])
    ],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> dict:
    """
    Admin: upload an audio file into the server-managed central library.
    The file is fingerprinted, pinned to IPFS, and stored as a system track.
    All future uploads that match this fingerprint will be auto-assigned to
    the same album.
    """
    content = await file.read()
    try:
        return await bus.handle(
            IngestCentralTrack(
                filename=file.filename or "track",
                content=content,
                file_size_bytes=len(content),
                mime_type=file.content_type or "audio/mpeg",
            )
        )
    except GrootException as e:
        raise to_http_exception(e)


@router.get("/library")
@inject
async def list_central_library(
    _: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_ADMIN])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[dict]:
    """Admin: list all tracks in the central library."""
    return await views.get_central_library(uow)


@router.get("/fingerprints")
@inject
async def list_fingerprints(
    _: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_ADMIN])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[dict]:
    """Admin: inspect the global fingerprint database."""
    return await views.get_all_fingerprints(uow)

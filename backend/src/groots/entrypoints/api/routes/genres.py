from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends

from groots.entrypoints.api import views
from groots.entrypoints.api.auth import get_current_user
from groots.entrypoints.api.container import Container
from groots.service_layer.unit_of_work import AbstractUnitOfWork

router = APIRouter(prefix="/genres", tags=["genres"])


@router.get("")
@inject
async def list_genres(
    current_user: Annotated[dict, Depends(get_current_user)],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[str]:
    return await views.get_user_genres(current_user["user_id"], uow)


@router.get("/{genre}/tracks")
@inject
async def tracks_by_genre(
    genre: str,
    current_user: Annotated[dict, Depends(get_current_user)],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> list[dict]:
    return await views.get_tracks_by_genre(current_user["user_id"], genre, uow)

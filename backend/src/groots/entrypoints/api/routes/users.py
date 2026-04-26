from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, Security, HTTPException, status

from groots.entrypoints.api import views
from groots.entrypoints.api.auth import OAuthUser, get_current_oauth_user
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.user import UserResponse
from groots.service_layer.unit_of_work import AbstractUnitOfWork
from typing import Annotated
from groots.config import settings


router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me")
@inject
async def get_me(
    current_user: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.USER_READ])
    ],
    uow: Annotated[AbstractUnitOfWork, Depends(Provide[Container.uow])],
) -> UserResponse:
    profile = await views.get_user_profile(current_user.user_id, uow)
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return UserResponse(**profile)

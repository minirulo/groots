from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends

from groots.entrypoints.api import views
from groots.entrypoints.api.auth import get_current_user
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.user import UserResponse
from groots.service_layer.unit_of_work import AbstractUnitOfWork

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserResponse)
@inject
async def get_me(
    current_user: dict = Depends(get_current_user),
    uow: AbstractUnitOfWork = Depends(Provide[Container.uow]),
) -> UserResponse:
    profile = await views.get_user_profile(current_user["user_id"], uow)
    if not profile:
        from fastapi import HTTPException, status

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
        )
    return UserResponse(**profile)

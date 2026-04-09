from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends
from fastapi.security import OAuth2PasswordRequestForm

from groots.domain.commands import LoginUser, RegisterUser
from groots.domain.errors import SoundNetError
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.user import (
    RegisterRequest,
    TokenResponse,
)
from groots.service_layer.errors import to_http_exception
from groots.service_layer.messagebus import MessageBus

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", status_code=201)
@inject
async def register(
    body: RegisterRequest,
    bus: MessageBus = Depends(Provide[Container.messagebus]),
) -> dict:
    try:
        return await bus.handle(
            RegisterUser(
                username=body.username,
                email=body.email,
                password=body.password,
            )
        )
    except SoundNetError as e:
        raise to_http_exception(e)


@router.post("/login", response_model=TokenResponse)
@inject
async def login(
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    bus: Annotated[MessageBus, Depends(Provide[Container.messagebus])],
) -> TokenResponse:
    try:
        result = await bus.handle(
            LoginUser(email=form.username, password=form.password)
        )
        return TokenResponse(**result)
    except SoundNetError as e:
        raise to_http_exception(e)

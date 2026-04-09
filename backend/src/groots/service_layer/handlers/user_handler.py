from groots.config import settings
from groots.domain.commands import LoginUser, RegisterUser
from groots.domain.errors import InvalidCredentials, UserAlreadyExists
from groots.domain.model.user import User
from groots.entrypoints.api.auth import (
    create_access_token,
    hash_password,
    verify_password,
)
from groots.service_layer.unit_of_work import AbstractUnitOfWork


async def handle_register_user(cmd: RegisterUser, uow: AbstractUnitOfWork) -> dict:
    async with uow:
        if await uow.users.get_by_email(cmd.email):
            raise UserAlreadyExists(cmd.email)
        if await uow.users.get_by_username(cmd.username):
            raise UserAlreadyExists(cmd.username)

        is_admin = cmd.email.lower() in settings.admin_email_set
        user = User(
            username=cmd.username,
            email=cmd.email,
            hashed_password=hash_password(cmd.password),
            is_admin=is_admin,
        )
        await uow.users.add(user)
        await uow.commit()
        return {"user_id": user.id, "username": user.username, "email": user.email}


async def handle_login_user(cmd: LoginUser, uow: AbstractUnitOfWork) -> dict:
    async with uow:
        user = await uow.users.get_by_email(cmd.email)
        if not user or not verify_password(cmd.password, user.hashed_password):
            raise InvalidCredentials()

        # Re-stamp admin flag on every login so config changes take effect
        is_admin = user.is_admin or (cmd.email.lower() in settings.admin_email_set)
        token = create_access_token(
            {"sub": user.id, "email": user.email, "is_admin": is_admin}
        )
        return {"access_token": token, "token_type": "bearer"}

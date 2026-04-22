from datetime import UTC, datetime, timedelta

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, SecurityScopes
from jose import JWTError, jwt

from groots.config import settings

oauth2_scheme = OAuth2PasswordBearer(tokenUrl=f"{settings.API_STR}/auth/login")


class OAuthUser:
    user_id: str
    email: str
    is_admin: bool


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())


def create_access_token(data: dict) -> str:
    payload = data.copy()
    expire = datetime.now(UTC) + timedelta(
        minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload["exp"] = expire
    return jwt.encode(
        payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM
    )


def get_current_oauth_user(
    security_scopes: SecurityScopes,
    token: str = Depends(oauth2_scheme),
) -> OAuthUser:
    exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM]
        )
        user_id: str = payload.get("sub")
        if not user_id:
            raise exc

        token_scope_str: str = payload.get("scope", "")

        if isinstance(token_scope_str, str):
            token_scopes = token_scope_str.split()

            for scope in security_scopes.scopes:
                if scope not in token_scopes:
                    raise HTTPException(
                        403,
                        detail=f'Missing "{scope}" scope',
                    )

        return OAuthUser(
            user_id=user_id,
            email=payload.get("email"),
            is_admin=payload.get("is_admin", False),
        )
    except JWTError:
        raise exc

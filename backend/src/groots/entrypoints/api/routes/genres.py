from typing import Annotated

from fastapi import APIRouter, Security

from groots.domain.model.album import Genre
from groots.entrypoints.api.auth import OAuthUser, get_current_oauth_user
from groots.config import settings

router = APIRouter(prefix="/genres", tags=["genres"])


@router.get("")
async def list_genres(
    _: Annotated[
        OAuthUser, Security(get_current_oauth_user, scopes=[settings.GENRE_READ])
    ],
) -> list[str]:
    return [g.value for g in Genre]

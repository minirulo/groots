from fastapi import HTTPException, status

from groots.domain.errors import (
    AdminRequired,
    AlbumNotFound,
    AlbumNotOwnedByUser,
    FingerprintError,
    InvalidCredentials,
    IPFSError,
    PlaylistNotFound,
    PlaylistNotOwnedByUser,
    StorageQuotaExceeded,
    TrackNotFound,
    TrackNotOwnedByUser,
    UserAlreadyExists,
    UserNotFound,
)


_ACCESS_DENIED = "Access denied"


def to_http_exception(error: Exception) -> HTTPException:
    mapping = {
        UserAlreadyExists: (status.HTTP_409_CONFLICT, "User already exists"),
        UserNotFound: (status.HTTP_404_NOT_FOUND, "User not found"),
        InvalidCredentials: (status.HTTP_401_UNAUTHORIZED, "Invalid credentials"),
        TrackNotFound: (status.HTTP_404_NOT_FOUND, "Track not found"),
        TrackNotOwnedByUser: (status.HTTP_403_FORBIDDEN, _ACCESS_DENIED),
        StorageQuotaExceeded: (
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            "Storage quota exceeded",
        ),
        IPFSError: (status.HTTP_502_BAD_GATEWAY, "IPFS node error"),
        AlbumNotFound: (status.HTTP_404_NOT_FOUND, "Album not found"),
        AlbumNotOwnedByUser: (status.HTTP_403_FORBIDDEN, _ACCESS_DENIED),
        PlaylistNotFound: (status.HTTP_404_NOT_FOUND, "Playlist not found"),
        PlaylistNotOwnedByUser: (status.HTTP_403_FORBIDDEN, _ACCESS_DENIED),
        FingerprintError: (
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Audio fingerprinting failed",
        ),
        AdminRequired: (status.HTTP_403_FORBIDDEN, "Admin privileges required"),
    }
    status_code, detail = mapping.get(
        type(error), (status.HTTP_500_INTERNAL_SERVER_ERROR, str(error))
    )
    return HTTPException(status_code=status_code, detail=detail)

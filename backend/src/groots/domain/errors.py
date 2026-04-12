class SoundNetError(Exception):
    pass


class UserAlreadyExists(SoundNetError):
    pass


class UserNotFound(SoundNetError):
    pass


class RoleNotFound(SoundNetError):
    pass


class InvalidCredentials(SoundNetError):
    pass


class TrackNotFound(SoundNetError):
    pass


class TrackNotOwnedByUser(SoundNetError):
    pass


class StorageQuotaExceeded(SoundNetError):
    pass


class IPFSError(SoundNetError):
    pass


class AlbumNotFound(SoundNetError):
    pass


class AlbumNotOwnedByUser(SoundNetError):
    pass


class PlaylistNotFound(SoundNetError):
    pass


class PlaylistNotOwnedByUser(SoundNetError):
    pass


class FingerprintError(SoundNetError):
    pass


class AdminRequired(SoundNetError):
    pass

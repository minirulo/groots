class GrootException(Exception):
    pass


class UserAlreadyExists(GrootException):
    pass


class UserNotFound(GrootException):
    pass


class RoleNotFound(GrootException):
    pass


class InvalidCredentials(GrootException):
    pass


class TrackNotFound(GrootException):
    pass


class TrackNotOwnedByUser(GrootException):
    pass


class StorageQuotaExceeded(GrootException):
    pass


class IPFSError(GrootException):
    pass


class AlbumNotFound(GrootException):
    pass


class AlbumNotOwnedByUser(GrootException):
    pass


class PlaylistNotFound(GrootException):
    pass


class PlaylistNotOwnedByUser(GrootException):
    pass


class FingerprintError(GrootException):
    pass


class AdminRequired(GrootException):
    pass

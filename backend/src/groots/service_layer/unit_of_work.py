import abc

from motor.motor_asyncio import AsyncIOMotorClient

from groots.adapters.impl.audio_fingerprinter import AudioFingerprinter
from groots.adapters.impl.ipfs_client import IPFSClient
from groots.adapters.impl.metadata_extractor import MetadataExtractor
from groots.adapters.repositories.album_repo import AlbumRepository
from groots.adapters.repositories.fingerprint_repo import FingerprintRepository
from groots.adapters.repositories.playlist_repo import PlaylistRepository
from groots.adapters.repositories.track_repo import TrackRepository
from groots.adapters.repositories.user_repo import UserRepository
from groots.adapters.repositories.role_repo import RoleRepository


class AbstractUnitOfWork(abc.ABC):
    users: UserRepository
    roles: RoleRepository
    tracks: TrackRepository
    albums: AlbumRepository
    playlists: PlaylistRepository
    fingerprints: FingerprintRepository
    ipfs: IPFSClient
    fingerprinter: AudioFingerprinter
    extractor: MetadataExtractor

    async def __aenter__(self) -> "AbstractUnitOfWork":
        return self

    async def __aexit__(self, *args):
        await self.rollback()

    @abc.abstractmethod
    async def commit(self): ...

    @abc.abstractmethod
    async def rollback(self): ...


class MongoUnitOfWork(AbstractUnitOfWork):
    def __init__(
        self,
        db_uri: str,
        db_name: str,
        ipfs_client: IPFSClient,
        fingerprinter: AudioFingerprinter,
        extractor: MetadataExtractor,
    ):
        self._db_uri = db_uri
        self._db_name = db_name
        self.ipfs = ipfs_client
        self.fingerprinter = fingerprinter
        self.extractor = extractor

    async def __aenter__(self) -> "MongoUnitOfWork":
        self._client = AsyncIOMotorClient(self._db_uri)
        self._db = self._client[self._db_name]
        self.users = UserRepository(self._db)
        self.roles = RoleRepository(self._db)
        self.tracks = TrackRepository(self._db)
        self.albums = AlbumRepository(self._db)
        self.playlists = PlaylistRepository(self._db)
        self.fingerprints = FingerprintRepository(self._db)
        return self

    async def commit(self):
        pass  # No-op until replica set is configured

    async def rollback(self):
        pass  # No-op until replica set is configured

    async def __aexit__(self, *args):
        self._client.close()

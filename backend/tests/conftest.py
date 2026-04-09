import pytest
from unittest.mock import AsyncMock, MagicMock

from groots.adapters.impl.ipfs_client import IPFSClient
from groots.service_layer.unit_of_work import AbstractUnitOfWork


class FakeUserRepository:
    def __init__(self):
        self._store: dict = {}

    async def add(self, user):
        self._store[user.id] = user
        return user

    async def get(self, id: str):
        return self._store.get(id)

    async def get_by_email(self, email: str):
        return next((u for u in self._store.values() if u.email == email), None)

    async def get_by_username(self, username: str):
        return next((u for u in self._store.values() if u.username == username), None)

    async def update(self, user):
        self._store[user.id] = user
        return user


class FakeTrackRepository:
    def __init__(self):
        self._store: dict = {}

    async def add(self, track):
        self._store[track.id] = track
        return track

    async def get(self, id: str):
        return self._store.get(id)

    async def list_by_user(self, user_id: str):
        return [t for t in self._store.values() if t.user_id == user_id]

    async def update(self, track):
        self._store[track.id] = track
        return track

    async def delete(self, id: str):
        self._store.pop(id, None)


class FakeUnitOfWork(AbstractUnitOfWork):
    def __init__(self):
        self.users = FakeUserRepository()
        self.tracks = FakeTrackRepository()
        self.ipfs = AsyncMock(spec=IPFSClient)
        self.committed = False

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


@pytest.fixture
def fake_uow():
    return FakeUnitOfWork()

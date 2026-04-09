from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.base import from_document
from groots.domain.model.playlist import Playlist


class PlaylistRepository(BaseMongoRepository[Playlist]):
    collection_name = "playlists"
    model = Playlist

    async def list_by_user(self, user_id: str) -> list[Playlist]:
        cursor = self.collection.find({"user_id": user_id}, session=self.session)
        return [from_document(doc, Playlist) async for doc in cursor]

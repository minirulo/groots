from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.base import from_document
from groots.domain.model.track import Track


class TrackRepository(BaseMongoRepository[Track]):
    collection_name = "tracks"
    model = Track

    async def list_by_user(self, user_id: str) -> list[Track]:
        cursor = self.collection.find({"user_id": user_id}, session=self.session)
        return [from_document(doc, Track) async for doc in cursor]

    async def get_by_cid(self, cid: str, user_id: str) -> Track | None:
        doc = await self.collection.find_one(
            {"cid": cid, "user_id": user_id}, session=self.session
        )
        return from_document(doc, Track) if doc else None

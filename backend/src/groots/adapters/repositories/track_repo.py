from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.base import from_document
from groots.domain.model.track import Track


class TrackRepository(BaseMongoRepository[Track]):
    collection_name = "tracks"
    model = Track

    async def list_by_album_ids(self, album_ids: list[str]) -> list[Track]:
        ids = [aid for aid in album_ids if aid]
        if not ids:
            return []
        cursor = self.collection.find({"album_id": {"$in": ids}}, session=self.session)
        return [from_document(doc, Track) async for doc in cursor]

    async def list_by_album(self, album_id: str) -> list[Track]:
        cursor = self.collection.find({"album_id": album_id}, session=self.session)
        return [from_document(doc, Track) async for doc in cursor]

    async def get_by_cid(self, cid: str) -> Track | None:
        doc = await self.collection.find_one({"cid": cid}, session=self.session)
        return from_document(doc, Track) if doc else None

    async def backfill_null_disc_number(self, album_id: str, disc_number: int) -> None:
        """Set disc_number on every album track that currently has disc_number=None."""
        await self.collection.update_many(
            {"album_id": album_id, "disc_number": None},
            {"$set": {"disc_number": disc_number}},
            session=self.session,
        )

    async def backfill_null_side(self, album_id: str, side: str) -> None:
        """Set side on every album track that currently has side=None."""
        await self.collection.update_many(
            {"album_id": album_id, "side": None},
            {"$set": {"side": side}},
            session=self.session,
        )

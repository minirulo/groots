from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.album import Album
from groots.domain.model.base import from_document


class AlbumRepository(BaseMongoRepository[Album]):
    collection_name = "albums"
    model = Album

    async def list_all(self) -> list[Album]:
        cursor = self.collection.find({}, session=self.session)
        return [from_document(doc, Album) async for doc in cursor]

    async def list_for_user(
        self, user_id: str, track_album_ids: list[str]
    ) -> list[Album]:
        """Return albums that the given user has tracks in."""
        from bson import ObjectId

        oids = [ObjectId(aid) for aid in track_album_ids if aid]
        if not oids:
            return []
        cursor = self.collection.find({"_id": {"$in": oids}}, session=self.session)
        return [from_document(doc, Album) async for doc in cursor]

    async def find_by_title_artist(self, title: str, artist: str) -> Album | None:
        doc = await self.collection.find_one(
            {"title": title, "artist": artist}, session=self.session
        )
        return from_document(doc, Album) if doc else None

    async def search(self, query: str, limit: int = 20) -> list[Album]:
        """Case-insensitive substring search on title or artist."""
        regex = {"$regex": query, "$options": "i"}
        cursor = self.collection.find(
            {"$or": [{"title": regex}, {"artist": regex}]},
            session=self.session,
        ).limit(limit)
        return [from_document(doc, Album) async for doc in cursor]

from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.album import Album
from groots.domain.model.base import from_document


class AlbumRepository(BaseMongoRepository[Album]):
    collection_name = "albums"
    model = Album

    async def list_all(self) -> list[Album]:
        cursor = self.collection.find({}, session=self.session)
        return [from_document(doc, Album) async for doc in cursor]

    async def list_by_user(self, user_id: str) -> list[Album]:
        """Return all albums owned by the given user."""
        cursor = self.collection.find({"user_id": user_id}, session=self.session)
        return [from_document(doc, Album) async for doc in cursor]

    async def find_by_title_artist(
        self, title: str, artist: str, user_id: str | None = None
    ) -> Album | None:
        query: dict = {"title": title, "artist": artist}
        if user_id is not None:
            query["user_id"] = user_id
        doc = await self.collection.find_one(query, session=self.session)
        return from_document(doc, Album) if doc else None

    async def search(self, query: str, limit: int = 20) -> list[Album]:
        """Case-insensitive substring search on title or artist."""
        regex = {"$regex": query, "$options": "i"}
        cursor = self.collection.find(
            {"$or": [{"title": regex}, {"artist": regex}]},
            session=self.session,
        ).limit(limit)
        return [from_document(doc, Album) async for doc in cursor]

from typing import Generic, TypeVar

from motor.motor_asyncio import AsyncIOMotorCollection, AsyncIOMotorClientSession

from groots.domain.model.base import to_document, from_document

ModelType = TypeVar("ModelType")


class BaseMongoRepository(Generic[ModelType]):
    collection_name: str
    model: type

    def __init__(self, db, session: AsyncIOMotorClientSession | None = None):
        self.collection: AsyncIOMotorCollection = db[self.collection_name]
        self.session = session

    async def add(self, obj: ModelType) -> ModelType:
        doc = to_document(obj)
        await self.collection.insert_one(doc, session=self.session)
        return obj

    async def get(self, id: str) -> ModelType | None:
        from bson import ObjectId

        doc = await self.collection.find_one(
            {"_id": ObjectId(id)}, session=self.session
        )
        return from_document(doc, self.model) if doc else None

    async def update(self, obj: ModelType) -> ModelType:
        from bson import ObjectId
        from dataclasses import asdict
        from groots.domain.model.base import model_factory

        data = model_factory(asdict(obj))
        data.pop("id", None)
        await self.collection.update_one(
            {"_id": ObjectId(obj.id)},
            {"$set": data},
            session=self.session,
        )
        return obj

    async def delete(self, id: str) -> None:
        from bson import ObjectId

        await self.collection.delete_one({"_id": ObjectId(id)}, session=self.session)

from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.base import from_document
from groots.domain.model.user import User


class UserRepository(BaseMongoRepository[User]):
    collection_name = "users"
    model = User

    async def get_by_email(self, email: str) -> User | None:
        doc = await self.collection.find_one({"email": email}, session=self.session)
        return from_document(doc, User) if doc else None

    async def get_by_username(self, username: str) -> User | None:
        doc = await self.collection.find_one(
            {"username": username}, session=self.session
        )
        return from_document(doc, User) if doc else None

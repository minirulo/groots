from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.base import from_document
from groots.domain.model.role import Role


class RoleRepository(BaseMongoRepository[Role]):
    collection_name = "roles"
    model = Role

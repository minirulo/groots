"""${message}

Create Date: ${create_date}
"""

import logging

from groots.config import settings
from pymongo import MongoClient
from pymongo.database import Database

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def migrate(db: Database) -> None:
    """Add any optional data upgrade migrations here!"""
    pass


if __name__ == "__main__":
    client = MongoClient(settings.MONGO_DB_URI)
    migrate(client[settings.MONGO_DB])

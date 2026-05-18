"""Track/Album user refactor

- Remove user_id, artist, album, year, genre from track documents
- Set album.user_id from the user_id of that album's tracks

Create Date: 20260517
"""

import logging

from groots.config import settings
from pymongo import MongoClient
from pymongo.database import Database

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def migrate(db: Database) -> None:
    tracks_col = db["tracks"]
    albums_col = db["albums"]

    # ── 1. Allocate album.user_id from tracks ─────────────────────────────────
    # For each album, find the first track that has a user_id and use it as the
    # album owner. Albums created before any track was assigned may have no
    # tracks, so they remain with user_id=None (system/orphan albums).
    albums = list(albums_col.find({"user_id": {"$exists": False}}))
    logger.info("Albums missing user_id: %d", len(albums))

    albums_updated = 0
    for album in albums:
        album_id_str = str(album["_id"])
        track = tracks_col.find_one(
            {"album_id": album_id_str, "user_id": {"$exists": True, "$ne": None}},
            projection={"user_id": 1},
        )
        if track:
            albums_col.update_one(
                {"_id": album["_id"]},
                {"$set": {"user_id": track["user_id"]}},
            )
            albums_updated += 1

    logger.info("Albums updated with user_id: %d", albums_updated)

    # ── 2. Also rename created_by → user_id for albums that used the old field ─
    albums_with_created_by = list(
        albums_col.find({"created_by": {"$exists": True}, "user_id": {"$exists": False}})
    )
    logger.info("Albums with legacy created_by field: %d", len(albums_with_created_by))
    for album in albums_with_created_by:
        albums_col.update_one(
            {"_id": album["_id"]},
            {
                "$set": {"user_id": album["created_by"]},
                "$unset": {"created_by": ""},
            },
        )
    # Drop created_by from any remaining albums (where user_id already set)
    albums_col.update_many(
        {"created_by": {"$exists": True}},
        {"$unset": {"created_by": ""}},
    )
    logger.info("Migrated created_by → user_id on albums")

    # ── 3. Delete tracks with no album assigned ───────────────────────────────
    orphan_result = tracks_col.delete_many(
        {"$or": [{"album_id": {"$exists": False}}, {"album_id": None}]}
    )
    logger.info("Deleted %d orphan tracks (no album_id)", orphan_result.deleted_count)

    # ── 4. Drop removed fields from track documents ───────────────────────────
    fields_to_drop = {"user_id": "", "artist": "", "album": "", "year": "", "genre": ""}
    result = tracks_col.update_many(
        {"$or": [{f: {"$exists": True}} for f in fields_to_drop]},
        {"$unset": fields_to_drop},
    )
    logger.info(
        "Removed legacy fields (user_id, artist, album, year, genre) from %d track documents",
        result.modified_count,
    )

    # ── 4. Drop the tracks_without_fingerprint view if it references old fields ─
    # The view was created by a previous migration and projects user_id/artist/
    # album which no longer exist. Drop and recreate without those fields.
    if "tracks_without_fingerprint" in db.list_collection_names():
        db.drop_collection("tracks_without_fingerprint")
        db.create_collection(
            "tracks_without_fingerprint",
            viewOn="tracks",
            pipeline=[
                {
                    "$match": {
                        "$or": [
                            {"fingerprint_id": {"$exists": False}},
                            {"fingerprint_id": None},
                        ]
                    }
                },
                {
                    "$project": {
                        "_id": 1,
                        "title": 1,
                        "album_id": 1,
                        "duration_seconds": 1,
                        "matched_central_id": 1,
                        "created_at": 1,
                    }
                },
            ],
        )
        logger.info("Recreated 'tracks_without_fingerprint' view without legacy fields")

    logger.info("Migration complete")


if __name__ == "__main__":
    client = MongoClient(settings.MONGO_DB_URI)
    migrate(client[settings.MONGO_DB])

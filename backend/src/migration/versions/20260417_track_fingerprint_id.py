"""Track fingerprint_id backfill

Create Date: 20260417
"""

import logging

from groots.config import settings
from pymongo import MongoClient
from pymongo.database import Database

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DURATION_TOLERANCE = 10


def migrate(db: Database) -> None:
    tracks = db["tracks"]
    fingerprints = db["fingerprints"]

    pending = list(tracks.find({"fingerprint_id": {"$exists": False}}))
    logger.info("Tracks without fingerprint_id: %d", len(pending))

    resolved = 0
    unresolved = 0

    for track in pending:
        track_id = track["_id"]

        # Strategy 1: already matched to a central fingerprint
        if track.get("matched_central_id"):
            tracks.update_one(
                {"_id": track_id},
                {"$set": {"fingerprint_id": track["matched_central_id"]}},
            )
            resolved += 1
            continue

        # Strategy 2: find a non-central fingerprint by metadata + duration
        duration = track.get("duration_seconds", 0)
        query: dict = {
            "duration_seconds": {
                "$gte": duration - DURATION_TOLERANCE,
                "$lte": duration + DURATION_TOLERANCE,
            },
        }
        if track.get("album_id"):
            query["album_id"] = track["album_id"]
        if track.get("title"):
            query["title"] = track["title"]
        if track.get("artist"):
            query["artist"] = track["artist"]

        candidates = list(fingerprints.find(query))
        if len(candidates) == 1:
            tracks.update_one(
                {"_id": track_id},
                {"$set": {"fingerprint_id": candidates[0]["_id"]}},
            )
            resolved += 1
        elif len(candidates) > 1:
            logger.warning(
                "Track %s matched %d fingerprints — skipping (manual review needed)",
                track_id,
                len(candidates),
            )
            unresolved += 1
        else:
            logger.warning(
                "Track %s (title=%r artist=%r) — no fingerprint found",
                track_id,
                track.get("title"),
                track.get("artist"),
            )
            unresolved += 1

    logger.info("Resolved: %d  |  Unresolved: %d", resolved, unresolved)

    # Drop and recreate the view so re-running the migration is idempotent
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
                    "user_id": 1,
                    "title": 1,
                    "artist": 1,
                    "album": 1,
                    "album_id": 1,
                    "duration_seconds": 1,
                    "matched_central_id": 1,
                    "created_at": 1,
                }
            },
        ],
    )
    logger.info("View 'tracks_without_fingerprint' created")


if __name__ == "__main__":
    client = MongoClient(settings.MONGO_DB_URI)
    migrate(client[settings.MONGO_DB])

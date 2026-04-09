from groots.adapters.repositories.repository import BaseMongoRepository
from groots.domain.model.base import from_document
from groots.domain.model.fingerprint import TrackFingerprint


class FingerprintRepository(BaseMongoRepository[TrackFingerprint]):
    collection_name = "fingerprints"
    model = TrackFingerprint

    async def find_candidates(
        self, duration_seconds: int, tolerance: int = 10
    ) -> list[TrackFingerprint]:
        """Return all fingerprints whose duration is within ±tolerance seconds."""
        cursor = self.collection.find(
            {
                "duration_seconds": {
                    "$gte": duration_seconds - tolerance,
                    "$lte": duration_seconds + tolerance,
                }
            },
            session=self.session,
        )
        return [from_document(doc, TrackFingerprint) async for doc in cursor]

    async def find_central_candidates(
        self, duration_seconds: int, tolerance: int = 10
    ) -> list[TrackFingerprint]:
        """Return only central-library fingerprints within the duration window."""
        cursor = self.collection.find(
            {
                "is_central": True,
                "duration_seconds": {
                    "$gte": duration_seconds - tolerance,
                    "$lte": duration_seconds + tolerance,
                },
            },
            session=self.session,
        )
        return [from_document(doc, TrackFingerprint) async for doc in cursor]

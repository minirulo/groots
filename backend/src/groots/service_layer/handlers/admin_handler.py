import os

from groots.config import settings
from groots.domain.commands import IngestCentralTrack
from groots.domain.model.fingerprint import TrackFingerprint
from groots.domain.model.track import Track
from groots.service_layer.handlers.library_handler import _resolve_album
from groots.service_layer.unit_of_work import AbstractUnitOfWork


async def handle_ingest_central_track(
    cmd: IngestCentralTrack, uow: AbstractUnitOfWork
) -> dict:
    """
    Admin command: ingest an audio file into the server-managed central library.

    Pipeline:
      1. IPFS add + pin
      2. Extract embedded metadata
      3. Fingerprint audio
      4. Find-or-create global album from metadata
      5. Persist Track (owned by SYSTEM_USER_ID) + central TrackFingerprint
    """
    async with uow:
        cid = await uow.ipfs.pin_add_bytes(cmd.content, cmd.filename)

        # ── metadata ─────────────────────────────────────────────────────────
        meta = uow.extractor.extract(cmd.content)
        stem = os.path.splitext(cmd.filename)[0]
        parts = stem.split(" - ", 1)
        title = meta.title or (parts[1] if len(parts) > 1 else stem)
        artist = meta.artist or (parts[0] if len(parts) > 1 else "Unknown")
        year = meta.year
        genre = meta.genre
        track_number = meta.track_number

        # ── fingerprint ───────────────────────────────────────────────────────
        suffix = os.path.splitext(cmd.filename)[1] or ".mp3"
        duration = 0
        fp_hex: str | None = None
        try:
            duration, fp_hex = await uow.fingerprinter.fingerprint(
                cmd.content, suffix=suffix
            )
        except Exception:
            pass  # Fingerprinting is best-effort; ingest continues without it

        # ── album ─────────────────────────────────────────────────────────────
        album_id: str | None = None
        album_title: str | None = meta.album
        if album_title and artist:
            album_id, _ = await _resolve_album(
                album_title, artist, settings.SYSTEM_USER_ID, uow
            )

        # ── persist track ─────────────────────────────────────────────────────
        track = Track(
            user_id=settings.SYSTEM_USER_ID,
            cid=cid,
            title=title,
            artist=artist,
            duration_seconds=duration,
            file_size_bytes=cmd.file_size_bytes,
            album=album_title,
            album_id=album_id,
            track_number=track_number,
            year=year,
            genre=genre,
            mime_type=cmd.mime_type,
            pinned=True,
        )
        await uow.tracks.add(track)

        # ── persist central fingerprint ───────────────────────────────────────
        fp_id: str | None = None
        if fp_hex:
            fp_record = TrackFingerprint(
                fingerprint_hex=fp_hex,
                duration_seconds=duration,
                album_id=album_id,
                title=title,
                artist=artist,
                is_central=True,
            )
            await uow.fingerprints.add(fp_record)
            fp_id = fp_record.id

        await uow.commit()
        return {
            "track_id": track.id,
            "cid": cid,
            "album_id": album_id,
            "fingerprint_id": fp_id,
        }

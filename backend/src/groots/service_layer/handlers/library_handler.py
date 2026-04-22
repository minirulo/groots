import os

from groots.domain.commands import AddTrack, PinTrack, RemoveTrack, UploadTrack
from groots.domain.errors import (
    StorageQuotaExceeded,
    TrackNotFound,
    TrackNotOwnedByUser,
)
from groots.domain.model.album import Album
from groots.domain.model.fingerprint import TrackFingerprint
from groots.domain.model.track import Track
from groots.service_layer.unit_of_work import AbstractUnitOfWork


# ── helpers ───────────────────────────────────────────────────────────────────


def _ext_for_mime(mime: str) -> str:
    return {
        "audio/mpeg": ".mp3",
        "audio/flac": ".flac",
        "audio/aac": ".aac",
        "audio/ogg": ".ogg",
        "audio/wav": ".wav",
        "audio/mp4": ".m4a",
        "audio/opus": ".opus",
    }.get(mime, ".mp3")


async def _resolve_album(
    album_title: str,
    artist: str,
    created_by: str | None,
    uow: AbstractUnitOfWork,
) -> tuple[str, bool]:
    """
    Find an existing global album by title+artist, or create one.
    Returns (album_id, is_new) where is_new=True means we just created it.
    """
    existing = await uow.albums.find_by_title_artist(album_title, artist)
    if existing:
        return existing.id, False

    new_album = Album(
        title=album_title,
        artist=artist,
        created_by=created_by,
    )
    await uow.albums.add(new_album)
    return new_album.id, True


async def _run_fingerprint_pipeline(
    content: bytes,
    mime: str,
    uow: AbstractUnitOfWork,
) -> tuple[int, str | None, str | None, str | None]:
    """
    Fingerprint the audio and compare against existing fingerprints.

    Returns (duration_seconds, fingerprint_hex, matched_central_fp_id, matched_user_fp_id).
    Central match takes priority; user-pool match is only set when central is None.
    Fingerprint generation failure is soft – returns (0, None, None, None).
    """
    suffix = _ext_for_mime(mime)
    try:
        duration, fp_hex = await uow.fingerprinter.fingerprint(content, suffix=suffix)
    except Exception:
        return 0, None, None, None

    # Priority 1: central library
    central_cands = await uow.fingerprints.find_central_candidates(duration)
    if central_cands:
        best_id, _ = uow.fingerprinter.best_match(
            fp_hex, [(c.id, c.fingerprint_hex) for c in central_cands]
        )
        if best_id:
            return duration, fp_hex, best_id, None

    # Priority 2: user fingerprint pool
    all_cands = await uow.fingerprints.find_candidates(duration)
    non_central = [c for c in all_cands if not c.is_central]
    if non_central:
        best_id, _ = uow.fingerprinter.best_match(
            fp_hex, [(c.id, c.fingerprint_hex) for c in non_central]
        )
        if best_id:
            return duration, fp_hex, None, best_id

    return duration, fp_hex, None, None


async def _get_album_from_fingerprint_match(
    matched_fp_id: str, uow: AbstractUnitOfWork
) -> str | None:
    """Return the album_id from a matched fingerprint record, if any."""
    fp = await uow.fingerprints.get(matched_fp_id)
    return fp.album_id if fp else None


async def _resolve_album_id(
    matched_central_id: str | None,
    matched_user_fp_id: str | None,
    meta_album: str | None,
    artist: str,
    created_by: str,
    uow: AbstractUnitOfWork,
) -> tuple[str | None, str | None, bool]:
    """
    Determine (album_id, album_title, promote_to_central) using three strategies:
      1. Central-library fingerprint match
      2. User-pool fingerprint match
      3. Embedded album tag  →  find-or-create global album

    promote_to_central=True means the album was brand-new (created via Priority 3)
    and the fingerprint should be stored as is_central=True so future uploads
    from any user are automatically matched against the central library.
    """
    album_title: str | None = meta_album

    # Priority 1: central library
    if matched_central_id:
        album_id = await _get_album_from_fingerprint_match(matched_central_id, uow)
        if album_id:
            return album_id, album_title, False

    # Priority 2: user fingerprint pool
    if matched_user_fp_id:
        album_id = await _get_album_from_fingerprint_match(matched_user_fp_id, uow)
        if album_id:
            fp_rec = await uow.fingerprints.get(matched_user_fp_id)
            title_hint = fp_rec.title if fp_rec else None
            return album_id, album_title or title_hint, False

    # Priority 3: embedded tag → find-or-create
    if album_title:
        album_id, is_new = await _resolve_album(album_title, artist, created_by, uow)
        # Promote to central when user introduced a genuinely new album
        return album_id, album_title, is_new

    return None, None, False


# ── command handlers ──────────────────────────────────────────────────────────


async def handle_add_track(cmd: AddTrack, uow: AbstractUnitOfWork) -> dict:
    async with uow:
        user = await uow.users.get(cmd.user_id)
        if user.used_storage_bytes + cmd.file_size_bytes > user.storage_quota_bytes:
            raise StorageQuotaExceeded()

        track = Track(
            user_id=cmd.user_id,
            cid=cmd.cid,
            title=cmd.title,
            artist=cmd.artist,
            duration_seconds=cmd.duration_seconds,
            file_size_bytes=cmd.file_size_bytes,
            album=cmd.album,
            album_id=cmd.album_id,
            track_number=cmd.track_number,
            year=cmd.year,
            genre=cmd.genre,
            mime_type=cmd.mime_type,
            source=cmd.source,
        )
        await uow.tracks.add(track)

        user.used_storage_bytes += cmd.file_size_bytes
        await uow.users.update(user)
        await uow.commit()
        return {"track_id": track.id, "cid": track.cid}


async def handle_remove_track(cmd: RemoveTrack, uow: AbstractUnitOfWork) -> None:
    async with uow:
        track = await uow.tracks.get(cmd.track_id)
        if not track:
            raise TrackNotFound(cmd.track_id)
        if track.user_id != cmd.user_id:
            raise TrackNotOwnedByUser()

        if track.pinned:
            await uow.ipfs.pin_rm(track.cid)
            await uow.ipfs.mfs_rm(f"{track.title}{_ext_for_mime(track.mime_type)}")

        user = await uow.users.get(cmd.user_id)
        user.used_storage_bytes = max(
            0, user.used_storage_bytes - track.file_size_bytes
        )
        await uow.users.update(user)

        await uow.tracks.delete(cmd.track_id)
        await uow.commit()


async def handle_upload_track(cmd: UploadTrack, uow: AbstractUnitOfWork) -> dict:
    """
    Full upload pipeline:
      1. Quota check
      2. IPFS add + pin → CID
      3. Extract embedded audio metadata (mutagen)
      4. Fingerprint the audio (chromaprint via fpcalc)
      5. Match fingerprint against global DB (central library first, then all)
      6. Resolve/create global album from metadata or fingerprint match
      7. Store track + fingerprint
    """
    async with uow:
        user = await uow.users.get(cmd.user_id)
        if user.used_storage_bytes + cmd.file_size_bytes > user.storage_quota_bytes:
            raise StorageQuotaExceeded()

        # ── 1. IPFS ──────────────────────────────────────────────────────────
        cid = await uow.ipfs.pin_add_bytes(cmd.content, cmd.filename)

        # ── 2. Embedded metadata ─────────────────────────────────────────────
        meta = uow.extractor.extract(cmd.content)

        # Fall back to filename parsing when metadata is missing
        stem = os.path.splitext(cmd.filename)[0]
        parts = stem.split(" - ", 1)
        fallback_artist = parts[0] if len(parts) > 1 else "Unknown"
        fallback_title = parts[1] if len(parts) > 1 else stem

        title = meta.title or fallback_title
        artist = meta.artist or fallback_artist
        year = meta.year
        genre = meta.genre
        track_number = meta.track_number

        # ── 3. Fingerprint + match ───────────────────────────────────────────
        duration, fp_hex, matched_central_id, matched_user_fp_id = (
            await _run_fingerprint_pipeline(cmd.content, cmd.mime_type, uow)
        )

        # ── 4. Resolve album ─────────────────────────────────────────────────
        album_id, album_title, promote_to_central = await _resolve_album_id(
            matched_central_id=matched_central_id,
            matched_user_fp_id=matched_user_fp_id,
            meta_album=meta.album,
            artist=artist,
            created_by=cmd.user_id,
            uow=uow,
        )

        # ── 4b. CD verification (only when user declared source as CD) ────────
        cd_verification: dict | None = None
        if cmd.source == "cd":
            from groots.adapters.impl.cd_verifier import CdVerifier

            cd_verification = CdVerifier().verify(meta).to_dict()

        # ── 5. Persist fingerprint (if we got one and it's genuinely new) ────
        # Skip when any existing fingerprint already covers this audio, to avoid
        # accumulating duplicates from repeated uploads of the same track.
        existing_fp_id = matched_central_id or matched_user_fp_id
        if fp_hex and not existing_fp_id:
            fp_record = TrackFingerprint(
                fingerprint_hex=fp_hex,
                duration_seconds=duration,
                album_id=album_id,
                title=title,
                artist=artist,
                is_central=promote_to_central,
            )
            await uow.fingerprints.add(fp_record)
            fp_id: str | None = fp_record.id
        else:
            fp_id = existing_fp_id

        # ── 6. Persist track ─────────────────────────────────────────────────
        track = Track(
            user_id=cmd.user_id,
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
            fingerprint_id=fp_id,
            matched_central_id=matched_central_id,
        )
        await uow.tracks.add(track)

        user.used_storage_bytes += cmd.file_size_bytes
        await uow.users.update(user)
        await uow.commit()
        result: dict = {
            "track_id": track.id,
            "cid": cid,
            "album_id": album_id,
            "matched_central": matched_central_id is not None,
        }
        if cd_verification is not None:
            result["cd_verification"] = cd_verification
        return result


async def handle_pin_track(cmd: PinTrack, uow: AbstractUnitOfWork) -> None:
    async with uow:
        track = await uow.tracks.get(cmd.track_id)
        if not track:
            raise TrackNotFound(cmd.track_id)
        if track.user_id != cmd.user_id:
            raise TrackNotOwnedByUser()

        await uow.ipfs.pin_add(cmd.cid)
        await uow.ipfs.mfs_copy(
            cmd.cid, f"{track.title}{_ext_for_mime(track.mime_type)}"
        )

        track.pinned = True
        await uow.tracks.update(track)
        await uow.commit()

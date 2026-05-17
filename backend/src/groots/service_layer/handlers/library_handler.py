import os

from groots.domain.commands import AddTrack, PinTrack, RemoveTrack, ReplaceRecording, UploadTrack
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
    user_id: str | None,
    uow: AbstractUnitOfWork,
) -> tuple[str, bool]:
    """
    Find an existing album owned by user_id with this title+artist, or create one.
    Returns (album_id, is_new) where is_new=True means we just created it.
    """
    existing = await uow.albums.find_by_title_artist(album_title, artist, user_id)
    if existing:
        return existing.id, False

    new_album = Album(
        title=album_title,
        artist=artist,
        user_id=user_id,
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
    user_id: str,
    uow: AbstractUnitOfWork,
) -> tuple[str | None, bool]:
    """
    Determine (album_id, promote_to_central) using three strategies:
      1. Central-library fingerprint match
      2. User-pool fingerprint match
      3. Embedded album tag  →  find-or-create user-owned album

    promote_to_central=True means the album was brand-new (created via Priority 3)
    and the fingerprint should be stored as is_central=True so future uploads
    from any user are automatically matched against the central library.
    """
    # Priority 1: central library
    if matched_central_id:
        album_id = await _get_album_from_fingerprint_match(matched_central_id, uow)
        if album_id:
            return album_id, False

    # Priority 2: user fingerprint pool
    if matched_user_fp_id:
        album_id = await _get_album_from_fingerprint_match(matched_user_fp_id, uow)
        if album_id:
            return album_id, False

    # Priority 3: embedded tag → find-or-create user-owned album
    if meta_album:
        album_id, is_new = await _resolve_album(meta_album, artist, user_id, uow)
        return album_id, is_new

    return None, False


def _maybe_verify_cd(meta, source: str | None) -> dict | None:
    if source != "cd":
        return None
    from groots.adapters.impl.cd_verifier import CdVerifier
    return CdVerifier().verify(meta).to_dict()


async def _pin_album_cover(
    album_id: str,
    cover_image: bytes,
    cover_mime: str | None,
    uow: AbstractUnitOfWork,
) -> None:
    album = await uow.albums.get(album_id)
    if not album or album.cover_cid:
        return
    ext = ".png" if (cover_mime or "").endswith("png") else ".jpg"
    album.cover_cid = await uow.ipfs.pin_add_bytes(
        cover_image, f"cover_{album_id}{ext}"
    )
    await uow.albums.update(album)


# ── command handlers ──────────────────────────────────────────────────────────


async def handle_add_track(cmd: AddTrack, uow: AbstractUnitOfWork) -> dict:
    async with uow:
        user = await uow.users.get(cmd.user_id)
        if user.used_storage_bytes + cmd.file_size_bytes > user.storage_quota_bytes:
            raise StorageQuotaExceeded()

        if cmd.disc_number is not None:
            await uow.tracks.backfill_null_disc_number(cmd.album_id, 1)
        if cmd.side is not None:
            await uow.tracks.backfill_null_side(cmd.album_id, "A")

        track = Track(
            cid=cmd.cid,
            title=cmd.title,
            duration_seconds=cmd.duration_seconds,
            file_size_bytes=cmd.file_size_bytes,
            album_id=cmd.album_id,
            track_number=cmd.track_number,
            mime_type=cmd.mime_type,
            source=cmd.source,
            disc_number=cmd.disc_number,
            side=cmd.side,
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
        album = await uow.albums.get(track.album_id) if track.album_id else None
        if not album or album.user_id != cmd.user_id:
            raise TrackNotOwnedByUser()

        if track.pinned:
            await uow.ipfs.pin_rm(track.cid)
            await uow.ipfs.mfs_rm(f"{track.title}{_ext_for_mime(track.mime_type)}")
            await uow.ipfs.repo_gc()

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

        title = meta.title or cmd.hint_title or fallback_title
        artist = meta.artist or cmd.hint_artist or fallback_artist
        track_number = meta.track_number or cmd.hint_track_number

        # ── 3. Fingerprint + match ───────────────────────────────────────────
        duration, fp_hex, matched_central_id, matched_user_fp_id = (
            await _run_fingerprint_pipeline(cmd.content, cmd.mime_type, uow)
        )

        # ── 4. Resolve album ─────────────────────────────────────────────────
        album_id, promote_to_central = await _resolve_album_id(
            matched_central_id=matched_central_id,
            matched_user_fp_id=matched_user_fp_id,
            meta_album=meta.album or cmd.hint_album,
            artist=artist,
            user_id=cmd.user_id,
            uow=uow,
        )

        # ── 4a. Auto-pin embedded cover art for newly created albums ─────────
        if promote_to_central and album_id and meta.cover_image:
            await _pin_album_cover(album_id, meta.cover_image, meta.cover_mime, uow)

        # ── 4b. CD verification (only when user declared source as CD) ────────
        cd_verification = _maybe_verify_cd(meta, cmd.source)

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
            cid=cid,
            title=title,
            duration_seconds=duration,
            file_size_bytes=cmd.file_size_bytes,
            album_id=album_id,
            track_number=track_number,
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


async def handle_replace_recording(
    cmd: ReplaceRecording, uow: AbstractUnitOfWork
) -> dict:
    """
    Replace the audio file of an existing track.

    Behaviour:
    - The track's title and all other metadata are preserved.
    - The filename stored in IPFS MFS is derived from the track title (not the
      uploaded filename) so the conceptual identity of the track doesn't change.
    - Old CID is unpinned from the IPFS core node and removed from MFS; the
      cluster propagates the removal to its peers automatically.
    - The new file is added and pinned, generating a new CID.
    - User quota is adjusted by the size delta (new − old).
    """
    async with uow:
        track = await uow.tracks.get(cmd.track_id)
        if not track:
            raise TrackNotFound(cmd.track_id)
        album = await uow.albums.get(track.album_id) if track.album_id else None
        if not album or album.user_id != cmd.user_id:
            raise TrackNotOwnedByUser()

        old_cid = track.cid
        old_mime = track.mime_type
        old_size = track.file_size_bytes

        # ── 1. Adjust quota (reject early if the new file would overflow) ──────
        user = await uow.users.get(cmd.user_id)
        size_delta = cmd.file_size_bytes - old_size
        if size_delta > 0 and user.used_storage_bytes + size_delta > user.storage_quota_bytes:
            raise StorageQuotaExceeded()

        # ── 2. Add new file to IPFS under the track's title as filename ─────────
        new_ext = _ext_for_mime(cmd.mime_type)
        ipfs_filename = f"{track.title}{new_ext}"
        new_cid = await uow.ipfs.pin_add_bytes(cmd.content, ipfs_filename)

        # ── 3. Unpin old CID, remove its MFS entry, and run GC ────────────────
        if track.pinned:
            await uow.ipfs.pin_rm(old_cid)
            await uow.ipfs.mfs_rm(f"{track.title}{_ext_for_mime(old_mime)}")
            await uow.ipfs.repo_gc()

        # ── 4. Extract duration from the new file (best-effort) ────────────────
        try:
            duration, _ = await uow.fingerprinter.fingerprint(cmd.content, suffix=new_ext)
        except Exception:
            duration = track.duration_seconds  # keep old value on failure

        # ── 5. Copy new file into MFS for webui visibility ─────────────────────
        await uow.ipfs.mfs_copy(new_cid, ipfs_filename)

        # ── 6. Update track record ─────────────────────────────────────────────
        track.cid = new_cid
        track.mime_type = cmd.mime_type
        track.file_size_bytes = cmd.file_size_bytes
        track.duration_seconds = duration
        track.pinned = True
        await uow.tracks.update(track)

        # ── 7. Adjust user quota ───────────────────────────────────────────────
        user.used_storage_bytes = max(0, user.used_storage_bytes + size_delta)
        await uow.users.update(user)

        await uow.commit()
        return {"track_id": track.id, "cid": new_cid}


async def handle_pin_track(cmd: PinTrack, uow: AbstractUnitOfWork) -> None:
    async with uow:
        track = await uow.tracks.get(cmd.track_id)
        if not track:
            raise TrackNotFound(cmd.track_id)
        album = await uow.albums.get(track.album_id) if track.album_id else None
        if not album or album.user_id != cmd.user_id:
            raise TrackNotOwnedByUser()

        await uow.ipfs.pin_add(cmd.cid)
        await uow.ipfs.mfs_copy(
            cmd.cid, f"{track.title}{_ext_for_mime(track.mime_type)}"
        )

        track.pinned = True
        await uow.tracks.update(track)
        await uow.commit()

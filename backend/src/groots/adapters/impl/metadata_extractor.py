import io

_JPEG = "image/jpeg"


class AudioMetadata:
    __slots__ = ("title", "artist", "album", "year", "genre", "track_number", "isrc", "mcn", "encoder", "cover_image", "cover_mime")

    def __init__(
        self,
        title: str | None = None,
        artist: str | None = None,
        album: str | None = None,
        year: int | None = None,
        genre: str | None = None,
        track_number: int | None = None,
        isrc: str | None = None,
        mcn: str | None = None,
        encoder: str | None = None,
        cover_image: bytes | None = None,
        cover_mime: str | None = None,
    ):
        self.title = title
        self.artist = artist
        self.album = album
        self.year = year
        self.genre = genre
        self.track_number = track_number
        self.isrc = isrc
        self.mcn = mcn
        self.encoder = encoder
        self.cover_image = cover_image
        self.cover_mime = cover_mime


def _tag_first(tag_obj) -> str | None:
    """Return the first non-empty string value of a mutagen tag."""
    if tag_obj is None:
        return None
    if not hasattr(tag_obj, "__iter__"):
        val = str(tag_obj)
    elif tag_obj:
        val = str(tag_obj[0])
    else:
        return None
    return val.strip() or None


def _tag_get(tags, *keys: str) -> str | None:
    for k in keys:
        try:
            v = _tag_first(tags.get(k))
        except (ValueError, KeyError):
            # VorbisComment.get() raises ValueError for keys that
            # contain characters invalid in the Vorbis spec (e.g. ©nam)
            v = None
        if v:
            return v
    return None


def _parse_year(val: str | None) -> int | None:
    if not val:
        return None
    try:
        return int(str(val)[:4])
    except (ValueError, TypeError):
        return None


def _parse_tracknum(val: str | None) -> int | None:
    if not val:
        return None
    try:
        return int(str(val).split("/")[0])
    except (ValueError, TypeError):
        return None


def _cover_from_id3(tags) -> tuple[bytes, str] | None:
    """Extract cover art from ID3 APIC frames."""
    from mutagen.id3 import APIC
    apic_frames = [v for k, v in tags.items() if k.startswith("APIC")]
    if not apic_frames:
        return None
    front = next((a for a in apic_frames if isinstance(a, APIC) and a.type == 3), apic_frames[0])
    if isinstance(front, APIC) and front.data:
        return front.data, front.mime or _JPEG
    return None


def _cover_from_flac(f) -> tuple[bytes, str] | None:
    """Extract cover art from FLAC picture blocks."""
    from mutagen.flac import FLAC as MutagenFLAC
    if not isinstance(f, MutagenFLAC) or not f.pictures:
        return None
    pic = next((p for p in f.pictures if p.type == 3), f.pictures[0])
    if pic.data:
        return pic.data, pic.mime or _JPEG
    return None


def _cover_from_mp4(tags) -> tuple[bytes, str] | None:
    """Extract cover art from MP4 covr atom."""
    from mutagen.mp4 import MP4Cover
    covr = tags.get("covr")
    if not covr:
        return None
    atom = covr[0]
    if isinstance(atom, MP4Cover) and atom:
        mime = "image/png" if atom.imageformat == MP4Cover.FORMAT_PNG else _JPEG
        return bytes(atom), mime
    return None


def _extract_cover(f, tags) -> tuple[bytes | None, str | None]:
    try:
        result = _cover_from_id3(tags) or _cover_from_flac(f) or _cover_from_mp4(tags)
        if result:
            return result
    except Exception:
        pass
    return None, None


class MetadataExtractor:
    """
    Reads embedded audio metadata (ID3, Vorbis, MP4 atoms, …) using mutagen.
    Returns an AudioMetadata dataclass with whatever fields are present.
    """

    def extract(self, content: bytes) -> AudioMetadata:
        try:
            from mutagen import File as MutagenFile
        except ImportError:
            return AudioMetadata()

        try:
            f = MutagenFile(io.BytesIO(content))
        except Exception:
            return AudioMetadata()

        if f is None or not f.tags:
            return AudioMetadata()

        tags = f.tags
        cover_image, cover_mime = _extract_cover(f, tags)

        return AudioMetadata(
            title=_tag_get(tags, "TIT2", "title", "\xa9nam"),
            artist=_tag_get(tags, "TPE1", "artist", "\xa9ART"),
            album=_tag_get(tags, "TALB", "album", "\xa9alb"),
            year=_parse_year(_tag_get(tags, "TDRC", "date", "\xa9day")),
            genre=_tag_get(tags, "TCON", "genre", "\xa9gen"),
            track_number=_parse_tracknum(_tag_get(tags, "TRCK", "tracknumber", "trkn")),
            # CD provenance signals
            isrc=_tag_get(tags, "TSRC", "ISRC", "isrc"),
            mcn=_tag_get(tags, "TXXX:MCN", "TXXX:BARCODE", "TXXX:CATALOGNUMBER", "MCN", "BARCODE", "CATALOGNUMBER"),
            encoder=_tag_get(tags, "TENC", "encoded-by", "\xa9too"),
            cover_image=cover_image,
            cover_mime=cover_mime,
        )

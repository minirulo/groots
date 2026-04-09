import io


class AudioMetadata:
    __slots__ = ("title", "artist", "album", "year", "genre", "track_number")

    def __init__(
        self,
        title: str | None = None,
        artist: str | None = None,
        album: str | None = None,
        year: int | None = None,
        genre: str | None = None,
        track_number: int | None = None,
    ):
        self.title = title
        self.artist = artist
        self.album = album
        self.year = year
        self.genre = genre
        self.track_number = track_number


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

        def _first(tag_obj) -> str | None:
            """Return the first non-empty string value of a mutagen tag."""
            if tag_obj is None:
                return None
            val = str(tag_obj) if not hasattr(tag_obj, "__iter__") else (
                str(tag_obj[0]) if tag_obj else None
            )
            return val.strip() or None

        def _get(*keys: str) -> str | None:
            for k in keys:
                v = _first(tags.get(k))
                if v:
                    return v
            return None

        def _year(val: str | None) -> int | None:
            if not val:
                return None
            try:
                return int(str(val)[:4])
            except (ValueError, TypeError):
                return None

        def _tracknum(val: str | None) -> int | None:
            if not val:
                return None
            try:
                return int(str(val).split("/")[0])
            except (ValueError, TypeError):
                return None

        # ID3 tags (MP3) and Vorbis comments (FLAC/OGG) and MP4 atoms
        title = _get("TIT2", "title", "\xa9nam")
        artist = _get("TPE1", "artist", "\xa9ART")
        album = _get("TALB", "album", "\xa9alb")
        year = _year(_get("TDRC", "date", "\xa9day"))
        genre = _get("TCON", "genre", "\xa9gen")
        track_number = _tracknum(_get("TRCK", "tracknumber", "trkn"))

        return AudioMetadata(
            title=title,
            artist=artist,
            album=album,
            year=year,
            genre=genre,
            track_number=track_number,
        )

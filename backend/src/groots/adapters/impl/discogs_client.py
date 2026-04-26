from dataclasses import dataclass, field

import httpx

_BASE = "https://api.discogs.com"


# ── Data transfer objects ─────────────────────────────────────────────────────


@dataclass
class DiscogsTrack:
    position: str
    title: str
    duration: str           # raw string from API, e.g. "3:34"
    duration_seconds: int | None
    side: str | None        # "A", "B", "C", "D", or None for non-sided releases


@dataclass
class DiscogsReleaseSummary:
    id: int
    title: str
    artist: str
    year: int | None
    label: str | None
    catalog_number: str | None
    format: str | None      # "Vinyl", "CD", etc.
    thumb_url: str | None
    resource_url: str


@dataclass
class DiscogsRelease:
    id: int
    title: str
    artist: str
    year: int | None
    label: str | None
    catalog_number: str | None
    format: str | None
    cover_url: str | None
    genres: list[str]
    styles: list[str]
    tracklist: list[DiscogsTrack]
    sides: dict[str, list[DiscogsTrack]] = field(default_factory=dict)


# ── Helpers ───────────────────────────────────────────────────────────────────


def _parse_duration(s: str) -> int | None:
    """Parse "3:34" → 214, "1:02:03" → 3723. Returns None for empty/invalid."""
    if not s or not s.strip():
        return None
    try:
        parts = [int(p) for p in s.strip().split(":")]
        if len(parts) == 2:
            return parts[0] * 60 + parts[1]
        if len(parts) == 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
    except (ValueError, IndexError):
        pass
    return None


def _extract_side(position: str) -> str | None:
    """Extract vinyl side from position: "A1" → "A", "B2" → "B", "1" → None."""
    if position and position[0].isalpha():
        return position[0].upper()
    return None


def _parse_track(raw: dict) -> DiscogsTrack:
    position = raw.get("position", "")
    duration = raw.get("duration", "")
    return DiscogsTrack(
        position=position,
        title=raw.get("title", ""),
        duration=duration,
        duration_seconds=_parse_duration(duration),
        side=_extract_side(position),
    )


def _group_by_side(tracks: list[DiscogsTrack]) -> dict[str, list[DiscogsTrack]]:
    sides: dict[str, list[DiscogsTrack]] = {}
    for t in tracks:
        key = t.side or "?"
        sides.setdefault(key, []).append(t)
    return sides


def _parse_summary(raw: dict) -> DiscogsReleaseSummary:
    # Discogs search results return "Artist - Title" as a combined title field
    combined = raw.get("title", "")
    parts = combined.split(" - ", 1)
    artist = parts[0].strip() if len(parts) > 1 else "Unknown"
    title = parts[1].strip() if len(parts) > 1 else combined

    labels = raw.get("label", [])
    label = labels[0] if labels else None

    formats = raw.get("format", [])
    fmt = formats[0] if formats else None

    try:
        year = int(str(raw["year"])) if raw.get("year") else None
    except (ValueError, TypeError):
        year = None

    return DiscogsReleaseSummary(
        id=raw.get("id", 0),
        title=title,
        artist=artist,
        year=year,
        label=label,
        catalog_number=raw.get("catno") or None,
        format=fmt,
        thumb_url=raw.get("thumb") or None,
        resource_url=raw.get("resource_url", ""),
    )


# ── Client ────────────────────────────────────────────────────────────────────


class DiscogsClient:
    """
    Thin async wrapper around the Discogs REST API.
    Requires a User-Agent string per Discogs policy.
    Optionally authenticates with a personal access token for higher rate limits
    (60 req/min unauthenticated → 240 req/min with token).
    """

    def __init__(self, user_agent: str, user_token: str | None = None):
        self._headers: dict[str, str] = {"User-Agent": user_agent}
        if user_token:
            self._headers["Authorization"] = f"Discogs token={user_token}"

    # ── Public API ────────────────────────────────────────────────────────────

    async def search_by_barcode(
        self, barcode: str, *, format: str | None = None
    ) -> list[DiscogsReleaseSummary]:
        """Look up releases matching a barcode (EAN / UPC)."""
        return await self._search(barcode=barcode, format=format)

    async def search(
        self,
        *,
        query: str | None = None,
        artist: str | None = None,
        album: str | None = None,
        format: str | None = None,
    ) -> list[DiscogsReleaseSummary]:
        """Free-text or structured artist/album search."""
        return await self._search(q=query, artist=artist, release_title=album, format=format)

    async def get_release(self, release_id: int) -> DiscogsRelease:
        """Fetch full release details including tracklist grouped by vinyl side."""
        async with httpx.AsyncClient(headers=self._headers, timeout=10.0) as client:
            resp = await client.get(f"{_BASE}/releases/{release_id}")
            resp.raise_for_status()
            data = resp.json()

        artists = data.get("artists", [])
        # Strip trailing " *" disambiguation suffix Discogs sometimes appends
        artist = artists[0].get("name", "Unknown").rstrip(" *") if artists else "Unknown"

        labels = data.get("labels", [])
        label = labels[0].get("name") if labels else None
        catno = labels[0].get("catno") if labels else None

        formats = data.get("formats", [])
        fmt = formats[0].get("name") if formats else None

        images = data.get("images", [])
        cover_url = next(
            (img["uri"] for img in images if img.get("type") == "primary"),
            images[0]["uri"] if images else None,
        )

        try:
            year = int(data["year"]) if data.get("year") else None
        except (ValueError, TypeError):
            year = None

        # Filter out section headings (type_ == "heading") which are not real tracks
        raw_tracks = [t for t in data.get("tracklist", []) if t.get("type_") != "heading"]
        tracks = [_parse_track(t) for t in raw_tracks]

        return DiscogsRelease(
            id=data["id"],
            title=data.get("title", ""),
            artist=artist,
            year=year,
            label=label,
            catalog_number=catno,
            format=fmt,
            cover_url=cover_url,
            genres=data.get("genres", []),
            styles=data.get("styles", []),
            tracklist=tracks,
            sides=_group_by_side(tracks),
        )

    # ── Internal ──────────────────────────────────────────────────────────────

    async def _search(self, **params) -> list[DiscogsReleaseSummary]:
        search_params = {k: v for k, v in params.items() if v is not None}
        search_params.setdefault("type", "release")
        search_params.setdefault("per_page", 10)

        async with httpx.AsyncClient(headers=self._headers, timeout=10.0) as client:
            resp = await client.get(f"{_BASE}/database/search", params=search_params)
            resp.raise_for_status()
            data = resp.json()

        return [_parse_summary(r) for r in data.get("results", [])]

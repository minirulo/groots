from pydantic import BaseModel


class DiscogsTrackSchema(BaseModel):
    position: str
    title: str
    duration: str
    duration_seconds: int | None
    side: str | None


class DiscogsReleaseSummarySchema(BaseModel):
    id: int
    title: str
    artist: str
    year: int | None
    label: str | None
    catalog_number: str | None
    format: str | None
    thumb_url: str | None


class DiscogsReleaseSchema(BaseModel):
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
    tracklist: list[DiscogsTrackSchema]
    sides: dict[str, list[DiscogsTrackSchema]]


class DiscogsSearchResponse(BaseModel):
    results: list[DiscogsReleaseSummarySchema]

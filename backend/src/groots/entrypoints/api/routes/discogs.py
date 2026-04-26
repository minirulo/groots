from typing import Annotated

import httpx
from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Query, Security, status

from groots.adapters.impl.discogs_client import DiscogsClient
from groots.config import settings
from groots.entrypoints.api.auth import get_current_oauth_user
from groots.entrypoints.api.container import Container
from groots.entrypoints.api.routes.schemas.discogs import (
    DiscogsReleaseSchema,
    DiscogsSearchResponse,
    DiscogsReleaseSummarySchema,
    DiscogsTrackSchema,
)

router = APIRouter(prefix="/discogs", tags=["discogs"])


def _http_error(exc: httpx.HTTPStatusError) -> HTTPException:
    if exc.response.status_code == 404:
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found on Discogs")
    if exc.response.status_code == 429:
        return HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Discogs rate limit reached — try again shortly")
    return HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Discogs API error")


@router.get("/search", response_model=DiscogsSearchResponse)
@inject
async def search_releases(
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_READ])
    ],
    discogs: Annotated[DiscogsClient, Depends(Provide[Container.discogs_client])],
    barcode: Annotated[str | None, Query(description="EAN / UPC barcode printed on the sleeve")] = None,
    artist: Annotated[str | None, Query(description="Artist name")] = None,
    album: Annotated[str | None, Query(description="Album / release title")] = None,
    q: Annotated[str | None, Query(description="Free-text query (fallback when artist/album unknown)")] = None,
    format: Annotated[str | None, Query(description='Discogs format filter, e.g. "Vinyl", "CD", "Cassette"')] = None,
) -> DiscogsSearchResponse:
    """
    Search Discogs for releases.

    Priority: barcode > artist+album > free-text query.
    At least one of barcode / artist / album / q is required.
    Use `format=Vinyl` to restrict results to vinyl pressings.
    """
    if not any([barcode, artist, album, q]):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Provide at least one of: barcode, artist, album, q",
        )
    try:
        if barcode:
            results = await discogs.search_by_barcode(barcode, format=format)
        else:
            results = await discogs.search(query=q, artist=artist, album=album, format=format)
    except httpx.HTTPStatusError as exc:
        raise _http_error(exc)
    except httpx.RequestError:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Could not reach Discogs")

    return DiscogsSearchResponse(
        results=[
            DiscogsReleaseSummarySchema(
                id=r.id,
                title=r.title,
                artist=r.artist,
                year=r.year,
                label=r.label,
                catalog_number=r.catalog_number,
                format=r.format,
                thumb_url=r.thumb_url,
            )
            for r in results
        ]
    )


@router.get("/releases/{release_id}", response_model=DiscogsReleaseSchema)
@inject
async def get_release(
    release_id: int,
    current_user: Annotated[
        dict, Security(get_current_oauth_user, scopes=[settings.LIBRARY_READ])
    ],
    discogs: Annotated[DiscogsClient, Depends(Provide[Container.discogs_client])],
) -> DiscogsReleaseSchema:
    """
    Fetch full release details from Discogs, including the tracklist grouped by
    vinyl side (A, B, C, D).  Use this after the user picks a result from /search
    to get the track names and durations needed for the waveform splitter.
    """
    try:
        release = await discogs.get_release(release_id)
    except httpx.HTTPStatusError as exc:
        raise _http_error(exc)
    except httpx.RequestError:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Could not reach Discogs")

    def _track(t) -> DiscogsTrackSchema:
        return DiscogsTrackSchema(
            position=t.position,
            title=t.title,
            duration=t.duration,
            duration_seconds=t.duration_seconds,
            side=t.side,
        )

    return DiscogsReleaseSchema(
        id=release.id,
        title=release.title,
        artist=release.artist,
        year=release.year,
        label=release.label,
        catalog_number=release.catalog_number,
        format=release.format,
        cover_url=release.cover_url,
        genres=release.genres,
        styles=release.styles,
        tracklist=[_track(t) for t in release.tracklist],
        sides={side: [_track(t) for t in tracks] for side, tracks in release.sides.items()},
    )

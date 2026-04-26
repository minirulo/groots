from fastapi import APIRouter

from groots.entrypoints.api.routes import (
    admin,
    albums,
    auth,
    discogs,
    genres,
    ipfs,
    library,
    playlists,
    users,
)

router = APIRouter()
router.include_router(auth.router)
router.include_router(users.router)
router.include_router(library.router)
router.include_router(albums.router)
router.include_router(playlists.router)
router.include_router(genres.router)
router.include_router(admin.router)
router.include_router(ipfs.router)
router.include_router(discogs.router)

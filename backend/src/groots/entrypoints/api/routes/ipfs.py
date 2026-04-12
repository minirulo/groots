import httpx
from fastapi import APIRouter, HTTPException

from groots.config import settings

router = APIRouter(prefix="/ipfs", tags=["ipfs"])


@router.get("/peer-id")
async def get_ipfs_peer_id() -> dict:
    """
    Returns the Kubo node's peer ID so client nodes (e.g. the Mac local
    IPFS daemon) can explicitly connect to it via swarm connect.

    Unauthenticated — the peer ID is not secret; the swarm key is what
    restricts who can actually join the private network.
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{settings.IPFS_API_URL}/api/v0/id",
                timeout=5.0,
            )
        data = response.json()
        return {"peer_id": data["ID"]}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"IPFS node unavailable: {exc}")

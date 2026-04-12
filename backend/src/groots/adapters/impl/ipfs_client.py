import json
import httpx

from groots.domain.errors import IPFSError


class IPFSClient:
    """Thin async wrapper around the Kubo (go-ipfs) HTTP RPC API."""

    def __init__(self, api_url: str, gateway_url: str):
        self.api_url = api_url.rstrip("/")
        self.gateway_url = gateway_url.rstrip("/")

    async def pin_add(self, cid: str) -> None:
        """Pin a CID on the central node so it persists when user goes offline."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_url}/api/v0/pin/add",
                params={"arg": cid, "recursive": "true"},
                timeout=30.0,
            )
        if response.status_code != 200:
            raise IPFSError(f"Failed to pin CID {cid}: {response.text}")

    async def pin_rm(self, cid: str) -> None:
        """Unpin a CID from the central node."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_url}/api/v0/pin/rm",
                params={"arg": cid},
                timeout=10.0,
            )
        if response.status_code != 200:
            raise IPFSError(f"Failed to unpin CID {cid}: {response.text}")

    async def is_pinned(self, cid: str) -> bool:
        """Check whether a CID is currently pinned on this node."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_url}/api/v0/pin/ls",
                params={"arg": cid, "type": "recursive"},
                timeout=10.0,
            )
        return response.status_code == 200

    async def pin_add_bytes(self, content: bytes, filename: str) -> str:
        """Add raw bytes to IPFS and pin them. Returns the CID."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_url}/api/v0/add",
                params={"pin": "true"},
                files={"file": (filename, content, "application/octet-stream")},
                timeout=120.0,
            )
        if response.status_code != 200:
            raise IPFSError(f"Failed to add file to IPFS: {response.text}")
        # Kubo returns newline-delimited JSON; last non-empty line is the root
        last_line = response.text.strip().split("\n")[-1]
        data = json.loads(last_line)
        return data["Hash"]

    async def mfs_rm(self, filename: str) -> None:
        """
        Remove /groots/<filename> from the Kubo MFS.

        Errors are silently ignored (file may not exist in MFS).
        """
        safe = filename.replace("/", "_")
        async with httpx.AsyncClient() as client:
            try:
                await client.post(
                    f"{self.api_url}/api/v0/files/rm",
                    params={"arg": f"/groots/{safe}"},
                    timeout=10.0,
                )
            except Exception:
                pass

    async def mfs_copy(self, cid: str, filename: str) -> None:
        """
        Copy a CID into the Kubo MFS at /groots/<filename>.

        This makes the file appear under the Files tab in ipfs-webui.
        Errors are silently ignored — MFS visibility is best-effort.
        """
        safe = filename.replace("/", "_")
        async with httpx.AsyncClient() as client:
            try:
                await client.post(
                    f"{self.api_url}/api/v0/files/mkdir",
                    params={"arg": "/groots", "parents": "true"},
                    timeout=10.0,
                )
                await client.post(
                    f"{self.api_url}/api/v0/files/cp",
                    params=[("arg", f"/ipfs/{cid}"), ("arg", f"/groots/{safe}")],
                    timeout=10.0,
                )
            except Exception:
                pass  # MFS copy is best-effort

    def stream_url(self, cid: str) -> str:
        """
        Return the gateway URL for streaming a CID.

        In production, route this through an authenticated nginx proxy so that
        only the owning user can access the content — raw IPFS gateway URLs
        are public by default.
        """
        return f"{self.gateway_url}/ipfs/{cid}"

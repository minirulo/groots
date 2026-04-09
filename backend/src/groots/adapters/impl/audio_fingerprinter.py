import asyncio
import os
import struct
import tempfile

from groots.domain.errors import FingerprintError


class AudioFingerprinter:
    """
    Generates and compares Chromaprint acoustic fingerprints.

    Requires the `fpcalc` binary (part of libchromaprint-tools) to be on PATH,
    and the `pyacoustid` Python package.
    """

    MATCH_THRESHOLD = 0.75  # minimum similarity score to consider a match

    async def fingerprint(
        self, content: bytes, suffix: str = ".mp3"
    ) -> tuple[int, str]:
        """
        Fingerprint raw audio bytes.  Returns (duration_seconds, fingerprint_hex).
        Runs fpcalc in a thread executor so it does not block the event loop.
        """
        import acoustid

        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            tmp.write(content)
            tmp_path = tmp.name

        try:
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None, acoustid.fingerprint_file, tmp_path
            )
            duration_sec, fp_bytes = result
            return int(duration_sec), fp_bytes.hex()
        except Exception as exc:
            raise FingerprintError(f"Fingerprinting failed: {exc}") from exc
        finally:
            os.unlink(tmp_path)

    @staticmethod
    def compare(fp1_hex: str, fp2_hex: str) -> float:
        """
        Compare two fingerprints stored as hex strings.
        Returns similarity score in [0, 1] using bit-error rate on the raw
        Chromaprint integer array (same approach as fpcalc -overlap).
        """
        try:
            b1 = bytes.fromhex(fp1_hex)
            b2 = bytes.fromhex(fp2_hex)
        except ValueError:
            return 0.0

        n = min(len(b1) // 4, len(b2) // 4)
        if n == 0:
            return 0.0

        ints1 = struct.unpack(f"<{n}I", b1[: n * 4])
        ints2 = struct.unpack(f"<{n}I", b2[: n * 4])
        error_bits = sum(bin(a ^ b).count("1") for a, b in zip(ints1, ints2))
        return 1.0 - (error_bits / (n * 32))

    def best_match(
        self, query_hex: str, candidates: list[tuple[str, str]]
    ) -> tuple[str | None, float]:
        """
        Find the best match from a list of (id, fingerprint_hex) candidates.
        Returns (best_id, score) or (None, 0.0) if no candidate exceeds the threshold.
        """
        best_id: str | None = None
        best_score = 0.0
        for cand_id, cand_fp in candidates:
            score = self.compare(query_hex, cand_fp)
            if score > best_score:
                best_score = score
                best_id = cand_id

        if best_score >= self.MATCH_THRESHOLD:
            return best_id, best_score
        return None, best_score

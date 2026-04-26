from dataclasses import dataclass

from groots.adapters.impl.metadata_extractor import AudioMetadata

# Lowercase substrings to match against the encoder tag value
_KNOWN_RIPPERS = {"xld", "eac", "exact audio copy", "dbpoweramp", "whipper", "cuerip"}


@dataclass
class CdVerificationResult:
    has_isrc: bool
    has_mcn: bool
    encoder: str | None
    confidence: str  # "strong" | "medium" | "weak"

    def to_dict(self) -> dict:
        return {
            "has_isrc": self.has_isrc,
            "has_mcn": self.has_mcn,
            "encoder": self.encoder,
            "confidence": self.confidence,
        }


class CdVerifier:
    """
    Examines AudioMetadata for signals that confirm a file originated from a
    physical CD rip.

    Confidence levels:
      strong  — ISRC present AND (MCN present OR known CD ripper tool)
      medium  — exactly one of: ISRC, MCN, known ripper encoder
      weak    — source declared as CD but none of the above signals found
    """

    def verify(self, meta: AudioMetadata) -> CdVerificationResult:
        has_isrc = bool(meta.isrc)
        has_mcn = bool(meta.mcn)
        known_ripper = self._is_known_ripper(meta.encoder)

        if has_isrc and (has_mcn or known_ripper):
            confidence = "strong"
        elif has_isrc or has_mcn or known_ripper:
            confidence = "medium"
        else:
            confidence = "weak"

        return CdVerificationResult(
            has_isrc=has_isrc,
            has_mcn=has_mcn,
            encoder=meta.encoder,
            confidence=confidence,
        )

    @staticmethod
    def _is_known_ripper(encoder: str | None) -> bool:
        if not encoder:
            return False
        enc_lower = encoder.lower()
        return any(r in enc_lower for r in _KNOWN_RIPPERS)

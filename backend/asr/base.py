from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


@dataclass(frozen=True)
class Transcription:
    text: str
    language: str = "zh"
    model: str = "unknown"


class ASREngine(Protocol):
    name: str

    def transcribe(self, audio_path: Path) -> Transcription:
        """Transcribe a mono WAV recording."""

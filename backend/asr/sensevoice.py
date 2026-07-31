from __future__ import annotations

from pathlib import Path
from threading import Lock
from typing import Any

from backend.asr.base import Transcription


class SenseVoiceEngine:
    name = "sensevoice"

    def __init__(self, device: str = "cpu", model: str = "iic/SenseVoiceSmall") -> None:
        self._device = device
        self._model_name = model
        self._model: Any | None = None
        self._lock = Lock()

    def _load(self) -> Any:
        if self._model is None:
            with self._lock:
                if self._model is None:
                    try:
                        from funasr import AutoModel
                    except ImportError as error:
                        raise RuntimeError(
                            "SenseVoice 依赖未安装，请运行 ./install.sh。"
                        ) from error
                    self._model = AutoModel(
                        model=self._model_name,
                        trust_remote_code=True,
                        vad_model="fsmn-vad",
                        vad_kwargs={"max_single_segment_time": 30_000},
                        device=self._device,
                        disable_update=True,
                    )
        return self._model

    def transcribe(self, audio_path: Path) -> Transcription:
        result = self._load().generate(
            input=str(audio_path),
            cache={},
            language="zh",
            use_itn=True,
            batch_size_s=60,
            merge_vad=True,
            merge_length_s=15,
        )
        text = self._extract_text(result)
        return Transcription(text=text, language="zh", model=self.name)

    @staticmethod
    def _extract_text(result: Any) -> str:
        if isinstance(result, list) and result:
            first = result[0]
            if isinstance(first, dict):
                return str(first.get("text", "")).strip()
            return str(first).strip()
        if isinstance(result, dict):
            return str(result.get("text", "")).strip()
        return str(result or "").strip()

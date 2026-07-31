from __future__ import annotations

from pathlib import Path
from threading import Lock
from typing import Any

from backend.asr.base import Transcription


class ParaformerEngine:
    name = "paraformer"

    def __init__(
        self,
        device: str = "cpu",
        model: str = "paraformer-zh",
        punctuation_model: str = "ct-punc",
    ) -> None:
        self._device = device
        self._model_name = model
        self._punctuation_model = punctuation_model
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
                            "FunASR 依赖未安装，请运行 ./install.sh。"
                        ) from error
                    self._model = AutoModel(
                        model=self._model_name,
                        punc_model=self._punctuation_model,
                        device=self._device,
                        disable_update=True,
                    )
        return self._model

    def transcribe(self, audio_path: Path) -> Transcription:
        result = self._load().generate(
            input=str(audio_path),
            batch_size_s=60,
            hotword="智能采油 科研项目 Research OS VoiceForge",
        )
        text = SenseVoiceCompatibleResult.extract(result)
        return Transcription(text=text, language="zh", model=self.name)


class SenseVoiceCompatibleResult:
    @staticmethod
    def extract(result: Any) -> str:
        if isinstance(result, list) and result:
            result = result[0]
        if isinstance(result, dict):
            return str(result.get("text", "")).strip()
        return str(result or "").strip()

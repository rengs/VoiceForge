from __future__ import annotations

from backend.asr.base import ASREngine
from backend.asr.funasr import ParaformerEngine
from backend.asr.sensevoice import SenseVoiceEngine


def create_asr_engine(name: str, device: str = "cpu") -> ASREngine:
    engines: dict[str, type[SenseVoiceEngine] | type[ParaformerEngine]] = {
        "sensevoice": SenseVoiceEngine,
        "sensevoicesmall": SenseVoiceEngine,
        "paraformer": ParaformerEngine,
        "funasr": ParaformerEngine,
    }
    try:
        engine_type = engines[name.lower()]
    except KeyError as error:
        supported = ", ".join(sorted(engines))
        raise ValueError(f"未知 ASR 模型 {name!r}，可选：{supported}") from error
    return engine_type(device=device)

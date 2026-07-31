from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    asr_model: str
    asr_device: str
    language: str
    llm_provider: str
    llm_model: str
    llm_timeout_seconds: float
    llm_max_tokens: int
    llm_think: bool
    llm_keep_alive: str
    ollama_url: str
    openai_base_url: str
    openai_api_key: str
    data_dir: Path

    @classmethod
    def load(cls) -> "Settings":
        _load_dotenv(PROJECT_ROOT / ".env")
        data_dir = Path(
            os.getenv("VOICEFORGE_DATA_DIR", str(PROJECT_ROOT / "data"))
        ).expanduser()
        return cls(
            host=os.getenv("VOICEFORGE_HOST", "127.0.0.1"),
            port=int(os.getenv("VOICEFORGE_PORT", "8765")),
            asr_model=os.getenv("VOICEFORGE_ASR_MODEL", "sensevoice").lower(),
            asr_device=os.getenv("VOICEFORGE_ASR_DEVICE", "cpu").lower(),
            language=os.getenv("VOICEFORGE_LANGUAGE", "zh"),
            llm_provider=os.getenv("VOICEFORGE_LLM_PROVIDER", "ollama").lower(),
            llm_model=os.getenv("VOICEFORGE_LLM_MODEL", "qwen2.5:3b"),
            llm_timeout_seconds=float(
                os.getenv("VOICEFORGE_LLM_TIMEOUT_SECONDS", "45")
            ),
            llm_max_tokens=int(os.getenv("VOICEFORGE_LLM_MAX_TOKENS", "512")),
            llm_think=_env_bool("VOICEFORGE_LLM_THINK", False),
            llm_keep_alive=os.getenv("VOICEFORGE_LLM_KEEP_ALIVE", "10m"),
            ollama_url=os.getenv(
                "VOICEFORGE_OLLAMA_URL", "http://127.0.0.1:11434"
            ).rstrip("/"),
            openai_base_url=os.getenv(
                "VOICEFORGE_OPENAI_BASE_URL", "https://api.openai.com/v1"
            ).rstrip("/"),
            openai_api_key=os.getenv("VOICEFORGE_OPENAI_API_KEY", ""),
            data_dir=data_dir,
        )

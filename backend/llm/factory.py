from __future__ import annotations

from backend.config import Settings
from backend.llm.provider import (
    DisabledProvider,
    LLMProvider,
    OllamaProvider,
    OpenAICompatibleProvider,
)


def create_llm_provider(settings: Settings) -> LLMProvider:
    if settings.llm_provider == "ollama":
        return OllamaProvider(
            settings.ollama_url,
            settings.llm_model,
            timeout_seconds=settings.llm_timeout_seconds,
            max_tokens=settings.llm_max_tokens,
            think=settings.llm_think,
            keep_alive=settings.llm_keep_alive,
        )
    if settings.llm_provider in {"openai", "openai-compatible"}:
        return OpenAICompatibleProvider(
            settings.openai_base_url,
            settings.llm_model,
            settings.openai_api_key,
            timeout_seconds=settings.llm_timeout_seconds,
            max_tokens=settings.llm_max_tokens,
        )
    if settings.llm_provider in {"disabled", "none"}:
        return DisabledProvider()
    raise ValueError(f"未知 LLM Provider：{settings.llm_provider}")

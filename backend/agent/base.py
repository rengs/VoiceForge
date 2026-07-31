from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from backend.llm.provider import LLMProvider


@dataclass(frozen=True)
class AgentContext:
    instruction: str
    content: str
    language: str = "zh"


class AgentPlugin(Protocol):
    intent: str

    def run(self, context: AgentContext, llm: LLMProvider) -> str:
        """Execute the Agent and return text ready for injection."""

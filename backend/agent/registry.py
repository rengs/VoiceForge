from __future__ import annotations

from backend.agent.base import AgentPlugin
from backend.agent.builtin import builtin_prompt_agents
from backend.agent.rewrite import RewriteAgent


class AgentRegistry:
    def __init__(self) -> None:
        self._agents: dict[str, AgentPlugin] = {}

    def register(self, agent: AgentPlugin) -> None:
        if agent.intent in self._agents:
            raise ValueError(f"Agent intent 已注册：{agent.intent}")
        self._agents[agent.intent] = agent

    def get(self, intent: str) -> AgentPlugin:
        try:
            return self._agents[intent]
        except KeyError as error:
            raise LookupError(f"没有处理 {intent!r} 的 Agent。") from error

    @property
    def intents(self) -> tuple[str, ...]:
        return tuple(sorted(self._agents))


def create_default_registry() -> AgentRegistry:
    registry = AgentRegistry()
    registry.register(RewriteAgent())
    for agent in builtin_prompt_agents():
        registry.register(agent)
    return registry

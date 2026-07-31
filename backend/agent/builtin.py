from __future__ import annotations

from dataclasses import dataclass

from backend.agent.base import AgentContext
from backend.llm.provider import LLMProvider


@dataclass(frozen=True)
class PromptAgent:
    intent: str
    role: str
    task: str

    def run(self, context: AgentContext, llm: LLMProvider) -> str:
        return llm.chat(
            [
                {
                    "role": "system",
                    "content": (
                        f"你是{self.role}。{self.task}"
                        "不要解释处理过程，只输出可直接使用的最终结果。"
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        f"用户要求：{context.instruction}\n\n"
                        f"处理内容：\n{context.content}"
                    ),
                },
            ]
        )


def builtin_prompt_agents() -> list[PromptAgent]:
    return [
        PromptAgent(
            intent="summarize",
            role="内容总结助手",
            task="提取关键信息，保持原意，使用与原文相同的语言。",
        ),
        PromptAgent(
            intent="translate",
            role="专业翻译助手",
            task="根据用户指令判断目标语言，准确翻译术语和上下文。",
        ),
        PromptAgent(
            intent="generate",
            role="中文内容创作助手",
            task="根据用户目标生成结构清晰、事实谨慎的内容。",
        ),
        PromptAgent(
            intent="code",
            role="资深编程助手",
            task="生成正确、简洁并符合用户语言和技术栈要求的代码。",
        ),
    ]

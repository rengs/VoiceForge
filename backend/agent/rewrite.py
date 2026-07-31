from __future__ import annotations

from backend.agent.base import AgentContext
from backend.llm.provider import LLMProvider


class RewriteAgent:
    intent = "rewrite"

    def run(self, context: AgentContext, llm: LLMProvider) -> str:
        return llm.chat(
            [
                {
                    "role": "system",
                    "content": (
                        "你是中文写作助手。严格按用户要求改写，保留事实和专有名词，"
                        "不要解释过程，只输出可直接使用的最终文本。"
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        f"改写要求：{context.instruction}\n\n"
                        f"待改写内容：\n{context.content}"
                    ),
                },
            ]
        )

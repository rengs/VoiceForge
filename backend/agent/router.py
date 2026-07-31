from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum


class Intent(StrEnum):
    INPUT = "input"
    REWRITE = "rewrite"
    SUMMARIZE = "summarize"
    TRANSLATE = "translate"
    GENERATE = "generate"
    CODE = "code"


@dataclass(frozen=True)
class RouteDecision:
    intent: Intent
    instruction: str
    content: str
    source: str


class IntentRouter:
    """Deterministic intent routing; no LLM call is needed for ordinary dictation."""

    _RULES: tuple[tuple[Intent, re.Pattern[str]], ...] = (
        (
            Intent.TRANSLATE,
            re.compile(r"(翻译|译成|translate|英文版|中文版)", re.IGNORECASE),
        ),
        (
            Intent.SUMMARIZE,
            re.compile(r"(总结|摘要|概括|提炼|summari[sz]e)", re.IGNORECASE),
        ),
        (
            Intent.CODE,
            re.compile(r"(写.*代码|生成.*代码|编程|函数|脚本|code)", re.IGNORECASE),
        ),
        (
            Intent.REWRITE,
            re.compile(
                r"(改写|润色|优化.*(?:表达|语言|文字)|改成.*(?:语言|口吻|风格)|"
                r"科研项目申报语言|科技项目申报语言)",
                re.IGNORECASE,
            ),
        ),
        (
            Intent.GENERATE,
            re.compile(r"(生成|撰写|起草|帮我写|写一[份段篇])", re.IGNORECASE),
        ),
    )

    def route(
        self,
        text: str,
        selected_text: str | None = None,
        recent_input: str | None = None,
    ) -> RouteDecision:
        for intent, pattern in self._RULES:
            if pattern.search(text):
                content, source = self._resolve_content(
                    text, selected_text, recent_input
                )
                return RouteDecision(
                    intent=intent,
                    instruction=text,
                    content=content,
                    source=source,
                )
        return RouteDecision(
            intent=Intent.INPUT,
            instruction="直接输入",
            content=text,
            source="dictation",
        )

    @staticmethod
    def _resolve_content(
        instruction: str,
        selected_text: str | None,
        recent_input: str | None,
    ) -> tuple[str, str]:
        if selected_text and selected_text.strip():
            return selected_text.strip(), "selection"
        if recent_input and recent_input.strip():
            return recent_input.strip(), "memory"
        return instruction.strip(), "instruction"

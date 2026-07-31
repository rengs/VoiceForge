from __future__ import annotations

import re


class TextProcessor:
    _TERMINAL_PUNCTUATION = set("。！？.!?")

    def __init__(self, terms: dict[str, str] | None = None) -> None:
        self._terms = terms or {}

    def process(self, text: str) -> str:
        cleaned = re.sub(r"\s+", " ", text).strip()
        cleaned = self._strip_model_tags(cleaned)
        for source, target in self._terms.items():
            cleaned = cleaned.replace(source, target)
        if cleaned and cleaned[-1] not in self._TERMINAL_PUNCTUATION:
            cleaned += "。"
        return cleaned

    def set_term(self, source: str, target: str) -> None:
        self._terms[source] = target

    @staticmethod
    def _strip_model_tags(text: str) -> str:
        # SenseVoice may prepend tokens such as <|zh|><|NEUTRAL|><|Speech|>.
        return re.sub(r"<\|[^|]+\|>", "", text).strip()

from __future__ import annotations

import json

import pytest

from backend.llm import provider as provider_module
from backend.llm.provider import OllamaProvider


class FakeResponse:
    def __init__(self, payload: dict[str, object]) -> None:
        self._data = json.dumps(payload).encode("utf-8")

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *args: object) -> None:
        del args

    def read(self) -> bytes:
        return self._data


def test_ollama_request_is_bounded(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, object] = {}

    def fake_urlopen(request: object, timeout: float) -> FakeResponse:
        captured["request"] = request
        captured["timeout"] = timeout
        return FakeResponse({"message": {"content": "已完成。"}})

    monkeypatch.setattr(provider_module, "urlopen", fake_urlopen)
    llm = OllamaProvider(
        "http://127.0.0.1:11434",
        "qwen2.5:3b",
        timeout_seconds=12,
        max_tokens=128,
        think=False,
        keep_alive="5m",
    )

    assert llm.chat([{"role": "user", "content": "测试"}]) == "已完成。"
    request = captured["request"]
    body = json.loads(request.data.decode("utf-8"))  # type: ignore[attr-defined]
    assert captured["timeout"] == 12
    assert body["think"] is False
    assert body["options"]["num_predict"] == 128
    assert body["keep_alive"] == "5m"


def test_llm_timeout_has_actionable_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fake_urlopen(request: object, timeout: float) -> FakeResponse:
        del request, timeout
        raise TimeoutError

    monkeypatch.setattr(provider_module, "urlopen", fake_urlopen)
    llm = OllamaProvider(
        "http://127.0.0.1:11434",
        "qwen2.5:3b",
        timeout_seconds=8,
    )

    with pytest.raises(RuntimeError, match="超过 8 秒.*自动中止"):
        llm.chat([{"role": "user", "content": "测试"}])

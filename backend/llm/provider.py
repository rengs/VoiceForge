from __future__ import annotations

import json
import socket
from abc import ABC, abstractmethod
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


Message = dict[str, str]


class LLMProvider(ABC):
    @abstractmethod
    def chat(self, messages: list[Message]) -> str:
        raise NotImplementedError

    def generate(self, prompt: str) -> str:
        return self.chat([{"role": "user", "content": prompt}])


class OllamaProvider(LLMProvider):
    def __init__(
        self,
        base_url: str,
        model: str,
        *,
        timeout_seconds: float = 45,
        max_tokens: int = 512,
        think: bool = False,
        keep_alive: str = "10m",
    ) -> None:
        self._url = f"{base_url.rstrip('/')}/api/chat"
        self._model = model
        self._timeout_seconds = timeout_seconds
        self._max_tokens = max_tokens
        self._think = think
        self._keep_alive = keep_alive

    def chat(self, messages: list[Message]) -> str:
        response = _post_json(
            self._url,
            {
                "model": self._model,
                "messages": messages,
                "stream": False,
                "think": self._think,
                "keep_alive": self._keep_alive,
                "options": {"num_predict": self._max_tokens},
            },
            timeout_seconds=self._timeout_seconds,
        )
        content = str(response.get("message", {}).get("content", "")).strip()
        if not content:
            raise RuntimeError("LLM 返回了空内容。")
        return content


class OpenAICompatibleProvider(LLMProvider):
    def __init__(
        self,
        base_url: str,
        model: str,
        api_key: str = "",
        *,
        timeout_seconds: float = 45,
        max_tokens: int = 512,
    ) -> None:
        self._url = f"{base_url.rstrip('/')}/chat/completions"
        self._model = model
        self._api_key = api_key
        self._timeout_seconds = timeout_seconds
        self._max_tokens = max_tokens

    def chat(self, messages: list[Message]) -> str:
        headers = {}
        if self._api_key:
            headers["Authorization"] = f"Bearer {self._api_key}"
        response = _post_json(
            self._url,
            {
                "model": self._model,
                "messages": messages,
                "max_tokens": self._max_tokens,
            },
            headers=headers,
            timeout_seconds=self._timeout_seconds,
        )
        choices = response.get("choices", [])
        if not choices:
            raise RuntimeError("LLM 返回中没有 choices。")
        return str(choices[0]["message"]["content"]).strip()


class DisabledProvider(LLMProvider):
    def chat(self, messages: list[Message]) -> str:
        del messages
        raise RuntimeError(
            "当前 AI Agent 需要 LLM。请安装并启动 Ollama，或在 .env 中配置兼容接口。"
        )


def _post_json(
    url: str,
    payload: dict[str, Any],
    headers: dict[str, str] | None = None,
    *,
    timeout_seconds: float = 45,
) -> dict[str, Any]:
    request_headers = {"Content-Type": "application/json", **(headers or {})}
    request = Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=request_headers,
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"LLM 请求失败（HTTP {error.code}）：{detail}") from error
    except (TimeoutError, socket.timeout) as error:
        raise RuntimeError(
            f"LLM 响应超过 {timeout_seconds:g} 秒，已自动中止。"
            "可缩短指令，或调整 .env 中的 "
            "VOICEFORGE_LLM_TIMEOUT_SECONDS。"
        ) from error
    except URLError as error:
        if isinstance(error.reason, (TimeoutError, socket.timeout)):
            raise RuntimeError(
                f"LLM 响应超过 {timeout_seconds:g} 秒，已自动中止。"
                "可缩短指令，或调整 .env 中的 "
                "VOICEFORGE_LLM_TIMEOUT_SECONDS。"
            ) from error
        raise RuntimeError(f"无法连接 LLM 服务：{error.reason}") from error

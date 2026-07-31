from __future__ import annotations

import importlib.util
import json
from dataclasses import dataclass, asdict
from urllib.error import URLError
from urllib.request import urlopen

from backend.config import Settings


@dataclass(frozen=True)
class Check:
    name: str
    ok: bool
    detail: str


def run_checks(settings: Settings | None = None) -> list[Check]:
    settings = settings or Settings.load()
    checks = [
        _module_check("FastAPI", "fastapi"),
        _module_check("SoundDevice", "sounddevice"),
        _module_check("FunASR", "funasr"),
        _module_check("ModelScope", "modelscope"),
        _microphone_check(),
    ]
    if settings.llm_provider == "ollama":
        checks.append(_ollama_check(settings.ollama_url, settings.llm_model))
    return checks


def _module_check(label: str, module: str) -> Check:
    installed = importlib.util.find_spec(module) is not None
    return Check(label, installed, "已安装" if installed else "未安装")


def _microphone_check() -> Check:
    try:
        import sounddevice as sd

        info = sd.query_devices(None, "input")
        return Check(
            "麦克风",
            int(info.get("max_input_channels", 0)) > 0,
            str(info.get("name", "未知设备")),
        )
    except Exception as error:
        return Check("麦克风", False, str(error))


def _ollama_check(base_url: str, model: str) -> Check:
    try:
        with urlopen(f"{base_url.rstrip('/')}/api/tags", timeout=2) as response:
            payload = json.loads(response.read().decode("utf-8"))
        models = [item.get("name", "") for item in payload.get("models", [])]
        found = any(name == model or name.startswith(f"{model}:") for name in models)
        detail = f"模型 {model} 已就绪" if found else f"服务在线，缺少模型 {model}"
        return Check("Ollama", found, detail)
    except (URLError, TimeoutError) as error:
        return Check("Ollama", False, f"服务未运行：{error}")


def format_checks(checks: list[Check]) -> str:
    lines = []
    for check in checks:
        symbol = "✓" if check.ok else "✗"
        lines.append(f"{symbol} {check.name}: {check.detail}")
    return "\n".join(lines)


def checks_as_json(checks: list[Check]) -> str:
    return json.dumps([asdict(check) for check in checks], ensure_ascii=False)

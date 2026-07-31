from __future__ import annotations

from pathlib import Path

import pytest

from backend.agent.registry import create_default_registry
from backend.agent.router import IntentRouter
from backend.events import EventBus
from backend.memory.store import MemoryStore
from backend.service import VoiceForgeService
from backend.text.processor import TextProcessor


class FakeRecorder:
    is_recording = False

    def start(self) -> None:
        self.is_recording = True

    def stop(self) -> Path:
        self.is_recording = False
        return Path("/tmp/fake.wav")


class FakeASR:
    name = "fake"

    def transcribe(self, audio_path: Path):
        del audio_path
        from backend.asr.base import Transcription

        return Transcription("今天完成智能采油项目方案编制", model=self.name)


class FakeLLM:
    def __init__(self) -> None:
        self.messages: list[dict[str, str]] = []

    def chat(self, messages: list[dict[str, str]]) -> str:
        self.messages = messages
        return "本项目拟完成智能采油项目方案的系统化编制。"

    def generate(self, prompt: str) -> str:
        return self.chat([{"role": "user", "content": prompt}])


@pytest.fixture
def service(tmp_path: Path) -> VoiceForgeService:
    events = EventBus()
    memory = MemoryStore(tmp_path / "memory.sqlite3")
    events.subscribe("*", memory.record_event)
    return VoiceForgeService(
        recorder=FakeRecorder(),  # type: ignore[arg-type]
        asr=FakeASR(),  # type: ignore[arg-type]
        processor=TextProcessor(),
        router=IntentRouter(),
        agents=create_default_registry(),
        llm=FakeLLM(),  # type: ignore[arg-type]
        memory=memory,
        events=events,
    )

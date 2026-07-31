from __future__ import annotations

import os
from dataclasses import dataclass

from backend.agent.registry import create_default_registry
from backend.agent.router import IntentRouter
from backend.asr.factory import create_asr_engine
from backend.config import Settings
from backend.events import EventBus
from backend.llm.factory import create_llm_provider
from backend.memory.store import MemoryStore
from backend.service import VoiceForgeService
from backend.text.processor import TextProcessor
from backend.voice.recorder import AudioRecorder


@dataclass
class Runtime:
    settings: Settings
    service: VoiceForgeService
    memory: MemoryStore
    events: EventBus

    def close(self) -> None:
        self.memory.close()


def create_runtime(settings: Settings | None = None) -> Runtime:
    settings = settings or Settings.load()
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    events = EventBus()
    memory = MemoryStore(settings.data_dir / "voiceforge.sqlite3")
    events.subscribe("*", memory.record_event)
    processor = TextProcessor(memory.terms())
    recorder = AudioRecorder(settings.data_dir / "recordings")
    if os.environ.get("VOICEFORGE_PREWARM_MIC") == "1":
        recorder.warm_up()
    service = VoiceForgeService(
        recorder=recorder,
        asr=create_asr_engine(settings.asr_model, settings.asr_device),
        processor=processor,
        router=IntentRouter(),
        agents=create_default_registry(),
        llm=create_llm_provider(settings),
        memory=memory,
        events=events,
        language=settings.language,
    )
    return Runtime(
        settings=settings,
        service=service,
        memory=memory,
        events=events,
    )

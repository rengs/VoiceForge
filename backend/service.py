from __future__ import annotations

from dataclasses import asdict, dataclass
from enum import StrEnum
from pathlib import Path
from threading import RLock
from typing import Any

from backend.agent.base import AgentContext
from backend.agent.registry import AgentRegistry
from backend.agent.router import Intent, IntentRouter
from backend.asr.base import ASREngine
from backend.events import EventBus
from backend.llm.provider import LLMProvider
from backend.memory.store import MemoryStore
from backend.text.processor import TextProcessor
from backend.voice.recorder import AudioRecorder


class ServiceState(StrEnum):
    READY = "ready"
    LISTENING = "listening"
    PROCESSING = "processing"
    ERROR = "error"


@dataclass(frozen=True)
class ProcessResult:
    text: str
    raw_text: str
    intent: str
    source: str
    model: str


class VoiceForgeService:
    def __init__(
        self,
        recorder: AudioRecorder,
        asr: ASREngine,
        processor: TextProcessor,
        router: IntentRouter,
        agents: AgentRegistry,
        llm: LLMProvider,
        memory: MemoryStore,
        events: EventBus,
        language: str = "zh",
    ) -> None:
        self._recorder = recorder
        self._asr = asr
        self._processor = processor
        self._router = router
        self._agents = agents
        self._llm = llm
        self._memory = memory
        self._events = events
        self._language = language
        self._state = ServiceState.READY
        self._last_error: str | None = None
        self._lock = RLock()

    def status(self) -> dict[str, Any]:
        with self._lock:
            return {
                "state": self._state,
                "last_error": self._last_error,
                "asr_model": self._asr.name,
                "language": self._language,
                "agents": self._agents.intents,
            }

    def start_recording(self) -> None:
        with self._lock:
            if self._state == ServiceState.ERROR:
                self._last_error = None
                self._set_state(ServiceState.READY)
            if self._state != ServiceState.READY:
                raise RuntimeError(f"当前状态无法开始录音：{self._state}")
            try:
                self._recorder.start()
                self._set_state(ServiceState.LISTENING)
                self._events.publish("voice.capture.started", {})
            except Exception as error:
                self._fail(error)
                raise

    def stop_and_process(self, selected_text: str | None = None) -> ProcessResult:
        with self._lock:
            if self._state != ServiceState.LISTENING:
                raise RuntimeError("当前没有录音。")
            self._set_state(ServiceState.PROCESSING)
        try:
            audio_path = self._recorder.stop()
            self._events.publish(
                "voice.capture.completed", {"path": str(audio_path)}
            )
            transcription = self._asr.transcribe(audio_path)
            result = self.process_text(
                transcription.text,
                selected_text=selected_text,
                model=transcription.model,
            )
            with self._lock:
                self._last_error = None
                self._set_state(ServiceState.READY)
            return result
        except Exception as error:
            self._fail(error)
            with self._lock:
                self._set_state(ServiceState.READY)
            raise

    def process_text(
        self,
        raw_text: str,
        selected_text: str | None = None,
        model: str = "manual",
    ) -> ProcessResult:
        text = self._processor.process(raw_text)
        if not text:
            raise RuntimeError(
                "未识别到清晰语音，请靠近麦克风、清晰讲话后重试。"
            )
        self._events.publish("voice.text.received", {"text": text, "model": model})
        decision = self._router.route(
            text,
            selected_text=selected_text,
            recent_input=self._memory.latest_input(),
        )
        self._events.publish(
            "agent.intent.detected",
            {
                "intent": decision.intent,
                "source": decision.source,
                "instruction": decision.instruction,
            },
        )

        if decision.intent == Intent.INPUT:
            output = decision.content
        else:
            agent = self._agents.get(decision.intent)
            output = agent.run(
                AgentContext(
                    instruction=decision.instruction,
                    content=decision.content,
                    language=self._language,
                ),
                self._llm,
            ).strip()
            self._events.publish(
                "llm.response.completed",
                {"intent": decision.intent, "text": output},
            )
        if not output:
            raise RuntimeError("处理结果为空。")

        self._memory.add_entry(
            "input",
            output,
            {
                "raw_text": raw_text,
                "intent": decision.intent,
                "source": decision.source,
                "model": model,
            },
        )
        result = ProcessResult(
            text=output,
            raw_text=raw_text,
            intent=decision.intent,
            source=decision.source,
            model=model,
        )
        return result

    def record_injection(self, result: ProcessResult, application: str = "") -> None:
        self._events.publish(
            "text.inject.completed",
            {**asdict(result), "application": application},
        )

    def set_term(self, source: str, target: str) -> None:
        source = source.strip()
        target = target.strip()
        if not source or not target:
            raise ValueError("术语原词和目标词不能为空。")
        self._memory.set_term(source, target)
        self._processor.set_term(source, target)

    def reset_error(self) -> None:
        with self._lock:
            self._last_error = None
            self._set_state(ServiceState.READY)

    def _set_state(self, state: ServiceState) -> None:
        self._state = state
        self._events.publish("service.state.changed", {"state": state})

    def _fail(self, error: Exception) -> None:
        with self._lock:
            self._last_error = str(error)
            self._set_state(ServiceState.ERROR)
        self._events.publish(
            "service.error",
            {"type": type(error).__name__, "message": str(error)},
        )

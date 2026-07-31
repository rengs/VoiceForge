from __future__ import annotations

from pathlib import Path

from backend.asr.sensevoice import SenseVoiceEngine


class FakeSenseVoiceModel:
    def __init__(self) -> None:
        self.kwargs: dict[str, object] = {}

    def generate(self, **kwargs: object) -> list[dict[str, str]]:
        self.kwargs = kwargs
        return [
            {
                "text": (
                    "<|zh|><|NEUTRAL|><|Speech|><|withitn|>第一段。 "
                    "<|zh|><|NEUTRAL|><|Speech|><|withitn|>第二段。"
                )
            }
        ]


def test_sensevoice_enables_vad_for_long_audio() -> None:
    engine = SenseVoiceEngine()
    fake = FakeSenseVoiceModel()
    engine._model = fake  # noqa: SLF001 - isolate model API in unit test

    transcription = engine.transcribe(Path("/tmp/long-recording.wav"))

    assert fake.kwargs["merge_vad"] is True
    assert fake.kwargs["merge_length_s"] == 15
    assert fake.kwargs["batch_size_s"] == 60
    assert "第一段" in transcription.text
    assert "第二段" in transcription.text

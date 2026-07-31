from backend.text.processor import TextProcessor


def test_processor_restores_terminal_punctuation() -> None:
    processor = TextProcessor()
    assert (
        processor.process("今天完成智能采油项目方案编制")
        == "今天完成智能采油项目方案编制。"
    )


def test_processor_removes_sensevoice_tags_and_applies_terms() -> None:
    processor = TextProcessor({"voice forge": "VoiceForge"})
    assert (
        processor.process("<|zh|><|NEUTRAL|>voice forge 可以用了")
        == "VoiceForge 可以用了。"
    )


def test_processor_can_update_terms_at_runtime() -> None:
    processor = TextProcessor()
    processor.set_term("语音锻造", "VoiceForge")
    assert processor.process("语音锻造 可以用了") == "VoiceForge 可以用了。"

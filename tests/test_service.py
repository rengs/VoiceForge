import pytest

from backend.service import ServiceState


def test_acceptance_plain_dictation(service) -> None:
    result = service.process_text("今天完成智能采油项目方案编制")
    assert result.text == "今天完成智能采油项目方案编制。"
    assert result.intent == "input"


def test_acceptance_rewrite_invokes_agent(service) -> None:
    result = service.process_text(
        "把这句话改成科技项目申报语言",
        selected_text="我们要完成智能采油方案。",
    )
    assert result.intent == "rewrite"
    assert result.source == "selection"
    assert result.text == "本项目拟完成智能采油项目方案的系统化编制。"


def test_push_to_talk_pipeline(service) -> None:
    service.start_recording()
    assert service.status()["state"] == ServiceState.LISTENING
    result = service.stop_and_process()
    assert result.text == "今天完成智能采油项目方案编制。"
    assert service.status()["state"] == ServiceState.READY


def test_reports_when_asr_returns_no_clear_speech(service) -> None:
    with pytest.raises(RuntimeError, match="未识别到清晰语音"):
        service.process_text("")

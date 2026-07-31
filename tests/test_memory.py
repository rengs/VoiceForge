from pathlib import Path

from backend.events import EventBus
from backend.memory.store import MemoryStore


def test_memory_entries_preferences_terms_and_events(tmp_path: Path) -> None:
    memory = MemoryStore(tmp_path / "memory.sqlite3")
    memory.add_entry("input", "第一条")
    memory.add_entry("input", "第二条", {"intent": "input"})
    assert memory.latest_input() == "第二条"
    assert memory.recent(limit=1)[0]["metadata"] == {"intent": "input"}

    memory.set_preference("language", "zh")
    assert memory.get_preference("language") == "zh"

    memory.set_term("语音锻造", "VoiceForge")
    assert memory.terms() == {"语音锻造": "VoiceForge"}

    bus = EventBus()
    bus.subscribe("*", memory.record_event)
    event = bus.publish("voice.text.received", {"text": "测试"})
    row = memory._connection.execute(  # noqa: SLF001 - schema verification
        "SELECT topic FROM events WHERE id = ?", (event.id,)
    ).fetchone()
    assert row["topic"] == "voice.text.received"

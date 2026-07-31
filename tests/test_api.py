from dataclasses import replace
from pathlib import Path

from fastapi.testclient import TestClient

from backend.api import create_app
from backend.config import Settings
from backend.events import EventBus
from backend.memory.store import MemoryStore
from backend.runtime import Runtime


def test_health_and_manual_processing(service, tmp_path: Path) -> None:
    memory = service._memory  # noqa: SLF001 - test runtime assembly
    runtime = Runtime(
        settings=replace(
            Settings.load(),
            data_dir=tmp_path,
        ),
        service=service,
        memory=memory,
        events=EventBus(),
    )
    with TestClient(create_app(runtime)) as client:
        health = client.get("/health")
        assert health.status_code == 200
        assert health.json()["ok"] is True

        response = client.post(
            "/v1/process",
            json={"text": "今天完成智能采油项目方案编制"},
        )
        assert response.status_code == 200
        assert response.json()["text"] == "今天完成智能采油项目方案编制。"

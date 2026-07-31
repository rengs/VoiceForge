from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from threading import RLock
from typing import Any, Callable
from uuid import uuid4


@dataclass(frozen=True)
class Event:
    topic: str
    payload: dict[str, Any]
    id: str = field(default_factory=lambda: str(uuid4()))
    created_at: str = field(
        default_factory=lambda: datetime.now(UTC).isoformat()
    )


EventHandler = Callable[[Event], None]


class EventBus:
    """Small in-process event bus with wildcard subscribers."""

    def __init__(self) -> None:
        self._handlers: dict[str, list[EventHandler]] = defaultdict(list)
        self._lock = RLock()

    def subscribe(self, topic: str, handler: EventHandler) -> Callable[[], None]:
        with self._lock:
            self._handlers[topic].append(handler)

        def unsubscribe() -> None:
            with self._lock:
                if handler in self._handlers[topic]:
                    self._handlers[topic].remove(handler)

        return unsubscribe

    def publish(self, topic: str, payload: dict[str, Any]) -> Event:
        event = Event(topic=topic, payload=payload)
        with self._lock:
            handlers = [
                *self._handlers.get(topic, ()),
                *self._handlers.get("*", ()),
            ]
        for handler in handlers:
            handler(event)
        return event

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from threading import RLock
from typing import Any

from backend.events import Event


class MemoryStore:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._lock = RLock()
        self._create_schema()

    def _create_schema(self) -> None:
        with self._connection:
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    kind TEXT NOT NULL,
                    content TEXT NOT NULL,
                    metadata TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE TABLE IF NOT EXISTS preferences (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE TABLE IF NOT EXISTS terms (
                    source TEXT PRIMARY KEY,
                    target TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE TABLE IF NOT EXISTS events (
                    id TEXT PRIMARY KEY,
                    topic TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )

    def add_entry(
        self, kind: str, content: str, metadata: dict[str, Any] | None = None
    ) -> int:
        with self._lock, self._connection:
            cursor = self._connection.execute(
                "INSERT INTO entries(kind, content, metadata) VALUES (?, ?, ?)",
                (kind, content, json.dumps(metadata or {}, ensure_ascii=False)),
            )
            return int(cursor.lastrowid)

    def recent(self, kind: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
        query = "SELECT * FROM entries"
        parameters: tuple[Any, ...] = ()
        if kind:
            query += " WHERE kind = ?"
            parameters = (kind,)
        query += " ORDER BY id DESC LIMIT ?"
        parameters += (limit,)
        with self._lock:
            rows = self._connection.execute(query, parameters).fetchall()
        return [
            {
                **dict(row),
                "metadata": json.loads(row["metadata"]),
            }
            for row in rows
        ]

    def latest_input(self) -> str | None:
        rows = self.recent(kind="input", limit=1)
        return rows[0]["content"] if rows else None

    def set_preference(self, key: str, value: str) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO preferences(key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (key, value),
            )

    def get_preference(self, key: str, default: str | None = None) -> str | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT value FROM preferences WHERE key = ?", (key,)
            ).fetchone()
        return row["value"] if row else default

    def set_term(self, source: str, target: str) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO terms(source, target) VALUES (?, ?)
                ON CONFLICT(source) DO UPDATE SET
                    target = excluded.target,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (source, target),
            )

    def terms(self) -> dict[str, str]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT source, target FROM terms ORDER BY length(source) DESC"
            ).fetchall()
        return {row["source"]: row["target"] for row in rows}

    def record_event(self, event: Event) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT OR IGNORE INTO events(id, topic, payload, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (
                    event.id,
                    event.topic,
                    json.dumps(event.payload, ensure_ascii=False, default=str),
                    event.created_at,
                ),
            )

    def close(self) -> None:
        with self._lock:
            self._connection.close()

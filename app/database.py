from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator, Optional

from app.models import MeetingStatus


def now_utc_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat()


class Database:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self.db_path, timeout=60.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON;")
        conn.execute("PRAGMA journal_mode = WAL;")
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def init_db(self) -> None:
        with self.connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS meetings (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    status TEXT NOT NULL,
                    original_audio_path TEXT NOT NULL,
                    compressed_audio_path TEXT,
                    normalized_audio_path TEXT,
                    transcript_text TEXT NOT NULL DEFAULT '',
                    duration_sec REAL,
                    error_message TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS transcript_segments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    meeting_id TEXT NOT NULL,
                    start_sec REAL NOT NULL,
                    end_sec REAL NOT NULL,
                    speaker_label TEXT,
                    text TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(meeting_id) REFERENCES meetings(id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_meetings_created_at ON meetings(created_at DESC);
                CREATE INDEX IF NOT EXISTS idx_meetings_status ON meetings(status);
                CREATE INDEX IF NOT EXISTS idx_segments_meeting_id ON transcript_segments(meeting_id);

                CREATE VIRTUAL TABLE IF NOT EXISTS transcript_fts USING fts5(
                    meeting_id UNINDEXED,
                    segment_id UNINDEXED,
                    source UNINDEXED,
                    text,
                    tokenize='unicode61'
                );
                """
            )
            self._ensure_column_exists(conn, "meetings", "compressed_audio_path", "TEXT")
            self._ensure_column_exists(conn, "transcript_segments", "speaker_label", "TEXT")

    def _ensure_column_exists(
        self,
        conn: sqlite3.Connection,
        table_name: str,
        column_name: str,
        column_type_sql: str,
    ) -> None:
        rows = conn.execute(f"PRAGMA table_info({table_name})").fetchall()
        existing_columns = {row["name"] for row in rows}
        if column_name not in existing_columns:
            conn.execute(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_type_sql}")

    def _row_to_dict(self, row: Optional[sqlite3.Row]) -> Optional[dict]:
        if row is None:
            return None
        return dict(row)

    def list_meetings(self, limit: int = 20) -> list[dict]:
        with self.connect() as conn:
            rows = conn.execute(
                """
                SELECT id, title, status, original_audio_path, compressed_audio_path, normalized_audio_path,
                       transcript_text, duration_sec, error_message, created_at, updated_at
                FROM meetings
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_meeting(self, meeting_id: str) -> Optional[dict]:
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT id, title, status, original_audio_path, compressed_audio_path, normalized_audio_path,
                       transcript_text, duration_sec, error_message, created_at, updated_at
                FROM meetings
                WHERE id = ?
                """,
                (meeting_id,),
            ).fetchone()
        return self._row_to_dict(row)

    def insert_meeting(
        self,
        meeting_id: str,
        title: str,
        status: MeetingStatus,
        original_audio_path: str,
    ) -> None:
        timestamp = now_utc_iso()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO meetings (
                    id, title, status, original_audio_path, transcript_text,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, '', ?, ?)
                """,
                (meeting_id, title, status.value, original_audio_path, timestamp, timestamp),
            )

    def update_meeting_title(self, meeting_id: str, title: str) -> None:
        with self.connect() as conn:
            conn.execute(
                "UPDATE meetings SET title = ?, updated_at = ? WHERE id = ?",
                (title, now_utc_iso(), meeting_id),
            )

    def update_status(
        self,
        meeting_id: str,
        status: MeetingStatus,
        error_message: Optional[str] = None,
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE meetings
                SET status = ?, error_message = ?, updated_at = ?
                WHERE id = ?
                """,
                (status.value, error_message, now_utc_iso(), meeting_id),
            )

    def update_after_preprocess(
        self,
        meeting_id: str,
        normalized_audio_path: str,
        compressed_audio_path: str,
        duration_sec: float,
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE meetings
                SET normalized_audio_path = ?, compressed_audio_path = ?, duration_sec = ?, updated_at = ?
                WHERE id = ?
                """,
                (normalized_audio_path, compressed_audio_path, duration_sec, now_utc_iso(), meeting_id),
            )

    def get_segments(self, meeting_id: str) -> list[dict]:
        with self.connect() as conn:
            rows = conn.execute(
                """
                SELECT id, meeting_id, start_sec, end_sec, speaker_label, text, created_at
                FROM transcript_segments
                WHERE meeting_id = ?
                ORDER BY start_sec ASC
                """,
                (meeting_id,),
            ).fetchall()
        return [dict(row) for row in rows]

    def update_segment_speaker(
        self,
        meeting_id: str,
        segment_id: int,
        speaker_label: Optional[str],
    ) -> bool:
        with self.connect() as conn:
            exists = conn.execute(
                "SELECT 1 FROM transcript_segments WHERE id = ? AND meeting_id = ?",
                (segment_id, meeting_id),
            ).fetchone()
            if not exists:
                return False

            conn.execute(
                """
                UPDATE transcript_segments
                SET speaker_label = ?
                WHERE id = ? AND meeting_id = ?
                """,
                (speaker_label, segment_id, meeting_id),
            )
            return True

    def reset_for_reprocess(self, meeting_id: str) -> None:
        with self.connect() as conn:
            conn.execute("DELETE FROM transcript_segments WHERE meeting_id = ?", (meeting_id,))
            conn.execute("DELETE FROM transcript_fts WHERE meeting_id = ?", (meeting_id,))
            conn.execute(
                """
                UPDATE meetings
                SET transcript_text = '', error_message = NULL, status = ?, updated_at = ?
                WHERE id = ?
                """,
                (MeetingStatus.UPLOADED.value, now_utc_iso(), meeting_id),
            )

    def save_transcript(
        self,
        meeting_id: str,
        transcript_text: str,
        segments: Iterable[tuple[float, float, str]],
    ) -> None:
        now = now_utc_iso()
        with self.connect() as conn:
            conn.execute("DELETE FROM transcript_segments WHERE meeting_id = ?", (meeting_id,))
            conn.execute("DELETE FROM transcript_fts WHERE meeting_id = ?", (meeting_id,))

            conn.execute(
                """
                UPDATE meetings
                SET transcript_text = ?, status = ?, error_message = NULL, updated_at = ?
                WHERE id = ?
                """,
                (transcript_text, MeetingStatus.READY.value, now, meeting_id),
            )

            conn.execute(
                """
                INSERT INTO transcript_fts(meeting_id, segment_id, source, text)
                VALUES (?, NULL, 'meeting', ?)
                """,
                (meeting_id, transcript_text),
            )

            for start_sec, end_sec, text in segments:
                cur = conn.execute(
                    """
                    INSERT INTO transcript_segments(
                        meeting_id, start_sec, end_sec, speaker_label, text, created_at
                    ) VALUES (?, ?, ?, NULL, ?, ?)
                    """,
                    (meeting_id, start_sec, end_sec, text, now),
                )
                segment_id = cur.lastrowid
                conn.execute(
                    """
                    INSERT INTO transcript_fts(meeting_id, segment_id, source, text)
                    VALUES (?, ?, 'segment', ?)
                    """,
                    (meeting_id, segment_id, text),
                )

    def mark_failed(self, meeting_id: str, error_message: str) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE meetings
                SET status = ?, error_message = ?, updated_at = ?
                WHERE id = ?
                """,
                (MeetingStatus.FAILED.value, error_message[:2000], now_utc_iso(), meeting_id),
            )

    def delete_meeting(self, meeting_id: str) -> Optional[dict]:
        meeting = self.get_meeting(meeting_id)
        if meeting is None:
            return None

        with self.connect() as conn:
            conn.execute("DELETE FROM transcript_fts WHERE meeting_id = ?", (meeting_id,))
            conn.execute("DELETE FROM meetings WHERE id = ?", (meeting_id,))

        return meeting

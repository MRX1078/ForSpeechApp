from __future__ import annotations

import re
import sqlite3

from app.database import Database


class SearchService:
    def __init__(self, db: Database) -> None:
        self.db = db

    def _to_fts_query(self, q: str) -> str:
        tokens = re.findall(r"[\w']+", q.strip(), flags=re.UNICODE)
        if not tokens:
            return ""
        return " ".join(f'"{token}"*' for token in tokens)

    def global_search(self, q: str, limit: int = 50) -> list[dict]:
        query = self._to_fts_query(q)
        if not query:
            return []

        try:
            with self.db.connect() as conn:
                rows = conn.execute(
                    """
                    SELECT
                        transcript_fts.meeting_id AS meeting_id,
                        m.title AS meeting_title,
                        m.created_at AS meeting_created_at,
                        snippet(transcript_fts, 3, '<mark>', '</mark>', ' ... ', 12) AS snippet,
                        MIN(bm25(transcript_fts)) AS rank
                    FROM transcript_fts
                    JOIN meetings AS m ON m.id = transcript_fts.meeting_id
                    WHERE transcript_fts MATCH ?
                    GROUP BY transcript_fts.meeting_id
                    ORDER BY rank ASC, m.created_at DESC
                    LIMIT ?
                    """,
                    (query, limit),
                ).fetchall()
            return [dict(row) for row in rows]
        except sqlite3.OperationalError:
            return []

    def search_in_meeting(self, meeting_id: str, q: str, limit: int = 200) -> list[dict]:
        query = self._to_fts_query(q)
        if not query:
            return []

        try:
            with self.db.connect() as conn:
                rows = conn.execute(
                    """
                    SELECT
                        ts.id AS segment_id,
                        ts.start_sec AS start_sec,
                        ts.end_sec AS end_sec,
                        ts.text AS text,
                        snippet(transcript_fts, 3, '<mark>', '</mark>', ' ... ', 12) AS snippet,
                        bm25(transcript_fts) AS rank
                    FROM transcript_fts
                    JOIN transcript_segments AS ts ON ts.id = transcript_fts.segment_id
                    WHERE transcript_fts.meeting_id = ?
                      AND transcript_fts.source = 'segment'
                      AND transcript_fts MATCH ?
                    ORDER BY rank ASC, ts.start_sec ASC
                    LIMIT ?
                    """,
                    (meeting_id, query, limit),
                ).fetchall()
            return [dict(row) for row in rows]
        except sqlite3.OperationalError:
            return []

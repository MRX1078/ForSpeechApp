from __future__ import annotations

from datetime import datetime

from app.database import Database
from app.i18n import status_label_ru
from app.services.storage import StorageService


class ExportService:
    def __init__(self, db: Database, storage: StorageService) -> None:
        self.db = db
        self.storage = storage

    def export_txt(self, meeting_id: str) -> str:
        meeting = self.db.get_meeting(meeting_id)
        if meeting is None:
            raise ValueError("Встреча не найдена")

        segments = self.db.get_segments(meeting_id)

        lines: list[str] = []
        lines.append(f"Название: {meeting['title']}")
        lines.append(f"Статус: {status_label_ru(meeting['status'])}")
        lines.append(f"Создано (UTC): {meeting['created_at']}")
        lines.append(f"Длительность: {meeting.get('duration_sec') or 0:.2f} сек")
        lines.append("")
        lines.append("Транскрипт:")
        lines.append(meeting.get("transcript_text") or "")
        lines.append("")
        lines.append("Сегменты:")

        for seg in segments:
            speaker = f"{seg['speaker_label']}: " if seg.get("speaker_label") else ""
            lines.append(f"[{seg['start_sec']:.2f} - {seg['end_sec']:.2f}] {speaker}{seg['text']}")

        content = "\n".join(lines)
        out_path = self.storage.export_txt_path(meeting_id)
        out_path.write_text(content, encoding="utf-8")
        return str(out_path)

    def export_markdown(self, meeting_id: str) -> str:
        meeting = self.db.get_meeting(meeting_id)
        if meeting is None:
            raise ValueError("Встреча не найдена")

        segments = self.db.get_segments(meeting_id)
        created_at = meeting.get("created_at")
        created_fmt = created_at
        try:
            created_fmt = datetime.fromisoformat(created_at).strftime("%Y-%m-%d %H:%M:%S UTC")
        except Exception:
            pass

        lines: list[str] = []
        lines.append(f"# {meeting['title']}")
        lines.append("")
        lines.append(f"- ID встречи: `{meeting['id']}`")
        lines.append(f"- Статус: `{status_label_ru(meeting['status'])}`")
        lines.append(f"- Создано: `{created_fmt}`")
        lines.append(f"- Длительность: `{(meeting.get('duration_sec') or 0):.2f} сек`")
        lines.append("")
        lines.append("## Транскрипт")
        lines.append("")
        lines.append(meeting.get("transcript_text") or "")
        lines.append("")
        lines.append("## Сегменты")
        lines.append("")

        for seg in segments:
            speaker = f"**{seg['speaker_label']}**: " if seg.get("speaker_label") else ""
            lines.append(f"- `{seg['start_sec']:.2f}` - `{seg['end_sec']:.2f}`: {speaker}{seg['text']}")

        content = "\n".join(lines)
        out_path = self.storage.export_md_path(meeting_id)
        out_path.write_text(content, encoding="utf-8")
        return str(out_path)

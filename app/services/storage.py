from __future__ import annotations

import mimetypes
import os
from pathlib import Path

from app.config import Settings


class StorageService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def choose_extension(self, filename: str | None, content_type: str | None) -> str:
        if filename:
            suffix = Path(filename).suffix.lower()
            if suffix:
                return suffix

        if content_type:
            guessed = mimetypes.guess_extension(content_type)
            if guessed:
                return guessed

        return ".webm"

    def original_audio_path(self, meeting_id: str, extension: str) -> Path:
        return self.settings.recordings_dir / f"{meeting_id}{extension}"

    def normalized_audio_path(self, meeting_id: str) -> Path:
        return self.settings.processed_dir / f"{meeting_id}.wav"

    def compressed_audio_path(self, meeting_id: str) -> Path:
        return self.settings.recordings_dir / f"{meeting_id}.archive.m4a"

    def segment_audio_path(self, meeting_id: str, segment_idx: int) -> Path:
        return self.settings.processed_dir / f"{meeting_id}.seg_{segment_idx:04d}.wav"

    def export_txt_path(self, meeting_id: str) -> Path:
        return self.settings.exports_dir / f"{meeting_id}.txt"

    def export_md_path(self, meeting_id: str) -> Path:
        return self.settings.exports_dir / f"{meeting_id}.md"

    def save_original_audio(
        self,
        meeting_id: str,
        data: bytes,
        extension: str,
    ) -> Path:
        path = self.original_audio_path(meeting_id, extension)
        path.write_bytes(data)
        return path

    def delete_meeting_assets(self, meeting_id: str, meeting: dict | None = None) -> None:
        paths: list[Path] = []

        if meeting:
            original = meeting.get("original_audio_path")
            compressed = meeting.get("compressed_audio_path")
            normalized = meeting.get("normalized_audio_path")
            if original:
                paths.append(Path(original))
            if compressed:
                paths.append(Path(compressed))
            if normalized:
                paths.append(Path(normalized))

        paths.append(self.export_txt_path(meeting_id))
        paths.append(self.export_md_path(meeting_id))

        for path in paths:
            if path.exists() and path.is_file():
                path.unlink(missing_ok=True)

        for seg_path in self.settings.processed_dir.glob(f"{meeting_id}.seg_*.wav"):
            seg_path.unlink(missing_ok=True)

    def file_exists_and_readable(self, path: Path) -> bool:
        return path.exists() and path.is_file() and os.access(path, os.R_OK)

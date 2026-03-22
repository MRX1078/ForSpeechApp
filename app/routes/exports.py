from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from app.database import Database
from app.deps import get_db, get_export_service, get_storage_service
from app.services.exports import ExportService
from app.services.storage import StorageService

router = APIRouter(prefix="/api/meetings", tags=["exports"])


@router.get("/{meeting_id}/export.txt")
def export_txt(
    meeting_id: str,
    export_service: ExportService = Depends(get_export_service),
) -> FileResponse:
    try:
        path = Path(export_service.export_txt(meeting_id))
    except ValueError:
        raise HTTPException(status_code=404, detail="Meeting not found")

    return FileResponse(path=str(path), filename=path.name, media_type="text/plain")


@router.get("/{meeting_id}/export.md")
def export_md(
    meeting_id: str,
    export_service: ExportService = Depends(get_export_service),
) -> FileResponse:
    try:
        path = Path(export_service.export_markdown(meeting_id))
    except ValueError:
        raise HTTPException(status_code=404, detail="Meeting not found")

    return FileResponse(path=str(path), filename=path.name, media_type="text/markdown")


@router.get("/{meeting_id}/audio-compressed")
def download_compressed_audio(
    meeting_id: str,
    db: Database = Depends(get_db),
    storage: StorageService = Depends(get_storage_service),
) -> FileResponse:
    meeting = db.get_meeting(meeting_id)
    if meeting is None:
        raise HTTPException(status_code=404, detail="Встреча не найдена")

    path_raw = meeting.get("compressed_audio_path")
    if not path_raw:
        raise HTTPException(status_code=404, detail="Сжатый аудиоархив еще не готов")

    path = Path(path_raw)
    if not storage.file_exists_and_readable(path):
        raise HTTPException(status_code=404, detail="Файл сжатого аудио не найден")

    return FileResponse(path=str(path), filename=path.name, media_type="audio/mp4")

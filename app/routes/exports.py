from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from app.deps import get_export_service
from app.services.exports import ExportService

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

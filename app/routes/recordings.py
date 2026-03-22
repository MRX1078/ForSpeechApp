from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status

from app.database import Database
from app.deps import get_db, get_storage_service, get_transcript_pipeline
from app.models import MeetingStatus
from app.schemas import MeetingResponse
from app.services.storage import StorageService
from app.services.transcript_pipeline import TranscriptPipeline

router = APIRouter(prefix="/api", tags=["recordings"])


@router.post("/meetings/upload-audio", response_model=MeetingResponse, status_code=status.HTTP_201_CREATED)
async def upload_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    title: str | None = Form(default=None),
    db: Database = Depends(get_db),
    storage: StorageService = Depends(get_storage_service),
    pipeline: TranscriptPipeline = Depends(get_transcript_pipeline),
) -> dict:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Загруженный файл пустой")

    if file.content_type and not file.content_type.startswith("audio/"):
        raise HTTPException(status_code=400, detail="Ожидался аудиофайл")

    meeting_id = str(uuid4())
    extension = storage.choose_extension(file.filename, file.content_type)
    original_path = storage.save_original_audio(meeting_id, data, extension)

    cleaned_title = (title or "").strip()
    if not cleaned_title:
        now = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        cleaned_title = f"Встреча {now}"

    db.insert_meeting(
        meeting_id=meeting_id,
        title=cleaned_title,
        status=MeetingStatus.UPLOADED,
        original_audio_path=str(original_path),
    )

    background_tasks.add_task(pipeline.process_meeting, meeting_id)
    meeting = db.get_meeting(meeting_id)
    if meeting is None:
        raise HTTPException(status_code=500, detail="Не удалось создать встречу")

    return meeting

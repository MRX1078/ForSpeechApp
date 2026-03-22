from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query

from app.database import Database
from app.deps import get_db, get_storage_service, get_transcript_pipeline
from app.schemas import MeetingResponse, MeetingTranscriptResponse, MeetingUpdate, SegmentResponse
from app.services.storage import StorageService
from app.services.transcript_pipeline import TranscriptPipeline

router = APIRouter(prefix="/api/meetings", tags=["meetings"])


@router.get("", response_model=list[MeetingResponse])
def list_meetings(
    limit: int = Query(default=20, ge=1, le=200),
    db: Database = Depends(get_db),
) -> list[dict]:
    return db.list_meetings(limit=limit)


@router.get("/{meeting_id}", response_model=MeetingResponse)
def get_meeting(meeting_id: str, db: Database = Depends(get_db)) -> dict:
    meeting = db.get_meeting(meeting_id)
    if meeting is None:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return meeting


@router.get("/{meeting_id}/transcript", response_model=MeetingTranscriptResponse)
def get_meeting_transcript(meeting_id: str, db: Database = Depends(get_db)) -> dict:
    meeting = db.get_meeting(meeting_id)
    if meeting is None:
        raise HTTPException(status_code=404, detail="Meeting not found")

    segments = db.get_segments(meeting_id)
    return {
        "meeting": meeting,
        "segments": segments,
    }


@router.patch("/{meeting_id}", response_model=MeetingResponse)
def update_meeting(
    meeting_id: str,
    payload: MeetingUpdate,
    db: Database = Depends(get_db),
) -> dict:
    if db.get_meeting(meeting_id) is None:
        raise HTTPException(status_code=404, detail="Meeting not found")

    db.update_meeting_title(meeting_id, payload.title.strip())
    updated = db.get_meeting(meeting_id)
    if updated is None:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return updated


@router.delete("/{meeting_id}")
def delete_meeting(
    meeting_id: str,
    db: Database = Depends(get_db),
    storage: StorageService = Depends(get_storage_service),
) -> dict:
    meeting = db.delete_meeting(meeting_id)
    if meeting is None:
        raise HTTPException(status_code=404, detail="Meeting not found")

    storage.delete_meeting_assets(meeting_id, meeting)
    return {"ok": True}


@router.post("/{meeting_id}/reprocess", response_model=MeetingResponse)
def reprocess_meeting(
    meeting_id: str,
    background_tasks: BackgroundTasks,
    db: Database = Depends(get_db),
    pipeline: TranscriptPipeline = Depends(get_transcript_pipeline),
) -> dict:
    meeting = db.get_meeting(meeting_id)
    if meeting is None:
        raise HTTPException(status_code=404, detail="Meeting not found")

    db.reset_for_reprocess(meeting_id)
    background_tasks.add_task(pipeline.process_meeting, meeting_id)

    refreshed = db.get_meeting(meeting_id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return refreshed

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class MeetingUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=255)


class MeetingResponse(BaseModel):
    id: str
    title: str
    status: str
    original_audio_path: Optional[str] = None
    normalized_audio_path: Optional[str] = None
    transcript_text: str = ""
    duration_sec: Optional[float] = None
    error_message: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class SegmentResponse(BaseModel):
    id: int
    meeting_id: str
    start_sec: float
    end_sec: float
    text: str
    created_at: datetime


class MeetingTranscriptResponse(BaseModel):
    meeting: MeetingResponse
    segments: list[SegmentResponse]


class SearchResult(BaseModel):
    meeting_id: str
    meeting_title: str
    meeting_created_at: datetime
    snippet: str


class MeetingSearchResult(BaseModel):
    segment_id: int
    start_sec: float
    end_sec: float
    text: str
    snippet: str

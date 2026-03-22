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
    compressed_audio_path: Optional[str] = None
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
    speaker_label: Optional[str] = None
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


class SegmentSpeakerUpdate(BaseModel):
    speaker_label: Optional[str] = Field(default=None, max_length=64)


class MeetingAgreementCreate(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    owner: Optional[str] = Field(default=None, max_length=128)
    status: str = Field(default="open", pattern="^(open|done)$")


class MeetingAgreementUpdate(BaseModel):
    text: Optional[str] = Field(default=None, min_length=1, max_length=2000)
    owner: Optional[str] = Field(default=None, max_length=128)
    status: Optional[str] = Field(default=None, pattern="^(open|done)$")


class MeetingAgreementResponse(BaseModel):
    id: int
    meeting_id: str
    text: str
    owner: Optional[str] = None
    status: str
    created_at: datetime
    updated_at: datetime


class KeyAgreementResponse(BaseModel):
    id: int
    meeting_id: str
    meeting_title: str
    meeting_created_at: datetime
    text: str
    owner: Optional[str] = None
    status: str
    created_at: datetime
    updated_at: datetime


class WorkspaceItemCreate(BaseModel):
    kind: str = Field(pattern="^(task|note)$")
    title: str = Field(min_length=1, max_length=255)
    content: str = Field(default="", max_length=4000)
    status: str = Field(default="open", pattern="^(open|done)$")


class WorkspaceItemUpdate(BaseModel):
    kind: Optional[str] = Field(default=None, pattern="^(task|note)$")
    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    content: Optional[str] = Field(default=None, max_length=4000)
    status: Optional[str] = Field(default=None, pattern="^(open|done)$")


class WorkspaceItemResponse(BaseModel):
    id: int
    kind: str
    title: str
    content: str
    status: str
    created_at: datetime
    updated_at: datetime

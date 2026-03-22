from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.deps import get_search_service
from app.schemas import MeetingSearchResult, SearchResult
from app.services.search import SearchService

router = APIRouter(prefix="/api", tags=["search"])


@router.get("/search", response_model=list[SearchResult])
def global_search(
    q: str = Query(..., min_length=1),
    limit: int = Query(default=50, ge=1, le=200),
    search_service: SearchService = Depends(get_search_service),
) -> list[dict]:
    return search_service.global_search(q=q, limit=limit)


@router.get("/meetings/{meeting_id}/search", response_model=list[MeetingSearchResult])
def search_in_meeting(
    meeting_id: str,
    q: str = Query(..., min_length=1),
    limit: int = Query(default=200, ge=1, le=500),
    search_service: SearchService = Depends(get_search_service),
) -> list[dict]:
    return search_service.search_in_meeting(meeting_id=meeting_id, q=q, limit=limit)

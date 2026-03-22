from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import Database
from app.deps import get_db
from app.schemas import (
    KeyAgreementResponse,
    WorkspaceItemCreate,
    WorkspaceItemResponse,
    WorkspaceItemUpdate,
)

router = APIRouter(prefix="/api/planning", tags=["planning"])


@router.get("/agreements", response_model=list[KeyAgreementResponse])
def list_key_agreements(
    limit: int = Query(default=300, ge=1, le=1000),
    db: Database = Depends(get_db),
) -> list[dict]:
    return db.list_key_agreements(limit=limit)


@router.get("/work-items", response_model=list[WorkspaceItemResponse])
def list_workspace_items(
    limit: int = Query(default=400, ge=1, le=2000),
    db: Database = Depends(get_db),
) -> list[dict]:
    return db.list_workspace_items(limit=limit)


@router.post("/work-items", response_model=WorkspaceItemResponse)
def create_workspace_item(
    payload: WorkspaceItemCreate,
    db: Database = Depends(get_db),
) -> dict:
    title = payload.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="Work item title cannot be empty")

    return db.create_workspace_item(
        kind=payload.kind,
        title=title,
        content=payload.content.strip(),
        status=payload.status,
    )


@router.patch("/work-items/{item_id}", response_model=WorkspaceItemResponse)
def update_workspace_item(
    item_id: int,
    payload: WorkspaceItemUpdate,
    db: Database = Depends(get_db),
) -> dict:
    current = db.get_workspace_item(item_id)
    if current is None:
        raise HTTPException(status_code=404, detail="Work item not found")

    kind = current["kind"]
    title = current["title"]
    content = current["content"]
    status = current["status"]

    if payload.kind is not None:
        kind = payload.kind
    if payload.title is not None:
        title = payload.title.strip()
        if not title:
            raise HTTPException(status_code=400, detail="Work item title cannot be empty")
    if payload.content is not None:
        content = payload.content.strip()
    if payload.status is not None:
        status = payload.status

    updated = db.update_workspace_item(
        item_id=item_id,
        kind=kind,
        title=title,
        content=content,
        status=status,
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Work item not found")

    refreshed = db.get_workspace_item(item_id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="Work item not found")
    return refreshed


@router.delete("/work-items/{item_id}")
def delete_workspace_item(item_id: int, db: Database = Depends(get_db)) -> dict:
    deleted = db.delete_workspace_item(item_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Work item not found")
    return {"ok": True}

from __future__ import annotations

import shutil

from fastapi import APIRouter, Depends

from app.config import Settings
from app.deps import get_settings

router = APIRouter(prefix="/api", tags=["health"])


@router.get("/health")
def health(settings: Settings = Depends(get_settings)) -> dict:
    return {
        "status": "ok",
        "ffmpeg": bool(shutil.which("ffmpeg")),
        "ffprobe": bool(shutil.which("ffprobe")),
        "whisper_bin": str(settings.whisper_cpp_bin),
        "whisper_model": str(settings.whisper_model_path),
    }

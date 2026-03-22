from __future__ import annotations

from fastapi import Depends, FastAPI, Query, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.database import Database
from app.deps import get_db, get_search_service, get_settings
from app.routes.exports import router as exports_router
from app.routes.health import router as health_router
from app.routes.meetings import router as meetings_router
from app.routes.recordings import router as recordings_router
from app.routes.search import router as search_router
from app.services.search import SearchService


def create_app() -> FastAPI:
    settings = get_settings()
    templates = Jinja2Templates(directory=str(settings.templates_dir))

    app = FastAPI(title="Local Meeting Recorder", version="0.1.0")
    app.mount("/static", StaticFiles(directory=str(settings.static_dir)), name="static")

    @app.on_event("startup")
    def on_startup() -> None:
        settings.ensure_directories()
        db = get_db()
        db.init_db()

    app.include_router(health_router)
    app.include_router(recordings_router)
    app.include_router(meetings_router)
    app.include_router(search_router)
    app.include_router(exports_router)

    @app.get("/", response_class=HTMLResponse)
    def index(request: Request, db: Database = Depends(get_db)):
        meetings = db.list_meetings(limit=10)
        return templates.TemplateResponse(
            "index.html",
            {
                "request": request,
                "meetings": meetings,
            },
        )

    @app.get("/meetings", response_class=HTMLResponse)
    def meetings_page(request: Request, db: Database = Depends(get_db)):
        meetings = db.list_meetings(limit=200)
        return templates.TemplateResponse(
            "meetings.html",
            {
                "request": request,
                "meetings": meetings,
            },
        )

    @app.get("/meetings/{meeting_id}", response_class=HTMLResponse)
    def meeting_detail_page(
        request: Request,
        meeting_id: str,
        q: str = Query(default=""),
        db: Database = Depends(get_db),
        search_service: SearchService = Depends(get_search_service),
    ):
        meeting = db.get_meeting(meeting_id)
        if meeting is None:
            return templates.TemplateResponse(
                "meeting_detail.html",
                {
                    "request": request,
                    "meeting": None,
                    "segments": [],
                    "meeting_search_results": [],
                    "q": q,
                },
                status_code=404,
            )

        segments = db.get_segments(meeting_id)
        meeting_search_results = []
        if q.strip():
            meeting_search_results = search_service.search_in_meeting(meeting_id, q, limit=200)

        return templates.TemplateResponse(
            "meeting_detail.html",
            {
                "request": request,
                "meeting": meeting,
                "segments": segments,
                "meeting_search_results": meeting_search_results,
                "q": q,
            },
        )

    @app.get("/search", response_class=HTMLResponse)
    def search_page(
        request: Request,
        q: str = Query(default=""),
        search_service: SearchService = Depends(get_search_service),
    ):
        results = search_service.global_search(q=q, limit=settings.max_search_results) if q.strip() else []
        return templates.TemplateResponse(
            "search.html",
            {
                "request": request,
                "q": q,
                "results": results,
            },
        )

    return app


app = create_app()

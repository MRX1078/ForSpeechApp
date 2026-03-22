from __future__ import annotations

from functools import lru_cache

from app.config import Settings
from app.database import Database
from app.services.audio_preprocess import AudioPreprocessor
from app.services.exports import ExportService
from app.services.search import SearchService
from app.services.storage import StorageService
from app.services.transcriber import WhisperCppTranscriber
from app.services.transcript_pipeline import TranscriptPipeline
from app.services.vad import SileroVADService


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def get_db() -> Database:
    settings = get_settings()
    return Database(settings.db_path)


@lru_cache
def get_storage_service() -> StorageService:
    return StorageService(get_settings())


@lru_cache
def get_audio_preprocessor() -> AudioPreprocessor:
    return AudioPreprocessor(get_settings())


@lru_cache
def get_vad_service() -> SileroVADService:
    return SileroVADService(get_settings())


@lru_cache
def get_transcriber() -> WhisperCppTranscriber:
    return WhisperCppTranscriber(get_settings())


@lru_cache
def get_transcript_pipeline() -> TranscriptPipeline:
    return TranscriptPipeline(
        settings=get_settings(),
        db=get_db(),
        storage=get_storage_service(),
        preprocessor=get_audio_preprocessor(),
        vad_service=get_vad_service(),
        transcriber=get_transcriber(),
    )


@lru_cache
def get_search_service() -> SearchService:
    return SearchService(get_db())


@lru_cache
def get_export_service() -> ExportService:
    return ExportService(get_db(), get_storage_service())


def clear_caches() -> None:
    get_export_service.cache_clear()
    get_search_service.cache_clear()
    get_transcript_pipeline.cache_clear()
    get_transcriber.cache_clear()
    get_vad_service.cache_clear()
    get_audio_preprocessor.cache_clear()
    get_storage_service.cache_clear()
    get_db.cache_clear()
    get_settings.cache_clear()

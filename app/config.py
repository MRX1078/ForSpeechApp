from __future__ import annotations

import os
from pathlib import Path


class Settings:
    def __init__(self) -> None:
        self.base_dir = Path(__file__).resolve().parent.parent
        self.app_dir = self.base_dir / "app"

        self.host = os.getenv("APP_HOST", "127.0.0.1")
        self.port = int(os.getenv("APP_PORT", "8000"))

        self.data_dir = Path(os.getenv("APP_DATA_DIR", self.base_dir / "data"))
        self.recordings_dir = self.data_dir / "recordings"
        self.processed_dir = self.data_dir / "processed"
        self.exports_dir = self.data_dir / "exports"

        self.models_dir = Path(os.getenv("APP_MODELS_DIR", self.base_dir / "models"))
        self.db_path = Path(os.getenv("APP_DB_PATH", self.data_dir / "app.db"))

        self.templates_dir = self.app_dir / "templates"
        self.static_dir = self.app_dir / "static"

        self.whisper_cpp_bin = Path(
            os.getenv(
                "WHISPER_CPP_BIN",
                self.models_dir / "whisper.cpp" / "build" / "bin" / "whisper-cli",
            )
        )
        self.whisper_model_path = Path(
            os.getenv("WHISPER_MODEL_PATH", self.models_dir / "ggml-base.bin")
        )
        self.whisper_language = os.getenv("WHISPER_LANGUAGE", "auto")
        self.whisper_threads = int(os.getenv("WHISPER_THREADS", "4"))

        self.vad_threshold = float(os.getenv("VAD_THRESHOLD", "0.5"))
        self.vad_min_speech_ms = int(os.getenv("VAD_MIN_SPEECH_MS", "250"))
        self.vad_min_silence_ms = int(os.getenv("VAD_MIN_SILENCE_MS", "100"))
        self.vad_padding_sec = float(os.getenv("VAD_PADDING_SEC", "0.2"))
        self.min_segment_sec = float(os.getenv("MIN_SEGMENT_SEC", "0.15"))

        self.max_search_results = int(os.getenv("MAX_SEARCH_RESULTS", "50"))

    def ensure_directories(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.recordings_dir.mkdir(parents=True, exist_ok=True)
        self.processed_dir.mkdir(parents=True, exist_ok=True)
        self.exports_dir.mkdir(parents=True, exist_ok=True)
        self.models_dir.mkdir(parents=True, exist_ok=True)

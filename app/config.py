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
        whisper_model_path_raw = os.getenv("WHISPER_MODEL_PATH", "").strip()
        self.whisper_model_path = Path(whisper_model_path_raw) if whisper_model_path_raw else None
        model_priority_raw = os.getenv(
            "WHISPER_MODEL_PRIORITY",
            "large-v3,large-v2,medium,small,base",
        )
        self.whisper_model_priority = [
            item.strip() for item in model_priority_raw.split(",") if item.strip()
        ]
        self.whisper_language = os.getenv("WHISPER_LANGUAGE", "ru")
        self.whisper_threads = int(os.getenv("WHISPER_THREADS", "4"))
        self.whisper_beam_size = int(os.getenv("WHISPER_BEAM_SIZE", "7"))
        self.whisper_best_of = int(os.getenv("WHISPER_BEST_OF", "7"))
        self.whisper_temperature = float(os.getenv("WHISPER_TEMPERATURE", "0.0"))
        self.whisper_no_speech_thold = float(os.getenv("WHISPER_NO_SPEECH_THOLD", "0.45"))
        self.whisper_logprob_thold = float(os.getenv("WHISPER_LOGPROB_THOLD", "-0.8"))
        self.whisper_entropy_thold = float(os.getenv("WHISPER_ENTROPY_THOLD", "2.4"))
        self.whisper_prompt = os.getenv(
            "WHISPER_PROMPT",
            "Это русская речь с рабочей встречи. Сохраняй имена, цифры и технические термины максимально точно.",
        )
        self.compressed_audio_bitrate_kbps = int(os.getenv("COMPRESSED_AUDIO_BITRATE_KBPS", "32"))

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

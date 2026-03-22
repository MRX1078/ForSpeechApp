from __future__ import annotations

import os
import subprocess
import tempfile
from abc import ABC, abstractmethod
from pathlib import Path

from app.config import Settings


class SpeechTranscriber(ABC):
    @abstractmethod
    def transcribe_segment(self, audio_path: Path) -> str:
        raise NotImplementedError


class WhisperCppTranscriber(SpeechTranscriber):
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def _resolve_binary(self) -> Path:
        candidates = [
            self.settings.whisper_cpp_bin,
            self.settings.models_dir / "whisper.cpp" / "main",
            self.settings.models_dir / "whisper.cpp" / "build" / "bin" / "whisper-cli",
            Path("/usr/local/bin/whisper-cli"),
            Path("/opt/homebrew/bin/whisper-cli"),
        ]
        for candidate in candidates:
            if candidate.exists() and candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate
        raise FileNotFoundError(
            "whisper.cpp binary not found. Set WHISPER_CPP_BIN or build models/whisper.cpp"
        )

    def _resolve_model(self) -> Path:
        model_path = self.settings.whisper_model_path
        if not model_path.exists():
            raise FileNotFoundError(
                f"Whisper model not found: {model_path}. Set WHISPER_MODEL_PATH correctly."
            )
        return model_path

    def transcribe_segment(self, audio_path: Path) -> str:
        whisper_bin = self._resolve_binary()
        model_path = self._resolve_model()

        with tempfile.TemporaryDirectory(prefix="whisper_cpp_") as tmp_dir:
            output_prefix = Path(tmp_dir) / "segment"
            cmd = [
                str(whisper_bin),
                "-m",
                str(model_path),
                "-f",
                str(audio_path),
                "-otxt",
                "-of",
                str(output_prefix),
                "-nt",
            ]

            if self.settings.whisper_language and self.settings.whisper_language != "auto":
                cmd.extend(["-l", self.settings.whisper_language])

            if self.settings.whisper_threads > 0:
                cmd.extend(["-t", str(self.settings.whisper_threads)])

            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
            if result.returncode != 0:
                message = result.stderr.strip() or result.stdout.strip() or "Unknown whisper.cpp error"
                raise RuntimeError(f"whisper.cpp failed: {message}")

            out_path = output_prefix.with_suffix(".txt")
            if out_path.exists():
                text = out_path.read_text(encoding="utf-8", errors="ignore")
            else:
                text = result.stdout

        return " ".join(text.split())

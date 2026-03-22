from __future__ import annotations

import subprocess
from pathlib import Path

from app.config import Settings


class AudioPreprocessor:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def preprocess(self, input_path: Path, output_path: Path) -> float:
        cmd = [
            "ffmpeg",
            "-y",
            "-i",
            str(input_path),
            "-ac",
            "1",
            "-ar",
            "16000",
            "-c:a",
            "pcm_s16le",
            "-af",
            "loudnorm=I=-16:TP=-1.5:LRA=11",
            str(output_path),
        ]
        self._run(cmd, "ffmpeg preprocessing failed")
        return self.get_duration_sec(output_path)

    def extract_segment(
        self,
        input_path: Path,
        start_sec: float,
        end_sec: float,
        output_path: Path,
    ) -> None:
        duration_sec = max(0.01, end_sec - start_sec)
        cmd = [
            "ffmpeg",
            "-y",
            "-i",
            str(input_path),
            "-ss",
            f"{start_sec:.3f}",
            "-t",
            f"{duration_sec:.3f}",
            "-ac",
            "1",
            "-ar",
            "16000",
            "-c:a",
            "pcm_s16le",
            str(output_path),
        ]
        self._run(cmd, "ffmpeg segment extraction failed")

    def get_duration_sec(self, input_path: Path) -> float:
        cmd = [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(input_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise RuntimeError(f"ffprobe failed: {result.stderr.strip()}")

        text = result.stdout.strip()
        try:
            return float(text)
        except ValueError as exc:
            raise RuntimeError(f"Invalid duration from ffprobe: {text!r}") from exc

    def _run(self, cmd: list[str], error_prefix: str) -> None:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            stderr = result.stderr.strip()
            raise RuntimeError(f"{error_prefix}: {stderr}")

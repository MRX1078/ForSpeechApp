from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.config import Settings


@dataclass
class SpeechWindow:
    start_sec: float
    end_sec: float


class SileroVADService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._model = None
        self._read_audio = None
        self._get_speech_timestamps = None

    def _get_model(self):
        if self._model is None:
            try:
                from silero_vad import (
                    get_speech_timestamps as _get_speech_timestamps,
                    load_silero_vad,
                    read_audio as _read_audio,
                )
            except ImportError as exc:
                raise RuntimeError(
                    "silero-vad is not installed. Install dependencies from requirements.txt."
                ) from exc

            self._model = load_silero_vad()
            self._read_audio = _read_audio
            self._get_speech_timestamps = _get_speech_timestamps
        return self._model

    def detect_segments(self, audio_path: Path, duration_sec: float) -> list[SpeechWindow]:
        model = self._get_model()
        assert self._read_audio is not None
        assert self._get_speech_timestamps is not None
        audio = self._read_audio(str(audio_path), sampling_rate=16000)

        timestamps = self._get_speech_timestamps(
            audio,
            model,
            sampling_rate=16000,
            threshold=self.settings.vad_threshold,
            min_speech_duration_ms=self.settings.vad_min_speech_ms,
            min_silence_duration_ms=self.settings.vad_min_silence_ms,
        )

        raw_segments: list[SpeechWindow] = []
        for ts in timestamps:
            start = max(0.0, ts["start"] / 16000.0 - self.settings.vad_padding_sec)
            end = min(duration_sec, ts["end"] / 16000.0 + self.settings.vad_padding_sec)
            if end - start >= self.settings.min_segment_sec:
                raw_segments.append(SpeechWindow(start_sec=start, end_sec=end))

        if not raw_segments and duration_sec > 0:
            return [SpeechWindow(start_sec=0.0, end_sec=duration_sec)]

        return self._merge_overlapping(raw_segments)

    def _merge_overlapping(self, segments: list[SpeechWindow]) -> list[SpeechWindow]:
        if not segments:
            return []

        segments.sort(key=lambda seg: seg.start_sec)
        merged = [segments[0]]

        for current in segments[1:]:
            prev = merged[-1]
            if current.start_sec <= prev.end_sec:
                prev.end_sec = max(prev.end_sec, current.end_sec)
            else:
                merged.append(current)

        return merged

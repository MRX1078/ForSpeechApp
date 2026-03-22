from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import wave

import numpy as np

from app.config import Settings


@dataclass
class SpeechWindow:
    start_sec: float
    end_sec: float


class SileroVADService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._model = None
        self._get_speech_timestamps = None

    def _get_model(self):
        if self._model is None:
            try:
                from silero_vad import (
                    get_speech_timestamps as _get_speech_timestamps,
                    load_silero_vad,
                )
            except ImportError as exc:
                raise RuntimeError(
                    "silero-vad is not installed. Install dependencies from requirements.txt."
                ) from exc

            self._model = load_silero_vad()
            self._get_speech_timestamps = _get_speech_timestamps
        return self._model

    def _read_normalized_wav(self, audio_path: Path):
        """
        Read normalized PCM WAV directly to avoid torchaudio backend issues.
        Pipeline guarantees mono/16kHz/pcm_s16le before VAD.
        """
        try:
            import torch
        except ImportError as exc:
            raise RuntimeError("torch is required for VAD but is not installed.") from exc

        try:
            with wave.open(str(audio_path), "rb") as wav_file:
                channels = wav_file.getnchannels()
                sample_width = wav_file.getsampwidth()
                sample_rate = wav_file.getframerate()
                frame_count = wav_file.getnframes()
                raw = wav_file.readframes(frame_count)
        except wave.Error as exc:
            raise RuntimeError(f"Invalid WAV for VAD: {audio_path}") from exc

        if channels != 1:
            raise RuntimeError(f"Expected mono WAV, got {channels} channels: {audio_path}")
        if sample_rate != 16000:
            raise RuntimeError(f"Expected 16kHz WAV, got {sample_rate} Hz: {audio_path}")
        if sample_width != 2:
            raise RuntimeError(f"Expected 16-bit WAV, got {sample_width * 8}-bit: {audio_path}")

        audio_np = np.frombuffer(raw, dtype=np.int16).astype(np.float32)
        if audio_np.size == 0:
            return torch.zeros(1, dtype=torch.float32)

        audio_np /= 32768.0
        return torch.from_numpy(audio_np)

    def detect_segments(self, audio_path: Path, duration_sec: float) -> list[SpeechWindow]:
        model = self._get_model()
        assert self._get_speech_timestamps is not None
        audio = self._read_normalized_wav(audio_path)

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

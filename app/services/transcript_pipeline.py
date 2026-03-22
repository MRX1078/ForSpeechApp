from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.config import Settings
from app.database import Database
from app.models import MeetingStatus
from app.services.audio_preprocess import AudioPreprocessor
from app.services.storage import StorageService
from app.services.transcriber import SpeechTranscriber
from app.services.vad import SileroVADService


@dataclass
class TranscriptSegment:
    start_sec: float
    end_sec: float
    text: str


class TranscriptPipeline:
    def __init__(
        self,
        settings: Settings,
        db: Database,
        storage: StorageService,
        preprocessor: AudioPreprocessor,
        vad_service: SileroVADService,
        transcriber: SpeechTranscriber,
    ) -> None:
        self.settings = settings
        self.db = db
        self.storage = storage
        self.preprocessor = preprocessor
        self.vad_service = vad_service
        self.transcriber = transcriber

    def process_meeting(self, meeting_id: str) -> None:
        meeting = self.db.get_meeting(meeting_id)
        if meeting is None:
            return

        try:
            self.db.update_status(meeting_id, MeetingStatus.PREPROCESSING)

            original_audio_path = meeting.get("original_audio_path")
            if not original_audio_path:
                raise RuntimeError("Meeting has no original audio path")

            normalized_path = self.storage.normalized_audio_path(meeting_id)
            compressed_path = self.storage.compressed_audio_path(meeting_id)
            duration_sec = self.preprocessor.preprocess(
                input_path=Path(original_audio_path),
                output_path=normalized_path,
            )
            self.preprocessor.create_compressed_archive(
                input_path=normalized_path,
                output_path=compressed_path,
            )
            self.db.update_after_preprocess(
                meeting_id=meeting_id,
                normalized_audio_path=str(normalized_path),
                compressed_audio_path=str(compressed_path),
                duration_sec=duration_sec,
            )

            self.db.update_status(meeting_id, MeetingStatus.TRANSCRIBING)
            windows = self.vad_service.detect_segments(normalized_path, duration_sec)

            segments: list[TranscriptSegment] = []
            for idx, window in enumerate(windows):
                segment_audio_path = self.storage.segment_audio_path(meeting_id, idx)
                self.preprocessor.extract_segment(
                    input_path=normalized_path,
                    start_sec=window.start_sec,
                    end_sec=window.end_sec,
                    output_path=segment_audio_path,
                )
                text = self.transcriber.transcribe_segment(segment_audio_path)
                if text.strip():
                    segments.append(
                        TranscriptSegment(
                            start_sec=window.start_sec,
                            end_sec=window.end_sec,
                            text=text.strip(),
                        )
                    )

            transcript_text = "\n".join(segment.text for segment in segments).strip()
            self.db.save_transcript(
                meeting_id=meeting_id,
                transcript_text=transcript_text,
                segments=[(seg.start_sec, seg.end_sec, seg.text) for seg in segments],
            )
        except Exception as exc:
            self.db.mark_failed(meeting_id, str(exc))

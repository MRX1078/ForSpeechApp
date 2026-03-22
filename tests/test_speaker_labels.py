from __future__ import annotations

import io
import wave

from app.deps import get_db


def _silent_wav_bytes(duration_sec: float = 0.4, sample_rate: int = 16000) -> bytes:
    num_samples = int(duration_sec * sample_rate)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(b"\x00\x00" * num_samples)
    return buf.getvalue()


def test_patch_segment_speaker_label(client):
    response = client.post(
        "/api/meetings/upload-audio",
        files={"file": ("sample.wav", _silent_wav_bytes(), "audio/wav")},
        data={"title": "Meeting with labels"},
    )
    assert response.status_code == 201
    meeting_id = response.json()["id"]

    db = get_db()
    db.save_transcript(
        meeting_id=meeting_id,
        transcript_text="Привет, это тест.",
        segments=[(0.0, 1.2, "Привет, это тест.")],
    )
    segment_id = db.get_segments(meeting_id)[0]["id"]

    patch = client.patch(
        f"/api/meetings/{meeting_id}/segments/{segment_id}",
        json={"speaker_label": "Спикер 1"},
    )
    assert patch.status_code == 200
    assert patch.json()["speaker_label"] == "Спикер 1"
